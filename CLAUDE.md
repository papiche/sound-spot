# CLAUDE.md

SoundSpot is a decentralized audio streaming infrastructure for the UPlanet cooperative ecosystem. It turns a Raspberry Pi Zero 2W into a WiFi access point that streams synchronized audio (via Snapcast) to connected clients and a paired Bluetooth speaker — no app or login required for visitors.

## Project layout

```
sound-spot/
├── deploy_on_pi.sh      ← RPi: master + satellite install (main entry point)
├── check.sh             ← Diagnostic complet (services, réseau, audio, BT, pare-feu)
├── dj_mixxx_setup.sh    ← PC DJ: Snapclient + Mixxx + ~/zicmama_play.sh
├── zicmama_play.sh      ← Script de session DJ généré par dj_mixxx_setup.sh
├── restart.sh           ← Redémarrage rapide des services audio
├── update.sh            ← Mise à jour du code depuis git
├── HOWTO.md             ← single-page guide (start here)
├── README.md
├── CLAUDE.md
├── docs/                ← Guides how-to et références
│   ├── howto-dj-configuration.md
│   ├── howto-festival-survival.md
│   ├── howto-logs-diagnostic.md
│   ├── howto-mesh-satellite.md
│   ├── howto-montage-materiel.md
│   ├── howto-vj-drone.md
│   ├── howto-steamdeck.md           ← Console DJ (Steam Deck) et IA distante (Sagittarius)
│   ├── reference-api-config.md
│   ├── reference-nomenclature.md    ← Liste du matériel, budget et liens d'achats
│   ├── tutorial-co-developpement.md
│   ├── tutorial-premier-noeud.md
│   └── explanation-architecture.md
├── monitor/             ← Scripts de surveillance runtime
│   ├── analyse_ipfs.sh
│   ├── portal_logs.sh
│   ├── proc_inspect.sh
│   ├── proc_watch.sh
│   └── pstree.sh
├── tests/               ← Tests d'intégration
│   ├── BENCH_REFERENCE.md
│   ├── live.stats.sh
│   ├── test_astroport_tools.sh
│   ├── test_audio.sh
│   ├── test_audio_orpheus.me.sh
│   ├── test_nostr_node.sh
│   └── test_voices.sh
└── src/                 ← Internals
    ├── install_soundspot.sh    ← Orchestre l'install master (source tous les modules install/)
    ├── install_satellite.sh    ← Install satellite (PipeWire + Snapclient uniquement)
    ├── install_astroport_light.sh  ← Clone Astroport.ONE, venv ~/.astro/, symlinks
    ├── wpa_supplicant.conf         ← Template WiFi client upstream
    ├── install/          ← Modules setup_* sourcés par install_soundspot.sh
    ├── backend/          ← Scripts copiés dans /opt/soundspot/backend/ au runtime
    │   ├── audio/        ← (idle_announcer, bt-combine-sinks, split_audio, set_audio_output…)
    │   ├── video/        ← (flux RTMP drone)
    │   └── system/       ← (control_center, fleet_commander, fleet_listener, bt-connect, bt_update…)
    ├── portal/           ← Portail captif lighttpd
    │   ├── index.html    ← Interface utilisateur principale
    │   ├── api.sh        ← Dispatcher CGI → sous-scripts api/
    │   └── api/          ← Handlers bash (core/, apps/, network/, services/)
    ├── config/           ← Templates de configuration
    │   ├── soundspot.conf.master.env    ← Template soundspot.conf (master)
    │   ├── soundspot.conf.satellite.env ← Template soundspot.conf (satellite)
    │   ├── services/     ← Fichiers .service systemd
    │   ├── network/      ← hostapd.conf, dnsmasq.conf, NetworkManager overrides
    │   └── system/       ← rsyslog, logrotate
    ├── dev/              ← Outils de développement sur RPi
    │   ├── dev_setup.sh      ← Environnement dev (rsync hot-reload)
    │   ├── dev_reload.sh     ← Rechargement à chaud du code
    │   ├── dev_restore.sh    ← Restauration état prod
    │   ├── dev_switch.sh     ← Bascule dev ↔ prod
    │   └── prepare_iso.sh    ← Préparation image SD
    ├── templates/        ← Templates envsubst (soundspot.conf, logrotate)
    └── picoport/         ← Astroport.ONE UPlanet (IPFS + Nostr + G1 + IA swarm)
        ├── install_picoport.sh         ← IPFS Kubo arm64 + g1cli + clés Y-Level + picoport.service
        ├── picoport_init_keys.sh       ← Identité déterministe SSH→IPFS→Nostr
        ├── picoport.sh                 ← Daemon principal Picoport
        └── pico_bashrc_manager.sh      ← Alias shell (check, ai, asys, bt-fix…)
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
bash src/backend/system/bt_update.sh pi@soundspot.local

# Dev workflow on RPi:
bash src/dev/dev_setup.sh   # prepare hot-reload environment
bash src/dev/dev_reload.sh  # push changes without reboot
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
2. `soundspot-decoder.service` runs `ffmpeg` in a loop: reads `http://127.0.0.1:8111/live`, decodes to raw PCM s16le 48 kHz, writes to `/dev/shm/snapfifo`
3. `snapserver` reads the FIFO (raw PCM) and serves the stream on port 1704
4. All `snapclient` instances (PC headphone monitor, visitor devices, satellite RPis) receive synchronized audio
5. `soundspot-client.service` runs a local snapclient → PipeWire → Bluetooth speaker

