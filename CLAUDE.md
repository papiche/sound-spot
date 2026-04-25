# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

SoundSpot is a decentralized audio streaming infrastructure for the UPlanet cooperative ecosystem. It turns a Raspberry Pi Zero 2W into a WiFi access point that streams synchronized audio (via Snapcast) to connected clients and a paired Bluetooth speaker — no app or login required for visitors.

## Project layout

```
sound-spot/
├── deploy_on_pi.sh      ← RPi: master + satellite install (main entry point)
├── check.sh             ← Diagnostic complet (services, réseau, audio, BT, pare-feu)
├── dj_mixxx_setup.sh    ← PC DJ: Snapclient + Mixxx + ~/zicmama_play.sh
├── HOWTO.md             ← single-page guide (start here)
├── README.md
├── CLAUDE.md
└── src/                 ← internals (install scripts, Python, templates)
    ├── install_soundspot.sh
    ├── install_satellite.sh
    ├── install_battery_monitor.sh
    ├── install_astroport_light.sh   ← Astroport.ONE clone + venv ~/.astro/ + symlinks
    ├── idle_announcer.sh    ← Clocher numérique (bip + cloche + heure solaire + messages)
    ├── bt_update.sh
    ├── presence_detector.py
    ├── battery_monitor.py
    ├── picoport/         ← Astroport.ONE UPlanet (IPFS + Nostr + G1 + IA swarm)
    │   ├── install_picoport.sh         ← IPFS Kubo + g1cli + clés Y-Level + service systemd
    │   ├── picoport_init_keys.sh       ← Identité déterministe SSH→IPFS→Nostr
    │   ├── picoport.sh                 ← Daemon principal Picoport
    │   └── pico_bashrc_manager.sh      ← Alias shell (check, ai, asys, bt-fix…)
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

[Visitor phone/PC]──WiFi SPOT_NAME──→ lighttpd portail captif ──→ snapclient → 192.168.10.1:1704

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
| `deploy_on_pi.sh` | **Main entry point** — interactive wizard: mode, WiFi, BT, timezone, Picoport opt-in, reboot |
| `check.sh` | Diagnostic complet — services systemd, réseau, pare-feu, pipeline audio, BT, portail captif |
| `install_soundspot.sh` | Master install: networking (hostapd/dnsmasq/firewall), icecast2, Snapcast, PipeWire, Bluetooth, idle, Picoport (optionnel), services systemd |
| `install_satellite.sh` | Satellite install: PipeWire + Snapclient only (no AP, no Icecast) |
| `install_astroport_light.sh` | Clone Astroport.ONE, venv `~/.astro/`, pip keygen+Nostr+G1, symlinks `~/.local/bin/` (keygen, solar_time, astrosystemctl) |
| `idle_announcer.sh` | Clocher numérique — boucle toutes les 15 min : bip 429.62 Hz + coups de cloche + **heure solaire** (correction longitude/fuseau) + messages. Hot-reload de CLOCK_MODE sans redémarrage |
| `picoport/install_picoport.sh` | IPFS Kubo arm64 + g1cli (Duniter v2s, paiements ẑen) + identité Y-Level + service picoport.service |
| `picoport/picoport_init_keys.sh` | Identité déterministe : SSH → sha512 → IPFS PeerID + NOSTR MULTIPASS (make_NOSTRCARD.sh) |
| `picoport/pico_bashrc_manager.sh` | Installe les alias shell : `check`, `ai`, `asys*`, `bt-fix`, `clock-bells/silent`, `pico-status`, `pico-power`, `swarm-nodes` |
| `presence_detector.py` | Face detection daemon (OpenCV Haar, 80×60 px); triggers welcome audio via `threading.Thread` |
| `battery_monitor.py` | INA219 solar battery monitor; replaces welcome.wav with low-battery alert |
| `bt_update.sh` | Interactive BT speaker management (scan, pair, update soundspot.conf) |
| `dj_mixxx_setup.sh` | PC DJ setup: Snapclient + Mixxx + `~/zicmama_play.sh` generator |

### Runtime configuration

`/opt/soundspot/soundspot.conf` is generated during install and holds all tunables:

```
SPOT_NAME                SSID WiFi visiteurs (AP ouverte)
SPOT_IP                  IP fixe du RPi côté AP (192.168.10.1)
WIFI_SSID                Réseau amont (qo-op)
WIFI_CHANNEL             Canal WiFi (ajusté au boot par soundspot-channel-sync)
BT_MAC                   MAC enceinte principale (rétrocompat)
BT_MACS                  MACs espace-séparés (multi-enceintes)
SNAPCAST_PORT            1704
ICECAST_PORT             8111
PRESENCE_COOLDOWN        Secondes entre deux messages d'accueil
PRESENCE_ENABLED         true/false — détecteur de présence (Pi 4 + Module 3 requis)
INSTALL_DIR              /opt/soundspot
SOUNDSPOT_USER           Utilisateur système qui exécute PipeWire/Snapclient (défaut: pi)
IDLE_ANNOUNCE_INTERVAL   Secondes entre annonces clocher (défaut: 900 = 15 min)
CLOCK_MODE               "bells" (coups de cloche à l'heure) ou "silent" (heure vocale seule)
PICOPORT_ENABLED         true/false — active le nœud Picoport UPlanet (défaut: true)
```

**Note `CLOCK_MODE`** : modifiable à chaud depuis le portail captif via `set_clock_mode.sh` — `idle_announcer.sh` relit `soundspot.conf` à chaque itération, sans redémarrage du service.

**Note `PICOPORT_ENABLED`** : posé comme question par `deploy_on_pi.sh` (défaut : oui). Si `false`, `setup_picoport()` est ignoré — aucun IPFS, aucun clone Astroport.ONE, aucun venv Python keygen.

### Clocher numérique et messages personnalisables

Les textes sources et fichiers audio sont dans `/opt/soundspot/wav/` :

```
wav/
├── tone_429hz.wav     ← bip 429.62 Hz 4s (signal de vie du nœud)
├── bell_429hz.wav     ← coup de cloche 2.5s (fondu progressif)
├── message_01.txt     ← texte source (modifiable librement)
├── message_01.wav     ← audio généré par espeak-ng (ou remplacé manuellement)
├── message_02.txt
├── message_02.wav
└── …                  (jusqu'à message_08)
```

Pour personnaliser un message : remplacer le `.wav` correspondant par votre enregistrement. Le `.txt` est conservé comme référence. Si le `.wav` est absent ou le `.txt` plus récent, `idle_announcer.sh` régénère automatiquement.

### Systemd services on the RPi master

Boot order:
```
wpa_supplicant@wlan0
  → soundspot-channel-sync
  → uap0 → uap0-ip
  → ipset-soundspot                        (ipset hash:ip timeout 900)
  → soundspot-firewall                     (iptables NAT + portail captif)
  → hostapd → dnsmasq
  → icecast2
  → snapserver + soundspot-decoder
  → soundspot-client (wait-pw-socket + wait-bt-sink)
  → bt-autoconnect
  → soundspot-idle                         (clocher numérique idle_announcer.sh)
  → soundspot-presence (si PRESENCE_ENABLED=true)
  → soundspot-battery
```

**Pare-feu** : `soundspot-firewall.service` remplace `netfilter-persistent` pour éviter la race condition avec `ipset`. `netfilter-persistent` est désactivé. Les règles iptables sont ré-appliquées depuis `soundspot-firewall.sh` à chaque boot (idempotent : flush + re-apply).

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
| `colors.sh` | `log/warn/err/hdr` + `install_template` (envsubst avec liste explicite de variables) |
| `networking.sh` | `setup_networking` — uap0, hostapd, dnsmasq, NAT iptables. **`${IFACE_AP}` doit figurer dans la liste envsubst de chaque `install_template` qui l'utilise.** |
| `captive_portal.sh` | `setup_captive_portal` — lighttpd + HTML theme |
| `icecast.sh` | `setup_icecast` — enable + password |
| `bluetooth.sh` | `setup_bluetooth` — bt-autoconnect service |
| `pipewire.sh` | `setup_pipewire` — loginctl enable-linger |
| `snapserver.sh` | `setup_snapserver` — mkfifo + snapserver.conf |
| `snapclient.sh` | `setup_snapclient [master|satellite]` |
| `channel_sync.sh` | `setup_channel_sync` — sync_channel.sh + systemd overrides |
| `presence.sh` | `setup_presence` — welcome.wav + presence + battery services + venv |

### Picoport (Astroport.ONE sur RPi Zero 2W)

`setup_picoport()` dans `install_soundspot.sh` :
1. `cp -r src/picoport/ /opt/soundspot/picoport/`
2. `chown -R SOUNDSPOT_USER` (nécessaire — `install_astroport_light.sh` tourne en non-root)
3. `sudo -u SOUNDSPOT_USER bash install_astroport_light.sh` — clone Astroport.ONE, venv `~/.astro/`, pip, symlinks
4. `bash install_picoport.sh` — IPFS, g1cli arm64, clés Y-Level, `picoport.service`

**Chaîne de clés Y-Level** (`picoport_init_keys.sh`) :
```
id_ed25519 (SSH) → sha512sum → SECRET1 + SECRET2
  → keygen -t ipfs   → IPFS PeerID + PrivKey  (injecté dans ~/.ipfs/config)
  → keygen -t nostr  → MULTIPASS Nostr (make_NOSTRCARD.sh)
  → keygen -t g1     → Portefeuille Ğ1 (paiements ẑen via g1cli)
```

**g1cli** : binaire arm64 téléchargé depuis `git.duniter.org/api/v4/projects/clients%2Frust%2Fg1cli/releases/`.
Symlink `gcli → g1cli` créé pour compatibilité `PAYforSURE.sh` et `my.sh`.

**`astrosystemctl`** (`~/.local/bin/astrosystemctl` → `~/.zen/Astroport.ONE/tools/astrosystemctl.sh`) :
Gestion cloud P2P — compare le Power-Score local (toujours 🌿 Light sur Zero 2W) avec les Brain-Nodes du swarm. Permet de consommer des services IA distants via tunnels IPFS P2P (`connect ollama`, `enable comfyui`…).

## Conventions

- All user-facing text is in French
- Target hardware: Raspberry Pi Zero 2W (arm64), installed from Raspberry Pi OS Bookworm Lite
- WiFi AP uses a virtual interface `uap0` (MAC-cloned from `wlan0`); upstream connection stays on `wlan0`
- Satellites connect to the master via qo-op network (mDNS `soundspot.local`) — NOT via the AP network
- `SOUNDSPOT_USER` defaults to `${SUDO_USER:-pi}` — the user running audio services (PipeWire, snapclient)
- Python scripts (`presence_detector.py`, `battery_monitor.py`) are copied to `$INSTALL_DIR` by `deploy_on_pi.sh` before calling the installers
- `install_template SRC DEST 'VARS'` — `envsubst` substitue **uniquement** les variables listées en argument. Toute variable manquante dans la liste reste littérale dans le fichier installé (`${IFACE_AP}` non substitué → hostapd/dnsmasq plantent)
- `bt-connect.sh` redémarre `soundspot-client` après connexion BT réussie — sans ça, snapclient reste sur le sink null démarré au boot
- L'heure solaire dans `idle_announcer.sh` utilise la correction `lon × 4 - tz_offset_min` appliquée à l'heure locale (pas UTC). Fallback : méridien du fuseau horaire si `~/.zen/GPS` absent
- The project is part of the UPlanet ecosystem; see `../CLAUDE.md` for cross-project context
