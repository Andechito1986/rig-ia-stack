#!/usr/bin/env bash
#
# 03-instalar-docker-openwebui.sh
# Instala Docker Engine con el script oficial y despliega Open WebUI
# con docker compose. Open WebUI se conecta al Ollama del anfitrión
# (http://host.docker.internal:11434).
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

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USUARIO_RIG="${SUDO_USER:-$(whoami)}"

echo "=============================================================="
echo "  Instalación de Docker + despliegue de Open WebUI"
echo "=============================================================="
echo

# ---------------------------------------------------------------------------
# 1. Comprobar que Ollama está accesible (Open WebUI lo necesita)
# ---------------------------------------------------------------------------
log_info "Comprobando que Ollama responde en el anfitrión..."
if curl -fsS http://localhost:11434/api/version >/dev/null 2>&1; then
    log_ok "Ollama responde en localhost:11434."
else
    log_aviso "Ollama no responde en localhost:11434."
    log_aviso "Open WebUI se instalará igualmente, pero no tendrá modelos hasta que"
    log_aviso "Ollama esté en marcha (ejecuta scripts/02-instalar-ollama.sh)."
fi
echo

# ---------------------------------------------------------------------------
# 2. Instalar Docker con el script oficial
# ---------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1; then
    log_ok "Docker ya está instalado: $(docker --version)"
else
    log_info "Instalando Docker con el script oficial (https://get.docker.com)..."
    curl -fsSL https://get.docker.com | sudo sh
    log_ok "Docker instalado: $(docker --version)"
fi

log_info "Habilitando y arrancando el servicio docker..."
sudo systemctl enable --now docker >/dev/null 2>&1 || true
log_ok "Servicio docker activo."
echo

# ---------------------------------------------------------------------------
# 3. Añadir el usuario al grupo docker
# ---------------------------------------------------------------------------
log_info "Añadiendo el usuario '${USUARIO_RIG}' al grupo docker..."
if id -nG "${USUARIO_RIG}" | grep -qw docker; then
    log_ok "El usuario '${USUARIO_RIG}' ya pertenece al grupo docker."
else
    sudo usermod -aG docker "${USUARIO_RIG}"
    log_ok "Usuario añadido al grupo docker."
    log_aviso "IMPORTANTE: cierra y vuelve a abrir la sesión SSH para que el grupo"
    log_aviso "docker tenga efecto (o ejecuta: newgrp docker)."
fi
echo

# ---------------------------------------------------------------------------
# 4. Desplegar Open WebUI con docker compose
# ---------------------------------------------------------------------------
log_info "Desplegando Open WebUI con docker compose..."
cd "${REPO_DIR}"

# Usar sudo si la sesión actual aún no tiene el grupo docker activo
if docker info >/dev/null 2>&1; then
    DOCKER="docker"
else
    log_aviso "La sesión actual aún no tiene permisos sobre el socket de Docker; usando sudo."
    DOCKER="sudo docker"
fi

${DOCKER} compose pull
${DOCKER} compose up -d
log_ok "Contenedor open-webui en marcha."
echo

# ---------------------------------------------------------------------------
# 5. Verificación
# ---------------------------------------------------------------------------
log_info "Esperando a que Open WebUI responda en http://localhost:3000 ..."
INTENTOS=0
MAX_INTENTOS=30
until curl -fsS http://localhost:3000 >/dev/null 2>&1; do
    INTENTOS=$((INTENTOS + 1))
    if [[ "${INTENTOS}" -ge "${MAX_INTENTOS}" ]]; then
        log_error "Open WebUI no responde tras ${MAX_INTENTOS} intentos."
        log_error "Revisa los logs con: ${DOCKER} logs open-webui"
        exit 1
    fi
    sleep 2
done
log_ok "Open WebUI responde en http://localhost:3000"
echo
echo "=============================================================="
log_ok "Open WebUI desplegado."
echo "  - Acceso desde el rig:  http://localhost:3000"
echo "  - Acceso desde la LAN:  http://172.16.16.70:3000"
echo "  - La primera vez pedirá crear la cuenta de administrador."
echo
log_aviso "Recuerda: si acabas de entrar en el grupo docker, cierra y reabre"
log_aviso "la sesión SSH para poder usar 'docker' sin sudo."
