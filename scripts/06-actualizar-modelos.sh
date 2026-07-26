#!/usr/bin/env bash
#
# 06-actualizar-modelos.sh
# Actualiza los modelos instalados a la última "build" de su tag.
#
# Cómo funcionan las actualizaciones en Ollama:
#   - Un tag (p. ej. qwen3:14b) apunta siempre a la última build publicada
#     por los mantenedores de la librería (mejoras de quant, plantillas, fixes).
#   - 'ollama pull <tag>' descarga SOLO las capas que cambiaron (delta),
#     así que actualizar es rápido y no duplica espacio.
#   - Los modelos NUEVOS (otra generación, p. ej. un futuro qwen4) llegan
#     como tags nuevos: se instalan en paralelo, se comparan con el benchmark
#     (script 05) y se borra el perdedor con 'ollama rm <tag>'.
#
# Uso:
#   ./06-actualizar-modelos.sh                # actualiza TODOS los modelos instalados
#   ./06-actualizar-modelos.sh qwen3:14b      # actualiza solo ese modelo
#   ./06-actualizar-modelos.sh --ollama       # además actualiza el motor Ollama
#   ./06-actualizar-modelos.sh -h             # ayuda
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
    readonly C_RESET='\033[0m'
else
    readonly C_VERDE='' C_ROJO='' C_AMARILLO='' C_RESET='' C_AZUL=''
fi

log_info()  { echo -e "${C_AZUL}[INFO]${C_RESET} $*"; }
log_ok()    { echo -e "${C_VERDE}[OK]${C_RESET} $*"; }
log_aviso() { echo -e "${C_AMARILLO}[AVISO]${C_RESET} $*"; }
log_error() { echo -e "${C_ROJO}[ERROR]${C_RESET} $*" >&2; }

if [[ "$(uname -s)" != "Linux" ]] || [[ -z "${BASH_VERSION:-}" ]]; then
    log_error "Este script requiere Linux con bash."
    exit 1
fi

mostrar_ayuda() {
    cat <<'EOF'
Uso: ./06-actualizar-modelos.sh [OPCIONES] [modelo]

Actualiza los modelos instalados a la última build de su tag.
'ollama pull' solo descarga las capas que cambiaron (delta): actualizar
es rápido y no duplica espacio en disco.

Opciones:
  (sin args)      Actualiza TODOS los modelos instalados.
  modelo          Actualiza solo ese tag (p. ej. qwen3:14b).
  --ollama        Además, actualiza el motor Ollama a la última versión.
  -h, --help      Muestra esta ayuda.

Flujo recomendado para evaluar un modelo NUEVO que acaba de salir:
  1. ollama pull modelo-nuevo:tag
  2. ./05-benchmark.sh modelo-viejo:tag modelo-nuevo:tag   # comparar
  3. Probar ambos en Open WebUI con tus prompts habituales
  4. ollama rm modelo-viejo:tag                            # liberar espacio
EOF
}

# ---------------------------------------------------------------------------
# Parseo de argumentos
# ---------------------------------------------------------------------------
ACTUALIZAR_OLLAMA=0
MODELO_UNICO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ollama)   ACTUALIZAR_OLLAMA=1 ;;
        -h|--help)  mostrar_ayuda; exit 0 ;;
        -*)         log_error "Opción desconocida: $1"; echo; mostrar_ayuda; exit 1 ;;
        *)          MODELO_UNICO="$1" ;;
    esac
    shift
done

echo "=============================================================="
echo "  Actualización de modelos - rig-ia"
echo "=============================================================="
echo

# ---------------------------------------------------------------------------
# Comprobaciones previas
# ---------------------------------------------------------------------------
if ! command -v ollama >/dev/null 2>&1; then
    log_error "Ollama no está instalado. Ejecuta primero scripts/02-instalar-ollama.sh."
    exit 1
fi
if ! curl -fsS http://localhost:11434/api/version >/dev/null 2>&1; then
    log_error "La API de Ollama no responde en localhost:11434."
    log_error "Revisa el servicio con: systemctl status ollama.service"
    exit 1
fi

# ---------------------------------------------------------------------------
# Lista de modelos a actualizar
# ---------------------------------------------------------------------------
if [[ -n "${MODELO_UNICO}" ]]; then
    MODELOS=("${MODELO_UNICO}")
else
    mapfile -t MODELOS < <(ollama list | awk 'NR>1 {print $1}')
fi

if [[ "${#MODELOS[@]}" -eq 0 ]]; then
    log_aviso "No hay modelos instalados. Nada que actualizar."
    log_info "Descarga modelos con scripts/04-descargar-modelos.sh"
    exit 0
fi

log_info "Modelos a actualizar: ${MODELOS[*]}"
log_info "(solo se descargan las capas que cambiaron; si no hay cambios, no se descarga nada)"
echo

# ---------------------------------------------------------------------------
# Actualización con reintentos
# ---------------------------------------------------------------------------
declare -a FALLIDOS=()
for modelo in "${MODELOS[@]}"; do
    log_info "Actualizando ${modelo} ..."
    ok=0
    for intento in 1 2 3; do
        if ollama pull "${modelo}"; then
            ok=1
            break
        fi
        log_aviso "Falló la actualización de ${modelo} (intento ${intento}/3)."
        sleep 3
    done
    if [[ "${ok}" -eq 1 ]]; then
        log_ok "${modelo} al día."
    else
        log_error "No se pudo actualizar ${modelo}."
        FALLIDOS+=("${modelo}")
    fi
    echo
done

# ---------------------------------------------------------------------------
# Opcional: actualizar el motor Ollama
# ---------------------------------------------------------------------------
if [[ "${ACTUALIZAR_OLLAMA}" -eq 1 ]]; then
    log_info "Actualizando el motor Ollama con el script oficial..."
    curl -fsSL https://ollama.com/install.sh | sh
    log_ok "Motor Ollama actualizado: $(ollama --version 2>/dev/null || echo 'versión desconocida')"
    log_aviso "El servicio se reinicia solo al actualizar; los modelos se conservan intactos."
    echo
fi

# ---------------------------------------------------------------------------
# Resumen final
# ---------------------------------------------------------------------------
echo "=============================================================="
echo "  RESUMEN DE ACTUALIZACIÓN"
echo "=============================================================="
if [[ "${#FALLIDOS[@]}" -gt 0 ]]; then
    log_aviso "Modelos con problemas:"
    for m in "${FALLIDOS[@]}"; do
        echo "  - ${m}"
    done
else
    log_ok "Todos los modelos están al día."
fi
echo
log_info "Estado actual del rig:"
ollama list
echo
log_aviso "Consejo: tras actualizaciones grandes, repite el benchmark (scripts/05-benchmark.sh)"
log_aviso "para confirmar que el rendimiento se mantiene (o mejora)."
log_info "Para descubrir modelos nuevos: https://ollama.com/library?sort=newest"
