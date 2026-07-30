#!/usr/bin/env bash
# =============================================================================
# 09-instalar-comfyui.sh — FASE 4.5: generación/edición de IMÁGENES local
#
#   Instala ComfyUI + soporte GGUF y descarga Qwen-Image-Edit-2509 cuantizado
#   (edición por instrucción: "cambia el fondo por la bahía de Bahía Inglesa").
#
#   Calibrado para RTX 3080 10GB + 32GB RAM:
#     - Modelo edición Q3_K_M (~9.8GB)  → VRAM (rápido)
#     - Modelo edición Q4_K_M (~13GB)   → VRAM + offload RAM (máxima calidad)
#     - Encoder Qwen2.5-VL-7B Q4 (~4.4GB) → RAM (offload)
#     - LoRA Lightning 4/8 pasos → velocidad ×5
#   Archivos verificados en HuggingFace (julio 2026). Total descarga: ~28GB.
#
# Uso:  bash scripts/09-instalar-comfyui.sh
# Luego: cd ~/ComfyUI && ./venv/bin/python main.py --listen 0.0.0.0 --port 8188
#        Abrir: http://172.16.16.70:8188
# =============================================================================
set -euo pipefail

APP_DIR="$HOME/ComfyUI"
MODELS_DIR="/models/comfyui"

echo "==> Paquetes base"
sudo apt update
sudo apt install -y git wget python3-venv python3-pip

echo "==> Carpetas de modelos en el Netac ($MODELS_DIR)"
sudo mkdir -p "$MODELS_DIR"/{unet,text_encoders,vae,loras}
sudo chown -R "$USER":"$USER" "$MODELS_DIR"

echo "==> Clonando ComfyUI en $APP_DIR"
[[ -d "$APP_DIR" ]] || git clone https://github.com/comfyanonymous/ComfyUI "$APP_DIR"
cd "$APP_DIR"
git pull || true

echo "==> Entorno virtual + PyTorch CUDA"
[[ -d venv ]] || python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
./venv/bin/pip install -r requirements.txt

echo "==> Nodo ComfyUI-GGUF (soporte de modelos cuantizados)"
[[ -d custom_nodes/ComfyUI-GGUF ]] || git clone https://github.com/city96/ComfyUI-GGUF custom_nodes/ComfyUI-GGUF
./venv/bin/pip install -r custom_nodes/ComfyUI-GGUF/requirements.txt

echo "==> extra_model_paths.yaml (los modelos viven en el Netac)"
cat > extra_model_paths.yaml <<EOF
rig_netac:
  base_path: $MODELS_DIR/
  unet: unet
  text_encoders: text_encoders
  vae: vae
  loras: loras
EOF

dl() { # url destino
  local url="$1" dst="$2"
  if [[ -s "$dst" ]]; then
    echo "    ✓ ya existe: $(basename "$dst")"
  else
    echo "    ↓ $(basename "$dst") ..."
    wget -c -q --show-progress -O "$dst" "$url"
  fi
}

echo "==> Descargando modelos (~28GB; con tu fibra ≈ 5-7 min)"
dl "https://huggingface.co/QuantStack/Qwen-Image-Edit-2509-GGUF/resolve/main/Qwen-Image-Edit-2509-Q3_K_M.gguf" \
   "$MODELS_DIR/unet/Qwen-Image-Edit-2509-Q3_K_M.gguf"
# Q4_K_M (~13GB): más calidad, corre en 10GB con offload a RAM — para el duelo A/B vs Q3
dl "https://huggingface.co/QuantStack/Qwen-Image-Edit-2509-GGUF/resolve/main/Qwen-Image-Edit-2509-Q4_K_M.gguf" \
   "$MODELS_DIR/unet/Qwen-Image-Edit-2509-Q4_K_M.gguf"
dl "https://huggingface.co/unsloth/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/Qwen2.5-VL-7B-Instruct-Q4_0.gguf" \
   "$MODELS_DIR/text_encoders/Qwen2.5-VL-7B-Instruct-Q4_0.gguf"
# mmproj OBLIGATORIO (sin él, error mat1/mat2); renombrado para que el loader lo encuentre
dl "https://huggingface.co/unsloth/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/mmproj-F16.gguf" \
   "$MODELS_DIR/text_encoders/Qwen2.5-VL-7B-Instruct-mmproj-F16.gguf"
dl "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors" \
   "$MODELS_DIR/vae/qwen_image_vae.safetensors"
dl "https://huggingface.co/lightx2v/Qwen-Image-Lightning/resolve/main/Qwen-Image-Edit-2509/Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors" \
   "$MODELS_DIR/loras/Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors"
dl "https://huggingface.co/lightx2v/Qwen-Image-Lightning/resolve/main/Qwen-Image-Edit-2509/Qwen-Image-Edit-2509-Lightning-8steps-V1.0-bf16.safetensors" \
   "$MODELS_DIR/loras/Qwen-Image-Edit-2509-Lightning-8steps-V1.0-bf16.safetensors"

echo
echo "🎉 Instalación completa. Para arrancar ComfyUI:"
echo "   cd $APP_DIR && ./venv/bin/python main.py --listen 0.0.0.0 --port 8188"
echo "   Luego abre en el navegador:  http://172.16.16.70:8188"
