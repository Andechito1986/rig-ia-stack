#!/usr/bin/env bash
#
# 01-verificar-sistema.sh
# Comprueba que el rig está listo para el stack de IA local:
#   - Driver NVIDIA y GPU (modelo + VRAM)
#   - Punto de montaje /models para los pesos de los modelos
#   - Espacio libre en disco
#   - Estado de Secure Boot (los módulos NVIDIA sin firmar no cargan con SB activo)
# Termina con un resumen OK/KO de cada comprobación.
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

# ---------------------------------------------------------------------------
# Comprobación de entorno
# ---------------------------------------------------------------------------
if [[ "$(uname -s)" != "Linux" ]]; then
    log_error "Este script solo funciona en Linux (detectado: $(uname -s))."
    exit 1
fi
if [[ -z "${BASH_VERSION:-}" ]]; then
    log_error "Este script requiere bash. Ejecuta: bash $0"
    exit 1
fi

# Contadores para el resumen final
declare -a RESUMEN_OK=()
declare -a RESUMEN_KO=()

marca_ok() { RESUMEN_OK+=("$1"); }
marca_ko() { RESUMEN_KO+=("$1"); }

echo "=============================================================="
echo "  Verificación del sistema - rig-ia (stack de IA local)"
echo "=============================================================="
echo

# ---------------------------------------------------------------------------
# 1. Driver NVIDIA / nvidia-smi
# ---------------------------------------------------------------------------
log_info "Comprobando driver NVIDIA (nvidia-smi)..."
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    GPU_NOMBRE="$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)"
    VRAM_MB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)"
    DRIVER_VER="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)"
    log_ok "GPU detectada: ${GPU_NOMBRE}"
    log_ok "VRAM total: ${VRAM_MB} MB"
    log_ok "Versión del driver: ${DRIVER_VER}"
    marca_ok "Driver NVIDIA (${GPU_NOMBRE}, ${VRAM_MB} MB VRAM)"
else
    log_error "nvidia-smi no funciona o no está instalado."
    log_aviso "El driver propietario de NVIDIA es imprescindible para usar la GPU."
    if command -v ubuntu-drivers >/dev/null 2>&1; then
        echo
        read -r -p "¿Quieres instalar el driver recomendado ahora con 'sudo ubuntu-drivers install'? [s/N] " respuesta
        if [[ "${respuesta}" =~ ^[sS]$ ]]; then
            sudo ubuntu-drivers install
            log_aviso "Driver instalado. ES NECESARIO REINICIAR el equipo para que cargue."
            log_aviso "Tras reiniciar, vuelve a ejecutar este script."
            marca_ko "Driver NVIDIA (instalado, pendiente de reinicio)"
        else
            log_aviso "Puedes instalarlo más tarde con: sudo ubuntu-drivers install"
            log_aviso "Recuerda que habrá que reiniciar después de instalarlo."
            marca_ko "Driver NVIDIA (no instalado)"
        fi
    else
        log_aviso "No se encontró 'ubuntu-drivers'. Instala el driver manualmente:"
        log_aviso "  sudo apt update && sudo apt install nvidia-driver-XXX"
        marca_ko "Driver NVIDIA (no instalado)"
    fi
fi
echo

# ---------------------------------------------------------------------------
# 2. Punto de montaje /models
# ---------------------------------------------------------------------------
log_info "Comprobando la partición dedicada /models..."
if mountpoint -q /models; then
    TAMANO="$(df -h /models | awk 'NR==2 {print $2}')"
    LIBRE="$(df -h /models | awk 'NR==2 {print $4}')"
    log_ok "/models está montada (tamaño: ${TAMANO}, libre: ${LIBRE})"
    marca_ok "Partición /models montada (${LIBRE} libres)"
elif [[ -d /models ]]; then
    log_aviso "El directorio /models existe pero NO es un punto de montaje."
    log_aviso "Los modelos se guardarían en el disco del sistema. Revisa /etc/fstab."
    marca_ko "/models no es punto de montaje (los modelos irían al disco del sistema)"
