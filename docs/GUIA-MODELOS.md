# Guía de modelos — qué usar para qué (y qué NO pedirles)

> La regla de oro: **ningún LLM local lo hace todo**. Cada modelo tiene una especialidad.
> Elegir el modelo correcto para cada tarea es más importante que elegir el modelo más grande.

## 1. Conceptos rápidos

### Denso vs MoE
- **Denso**: todos los parámetros trabajan en cada token. Más grande = más lento. Al quedarse sin VRAM → se desploma (acantilado).
- **MoE** (Mixture of Experts): tiene muchos parámetros totales, pero solo activa unos pocos por token (los "expertos" relevantes). Resultado: calidad de modelo grande con velocidad de modelo chico. Ideal para GPUs con poca VRAM como nuestra 3080 10GB.

### Velocidad vs Inteligencia (¡no son lo mismo!)
- El **hardware compra velocidad**: una GPU mejor hace que el MISMO modelo responda más rápido.
- La **inteligencia la pone el modelo**: su tamaño, arquitectura y datos de entrenamiento.
- Un llama3.3:70b corriendo a velocidad infinita **sigue sin ser GPT-4** — los modelos frontera tienen 1T+ parámetros. Nuestro 70b local es comparable a modelos de nube de gama media, no a los frontera.
- Conclusión: para tareas diarias, un MoE 30B local es sorprendentemente bueno; para problemas realmente duros, la nube sigue ganando (y no pasa nada, cada cosa para lo suyo).

## 2. Tu zoológico, modelo por modelo

Velocidades medidas en TU rig (benchmark 2026-07-26, RTX 3080):

| Modelo | Tipo | Velocidad | ✅ Úsalo para... | ❌ NO le pidas... |
|---|---|---|---|---|
| `qwen3:30b` | MoE (3B activos) | 54.9 tok/s | **Chat general por defecto**: redacción, resúmenes, traducción, ideas | — |
| `qwen3-coder:30b` | MoE (3B activos) | 54.4 tok/s | **Programación**: escribir, explicar y depurar código | Ver imágenes (es ciego) |
| `gpt-oss:20b` | MoE (3.6B activos) | 62.3 tok/s | **Tareas agénticas**: planes de varios pasos, uso de herramientas | — |
| `gemma4:e4b` | Eficiente + visión | 127.0 tok/s | **TODO lo que tenga imágenes**: describir, preguntar sobre fotos, leer texto en pantallas | Generar/editar imágenes |
| `qwen3:8b` | Denso | 115.8 tok/s | Respuestas rápidas y simples, pruebas | Problemas complejos |
| `qwen3:14b` | Denso | 39.5 tok/s | Chat general con más calidad que el 8b | — |
| `deepseek-r1:14b` | Denso razonador | 38.7 tok/s | **Lógica y matemáticas**: piensa paso a paso (verás su cadena de razonamiento) | Rapidez (piensa mucho antes de responder) |
| `qwen3.6:27b` | Denso | 5.8 tok/s | Comparación de calidad en benchmarks | Uso diario (acantilado VRAM) |
| `llama3.3:70b` | Denso | 0.21 tok/s | **Solo experimento** de la escalera | Todo lo demás por ahora |
| `nomic-embed-text` | Embeddings | N/A | RAG: buscar en TUS documentos desde WebUI | Conversar (no es un chat) |

## 3. Regla rápida de selección

```
¿Trae imagen?           → gemma4:e4b
¿Es código?             → qwen3-coder:30b
¿Matemática/lógica?     → deepseek-r1:14b
¿Tarea de varios pasos? → gpt-oss:20b
¿Necesitas velocidad?   → qwen3:8b
¿Todo lo demás?         → qwen3:30b  ← tu default
```

## 4. Lo que NINGÚN modelo de Ollama puede hacer (limitaciones del stack)

| Pedido típico | Por qué falla | Solución |
|---|---|---|
| "Edita esta foto" / "genera una imagen" | Los LLM solo devuelven TEXTO | Fase 4.5: ComfyUI + modelo de difusión |
| "¿Qué pasó hoy en las noticias?" | Sin internet, corte de conocimiento | Activar búsqueda web en WebUI (opcional) |
| "Recuerda esto para siempre" | Sin memoria entre chats | Memoria de WebUI (opcional) |
| "Resume este PDF de 300 páginas" | Contexto limitado | RAG con nomic-embed-text |

## 5. Convención de nombres en el selector de WebUI

El dropdown de WebUI muestra solo `nombre:tamaño`, así que renombramos a nivel de interfaz
(Panel de administración → Configuración → Modelos → ✏️ → Nombre). Es cosmético: Ollama y los scripts no se ven afectados.

- **🟢 = uso diario** (respuesta útil y fluida en la 3080): qwen3:30b (chat general), qwen3-coder:30b (código), gpt-oss:20b (agentes), gemma4:e4b (visión), deepseek-r1:14b (razonamiento), qwen3:14b y qwen3:8b (densos rápidos)
- **🧪 = laboratorio/benchmark** (lentos por diseño): qwen3.6:27b, llama3.3:70b
- **nomic-embed-text: oculto** del selector (toggle off) — sigue instalado para RAG
- Predeterminado para chats nuevos: 🟢 qwen3:30b (Configuración → General → Modelo predeterminado)
- Al fichar un modelo nuevo: mismo ritual (emoji + especialidad entre paréntesis), 30 segundos.

## 6. Criterio para futuros modelos

Cuando salga un modelo nuevo y te tiente instalarlo:
1. **¿Es MoE con ≤4B parámetros activos?** → correrá fluido en la 3080. Candidato.
2. **¿Qué especialidad cubre?** → si ya tienes esa cubierta, hazle benchmark al duelo: nuevo vs actual, gana el mejor (`./setup.sh` opción 5 y 7), `ollama rm` al perdedor.
3. **¿Es denso de >14B?** → en la 3080 será lento; espera a la futura GPU (Fase 5).