> Note: snapserver cannot decode compressed streams from HTTP — it only reads raw PCM. The ffmpeg decoder bridge is the correct and robust solution.

> Note FIFO path: le fichier FIFO est dans `/dev/shm/snapfifo` (RAM), non dans `/tmp/snapfifo`.

### Key scripts

| File | Responsibility |
|------|---------------|
| `deploy_on_pi.sh` | **Main entry point** — interactive wizard: mode, WiFi, BT, timezone, Picoport opt-in, reboot. Exporte `IFACE_AP`/`IFACE_WAN` selon le hardware détecté avant d'appeler install_soundspot.sh |
| `check.sh` | Diagnostic complet — services systemd, réseau, pare-feu, pipeline audio, BT, portail captif |
| `install_soundspot.sh` | Master install: source tous les modules `install/*.sh`, orchestre l'appel des `setup_*` |
| `install_satellite.sh` | Satellite install: PipeWire + Snapclient only (no AP, no Icecast) |
| `install_astroport_light.sh` | Clone Astroport.ONE, venv `~/.astro/`, pip keygen+Nostr+G1, symlinks `~/.local/bin/` (keygen, solar_time, astrosystemctl) |
| `idle_announcer.sh` | Clocher numérique — boucle toutes les 15 min : bip 429.62 Hz + coups de cloche + **heure solaire** (correction longitude/fuseau) + messages. Hot-reload de CLOCK_MODE sans redémarrage |
| `src/backend/system/control_center.sh` | Interface admin du portail captif (menu bash) — gestion BT, audio, flotte, Picoport |
| `src/backend/system/fleet_commander.sh` | Publie des ordres Kind 9 sur le relay fleet local (port 9999) |
| `src/backend/system/fleet_listener.sh` | Écoute les ordres fleet (shutdown, announce…) — IS_ENERGY=true pour le nœud énergie |
| `src/backend/system/fleet_relay.py` | Relay NOSTR WebSocket local (:9999) — uniquement Kind 9 éphémères |
| `src/backend/system/bt-connect.sh` | Connexion BT + redémarre soundspot-client après succès |
| `src/backend/system/bt_reactive.py` | Daemon reconnexion BT réactive (écoute D-Bus) |
| `src/backend/system/state_daemon.sh` | Publie l'état du nœud (uptime, températures) |
| `presence_detector.py` (→ `mon-oeil.py`) | Face detection daemon (OpenCV Haar, 80×60 px); triggers welcome audio via `threading.Thread` |
| `battery_monitor.py` | INA219 solar battery monitor; replaces welcome.wav with low-battery alert |
| `src/backend/system/bt_update.sh` | Interactive BT speaker management (scan, pair, update soundspot.conf) |
| `dj_mixxx_setup.sh` | PC DJ setup: Snapclient + Mixxx + `~/zicmama_play.sh` generator |
| `picoport/install_picoport.sh` | IPFS Kubo arm64 + g1cli (Duniter v2s, paiements ẑen) + identité Y-Level + service picoport.service |
| `picoport/picoport_init_keys.sh` | Identité déterministe : SSH → sha512 → IPFS PeerID + NOSTR MULTIPASS (make_NOSTRCARD.sh) |
| `picoport/pico_bashrc_manager.sh` | Installe les alias shell : `check`, `ai`, `asys*`, `bt-fix`, `clock-bells/silent`, `pico-status`, `pico-power`, `swarm-nodes` |

### Runtime configuration

`/opt/soundspot/soundspot.conf` is generated during install and holds all tunables:

