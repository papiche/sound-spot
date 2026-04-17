# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

SoundSpot is a decentralized audio streaming infrastructure for the UPlanet cooperative ecosystem. It turns a Raspberry Pi Zero 2W into a WiFi access point that streams synchronized audio (via Snapcast) to connected clients and a paired Bluetooth speaker — no app or login required for visitors.

## Project layout

```
sound-spot/
├── deploy_on_pi.sh      ← RPi: master + satellite install (main entry point)
├── dj_mixxx_setup.sh    ← PC DJ: Snapclient + Mixxx + ~/zicmama_play.sh
├── HOWTO.md             ← single-page guide (start here)
├── README.md
├── CLAUDE.md
└── src/                 ← internals (install scripts, Python, templates)
    ├── install_soundspot.sh
    ├── install_satellite.sh
    ├── install_battery_monitor.sh
    ├── bt_update.sh
    ├── presence_detector.py
    ├── battery_monitor.py
    ├── install/          (setup_* modules sourced by install scripts)
    └── templates/        (systemd services, hostapd.conf, soundspot.conf, captive portal)
```

## Deployment Commands

```bash
# On the RPi Zero 2W (primary entry point):
sudo bash deploy_on_pi.sh              # interactive wizard
sudo bash deploy_on_pi.sh --master     # force master mode
sudo bash deploy_on_pi.sh --satellite  # force satellite mode

# On the PC DJ:
bash dj_mixxx_setup.sh   # installs Snapclient + Mixxx, generates ~/zicmama_play.sh

# BT speaker management (after install):
bash src/bt_update.sh pi@soundspot.local
```

There is no build step — this project is pure Bash + Python. ShellCheck can be run from the parent workspace: `make check` (in `../Astroport.ONE/`).

## Architecture

### Network topology

```
[PC / Mixxx DJ]──Live Broadcasting (Ogg)──→[RPi Maître : 192.168.10.1]
                                               ├─ icecast2  :8111  (receives DJ stream)
                                               ├─ snapserver :1704 (reads Icecast, syncs clients)
                                               ├─ uap0  (WiFi AP, SSID=SPOT_NAME, open, captive portal)
                                               ├─ wlan0 (upstream WiFi qo-op, Internet + satellites)
                                               └─ Bluetooth → BT speaker A

[RPi Satellite]──wlan0 qo-op──→ snapclient → soundspot.local:1704 → BT speaker B
                 (Snapcast over qo-op, NOT over the AP)

[Visitor phone/PC]──WiFi SPOT_NAME──→ opennds splash ──→ snapclient → 192.168.10.1:1704

[PC / Mixxx DJ]──snapclient──→ 192.168.10.1:1704  (headphone monitor, direct via AP)
                                ⚠ pipeline latency: 1-3 s (Icecast+ffmpeg+Snapcast)
                                DJs must use Mixxx Cue (headphones) to beatmatch.
```

### Audio pipeline

1. Mixxx activates **Live Broadcasting** → streams Ogg Vorbis to `icecast2` on port 8111, mount `/live`
2. `soundspot-decoder.service` runs `ffmpeg` in a loop: reads `http://127.0.0.1:8111/live`, decodes to raw PCM s16le 48 kHz, writes to `/tmp/snapfifo`
3. `snapserver` reads the FIFO (raw PCM) and serves the stream on port 1704
4. All `snapclient` instances (PC headphone monitor, visitor devices, satellite RPis) receive synchronized audio
5. `soundspot-client.service` runs a local snapclient → PipeWire → Bluetooth speaker

> Note: snapserver cannot decode compressed streams from HTTP — it only reads raw PCM. The ffmpeg decoder bridge is the correct and robust solution.

### Key scripts

| File | Responsibility |
|------|---------------|
| `deploy_on_pi.sh` | **Main entry point** — interactive wizard on the RPi: mode selection (master/satellite), WiFi config, BT scan, copies Python scripts, calls correct installer, reboots |
| `install_soundspot.sh` | Master install: networking (hostapd/dnsmasq/opennds), icecast2, Snapcast, PipeWire, Bluetooth, all systemd services |
| `install_satellite.sh` | Satellite install: PipeWire + Snapclient only (no AP, no Icecast) |
| `presence_detector.py` | Face detection daemon (OpenCV Haar, 80×60 px); triggers welcome audio via `threading.Thread` |
| `battery_monitor.py` | INA219 solar battery monitor; replaces welcome.wav with low-battery alert |
| `bt_update.sh` | Interactive BT speaker management (scan, pair, update soundspot.conf) |
| `dj_mixxx_setup.sh` | PC DJ setup: Snapclient + Mixxx + `~/zicmama_play.sh` generator |

