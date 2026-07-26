#!/usr/bin/env bash
#
# 04-descargar-modelos.sh
# Descarga los modelos de Ollama del rig, en dos grupos:
#   ESCALERA: modelos de la escalera de benchmark (comparables entre GPUs)
#   ZOO:      modelos de uso diario
#
# Uso:
#   ./04-descargar-modelos.sh --escalera   # solo la escalera de benchmark
#   ./04-descargar-modelos.sh --zoo        # solo el zoo de uso diario
#   ./04-descargar-modelos.sh --todo       # todo, sin pedir confirmación (llama3.3:70b incluido)
#   ./04-descargar-modelos.sh --minimo     # qwen3:14b + gpt-oss:20b + nomic-embed-text
#   ./04-descargar-modelos.sh              # muestra esta ayuda
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

# ---------------------------------------------------------------------------
# Catálogo de modelos (tags verificados contra ollama.com/library, julio 2026)
# ---------------------------------------------------------------------------
# ESCALERA: misma serie ejecutada en cada GPU para benchmarks comparables.
ESCALERA=(
    "qwen3:14b"        # tier 0   - denso, ~9 GB  (cabe en la RTX 3080)
    "qwen3:30b"        # tier 25  - MoE 3B activos, ~19 GB
    "qwen3.6:27b"      # tier 50  - denso, ~17 GB (Qwen 3.6, mejor denso consumo 2026)
    "llama3.3:70b"     # tier 100 - denso, ~43 GB (descarga pesada: pide confirmación)
)

# ZOO: modelos de uso diario.
ZOO=(
    "gpt-oss:20b"      # daily driver MoE, MXFP4, ~14 GB
    "qwen3:8b"         # rápido, ~5 GB
    "qwen3-coder:30b"  # coder MoE, ~19 GB
    "gemma4:e4b"       # multimodal + tool calling (visión), ~6 GB - ideal para agentes
    "deepseek-r1:14b"  # razonamiento, ~9 GB
    "nomic-embed-text" # embeddings, ~274 MB
)

# Mínimo viable para empezar a trabajar.
MINIMO=(
    "qwen3:14b"
    "gpt-oss:20b"
    "nomic-embed-text"
)

MODELO_PESADO="llama3.3:70b"   # ~43 GB: requiere >= 50 GB libres y confirmación
GB_MINIMOS_PESADO=50

# ---------------------------------------------------------------------------
# Ayuda y parseo de flags
# ---------------------------------------------------------------------------
mostrar_ayuda() {
    cat <<'EOF'
Uso: ./04-descargar-modelos.sh [FLAG]

Flags (elige uno):
  --escalera   Descarga la escalera de benchmark:
               qwen3:14b, qwen3:30b, qwen3.6:27b, llama3.3:70b
  --zoo        Descarga el zoo de uso diario:
               gpt-oss:20b, qwen3:8b, qwen3-coder:30b, gemma4:e4b,
               deepseek-r1:14b, nomic-embed-text
  --todo       Descarga TODO sin pedir confirmación (llama3.3:70b incluido).
  --minimo     Solo lo imprescindible para empezar:
               qwen3:14b, gpt-oss:20b, nomic-embed-text

Sin flags se muestra esta ayuda.
Nota: llama3.3:70b ocupa ~43 GB. Con --escalera se pide confirmación
interactiva antes de descargarlo; con --todo se descarga directamente.
EOF
}

MODO=""
CONFIRMAR_PESADO=1
case "${1:-}" in
    --escalera) MODO="escalera" ;;
    --zoo)      MODO="zoo" ;;
    --todo)     MODO="todo"; CONFIRMAR_PESADO=0 ;;
    --minimo)   MODO="minimo" ;;
    -h|--help)  mostrar_ayuda; exit 0 ;;
    "")         mostrar_ayuda; exit 0 ;;
    *)
        log_error "Flag desconocido: $1"
        echo
        mostrar_ayuda
        exit 1
        ;;
esac

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

# Espacio libre donde viven los modelos
if mountpoint -q /models; then
    DISCO_MODELOS="/models"
else
    DISCO_MODELOS="${HOME}"
fi
LIBRE_GB="$(df -BG "${DISCO_MODELOS}" | awk 'NR==2 {gsub("G","",$4); print $4}')"
log_info "Espacio libre en ${DISCO_MODELOS}: ${LIBRE_GB} GB"

# ---------------------------------------------------------------------------
# Construir la lista de modelos a descargar
# ---------------------------------------------------------------------------
MODELOS=()
case "${MODO}" in
    escalera) MODELOS=("${ESCALERA[@]}") ;;
    zoo)      MODELOS=("${ZOO[@]}") ;;
    minimo)   MODELOS=("${MINIMO[@]}") ;;
    todo)     MODELOS=("${ESCALERA[@]}" "${ZOO[@]}") ;;
esac

echo "=============================================================="
echo "  Descarga de modelos - modo: ${MODO}"
echo "  Modelos: ${MODELOS[*]}"
echo "=============================================================="
echo

# ---------------------------------------------------------------------------
# Descarga con reintentos
# ---------------------------------------------------------------------------
descargar_modelo() {
    local modelo="$1"
    local intento
    for intento in 1 2 3; do
        log_info "Descargando ${modelo} (intento ${intento}/3)..."
        if ollama pull "${modelo}"; then
            log_ok "${modelo} descargado correctamente."
            return 0
        fi
        log_aviso "Falló la descarga de ${modelo} (intento ${intento}/3)."
        sleep 3
    done
    log_error "No se pudo descargar ${modelo} tras 3 intentos."
    return 1
}

declare -a FALLIDOS=()
for modelo in "${MODELOS[@]}"; do
    # Trato especial para el modelo pesado: espacio + confirmación
    if [[ "${modelo}" == "${MODELO_PESADO}" ]]; then
        if [[ "${LIBRE_GB}" -lt "${GB_MINIMOS_PESADO}" ]]; then
            log_error "Espacio insuficiente para ${modelo} (~43 GB):"
            log_error "quedan ${LIBRE_GB} GB libres y se recomiendan >= ${GB_MINIMOS_PESADO} GB."
            FALLIDOS+=("${modelo} (espacio insuficiente)")
            continue
        fi
        if [[ "${CONFIRMAR_PESADO}" -eq 1 ]]; then
            echo
            log_aviso "${modelo} ocupa ~43 GB. Es el tier 100 de la escalera de benchmark."
            read -r -p "¿Descargar ${modelo} ahora? [s/N] " respuesta
            if [[ ! "${respuesta}" =~ ^[sS]$ ]]; then
                log_aviso "Se omite ${modelo}. Puedes descargarlo luego con: ollama pull ${modelo}"
                continue
            fi
        fi
    fi

    if ! descargar_modelo "${modelo}"; then
        FALLIDOS+=("${modelo}")
    fi
    echo
done

# ---------------------------------------------------------------------------
# Resumen final
# ---------------------------------------------------------------------------
echo "=============================================================="
echo "  RESUMEN DE DESCARGA"
echo "=============================================================="
if [[ "${#FALLIDOS[@]}" -gt 0 ]]; then
    log_aviso "Modelos con problemas:"
    for m in "${FALLIDOS[@]}"; do
        echo "  - ${m}"
    done
else
    log_ok "Todos los modelos del modo '${MODO}' están descargados."
fi
echo
log_info "Modelos instalados actualmente:"
ollama list
