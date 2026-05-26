# Référence : Variables, API, GPIO et Ports

## Variables de Configuration (`/opt/soundspot/soundspot.conf`)

Ce fichier est généré à l'installation et modifiable à chaud pour la plupart des variables.

| Variable | Défaut | Description |
|----------|--------|-------------|
| `SPOT_NAME` | `ZICMAMA` | SSID public du portail captif (AP ouverte). |
| `SPOT_IP` | `192.168.10.1` | IP fixe du RPi côté AP (gateway visiteurs). |
| `IFACE_AP` | `uap0` | Interface AP virtuelle (`wlan0` si Ethernet, `wlan1` si dongle USB). |
| `IFACE_WAN` | `wlan0` | Interface upstream Internet (`eth0` si Ethernet). |
| `WIFI_SSID` | — | Réseau WiFi amont (ex: `qo-op`). |
| `WIFI_CHANNEL` | auto | Canal WiFi ; ajusté au boot par `soundspot-channel-sync` pour éviter les collisions. |
| `BT_MAC` | — | Adresse MAC de l'enceinte principale (rétrocompat). |
| `BT_MACS` | — | Liste de MACs séparés par des espaces (multi-enceintes). |
| `SNAPCAST_PORT` | `1704` | Port Snapserver (audio synchronisé). |
| `ICECAST_PORT` | `8111` | Port Icecast2 (ingestion flux DJ). |
| `PRESENCE_ENABLED` | `false` | Active le détecteur de présence (nécessite Pi 4 + Camera Module 3). |
| `PRESENCE_COOLDOWN` | `300` | Secondes minimales entre deux messages d'accueil. |
| `INSTALL_DIR` | `/opt/soundspot` | Répertoire d'installation des scripts et ressources. |
| `SOUNDSPOT_USER` | `pi` | Utilisateur système exécutant PipeWire / Snapclient / Django. |
| `IDLE_ANNOUNCE_INTERVAL` | `900` | Secondes entre deux cycles du clocher numérique (15 min). |
| `CLOCK_MODE` | `bells` | `bells` = coups de cloche à l'heure · `silent` = heure vocale seule. Modifiable à chaud depuis le portail Admin. |
| `PICOPORT_ENABLED` | `true` | Active le nœud Picoport UPlanet (IPFS + NOSTR + G1). Posé comme question lors de `deploy_on_pi.sh`. |

## API Web Locale (`/api.sh`)

Les requêtes s'effectuent en **HTTP GET ou POST** sur `http://192.168.10.1/api.sh?action=...` depuis le réseau `192.168.10.x`.

| Action | Méthode | Paramètres | Description |
|--------|---------|-----------|-------------|
| `speak` | POST | `text=...` `voice=pierre\|amelie` | Synthèse vocale (espeak-ng ou Orpheus TTS). |
| `projector` | POST | `mode=on\|off` | Contrôle du relais GPIO 18 (vidéoprojecteur). |
| `yt_copy` | POST | `url=...` | Copie YouTube P2P via Jukebox NOSTR. |
| `clock` | POST | `mode=bells\|silent` | Bascule le mode du clocher à chaud. |
| `status` | GET | — | JSON d'état du nœud (services, températures, BT). |
| `docs` | GET | `cmd=list\|read&file=...` | Navigation documentation Markdown. |
| `commentator` | POST | `cmd=start\|stop\|interval\|style\|trigger` | Contrôle du commentateur IA drone (VJ). |

## Table des Ports Réseau

| Port | Protocole | Service |
|------|-----------|---------|
| `80` | TCP HTTP | Lighttpd (portail captif visiteurs — AP 192.168.10.x) |
| `1704` | TCP | Snapserver (flux audio synchronisé vers tous les clients) |
| `8111` | TCP | Icecast2 (ingestion stream DJ depuis Mixxx) |
| `9999` | WebSocket | Relay NOSTR local (Kind 9 éphémères, commandes de flotte chiffrées) |
| `4001` | TCP/UDP | IPFS Swarm (Picoport — échange P2P fichiers et tunnels) |
| `8080` | TCP | IPFS Gateway HTTP (accès contenu CID localement) |
| `54321` | TCP | UPassport — API FastAPI Python (identité MULTIPASS, envoi ẑen) |

> **Port 9999** : relay NOSTR *local uniquement*, non accessible depuis Internet. N'accepte que les événements Kind 9 (éphémères, flotte). Ne pas confondre avec les relays publics (7777).

## GPIO (Brochage Hardware)

| Pin | Signal | Rôle |
|-----|--------|------|
| 2 (SDA) | I2C Data | Capteur INA219 (tension/courant batterie) |
| 3 (SCL) | I2C Clock | Capteur INA219 |
| GPIO 17 | Relais NO | Relais de survie énergétique (coupe l'alimentation générale sur ordre batterie critique) |
| GPIO 18 | Relais NO | Relais vidéoprojecteur Nebula Capsule 3 (contrôlé via `?action=projector`) |

> **GPIO 17** : déclenché par `battery_monitor.py` lorsque la batterie passe sous 20%. Coupe tout le système après extinction propre.

---

Voir aussi : [Architecture générale](explanation-architecture.md) · [Montage matériel](howto-montage-materiel.md)
