# SoundSpot — Zicmama

**Nœud audio collectif libre** — infrastructure sonore décentralisée pour espaces publics et tiers-lieux.

SoundSpot transforme un Raspberry Pi Zero 2W en point d'accès WiFi permettant à n'importe qui de diffuser sa musique sur les enceintes du lieu depuis son ordinateur, sans installation ni compte. La caméra intégrée détecte les visiteurs et joue automatiquement un message d'accueil vocal.

Projet [G1FabLab](https://opencollective.com/monnaie-libre) / [UPlanet ẐEN](https://qo-op.com) — Licence AGPL-3.0

---

## Principe de fonctionnement

```
[PC Mixxx / DJ]
      │ Live Broadcasting → Icecast :8111/live
      ▼
[RPi Zero 2W — 192.168.10.1]
  ├─ Icecast2            (relais Ogg Vorbis du DJ)
  ├─ snapserver :1704    (lit Icecast, distribue le stream)
  ├─ WiFi AP  SPOT_NAME  (visiteurs — réseau ouvert)
  ├─ WiFi     qo-op      (réseau amont — Internet)
  ├─ PipeWire            (routage audio)
  ├─ Camera Module 3     (détection de présence)
  └─ Bluetooth           (enceinte W-KING ou équivalent)
```

Un visiteur se connecte au WiFi du SoundSpot → internet s'ouvre immédiatement (DHCP) → la page d'accueil (portail captif) surgit automatiquement sur son téléphone → il clique « J'ai lu » → 15 minutes d'accès internet complet → peut installer Snapclient et écouter le stream synchronisé.

Le DJ ouvre Mixxx sur son PC, active le **Live Broadcasting** vers le RPi (Icecast), et sa session est diffusée en temps réel sur toutes les enceintes connectées (Bluetooth + Snapclients visiteurs).

---

## Matériel

| Composant | Référence |
|---|---|
| Ordinateur embarqué | Raspberry Pi Zero 2W |
| Caméra | Pi Camera Module 3 — SC1223, 75° |
| Enceinte | W-KING D9-1 (ou tout haut-parleur Bluetooth A2DP) |
| Carte SD | ≥ 8 Go (classe 10 / A1) |
| Alimentation | USB-C 5V / 2A |
| PC DJ | Linux (Ubuntu / Debian) avec Mixxx |

---

## Déploiement

### 1. Préparer la carte SD

Utiliser **[Raspberry Pi Imager](https://www.raspberrypi.com/software/)** pour flasher **Raspberry Pi OS Lite 64-bit (Bookworm)**.

Dans les options avancées de l'Imager, configurer :
- **Hostname** : `soundspot` (ou `soundspot-sat` pour un satellite)
- **Nom d'utilisateur** : `pi` / mot de passe au choix
- **WiFi** : SSID et mot de passe du réseau amont (`qo-op` / `0penS0urce!`)
- **SSH** : activer / clé publique ou mot de passe

### 2. Installer SoundSpot sur le RPi

Booter le RPi, attendre 60 s, puis se connecter en SSH :

```bash
ssh pi@soundspot.local
```

Cloner le dépôt et lancer l'assistant :

```bash
git clone https://github.com/papiche/sound-spot
cd sound-spot
sudo bash deploy_on_pi.sh
```

L'assistant pose 4 questions, puis installe tout en ~10 minutes et redémarre.

**Mode maître** (premier RPi) : crée le réseau WiFi visiteurs, Icecast, Snapserver, portail captif, caméra.

**Mode satellite** (enceinte supplémentaire) : Snapclient uniquement → se connecte au maître via Snapcast.

### 3. Coupler l'enceinte Bluetooth (si non saisie pendant l'installation)

```bash
ssh pi@soundspot.local
bluetoothctl
  power on
  scan on
  # Attendre que l'enceinte apparaisse
  pair XX:XX:XX:XX:XX:XX
  trust XX:XX:XX:XX:XX:XX
  connect XX:XX:XX:XX:XX:XX
  exit

sudo nano /opt/soundspot/soundspot.conf   # renseigner BT_MAC et BT_MACS
sudo systemctl enable --now bt-autoconnect
```

Ou utiliser l'assistant interactif (peut être exécuté après l'installation) :

```bash
bash bt_update.sh pi@soundspot.local
```

---

## Utilisation

### Côté DJ

Installer Snapclient et Mixxx sur le PC :

```bash
# Snapclient
sudo apt install snapclient
# Mixxx
sudo apt install mixxx
```

Se connecter au WiFi `SPOT_NAME` puis lancer :

```bash
snapclient -h 192.168.10.1   # retour casque (monitoring local, latence nulle)
mixxx
```

Dans Mixxx, activer le **Live Broadcasting** :

| Champ | Valeur |
|---|---|
| Type | Icecast2 |
| Serveur | `192.168.10.1` |
| Port | `8111` |
| Montage | `/live` |
| Login | `source` |
| Mot de passe | valeur de `WIFI_PASS` dans `soundspot.conf` |
| Format | Ogg Vorbis |

Cliquer sur l'icône **Antenne** dans Mixxx pour démarrer l'émission.

> **⚠ Latence 1-3 s** — les buffers Icecast + ffmpeg + Snapcast introduisent un délai incompressible. Calez vos mix sur la **pré-écoute casque (Cue) de Mixxx**, pas sur le son de l'espace public.

### Côté visiteur

1. Se connecter au WiFi `SPOT_NAME` — **réseau ouvert, aucun mot de passe**
2. Le portail SoundSpot surgit automatiquement (test de connectivité HTTP intercepté)
3. Cliquer **« J'ai lu »** — ouvre **15 minutes** d'accès Internet complet
4. Installer et lancer Snapclient pour écouter le stream audio :
   ```
   Android : Snapdroid (Play Store)
   Linux   : snapclient -h 192.168.10.1
   Windows : snapclient GUI sur snapcast.de
   ```

> Après 15 min, le téléphone affiche « Se connecter au réseau » → rouvrir le portail pour revalider.
> Le stream Snapcast (port 1704) reste accessible à tout moment, sans quota.

---

## Déploiement multi-enceintes (satellites)

Plusieurs RPi Zero 2W, chacun avec sa propre enceinte Bluetooth, synchronisés par Snapcast :

```
[Réseau qo-op — Internet]
    ├── [PC DJ]              → Mixxx → maître:8111/live (Icecast)
    ├── [RPi Maître]         → Icecast → Snapserver :1704 + Snapclient → BT A
    ├── [RPi Satellite 1]    → Snapclient → maître:1704 → BT B
    └── [RPi Satellite 2]    → Snapclient → maître:1704 → BT C

[WiFi AP SPOT_NAME — visiteurs]
    └── [Smartphones]        → Snapclient → maître:1704
```

**Déploiement d'un satellite** — identique au maître, mode différent :

```bash
ssh pi@soundspot-sat.local
git clone https://github.com/papiche/sound-spot
cd sound-spot
sudo bash deploy_on_pi.sh --satellite
# → entrer le hostname du maître : soundspot.local
```

---

## Détecteur de présence

La caméra Pi Module 3 (75°) détecte automatiquement les visiteurs et joue un message d'accueil vocal.

- **Détection** : Haar cascade OpenCV sur image 80×60 px — ~5 ms CPU, pas de ML lourd
- **Cooldown** : 30 secondes entre deux messages (configurable dans `soundspot.conf`)
- **Audio** : synthèse vocale française (`espeak-ng`, voix `fr+f3`), générée à l'installation

Personnaliser le message :

```bash
espeak-ng -v fr+f3 -s 120 -p 45 \
  "Bienvenue sur MonSpot ! Connectez-vous en WiFi puis lancez Snapclient." \
  -w /opt/soundspot/welcome.wav
```

---

## Services systemd (sur le RPi maître)

| Service | Rôle |
|---|---|
| `soundspot-channel-sync` | Lit le canal réel de wlan0 au boot, corrige hostapd.conf |
| `uap0` | Interface WiFi AP virtuelle (MAC dérivée de wlan0) |
| `hostapd` | Point d'accès WiFi (SSID) |
| `dnsmasq` | DHCP + DNS — appelle `dhcp_trigger.sh` à chaque bail |
| `ipset-soundspot` | Liste blanche `soundspot_auth` — timeout 15 min par entrée |
| `lighttpd` | Portail captif HTTP (intercepte port 80 via iptables REDIRECT) |
| ~~`opennds`~~ | ~~Portail captif~~ — **désactivé/masqué** (conflit iptables avec lighttpd) |
| `icecast2` | Relais audio Ogg (reçoit Mixxx Live Broadcasting) |
| `soundspot-decoder` | `ffmpeg` en boucle : Icecast → PCM → `/tmp/snapfifo` |
| `snapserver` | Serveur Snapcast (lit le pipe PCM, synchronise les clients) |
| `soundspot-client` | Snapclient → PipeWire → BT (maître ET satellites) |
| `bt-autoconnect` | Reconnexion BT au démarrage |
| `soundspot-presence` | Détecteur caméra + message d'accueil (maître seulement) |
| `soundspot-battery` | Monitoring batterie INA219 (optionnel) |

```bash
sudo systemctl status soundspot-*
http://192.168.10.1:1780    # interface web Snapcast
```

---

## Licence

AGPL-3.0 — [G1FabLab](https://opencollective.com/monnaie-libre) / [UPlanet ẐEN](https://qo-op.com) / [zicmama.com](https://zicmama.com)
