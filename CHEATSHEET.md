# 🧠 CHEATSHEET — Operación del rig-ia (para no tener que recordar nada)

Hoja de referencia rápida. Si no usas el rig en meses, vuelve aquí: esto es todo lo que necesitas.

---

## 🔑 Accesos

| Qué | Dónde |
|---|---|
| **Interfaz web (uso diario)** | http://172.16.16.70:3000 (Open WebUI, desde cualquier PC/móvil de la red) |
| **SSH al rig** | `ssh rig@172.16.16.70` (desde PowerShell de Windows) |
| **API de Ollama** | http://172.16.16.70:11434 (para herramientas externas) |
| **Menú maestro** | `cd ~/rig-ia-stack && ./setup.sh` |
| **Elegir SO al arrancar** | Tecla **F12** → Netac = Linux / Windows Boot Manager = Windows (arranca por defecto) |

---

## 🗓️ Mantenimiento (1 vez al mes, ~5 min)

```bash
cd ~/rig-ia-stack
git pull                                    # mejoras del repo
./scripts/06-actualizar-modelos.sh --ollama # modelos + motor al día
sudo apt update && sudo apt upgrade -y      # sistema al día
```

¿Novedades de modelos? → https://ollama.com/library?sort=newest

---

## 🆕 Probar un modelo nuevo que acaba de salir

```bash
ollama pull nombre:tag                      # 1. instala EN PARALELO (no borra nada)
./scripts/05-benchmark.sh viejo:tag nuevo:tag   # 2. comparación objetiva
# 3. pruébalo en Open WebUI (dropdown arriba)
ollama rm viejo:tag                         # 4. solo si el nuevo gana
```

---

## 🔧 Cambiaste hardware (GPU / RAM / driver) → ritual de comparación

```bash
cd ~/rig-ia-stack && git pull
./scripts/05-benchmark.sh              # nuevo CSV con el hardware nuevo
./scripts/07-comparar-benchmarks.sh    # tabla: antes vs ahora, % de mejora
```

Los CSV viven en `~/rig-ia-stack/benchmarks/`. **Nunca los borres**: son tu historial.
El CSV de referencia original (RTX 3080, 26-jul-2026): `benchmark_20260726_165759.csv`

---

## 🚨 Si algo no funciona (orden de diagnóstico)

```bash
systemctl status ollama                    # ¿motor de modelos activo?
curl localhost:11434/api/version           # ¿API responde?
docker ps                                  # ¿contenedor open-webui arriba?
nvidia-smi                                 # ¿GPU visible? ¿VRAM libre?
df -h /models                              # ¿espacio en disco de modelos?
```

- GPU no aparece en `nvidia-smi` → revisar Secure Boot / reinstalar driver: `sudo ubuntu-drivers install` + reinicio.
- Open WebUI no carga → `docker logs open-webui` y `docker compose up -d` desde `~/rig-ia-stack`.
- `permission denied` con docker → cierra y reabre la sesión SSH (grupo docker).

---

## 💡 Datos útiles

- **Todo arranca solo tras reiniciar**: Ollama (systemd) y Open WebUI (contenedor `unless-stopped`) sobreviven apagados. Enciende el rig y listo.
- **Los modelos viven en** `/models/ollama` (partición dedicada de 778 GB).
- **Monitor**: conectado a la iGPU (placa madre). La 3080 queda 100% libre para IA.
- **BitLocker en Windows**: tras terminar el proyecto, reactivarlo en Windows (Admin): `manage-bde -protectors -enable C:`
- **Actualizar el LCD del disipador**: TRCC Linux (ver conversación/README del proyecto).

---

## 🗺️ Fases del proyecto

- ✅ F1 — Dual boot (Windows por defecto, F12 para Linux)
- ✅ F2 — Stack: Ollama + Open WebUI + 10 modelos + benchmark base 3080
- ⬜ F3 — Headless total + Tailscale (acceso remoto seguro)
- ⬜ F4 — OpenClaw: `ollama launch openclaw` (asistente agente local)
- ⬜ F5 — Upgrades: 64GB RAM → RTX 5070 Ti / 5090 → repetir benchmark y comparar (opción 7)