else
    log_aviso "/models no existe. Se usará la ruta por defecto de Ollama (~/.ollama/models)."
    log_aviso "Cuando montes la partición dedicada, el script 02 configurará OLLAMA_MODELS=/models/ollama."
    marca_ko "/models no existe (se usará la ruta por defecto de Ollama)"
fi
echo

# ---------------------------------------------------------------------------
# 3. Espacio en disco
# ---------------------------------------------------------------------------
log_info "Comprobando espacio libre en disco..."
# Mínimo recomendado: 60 GB libres donde vayan a vivir los modelos
MIN_GB=60
if mountpoint -q /models; then
    DISCO_OBJETIVO="/models"
else
    DISCO_OBJETIVO="${HOME}"
fi
LIBRE_GB="$(df -BG "${DISCO_OBJETIVO}" | awk 'NR==2 {gsub("G","",$4); print $4}')"
if [[ "${LIBRE_GB}" -ge "${MIN_GB}" ]]; then
    log_ok "Espacio libre en ${DISCO_OBJETIVO}: ${LIBRE_GB} GB (mínimo recomendado: ${MIN_GB} GB)"
    marca_ok "Espacio en disco (${LIBRE_GB} GB libres en ${DISCO_OBJETIVO})"
else
    log_error "Solo quedan ${LIBRE_GB} GB libres en ${DISCO_OBJETIVO} (recomendado: >= ${MIN_GB} GB)."
    marca_ko "Espacio en disco insuficiente (${LIBRE_GB} GB libres)"
fi
echo

# ---------------------------------------------------------------------------
# 4. Secure Boot
# ---------------------------------------------------------------------------
log_info "Comprobando estado de Secure Boot..."
if command -v mokutil >/dev/null 2>&1; then
    SB_ESTADO="$(mokutil --sb-state 2>/dev/null || true)"
    if echo "${SB_ESTADO}" | grep -qi "SecureBoot enabled"; then
        log_aviso "Secure Boot está ACTIVADO."
        log_aviso "Si nvidia-smi falla tras instalar el driver, probablemente el módulo"
        log_aviso "del kernel no está firmado. Opciones: desactivar Secure Boot en la BIOS"
        log_aviso "o registrar una clave MOK (mokutil --import)."
        marca_ok "Secure Boot activado (anotado: vigilar firma del driver NVIDIA)"
    else
        log_ok "Secure Boot desactivado o no soportado: ${SB_ESTADO}"
        marca_ok "Secure Boot desactivado"
    fi
else
    log_aviso "mokutil no está instalado; no se puede comprobar Secure Boot."
    log_aviso "Para comprobarlo manualmente: sudo apt install mokutil && mokutil --sb-state"
    marca_ok "Secure Boot no comprobado (falta mokutil)"
fi
echo

# ---------------------------------------------------------------------------
# 5. Extras informativos: RAM, CPU y herramientas útiles
# ---------------------------------------------------------------------------
log_info "Información adicional del sistema:"
RAM_GB="$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)"
CPU_MODEL="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
echo "  - CPU: ${CPU_MODEL}"
echo "  - RAM: ${RAM_GB} GB"
echo "  - Kernel: $(uname -r)"
echo "  - SO: $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-desconocido}")"
echo

# ---------------------------------------------------------------------------
# Resumen final
# ---------------------------------------------------------------------------
echo "=============================================================="
echo "  RESUMEN DE VERIFICACIÓN"
echo "=============================================================="
for item in "${RESUMEN_OK[@]:-}"; do
    [[ -n "${item}" ]] && log_ok "${item}"
done
for item in "${RESUMEN_KO[@]:-}"; do
    [[ -n "${item}" ]] && log_error "${item}"
done
echo

if [[ "${#RESUMEN_KO[@]}" -gt 0 ]]; then
    log_aviso "Hay ${#RESUMEN_KO[@]} punto(s) que revisar antes de continuar."
    exit 1
else
    log_ok "Sistema verificado. Puedes continuar con el paso 02 (instalar Ollama)."
fi
