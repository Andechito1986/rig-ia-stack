#!/usr/bin/env bash
#
# 07-comparar-benchmarks.sh
# Compara dos CSV de benchmark modelo a modelo y muestra la diferencia
# de rendimiento (tokens/segundo y % de cambio).
#
# Caso de uso típico: cambiaste la GPU (o el driver, o la RAM) y quieres
# ver cuánto mejoró cada modelo respecto a la medición anterior.
#
# Uso:
#   ./07-comparar-benchmarks.sh                        # compara los 2 CSV más recientes
#   ./07-comparar-benchmarks.sh ANTIGUO.csv NUEVO.csv  # compara esos dos archivos
#
# Flujo recomendado al cambiar de hardware:
#   1. Conserva el CSV viejo (p. ej. benchmarks/benchmark_20260726_165759.csv)
#   2. Con el hardware nuevo, ejecuta scripts/05-benchmark.sh
#   3. Ejecuta este script: los 2 CSV más recientes se comparan solos
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

# ---------------------------------------------------------------------------
# Elegir los dos CSV a comparar
# ---------------------------------------------------------------------------
if [[ "$#" -ge 2 ]]; then
    ANTIGUO="$1"
    NUEVO="$2"
elif [[ "$#" -eq 0 ]]; then
    mapfile -t CSVS < <(ls -t "${DIR_BENCH}"/benchmark_*.csv 2>/dev/null || true)
    if [[ "${#CSVS[@]}" -lt 2 ]]; then
        log_error "Se necesitan al menos 2 CSV en ${DIR_BENCH} para comparar."
        log_info "Ejecuta scripts/05-benchmark.sh en dos momentos (o con distinto hardware)."
        exit 1
    fi
    NUEVO="${CSVS[0]}"      # ls -t: el primero es el más reciente
    ANTIGUO="${CSVS[1]}"
    log_info "Sin argumentos: comparando los 2 CSV más recientes."
else
    log_error "Uso: $0 [ANTIGUO.csv NUEVO.csv]"
    exit 1
fi

for f in "${ANTIGUO}" "${NUEVO}"; do
    if [[ ! -f "${f}" ]]; then
        log_error "No existe el archivo: ${f}"
        exit 1
    fi
done

echo "=============================================================="
echo "  Comparación de benchmarks"
echo "=============================================================="
echo -e "  Antiguo (base):  ${C_AMARILLO}${ANTIGUO}${C_RESET}"
echo -e "  Nuevo (actual):  ${C_VERDE}${NUEVO}${C_RESET}"
echo

# ---------------------------------------------------------------------------
# Comparar con python3 (robusto ante columnas opcionales ausentes)
# ---------------------------------------------------------------------------
ANTIGUO_CSV="${ANTIGUO}" NUEVO_CSV="${NUEVO}" python3 <<'PYEOF'
import csv
import os

def leer_csv(ruta):
    """Devuelve dict modelo -> dict con tps, gpu, driver, ollama (última fila por modelo)."""
    modelos = {}
    with open(ruta, newline="", encoding="utf-8") as f:
        for fila in csv.DictReader(f):
            modelo = (fila.get("modelo") or "").strip()
            if not modelo:
                continue
            try:
                tps = float(fila.get("tokens_por_segundo") or 0)
            except ValueError:
                tps = 0.0
            modelos[modelo] = {
                "tps": tps,
                "gpu": (fila.get("gpu") or "?").strip(),
                # driver/ollama son columnas nuevas: CSVs antiguos pueden no tenerlas
                "driver": (fila.get("driver") or "-").strip(),
                "ollama": (fila.get("ollama") or "-").strip(),
            }
    return modelos

antiguo = leer_csv(os.environ["ANTIGUO_CSV"])
nuevo = leer_csv(os.environ["NUEVO_CSV"])

# Contexto de cada medición (de la primera fila disponible)
for etiqueta, datos in (("Antiguo", antiguo), ("Nuevo  ", nuevo)):
    if datos:
        muestra = next(iter(datos.values()))
        print(f"  {etiqueta}: GPU={muestra['gpu']}  driver={muestra['driver']}  ollama={muestra['ollama']}")
print()

todos = sorted(set(antiguo) | set(nuevo))
if not todos:
    print("No hay datos de modelos en los CSV.")
    raise SystemExit(1)

ancho = max(len(m) for m in todos)
print(f"  {'MODELO'.ljust(ancho)}  {'ANTES tok/s':>11}  {'AHORA tok/s':>11}  {'CAMBIO':>10}")
print(f"  {'-' * ancho}  {'-' * 11}  {'-' * 11}  {'-' * 10}")

for modelo in todos:
    a = antiguo.get(modelo)
    n = nuevo.get(modelo)
    tps_a = f"{a['tps']:.2f}" if a else "-"
    tps_n = f"{n['tps']:.2f}" if n else "-"
    if a and n and a["tps"] > 0:
        cambio = (n["tps"] - a["tps"]) / a["tps"] * 100
        signo = "+" if cambio >= 0 else ""
        marca = " 🚀" if cambio >= 20 else (" 🐢" if cambio <= -20 else "")
        cambio_s = f"{signo}{cambio:.1f}%{marca}"
    elif not a:
        cambio_s = "(nuevo)"
    else:
        cambio_s = "(ausente)"
    print(f"  {modelo.ljust(ancho)}  {tps_a:>11}  {tps_n:>11}  {cambio_s:>10}")

print()
solo_en_nuevo = set(nuevo) - set(antiguo)
solo_en_antiguo = set(antiguo) - set(nuevo)
if solo_en_nuevo:
    print("  Modelos solo en el benchmark nuevo:   " + ", ".join(sorted(solo_en_nuevo)))
if solo_en_antiguo:
    print("  Modelos solo en el benchmark antiguo: " + ", ".join(sorted(solo_en_antiguo)))
PYEOF

echo
log_ok "Comparación terminada."
log_aviso "Nota: los CSV de benchmarks antiguos pueden no tener columnas 'driver'/'ollama' (se muestran como '-')."
