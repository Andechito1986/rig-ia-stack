# CONTEXTO — Proyecto rig-ia (pegar esto al inicio de cada sesión nueva)
> Actualizado: 2026-07-30, tras lograr la primera edición de imagen end-to-end.

## Quién soy y qué tengo
- Rig "rig-ia": B850 Gaming X WIFI6E, Ryzen 7 9700X, 32GB DDR5 6000, RTX 3080 10GB, fibra ~1Gbps.
- Ubuntu 26.04 LTS en SSD Netac 1TB, dual boot con Windows 11 Pro (RESUELTO: GRUB default Windows por ID osprober-efi-665B-D84F, menú 20s; F12 respaldo).
- Monitor en iGPU → la 3080 queda libre para IA.
- Red: rig en 172.16.16.70 (fija), SSH usuario `rig`.
- Repo: https://github.com/Andechito1986/rig-ia-stack (público, español). Usuario GitHub: Andechito1986.
- Plan maestro con todo el detalle: archivo `plan.md` (pedirle a Kimi que lo lea/actualice).

## Reglas de trabajo (no negociables)
- El que decide soy yo. Kimi sugiere, yo apruebo.
- Sin complacencia: decir las cosas como son, directo.
- Instrucciones paso a paso, clic por clic, en español. Nada de direcciones vagas de GUI.
- TODO opera dentro de la página de Open WebUI (todos los modelos, un solo lugar). Nada de apps/canvas separados para uso diario.

## Stack funcionando
- Ollama (systemd, modelos en /models/ollama) + Open WebUI (Docker, localhost:3000, restart unless-stopped).
- 10 modelos: escalera qwen3:14b / qwen3:30b / qwen3.6:27b / llama3.3:70b; zoo gpt-oss:20b, qwen3:8b, qwen3-coder:30b, gemma4:e4b (visión), deepseek-r1:14b, nomic-embed-text.
- Benchmark base completo en repo (benchmarks/benchmark_20260726_165759.csv). No borrar.

## F4.5 — Edición de imágenes local: FUNCIONA end-to-end (2026-07-30)
Cadena: chat WebUI → 🟢 gemma4:e4b (visión + capability "Generación de Imagen" + num_ctx 16384) → tool edit_image → ComfyUI (http://172.16.16.70:8188) → imagen editada de vuelta en el chat.
- Uso diario: chat nuevo → gemma4:e4b → 🖼️ ON → adjuntar foto → prompt → enviar.
- ComfyUI corre como SERVICIO systemd (arranque automático): `systemctl status comfyui`. Logs: `journalctl -u comfyui -f`.
- Config WebUI (Admin → Imágenes): motor ComfyUI en Crear y Editar; workflow `workflows/qwen-image-edit-2509-API-webui.json`; mapeo Edit: Image=image@78, Prompt=prompt@111, Model=unet_name@115; Crear: Prompt=prompt@111, Model=unet_name@115. Interruptor maestro ON, "Indicador para Generación de Imagen" OFF.
- Modelos ComfyUI: Qwen-Image-Edit-2509 GGUF Q3_K_M (unet), Qwen2.5-VL-7B Q4_0 + mmproj, qwen_image_vae, LoRA Lightning 8 pasos (modo rápido: 8 steps, cfg 1).
- Contingencia conocida: si gemma4 responde texto en vez de generar → config del modelo: "Modo de Llamada a Funciones" = Nativo.

## Pendiente inmediato (próxima sesión)
1. A/B de CALIDAD: el primer edit funcionó pero quedó "pegado" (sujetos con luz de día sobre atardecer, bordes duros). Modo calidad = unet Q4_K_M + LoRA Lightning bypass + steps 20-25 + cfg 2.5 (vía lienzo workflows/qwen-image-edit-2509-gguf-rig.json) + prompt con re-iluminación ("match sunset lighting, warm tones on the subjects"). Comparar vs modo rápido.

## Pendientes generales
- F3: headless total + Tailscale (acceso remoto fuera de casa).
- F4: OpenClaw endurecido (Telegram + allowlist, sin internet abierto).
- F5: upgrade GPU (5070 Ti/5090) → repetir benchmark y comparar CSV.
- Al final del proyecto: reactivar BitLocker en Windows (`manage-bde -protectors -enable C:`, tengo las claves).
- LCD Thermalright funcionando (TRCC vía pipx; detalle menor: RAM% muestra 0, desestimado).

## Mantenimiento
- Seguridad Ubuntu: automática. Modelos/Ollama/WebUI: ritual mensual manual (reproducibilidad benchmarks).
- NO `sudo apt autoremove` mientras el driver nvidia-firmware-595 funcione.
