#!/usr/bin/env bash
#
# setup.sh - Menú maestro del stack de IA local (rig-ia)
# Lanza, en orden, los scripts de instalación y configuración:
#   1) Verificación del sistema (GPU, /models, disco, Secure Boot)
#   2) Instalación y configuración de Ollama
#   3) Instalación de Docker + despliegue de Open WebUI
#   4) Descarga de modelos (escalera / zoo / mínimo)
#   5) Benchmark de generación con salida a CSV
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Funciones de log con colores
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    readonly C_VERDE='\033[0;32m'
    readonly C_ROJO='\033[0;31m'
    readonly C_AMARILLO='\033[0;33m'
    readonly C_AZUL='\033[0;34m'
    readonly C_NEGRITA='\033[1m'
    readonly C_RESET='\033[0m'
else
    readonly C_VERDE='' C_ROJO='' C_AMARILLO='' C_AZUL='' C_NEGRITA='' C_RESET=''
fi

log_info()  { echo -e "${C_AZUL}[INFO]${C_RESET} $*"; }
log_ok()    { echo -e "${C_VERDE}[OK]${C_RESET} $*"; }
log_aviso() { echo -e "${C_AMARILLO}[AVISO]${C_RESET} $*"; }
log_error() { echo -e "${C_ROJO}[ERROR]${C_RESET} $*" >&2; }

# ---------------------------------------------------------------------------
# Comprobación de entorno
# ---------------------------------------------------------------------------
if [[ "$(uname -s)" != "Linux" ]]; then
    log_error "Este stack solo funciona en Linux (detectado: $(uname -s))."
    exit 1
fi
if [[ -z "${BASH_VERSION:-}" ]]; then
    log_error "Este script requiere bash. Ejecuta: bash setup.sh"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${REPO_DIR}/scripts"

# ---------------------------------------------------------------------------
# Detección de pasos ya completados
# ---------------------------------------------------------------------------
paso_hecho_ollama()  { command -v ollama >/dev/null 2>&1 && systemctl is-active --quiet ollama.service 2>/dev/null; }
paso_hecho_docker()  { command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker 2>/dev/null; }
paso_hecho_webui()   { curl -fsS http://localhost:3000 >/dev/null 2>&1; }
paso_hay_modelos()   { command -v ollama >/dev/null 2>&1 && [[ "$(ollama list 2>/dev/null | awk 'NR>1' | wc -l)" -gt 0 ]]; }

estado() {
    # Devuelve una marca visual según si el paso parece completado.
    if "$1"; then
        echo -e "${C_VERDE}[hecho]${C_RESET}"
    else
        echo -e "${C_AMARILLO}[pendiente]${C_RESET}"
    fi
}

# ---------------------------------------------------------------------------
# Acciones del menú
# ---------------------------------------------------------------------------
ejecutar_script() {
    local script="$1"
    shift
    echo
    log_info "Lanzando ${script} $* ..."
    echo "--------------------------------------------------------------"
    local rc=0
    bash "${SCRIPTS}/${script}" "$@" || rc=$?
    echo "--------------------------------------------------------------"
    if [[ "${rc}" -eq 0 ]]; then
        log_ok "${script} terminó correctamente."
    else
        log_error "${script} terminó con código ${rc}."
    fi
    return "${rc}"
}

menu_modelos() {
    echo
    echo "  Descarga de modelos - elige modo:"
    echo "    1) --minimo    (qwen3:14b + gpt-oss:20b + nomic-embed-text)"
    echo "    2) --escalera  (benchmark entre GPUs: qwen3:14b/30b/32b + llama3.3:70b)"
    echo "    3) --zoo       (uso diario: gpt-oss, qwen3:8b, coder, vl, deepseek, embeddings)"
    echo "    4) --todo      (todo, sin confirmaciones; incluye llama3.3:70b ~43 GB)"
    echo "    0) Cancelar"
    echo
    read -r -p "  Opción: " op
    case "${op}" in
        1) ejecutar_script 04-descargar-modelos.sh --minimo ;;
        2) ejecutar_script 04-descargar-modelos.sh --escalera ;;
        3) ejecutar_script 04-descargar-modelos.sh --zoo ;;
        4) ejecutar_script 04-descargar-modelos.sh --todo ;;
        0) log_info "Cancelado." ;;
        *) log_error "Opción no válida." ;;
    esac
}

ejecutar_todo() {
    log_info "Ejecutando todos los pasos en orden..."
    ejecutar_script 01-verificar-sistema.sh || {
        log_aviso "La verificación del sistema reportó problemas."
        read -r -p "¿Continuar de todos modos? [s/N] " resp
        [[ "${resp}" =~ ^[sS]$ ]] || return 1
    }
    ejecutar_script 02-instalar-ollama.sh
    ejecutar_script 03-instalar-docker-openwebui.sh
    ejecutar_script 04-descargar-modelos.sh --minimo
    ejecutar_script 05-benchmark.sh
    echo
    log_ok "Instalación completa terminada."
    log_info "Open WebUI: http://172.16.16.70:3000 (o http://localhost:3000)"
}

# ---------------------------------------------------------------------------
# Bucle principal del menú
# ---------------------------------------------------------------------------
while true; do
    echo
    echo -e "${C_NEGRITA}=============================================================="
    echo "  rig-ia-stack - Menú maestro de instalación"
    echo -e "==============================================================${C_RESET}"
    echo -e "  Estado actual:"
    echo -e "    Ollama:          $(estado paso_hecho_ollama)"
    echo -e "    Docker:          $(estado paso_hecho_docker)"
    echo -e "    Open WebUI:      $(estado paso_hecho_webui)"
    echo -e "    Modelos:         $(estado paso_hay_modelos)"
    echo
    echo "  1) Verificar sistema (GPU, /models, disco, Secure Boot)"
    echo "  2) Instalar y configurar Ollama"
    echo "  3) Instalar Docker + Open WebUI"
    echo "  4) Descargar modelos (submenú de modos)"
    echo "  5) Ejecutar benchmark (CSV en benchmarks/)"
    echo "  6) Ejecutar TODO (pasos 1-5, con descarga --minimo)"
    echo "  0) Salir"
    echo
    read -r -p "Elige una opción: " opcion

    case "${opcion}" in
        1) ejecutar_script 01-verificar-sistema.sh || true ;;
        2) ejecutar_script 02-instalar-ollama.sh || true ;;
        3) ejecutar_script 03-instalar-docker-openwebui.sh || true ;;
        4) menu_modelos ;;
        5) ejecutar_script 05-benchmark.sh || true ;;
        6) ejecutar_todo || true ;;
        0) echo; log_info "¡Hasta luego!"; exit 0 ;;
        *) log_error "Opción no válida." ;;
    esac
done