```
SPOT_NAME                SSID WiFi visiteurs (AP ouverte)
SPOT_IP                  IP fixe du RPi côté AP (192.168.10.1)
IFACE_AP                 Interface AP (uap0 par défaut, wlan0 si Ethernet, wlan1 si dongle USB)
IFACE_WAN                Interface upstream (wlan0 par défaut, eth0 si Ethernet)
WIFI_SSID                Réseau amont (qo-op)
WIFI_CHANNEL             Canal WiFi (ajusté au boot par soundspot-channel-sync)
BT_MAC                   MAC enceinte principale (rétrocompat)
BT_MACS                  MACs espace-séparés (multi-enceintes)
SNAPCAST_PORT            1704
ICECAST_PORT             8111
PRESENCE_COOLDOWN        Secondes entre deux messages d'accueil
PRESENCE_ENABLED         true/false — détecteur de présence (Pi 4 + Module 3 requis)
INSTALL_DIR              /opt/soundspot
SOUNDSPOT_USER           Utilisateur système qui exécute PipeWire/Snapclient (défaut: ${SUDO_USER:-pi})
IDLE_ANNOUNCE_INTERVAL   Secondes entre annonces clocher (défaut: 900 = 15 min)
CLOCK_MODE               "bells" (coups de cloche à l'heure) ou "silent" (heure vocale seule)
PICOPORT_ENABLED         true/false — active le nœud Picoport UPlanet (défaut: true)
```

**Note `CLOCK_MODE`** : modifiable à chaud depuis le portail captif via `set_clock_mode.sh` — `idle_announcer.sh` relit `soundspot.conf` à chaque itération, sans redémarrage du service.

**Note `PICOPORT_ENABLED`** : posé comme question par `deploy_on_pi.sh` (défaut : oui). Si `false`, `setup_picoport()` est ignoré — aucun IPFS, aucun clone Astroport.ONE, aucun venv Python keygen.

**Note `IFACE_AP`/`IFACE_WAN`** : exportées par `deploy_on_pi.sh` *avant* d'appeler `install_soundspot.sh`. Elles doivent figurer dans la liste `envsubst` de chaque `install_template` qui les utilise (hostapd.conf, dnsmasq.conf, soundspot-ap.service). Toute variable absente de la liste reste **littérale** dans le fichier généré → service cassé au boot.

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
  → soundspot-ap → uap0-ip
  → ipset-soundspot                        (ipset hash:ip timeout 14400 = 4 heures)
  → soundspot-firewall                     (iptables NAT + portail captif)
  → hostapd → dnsmasq
  → icecast2
  → snapserver + soundspot-decoder
  → soundspot-client (wait-pw-socket + wait-bt-sink)
  → bt-autoconnect + soundspot-bt-reactive
  → soundspot-idle                         (clocher numérique idle_announcer.sh)
  → soundspot-presence (si PRESENCE_ENABLED=true) → mon-oeil.service
  → soundspot-battery
  → soundspot-fleet-relay                  (fleet_relay.py :9999)
  → soundspot-fleet                        (fleet_listener.sh)
  → soundspot-state                        (state_daemon.sh)
  → soundspot-jukebox                      (jukebox_listener.py)
  → soundspot-autodj                       (auto DJ fallback)
