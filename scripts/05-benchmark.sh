#!/usr/bin/env bash
#
# 05-benchmark.sh
# Ejecuta un benchmark de generación sobre los modelos instalados y guarda
# los resultados en benchmarks/benchmark_YYYYMMDD_HHMMSS.csv.
#
# Para cada modelo se llama a POST /api/generate con un prompt fijo en
# español y stream:false, y se calculan los tokens/segundo a partir de
# eval_count / eval_duration de la respuesta JSON (parseada con python3).
#
# Uso:
#   ./05-benchmark.sh                 # todos los modelos instalados
#   ./05-benchmark.sh qwen3:14b       # un solo modelo
#   ./05-benchmark.sh qwen3:14b qwen3:30b
#
# Repite este benchmark tras cada cambio de hardware (p. ej. al pasar de la
# RTX 3080 a una 5070 Ti o 5090) para tener cifras comparables.
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
DIR_BENCH="${REPO_DIR}/benchmarks"
mkdir -p "${DIR_BENCH}"

API_URL="http://localhost:11434/api/generate"
# Prompt fijo en español: el mismo en todos los benchmarks para que las
# cifras sean comparables entre GPUs y entre fechas.
PROMPT="Explica la fotosíntesis en unas 200 palabras, dirigido a un estudiante de secundaria. Incluye qué elementos necesita la planta, qué produce y por qué es importante para la vida en la Tierra."

echo "=============================================================="
echo "  Benchmark de generación - rig-ia"
echo "=============================================================="
echo

# ---------------------------------------------------------------------------
# Comprobaciones previas
# ---------------------------------------------------------------------------
if ! curl -fsS http://localhost:11434/api/version >/dev/null 2>&1; then
    log_error "La API de Ollama no responde en localhost:11434."
    log_error "Revisa el servicio con: systemctl status ollama.service"
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    log_error "python3 no está disponible (debería estarlo en Ubuntu). Es necesario para parsear el JSON."
    exit 1
fi

# Datos de GPU para el CSV (si no hay nvidia-smi se anota y se sigue: el
# benchmark también sirve para medir rendimiento en CPU).
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    GPU_INFO="$(nvidia-smi --query-gpu=name,memory.total,memory.used --format=csv,noheader,nounits | head -n1)"
    GPU_NOMBRE="$(echo "${GPU_INFO}" | cut -d, -f1 | xargs)"
    VRAM_TOTAL="$(echo "${GPU_INFO}" | cut -d, -f2 | xargs)"
    VRAM_USADA="$(echo "${GPU_INFO}" | cut -d, -f3 | xargs)"
    log_ok "GPU: ${GPU_NOMBRE} (${VRAM_USADA}/${VRAM_TOTAL} MB de VRAM en uso)"
else
    GPU_NOMBRE="sin-gpu"
    VRAM_TOTAL="0"
    VRAM_USADA="0"
    log_aviso "nvidia-smi no disponible: el benchmark correrá sobre CPU."
fi

# ---------------------------------------------------------------------------
# Lista de modelos a medir
# ---------------------------------------------------------------------------
if [[ "$#" -gt 0 ]]; then
    MODELOS=("$@")
else
    log_info "Sin argumentos: se medirán todos los modelos instalados."
    mapfile -t MODELOS < <(ollama list | awk 'NR>1 {print $1}')
fi

# Los modelos de embeddings no generan texto (usan /api/embed): excluirlos
MODELOS_FILTRADOS=()
for m in "${MODELOS[@]:-}"; do
    [[ -z "${m}" ]] && continue
    if [[ "${m}" == *embed* ]]; then
        log_aviso "${m}: es un modelo de embeddings; no aplica benchmark de generación. Se omite."
    else
        MODELOS_FILTRADOS+=("${m}")
    fi
done
MODELOS=("${MODELOS_FILTRADOS[@]:-}")

if [[ "${#MODELOS[@]}" -eq 0 ]] || [[ -z "${MODELOS[0]:-}" ]]; then
    log_error "No hay modelos de generación instalados. Ejecuta primero scripts/04-descargar-modelos.sh."
    exit 1
fi
log_info "Modelos a medir: ${MODELOS[*]}"
echo

# ---------------------------------------------------------------------------
# Preparar el CSV de salida
# ---------------------------------------------------------------------------
FECHA="$(date +%Y%m%d_%H%M%S)"
CSV="${DIR_BENCH}/benchmark_${FECHA}.csv"
echo "fecha,modelo,gpu,vram_total_mb,vram_usada_mb,eval_count,duracion_s,tokens_por_segundo" > "${CSV}"
log_info "Resultados en: ${CSV}"
echo

# ---------------------------------------------------------------------------
# Ejecutar el benchmark
# ---------------------------------------------------------------------------
for modelo in "${MODELOS[@]}"; do
    log_info "Midiendo ${modelo} ..."

    PAYLOAD="$(python3 -c 'import json,sys; print(json.dumps({"model": sys.argv[1], "prompt": sys.argv[2], "stream": False}, ensure_ascii=False))' "${modelo}" "${PROMPT}")"

    if ! RESPUESTA="$(curl -fsS -X POST "${API_URL}" -H "Content-Type: application/json" -d "${PAYLOAD}")"; then
        log_error "La API falló para ${modelo}. ¿Está descargado? (ollama pull ${modelo})"
        continue
    fi

    # Parsear el JSON, añadir la fila al CSV e imprimir el resumen por pantalla.
    # La respuesta viaja por la variable de entorno RESPUESTA_JSON para no
    # mezclar canales con el código python.
    RESULTADO="$(RESPUESTA_JSON="${RESPUESTA}" python3 - "${modelo}" "${GPU_NOMBRE}" "${VRAM_TOTAL}" "${VRAM_USADA}" "${CSV}" <<'PYEOF'
import json
import os
import sys
from datetime import datetime

modelo, gpu, vram_total, vram_usada, csv_path = sys.argv[1:6]
datos = json.loads(os.environ["RESPUESTA_JSON"])

eval_count = int(datos.get("eval_count", 0))
eval_duration_ns = int(datos.get("eval_duration", 0))
duracion_s = eval_duration_ns / 1e9
tps = eval_count / duracion_s if duracion_s > 0 else 0.0
fecha = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

fila = f"{fecha},{modelo},{gpu},{vram_total},{vram_usada},{eval_count},{duracion_s:.2f},{tps:.2f}"
with open(csv_path, "a", encoding="utf-8") as f:
    f.write(fila + "\n")

print(f"{eval_count} tokens | {duracion_s:.2f} s | {tps:.2f} tok/s")
PYEOF
)"
    log_ok "${modelo}: ${RESULTADO}"
done

echo
echo "=============================================================="
echo "  RESULTADOS DEL BENCHMARK"
echo "=============================================================="
column -s, -t "${CSV}" 2>/dev/null || cat "${CSV}"
echo
log_ok "CSV guardado en: ${CSV}"
echo
log_aviso "Recuerda: repite este benchmark tras cada cambio de hardware"
log_aviso "(nueva GPU, otro driver, etc.) para poder comparar las cifras."
