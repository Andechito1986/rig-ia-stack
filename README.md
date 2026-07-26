# rig-ia-stack

![Ubuntu](https://img.shields.io/badge/Ubuntu-26.04%20LTS-E95420?logo=ubuntu&logoColor=white)
![Ollama](https://img.shields.io/badge/Ollama-local%20LLM-000000)
![Docker](https://img.shields.io/badge/Docker-Open%20WebUI-2496ED?logo=docker&logoColor=white)
![GPU](https://img.shields.io/badge/GPU-RTX%203080%2010GB-76B900?logo=nvidia&logoColor=white)
![Licencia](https://img.shields.io/badge/licencia-MIT-green)

Stack de IA **100 % local** para el rig `rig-ia`: Ollama como servidor de modelos, Open WebUI como interfaz web y una batería de scripts para instalar, descargar modelos y hacer **benchmarks comparables entre GPUs**.

El objetivo es doble:

1. **Uso diario**: chat, código, visión y embeddings desde cualquier equipo de la red local (el rig funciona headless y se administra por SSH desde Windows).
2. **Benchmarks reproducibles**: una "escalera" fija de modelos medida con el mismo prompt, para comparar el rendimiento al cambiar de GPU en el futuro (RTX 5070 Ti, RTX 5090, …).

---

## Requisitos

| Componente | Detalle |
|---|---|
| Equipo | `rig-ia` — Ryzen 7 9700X, 32 GB RAM |
| SO | Ubuntu 26.04 LTS recién instalado |
| GPU | NVIDIA RTX 3080 10 GB (driver propietario) |
| Red | IP fija `172.16.16.70`, gateway `172.16.16.1` |
| Disco modelos | Partición dedicada ~780 GB montada en `/models` |
| Acceso | SSH desde Windows; el rig actúa como servidor headless |

Software que instalan los scripts: Ollama (script oficial), Docker Engine (script oficial `get.docker.com`) y Open WebUI (contenedor). Nada más.

---

## Los 10 modelos

Tags verificados contra [ollama.com/library](https://ollama.com/library) (julio 2026).

### Escalera de benchmark (comparable entre GPUs)

| Modelo | Tier | Tipo | Tamaño aprox. | Rol |
|---|---|---|---|---|
| `qwen3:14b` | 0 | Denso | ~9 GB | Base: cabe entero en los 10 GB de la 3080 |
| `qwen3:30b` | 25 | MoE (3B activos) | ~19 GB | MoE eficiente, buen tok/s incluso con offload |
| `qwen3.6:27b` | 50 | Denso | ~17 GB | Qwen 3.6 (abr 2026): el mejor denso para hardware de consumo; fuerza offload en la 3080 |
| `llama3.3:70b` | 100 | Denso | ~43 GB | Estrés: mayoritariamente en CPU/RAM |

> El tier es la puntuación de referencia de la escalera: sirve para construir un índice compuesto al comparar GPUs (p. ej. tok/s normalizados por tier).

### Zoo de uso diario

| Modelo | Tipo | Tamaño aprox. | Rol |
|---|---|---|---|
| `gpt-oss:20b` | MoE, MXFP4 | ~14 GB | Daily driver generalista |
| `qwen3:8b` | Denso | ~5 GB | Respuestas rápidas |
| `qwen3-coder:30b` | MoE | ~19 GB | Programación |
| `gemma4:e4b` | Multimodal + tool calling | ~6 GB | Visión y base para agentes (Fase 4: OpenClaw) |
| `deepseek-r1:14b` | Denso | ~9 GB | Razonamiento paso a paso |
| `nomic-embed-text` | Embeddings | ~274 MB | RAG / búsqueda semántica |

---

## Instalación paso a paso

```bash
git clone <url-del-repo> rig-ia-stack
cd rig-ia-stack
chmod +x setup.sh scripts/*.sh   # por si el bit de ejecución no se preservó
./setup.sh
```

`setup.sh` abre un menú numerado que muestra qué pasos ya están hechos y permite ejecutarlos en orden o todos de golpe:

1. **Verificar sistema** — GPU/VRAM con `nvidia-smi`, punto de montaje `/models`, espacio en disco y Secure Boot (`mokutil --sb-state`). Si falta el driver NVIDIA, ofrece `sudo ubuntu-drivers install` (requiere reinicio).
2. **Instalar Ollama** — script oficial + drop-in systemd (`config/ollama-override.conf`):
   - `OLLAMA_MODELS=/models/ollama` (los pesos van a la partición dedicada)
   - `OLLAMA_HOST=0.0.0.0:11434` (accesible desde Docker y desde la LAN)
3. **Instalar Docker + Open WebUI** — Docker con `get.docker.com`, usuario `rig` añadido al grupo `docker`, y `docker compose up -d` con el `docker-compose.yml` del repo.
4. **Descargar modelos** — submenú: `--minimo`, `--escalera`, `--zoo` o `--todo` (ver siguiente sección).
5. **Benchmark** — genera un CSV en `benchmarks/` con tok/s por modelo.
6. **Actualizar modelos** — pone al día todos los tags instalados (descarga delta; ver "Actualizar y rotar modelos").

También se puede ejecutar cada script por separado desde `scripts/`.

### Descarga de modelos (modos)

```bash
./scripts/04-descargar-modelos.sh --minimo     # qwen3:14b + gpt-oss:20b + nomic-embed-text
./scripts/04-descargar-modelos.sh --escalera   # los 4 de la escalera (70b pide confirmación)
./scripts/04-descargar-modelos.sh --zoo        # los 6 del zoo
./scripts/04-descargar-modelos.sh --todo       # todo, sin confirmaciones
./scripts/04-descargar-modelos.sh              # ayuda
```

`llama3.3:70b` (~43 GB) solo se descarga tras confirmación interactiva (o directamente con `--todo`), y siempre que haya ≥ 50 GB libres.

---

## Actualizar y rotar modelos

El rig está diseñado para que los modelos sean **fácilmente reemplazables**: a medida que salgan versiones mejores, puedes actualizar, probar y rotar sin rehacer nada.

### Cómo funcionan las actualizaciones en Ollama

- Un **tag** (p. ej. `qwen3:14b`) apunta siempre a la última *build* publicada por los mantenedores de la librería (mejoras de quant, plantillas de chat, correcciones).
- `ollama pull <tag>` descarga **solo las capas que cambiaron** (delta): actualizar es rápido y no duplica espacio.
- Las **nuevas generaciones** (p. ej. un futuro `qwen4`) llegan como tags *nuevos*: se instalan en paralelo con los actuales y conviven sin interferir.

### Actualizar lo instalado (opción 6 del menú)

```bash
./scripts/06-actualizar-modelos.sh              # todos los modelos instalados
./scripts/06-actualizar-modelos.sh qwen3:14b    # solo uno
./scripts/06-actualizar-modelos.sh --ollama     # además, actualiza el motor Ollama
```

Frecuencia sugerida: 1 vez al mes, o tras ver una novedad en [ollama.com/library?sort=newest](https://ollama.com/library?sort=newest) o en el [blog de Ollama](https://ollama.com/blog).

### Rotar: evaluar un modelo nuevo y jubilar el viejo

Cuando salga algo que prometa (ejemplo: un hipotético `qwen4:14b`):

```bash
# 1. Instalarlo EN PARALELO (no borra nada)
ollama pull qwen4:14b

# 2. Comparar rendimiento con el mismo benchmark
./scripts/05-benchmark.sh qwen3:14b qwen4:14b

# 3. Probar ambos en Open WebUI con tus prompts habituales (dropdown arriba)

# 4. Si el nuevo gana, jubilar el viejo y liberar espacio
ollama rm qwen3:14b
```

Para incorporarlo de forma permanente a la escalera o al zoo, edita los arrays `ESCALERA` / `ZOO` de `scripts/04-descargar-modelos.sh` (cada modelo tiene un comentario con su rol y tamaño).

> ⚠️ **Regla de oro de la escalera**: si cambias un modelo de la ESCALERA, repite el benchmark completo y anota el cambio en el nombre del CSV o en un comentario del commit — los CSV históricos solo son comparables mientras la escalera sea la misma.

---

## Uso diario

### Open WebUI (recomendado)

- Desde cualquier equipo de la red: **http://172.16.16.70:3000**
- La primera vez pide crear la cuenta de administrador (queda guardada en el volumen Docker `open-webui`).
- El modelo se cambia con el **desplegable de la parte superior** de la conversación. Los modelos disponibles son los que tengas descargados en Ollama.

### Terminal (por SSH)

```bash
ollama list                    # modelos instalados
ollama run qwen3:14b           # chat interactivo
ollama run gpt-oss:20b         # daily driver
ollama pull qwen3:8b           # descargar otro modelo
ollama rm llama3.3:70b         # liberar 43 GB
```

### API de Ollama (LAN)

La API está expuesta en `http://172.16.16.70:11434`, así que cualquier herramienta compatible con Ollama/OpenAI en la red local puede usar el rig como backend.

---

## Benchmarks: cómo interpretar el CSV

```bash
./scripts/05-benchmark.sh                 # todos los modelos instalados
./scripts/05-benchmark.sh qwen3:14b       # uno o varios modelos concretos
```

Cada ejecución crea `benchmarks/benchmark_YYYYMMDD_HHMMSS.csv` con estas columnas:

| Columna | Significado |
|---|---|
| `fecha` | Marca temporal de la medición |
| `modelo` | Tag de Ollama medido |
| `gpu` | Nombre de la GPU (de `nvidia-smi`) |
| `vram_total_mb` | VRAM total de la GPU |
| `vram_usada_mb` | VRAM en uso en el momento de la medición |
| `eval_count` | Tokens generados en la respuesta |
| `duracion_s` | Duración de la generación (`eval_duration`, en segundos) |
| `tokens_por_segundo` | `eval_count / eval_duration` — la métrica clave |

Cómo leerlo:

- **El prompt es fijo** (explicar la fotosíntesis en ~200 palabras), así que las cifras son comparables entre fechas y entre GPUs.
- `tokens_por_segundo` alto = mejor. En la RTX 3080 espera cifras altas en `qwen3:14b`/`qwen3:30b` (MoE) y un desplome en `qwen3.6:27b` y `llama3.3:70b` por el offload a CPU (solo hay 10 GB de VRAM).
- **Regla de oro**: tras cada cambio de hardware (nueva GPU, driver, etc.) vuelve a ejecutar el benchmark y conserva los CSV antiguos para comparar. Los CSV están en `.gitignore`: son datos locales de cada rig.
- Para comparar dos GPUs, compara el `tokens_por_segundo` de cada modelo de la **escalera** (mismos 4 modelos, mismo prompt).

---

## Solución de problemas

### `nvidia-smi` falla o "no devices found"
- Casi siempre es **Secure Boot**: el módulo NVIDIA sin firmar no carga. Compruébalo con `mokutil --sb-state`.
- Soluciones: desactivar Secure Boot en la BIOS, o registrar una clave MOK al instalar el driver.
- Reinstala el driver con `sudo ubuntu-drivers install` y **reinicia**.
- Logs del servicio: `journalctl -u ollama.service -n 50`.

### El puerto 3000 está ocupado
```bash
sudo ss -tlnp | grep 3000          # quién lo ocupa
```
Edita `docker-compose.yml` y cambia el mapeo, p. ej. `"3001:8080"`, y luego `docker compose up -d`.

### `permission denied` al usar `docker`
Acabas de ser añadido al grupo `docker`: **cierra y vuelve a abrir la sesión SSH** (o ejecuta `newgrp docker`). El paso 3 lo avisa al terminar.

### `/models` no existe o no está montada
- El paso 1 lo detecta y Ollama caerá a su ruta por defecto del sistema (`~/.ollama/models`), con el riesgo de llenar el disco raíz.
- Monta la partición dedicada y hazla persistente en `/etc/fstab`:
  ```bash
  lsblk -f                              # identifica la partición y su UUID
  sudo mkdir -p /models
  # añade a /etc/fstab:  UUID=<uuid>  /models  ext4  defaults  0  2
  sudo mount -a
  ```
- Después vuelve a ejecutar el paso 2 para crear `/models/ollama` con el propietario correcto (`ollama:ollama`).

### Open WebUI no ve los modelos
- Verifica que Ollama responde: `curl http://localhost:11434/api/version`.
- El compose usa `OLLAMA_BASE_URL=http://host.docker.internal:11434` con `extra_hosts: host-gateway`; funciona porque el drop-in pone `OLLAMA_HOST=0.0.0.0:11434`. Si cambiaste esa variable, Open WebUI no alcanzará la API.

---

## Roadmap

- [ ] **Mover el monitor a los gráficos integrados** (iGPU del 9700X) para liberar la VRAM que consume el escritorio y dejar los 10 GB enteros para inferencia.
- [ ] **Modo headless total + Tailscale**: quitar el monitor, acceso seguro desde fuera de casa sin abrir puertos en el router.
- [ ] **Fase 4 — OpenClaw**: desplegar el agente con `ollama launch openclaw` (integración nativa de Ollama) sobre los modelos ya instalados.
- [ ] **Upgrade de GPU (5070 Ti / 5090)**: al cambiarla, repetir `05-benchmark.sh` con la escalera completa y comparar los CSV contra la 3080 (más VRAM = menos offload = salto grande en `qwen3.6:27b` y `llama3.3:70b`).
- [ ] Automatizar benchmarks programados (cron/systemd timer) tras actualizaciones de driver o de Ollama.

---

## Estructura del repositorio

```
rig-ia-stack/
├── README.md
├── setup.sh                  # menú maestro interactivo (pasos 1-6)
├── docker-compose.yml        # Open WebUI (puerto 3000)
├── config/
│   └── ollama-override.conf  # drop-in systemd: OLLAMA_MODELS y OLLAMA_HOST
├── scripts/
│   ├── 01-verificar-sistema.sh
│   ├── 02-instalar-ollama.sh
│   ├── 03-instalar-docker-openwebui.sh
│   ├── 04-descargar-modelos.sh
│   ├── 05-benchmark.sh
│   └── 06-actualizar-modelos.sh
└── benchmarks/               # CSV de resultados (ignorados por git)
```

## Licencia

Sugerida: **MIT**. Úsalo, modifícalo y compártelo libremente.