```

**Services optionnels** : `soundspot-mic`, `soundspot-mesh`, `soundspot-rtmp-player`, `soundspot-swarm-sync`

**Pare-feu** : `soundspot-firewall.service` remplace `netfilter-persistent` pour éviter la race condition avec `ipset`. `netfilter-persistent` est désactivé. Les règles iptables sont ré-appliquées depuis `soundspot-firewall.sh` à chaque boot (idempotent : flush + re-apply).

**Note** : le service snapclient local est toujours nommé `soundspot-client`, que le nœud soit maître ou satellite (seul le contenu du service — quel serveur Snapcast il cible — diffère entre `soundspot-client-master.service` et `soundspot-client-satellite.service`, les deux templates sources dans `src/config/services/`).

### Installation modules (`src/install/`)

Each `install/*.sh` file exports a single `setup_*` function, sourced by `install_soundspot.sh`:

| Module | Function | Notes |
|---|---|---|
| `colors.sh` | `log/warn/err/hdr` + `install_template` | `envsubst` avec liste explicite — variable absente = littérale dans le fichier généré |
| `logging.sh` | `setup_logging` | Logs centralisés rsyslog + logrotate |
| `wifi_driver.sh` | `setup_wifi_driver` | Pilote clé USB Wi-Fi 5 GHz |
| `networking.sh` | `setup_networking` | uap0, hostapd, dnsmasq, NAT iptables, ipset, firewall |
| `captive_portal.sh` | `setup_captive_portal` | lighttpd + HTML theme |
| `icecast.sh` | `setup_icecast` | enable + password |
| `respeaker.sh` | `setup_respeaker` | Pilote microphone USB ReSpeaker |
| `bluetooth.sh` | `setup_bluetooth` | bt-autoconnect + bt-reactive services |
| `pipewire.sh` | `setup_pipewire` | loginctl enable-linger |
| `snapserver.sh` | `setup_snapserver` | mkfifo /dev/shm/snapfifo + snapserver.conf |
| `snapclient.sh` | `setup_snapclient [master\|satellite]` | Installe le template `soundspot-client-{master,satellite}.service` sous le nom fixe `soundspot-client.service` |
| `channel_sync.sh` | `setup_channel_sync` | sync_channel.sh + systemd overrides |
| `presence.sh` | `setup_presence` | welcome.wav + mon-oeil (OpenCV) |
| `battery.sh` | `setup_battery` | INA219 I2C — service soundspot-battery (indépendant de presence) |
| `idle.sh` | `setup_idle` | Clocher numérique idle_announcer.sh |
| `jukebox.sh` | `setup_jukebox` | Nostr Jukebox listener/player |
| `autodj.sh` | `setup_autodj` | Auto DJ fallback (quand aucun flux DJ actif) |
| `video_rtmp.sh` | `setup_video_rtmp` | Serveur flux vidéo drone RTMP |
| `zram.sh` | `setup_zram` | Compression RAM swap (optimisation RPi Zero 2W) |

### Presence detector (`presence_detector.py` → `mon-oeil.py`)

Lightweight face presence daemon — no ML, no dlib. Uses OpenCV Haar cascade on 80×60 px (frame downscaled ×4 from 320×240) to detect whether someone is in front of the camera. When a face is detected and the cooldown has elapsed, it runs `/opt/soundspot/play_welcome.sh` which plays `welcome.wav` via PipeWire.

- Camera: Pi Camera Module 3 (SC1223) — accessed via `picamera2` (libcamera), with V4L2 fallback
- Blind mode: if no camera is found, announces periodically (lighthouse pattern) at `PRESENCE_BLIND_INTERVAL` seconds
- Service uses `/usr/bin/python3` (system python3-opencv installed via apt)

### Battery monitor (`battery_monitor.py`)

Optional INA219 I2C sensor monitoring. Uses a dedicated Python venv (`/opt/soundspot/venv`) with `pi-ina219`. Exits cleanly (code 0) if the sensor is absent — `Restart=on-failure` will not restart it.

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
- `install_template SRC DEST 'VARS'` — `envsubst` substitue **uniquement** les variables listées en argument. Toute variable manquante dans la liste reste littérale dans le fichier installé (`${IFACE_AP}` non substitué → hostapd/dnsmasq plantent)
- FIFO snapcast dans `/dev/shm/snapfifo` (RAM tmpfs) et non `/tmp/snapfifo`
- Portail captif timeout : **4 heures** (ipset timeout 14400) — corriger toute doc qui dit "15 minutes"
- Le service snapclient local est toujours nommé `soundspot-client` (jamais suffixé `-master`/`-satellite`) — seuls les *templates sources* dans `src/config/services/` portent ce suffixe
- `bt-connect.sh` redémarre `soundspot-client` après connexion BT réussie — sans ça, snapclient reste sur le sink null démarré au boot
- L'heure solaire dans `idle_announcer.sh` utilise la correction `lon × 4 - tz_offset_min` appliquée à l'heure locale (pas UTC). Fallback : méridien du fuseau horaire si `~/.zen/GPS` absent
- The project is part of the UPlanet ecosystem; see `../CLAUDE.md` for cross-project context

## Pièges / Points d'attention

- **Règle sudo GPIO large** dans `src/install/captive_portal.sh` : `www-data ALL=(ALL) NOPASSWD: /bin/echo * > /sys/class/gpio/*` — le wildcard `*` après `/bin/echo` autorise echo avec n'importe quel argument en root. Restreindre au GPIO exact si le matériel est connu.
- **Identité IPFS fragile** dans `picoport_init_keys.sh` : le PeerID est dérivé du contenu de `id_ed25519` via sha512. Si la clé SSH est régénérée, le PeerID change silencieusement — sauvegarder `~/.ipfs/config` avant toute opération sur les clés SSH.
