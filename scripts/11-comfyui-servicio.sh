#!/usr/bin/env bash
# =============================================================
# 11-comfyui-servicio.sh — ComfyUI como servicio systemd
# Para que el motor de imágenes arranque SOLO con Ubuntu.
# También verifica que open-webui (Docker) tenga restart policy.
# Uso: bash 11-comfyui-servicio.sh
# =============================================================
set -euo pipefail

COMFY_DIR="$HOME/ComfyUI"
SERVICE=/etc/systemd/system/comfyui.service

if [ ! -f "$COMFY_DIR/main.py" ]; then
  echo "ERROR: no encuentro $COMFY_DIR/main.py — corre primero 09-instalar-comfyui.sh"
  exit 1
fi

echo "==> Deteniendo ComfyUI manual si está corriendo (libera el puerto 8188)..."
pkill -f "main.py --listen 0.0.0.0 --port 8188" 2>/dev/null || true
sleep 2

echo "==> Creando unidad systemd $SERVICE ..."
sudo tee "$SERVICE" > /dev/null << EOF
[Unit]
Description=ComfyUI - motor local de edicion de imagenes (rig-ia)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$COMFY_DIR
ExecStart=$COMFY_DIR/venv/bin/python $COMFY_DIR/main.py --listen 0.0.0.0 --port 8188
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "==> Activando e iniciando el servicio..."
sudo systemctl daemon-reload
sudo systemctl enable --now comfyui
sleep 6
systemctl --no-pager --full status comfyui | head -12 || true

echo ""
echo "==> Verificando restart policy del contenedor open-webui..."
POLICY=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' open-webui 2>/dev/null || echo "no-encontrado")
echo "    open-webui restart policy: $POLICY"
if [ "$POLICY" = "no" ] || [ -z "$POLICY" ]; then
  docker update --restart unless-stopped open-webui
  echo "    -> actualizada a unless-stopped"
fi

echo ""
echo "Listo: ComfyUI arrancara solo con Ubuntu en http://172.16.16.70:8188"
echo "  Ver logs:      journalctl -u comfyui -f"
echo "  Detener:       sudo systemctl stop comfyui"
echo "  Desactivar:    sudo systemctl disable comfyui"