### Runtime configuration

`/opt/soundspot/soundspot.conf` is generated during install and holds all tunables:

```
SPOT_NAME          SSID WiFi visiteurs (AP ouverte)
SPOT_IP            IP fixe du RPi côté AP (192.168.10.1)
WIFI_SSID          Réseau amont (qo-op)
WIFI_CHANNEL       Canal WiFi (ajusté au boot par soundspot-channel-sync)
BT_MAC             MAC enceinte principale (rétrocompat)
BT_MACS            MACs espace-séparés (multi-enceintes)
SNAPCAST_PORT      1704
PRESENCE_COOLDOWN  Secondes entre deux messages d'accueil
INSTALL_DIR        /opt/soundspot
```

### Systemd services on the RPi master

Boot order: `wpa_supplicant@wlan0` → `soundspot-channel-sync` → `uap0` → `hostapd` → `dnsmasq` → `opennds` → `icecast2` → `snapserver` + `soundspot-decoder` → `soundspot-client` → `bt-autoconnect` → `soundspot-presence` → `soundspot-battery`

### Presence detector (`presence_detector.py`)

Lightweight face presence daemon — no ML, no dlib. Uses OpenCV Haar cascade on 80×60 px (frame downscaled ×4 from 320×240) to detect whether someone is in front of the camera. When a face is detected and the cooldown has elapsed, it runs `/opt/soundspot/play_welcome.sh` which plays `welcome.wav` via PipeWire.

- Camera: Pi Camera Module 3 (SC1223) — accessed via `picamera2` (libcamera), with V4L2 fallback
- Blind mode: if no camera is found, announces periodically (lighthouse pattern) at `PRESENCE_BLIND_INTERVAL` seconds
- Service uses `/usr/bin/python3` (system python3-opencv installed via apt)

### Battery monitor (`battery_monitor.py`)

Optional INA219 I2C sensor monitoring. Uses a dedicated Python venv (`/opt/soundspot/venv`) with `pi-ina219`. Exits cleanly (code 0) if the sensor is absent — `Restart=on-failure` will not restart it.

### Installation modules (`install/`)

Each `install/*.sh` file exports a single `setup_*` function, sourced by `install_soundspot.sh`:

| Module | Function |
|---|---|
| `colors.sh` | `log/warn/err/hdr` + `install_template` (envsubst) |
| `networking.sh` | `setup_networking` — uap0, hostapd, dnsmasq, NAT iptables |
| `captive_portal.sh` | `setup_captive_portal` — opennds + HTML theme |
| `icecast.sh` | `setup_icecast` — enable + password |
| `bluetooth.sh` | `setup_bluetooth` — bt-autoconnect service |
| `pipewire.sh` | `setup_pipewire` — loginctl enable-linger |
| `snapserver.sh` | `setup_snapserver` — mkfifo + snapserver.conf |
| `snapclient.sh` | `setup_snapclient [master|satellite]` |
| `channel_sync.sh` | `setup_channel_sync` — sync_channel.sh + systemd overrides |
| `presence.sh` | `setup_presence` — welcome.wav + presence + battery services + venv |

## Conventions

- All user-facing text is in French
- Target hardware: Raspberry Pi Zero 2W (arm64), installed from Raspberry Pi OS Bookworm Lite
- WiFi AP uses a virtual interface `uap0` (MAC-cloned from `wlan0`); upstream connection stays on `wlan0`
- Satellites connect to the master via qo-op network (mDNS `soundspot.local`) — NOT via the AP network
- `SOUNDSPOT_USER` defaults to `${SUDO_USER:-pi}` — the user running audio services (PipeWire, snapclient)
- Python scripts (`presence_detector.py`, `battery_monitor.py`) are copied to `$INSTALL_DIR` by `deploy_on_pi.sh` before calling the installers
- The project is part of the UPlanet ecosystem; see `../CLAUDE.md` for cross-project context
