# Référence : API, GPIO et Services

## Variables de Configuration (`/opt/soundspot/soundspot.conf`)
| Variable | Description |
|---|---|
| `SPOT_NAME` | SSID public du portail captif. |
| `SPOT_IP` | IP Gateway de l'AP public (Défaut: 192.168.10.1). |
| `CLOCK_MODE` | `bells` ou `silent` (État du clocher numérique). |

## API Web Locale (`/api.sh`)
Les requêtes se font via `HTTP POST` sur le réseau `192.168.10.x`.
- `?action=speak` : Synthèse vocale. (Body: `text=...&voice=pierre`)
- `?action=projector` : Contrôle relais vidéo. (Body: `mode=on/off`)
- `?action=yt_copy` : Jukebox P2P. (Body: `url=...`)

## Table des Ports Réseau
| Port | Protocole | Service |
|---|---|---|
| `80` | TCP | Lighttpd (Portail Captif) |
| `1704` | TCP | Snapserver (Flux Audio Synchronisé) |
| `8111` | TCP | Icecast2 (Ingestion Mixxx DJ) |
| `9999` | WS | Relais Flotte NOSTR Local |
| `54321`| TCP | UPassport / API Python (Cerveau) |

## GPIO (Brochage Hardware)
- **I2C (SDA 2 / SCL 3)** : Capteur INA219.
- **GPIO 17** : Relais principal de survie énergétique.
- **GPIO 18** : Relais du Vidéoprojecteur Nebula.
