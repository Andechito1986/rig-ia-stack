#!/usr/bin/env bash
#
# 02-instalar-ollama.sh
# Instala Ollama con el script oficial y lo configura como servicio systemd:
#   - OLLAMA_MODELS=/models/ollama (partición dedicada, si está montada)
#   - OLLAMA_HOST=0.0.0.0:11434 (accesible desde Docker y desde la LAN)
# Usa el drop-in config/ollama-override.conf de este repositorio.
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

# Ubuntu Desktop no incluye curl; el instalador de Ollama lo necesita
if ! command -v curl >/dev/null 2>&1; then
    log_aviso "curl no está instalado; instalándolo..."
    sudo apt update && sudo apt install -y curl
fi

# Directorio raíz del repositorio (un nivel por encima de scripts/)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERRIDE_FUENTE="${REPO_DIR}/config/ollama-override.conf"
OVERRIDE_DIR="/etc/systemd/system/ollama.service.d"
OVERRIDE_DESTINO="${OVERRIDE_DIR}/override.conf"

echo "=============================================================="
echo "  Instalación y configuración de Ollama"
echo "=============================================================="
echo

# ---------------------------------------------------------------------------
# 1. Instalar Ollama (si no está instalado ya)
# ---------------------------------------------------------------------------
if command -v ollama >/dev/null 2>&1; then
    log_ok "Ollama ya está instalado: $(ollama --version 2>/dev/null || echo 'versión desconocida')"
else
    log_info "Instalando Ollama con el script oficial (https://ollama.com/install.sh)..."
    curl -fsSL https://ollama.com/install.sh | sh
    log_ok "Ollama instalado."
fi
echo

# ---------------------------------------------------------------------------
# 2. Preparar el directorio de modelos
# ---------------------------------------------------------------------------
log_info "Preparando el directorio de modelos..."
if mountpoint -q /models; then
    DIR_MODELOS="/models/ollama"
    log_ok "/models está montada; los pesos irán en ${DIR_MODELOS}."
else
    DIR_MODELOS="/models/ollama"
    log_aviso "/models NO está montada. Se configurará igualmente OLLAMA_MODELS=${DIR_MODELOS},"
    log_aviso "pero caerá en el disco del sistema si la partición no se monta antes de descargar modelos."
    log_aviso "Revisa /etc/fstab y monta la partición dedicada antes de seguir si es posible."
fi

sudo mkdir -p "${DIR_MODELOS}"
# El servicio ollama se ejecuta con el usuario 'ollama' (creado por el instalador).
if id ollama >/dev/null 2>&1; then
    sudo chown -R ollama:ollama "${DIR_MODELOS}"
    log_ok "Propietario de ${DIR_MODELOS}: ollama:ollama"
else
    log_aviso "El usuario 'ollama' no existe todavía; se dejan los permisos por defecto."
fi
echo

# ---------------------------------------------------------------------------
# 3. Instalar el drop-in de systemd
# ---------------------------------------------------------------------------
log_info "Instalando la configuración de systemd (drop-in override)..."
if [[ ! -f "${OVERRIDE_FUENTE}" ]]; then
    log_error "No se encuentra ${OVERRIDE_FUENTE}. ¿Estás ejecutando el script desde el repo completo?"
    exit 1
fi

sudo mkdir -p "${OVERRIDE_DIR}"
sudo cp "${OVERRIDE_FUENTE}" "${OVERRIDE_DESTINO}"
log_ok "Drop-in copiado a ${OVERRIDE_DESTINO}"

# Si /models no está montada, avisar de que la variable apunta a una ruta del disco de sistema
if ! mountpoint -q /models; then
    log_aviso "Recuerda: OLLAMA_MODELS apunta a /models/ollama pero /models no está montada."
fi
echo

# ---------------------------------------------------------------------------
# 4. Recargar systemd y reiniciar el servicio
# ---------------------------------------------------------------------------
log_info "Recargando systemd y reiniciando ollama.service..."
sudo systemctl daemon-reload
sudo systemctl enable ollama.service >/dev/null 2>&1 || true
sudo systemctl restart ollama.service
sleep 2
echo

# ---------------------------------------------------------------------------
# 5. Verificación
# ---------------------------------------------------------------------------
log_info "Verificando la instalación..."
if systemctl is-active --quiet ollama.service; then
    log_ok "Servicio ollama.service activo."
else
    log_error "El servicio ollama.service no está activo. Revisa: journalctl -u ollama.service -n 50"
    exit 1
fi

if curl -fsS http://localhost:11434/api/version >/dev/null 2>&1; then
    VERSION_API="$(curl -fsS http://localhost:11434/api/version)"
    log_ok "API de Ollama respondiendo en http://localhost:11434 -> ${VERSION_API}"
else
    log_error "La API de Ollama no responde en localhost:11434."
    log_error "Revisa los logs con: journalctl -u ollama.service -n 50"
    exit 1
fi

log_ok "Versión del cliente: $(ollama --version)"
echo
log_ok "Ollama instalado y configurado. Siguiente paso: 03 (Docker + Open WebUI) o 04 (descargar modelos)."
