#!/usr/bin/env bash
# =============================================================================
# 08-personalizar-webui.sh — Personaliza el selector de Open WebUI vía API
#
#   • Renombra modelos: 🟢 uso diario (con especialidad) / 🧪 laboratorio
#   • Oculta nomic-embed-text del selector (sigue sirviendo RAG)
#   • Intenta fijar qwen3:30b como modelo predeterminado
#
# ES COSMÉTICO: Ollama y los scripts de benchmark/actualización no se afectan.
# Validado en campo contra WebUI 0.11.0: create/update con payload completo,
# delete = POST con body. Re-ejecutable: ante conflicto de id borra y recrea.
#
# Requisitos:
#   1. API key de WebUI (avatar → Configuración → Cuenta → Claves API → crear)
#      (si no aparece la sección: Ajustes de Admin → Autenticación → Habilitar Claves API)
#   2. export WEBUI_API_KEY="sk-..."   (o te la pedirá al ejecutar)
# Uso:
#   bash scripts/08-personalizar-webui.sh
# =============================================================================
set -uo pipefail

WEBUI_URL="${WEBUI_URL:-http://localhost:3000}"
API_KEY="${WEBUI_API_KEY:-}"

if [[ -z "$API_KEY" ]]; then
  read -rsp "🔑 Pega tu API key de WebUI: " API_KEY
  echo
fi

# id_ollama|nombre_visible
RENOMBRAR=(
  "qwen3:30b|🟢 qwen3:30b — chat general (MoE)"
  "qwen3-coder:30b|🟢 qwen3-coder:30b — código (MoE)"
  "gpt-oss:20b|🟢 gpt-oss:20b — agentes (MoE)"
  "gemma4:e4b|🟢 gemma4:e4b — visión/fotos"
  "deepseek-r1:14b|🟢 deepseek-r1:14b — razonamiento"
  "qwen3:14b|🟢 qwen3:14b — chat denso"
  "qwen3:8b|🟢 qwen3:8b — rápido/liviano"
  "qwen3.6:27b|🧪 qwen3.6:27b — benchmark tier 50"
  "llama3.3:70b|🧪 llama3.3:70b — benchmark tier 100"
)
OCULTAR=("nomic-embed-text:latest" "nomic-embed-text")
DEFAULT_MODEL="qwen3:30b"

urlenc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }

# api METODO PATH [BODY] → imprime http_code
api() {
  curl -s -o /tmp/webui_api_resp.json -w "%{http_code}" -X "$1" \
    -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
    "$WEBUI_URL$2" ${3:+-d "$3"}
}

upsert_model() { # id, nombre, extra_json
  local id="$1" name="$2" extra="${3:-}" q body code
  q=$(urlenc "$id")
  body=$(python3 -c '
import json,sys
# Payload validado contra WebUI 0.11.0: base_model_id=null + params/meta completos
d={"id":sys.argv[1],"name":sys.argv[2],"base_model_id":None,"params":{},"meta":{"tags":[]},"is_active":True}
if len(sys.argv)>3 and sys.argv[3]: d.update(json.loads(sys.argv[3]))
print(json.dumps(d))' "$id" "$name" "$extra")
  code=$(api POST "/api/v1/models/model/update?id=$q" "$body")
  [[ "$code" == "200" ]] && return 0
  code=$(api POST "/api/v1/models/create" "$body")
  [[ "$code" == "200" ]] && return 0
  # Conflicto: ya existe una fila con ese id → borrar y recrear
  # (delete validado en WebUI 0.11.0: es POST y exige body)
  api POST "/api/v1/models/model/delete?id=$q" "$body" >/dev/null
  code=$(api POST "/api/v1/models/create" "$body")
  [[ "$code" == "200" ]]
}

echo "==> Verificando API key contra $WEBUI_URL ..."
code=$(api GET "/api/v1/models/")
if [[ "$code" != "200" ]]; then
  echo "❌ No autentica (HTTP $code). Revisa la API key o WEBUI_URL."; exit 1
fi
echo "    OK"

echo "==> Renombrando modelos..."
fallos=0
for par in "${RENOMBRAR[@]}"; do
  id="${par%%|*}"; nombre="${par#*|}"
  if upsert_model "$id" "$nombre"; then
    echo "    ✅ $nombre"
  else
    echo "    ❌ FALLÓ $id (renómbralo a mano: Admin → Configuración → Modelos)"
    fallos=$((fallos+1))
  fi
done

echo "==> Ocultando embeddings del selector..."
oculto=0
for id in "${OCULTAR[@]}"; do
  q=$(urlenc "$id")
  code=$(api POST "/api/v1/models/model/toggle?id=$q")
  if [[ "$code" == "200" ]]; then echo "    ✅ $id oculto"; oculto=1; break; fi
  if upsert_model "$id" "nomic-embed-text (embeddings — no chateable)" '{"is_active":false}'; then
    echo "    ✅ $id oculto (vía is_active)"; oculto=1; break
  fi
done
[[ $oculto -eq 0 ]] && echo "    ⚠️  No se pudo ocultar por API: hazlo a mano (toggle en Admin → Modelos)"

echo "==> Fijando modelo predeterminado ($DEFAULT_MODEL)..."
code=$(api POST "/api/v1/configs/models" "{\"DEFAULT_MODELS\":\"$DEFAULT_MODEL\"}")
if [[ "$code" == "200" ]]; then
  echo "    ✅ Predeterminado fijado"
else
  echo "    ⚠️  No por API: avatar → Configuración → General → Modelo predeterminado → $DEFAULT_MODEL"
fi

echo
if [[ $fallos -eq 0 ]]; then
  echo "🎉 Listo. Recarga la WebUI (F5) y abre el selector: 🟢 arriba, 🧪 abajo."
else
  echo "⚠️  $fallos modelo(s) no se pudieron renombrar por API (versión de WebUI distinta)."
  echo "    Solución manual: Panel de administración → Configuración → Modelos → ✏️ → Nombre."
fi
