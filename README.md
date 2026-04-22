# SoundSpot — Zicmama / PicoPort <=> Astroport / UPlanet / ORIGIN / ẐEN / ẑen

[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/12624/badge)](https://www.bestpractices.dev/projects/12624)

**Nœud audio collectif libre** — infrastructure sonore décentralisée pour espaces publics et tiers-lieux.

SoundSpot transforme un Raspberry Pi Zero 2W en point d'accès WiFi permettant à n'importe qui de diffuser sa musique sur les enceintes du lieu depuis son ordinateur, sans installation ni compte. La caméra intégrée détecte les visiteurs et joue automatiquement un message d'accueil vocal.

En option, **Picoport** transforme le même RPi en micro-nœud UPlanet : identité IPFS + Nostr + Ğ1 déterministe, capabilité de paiement ẑen (gcli Duniter v2s), et connexion au swarm de calcul IA décentralisé via `astrosystemctl`.

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
mkdir -p ~/.zen/workspace
cd ~/.zen/workspace

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

Ou utiliser le diagnostic complet (en SSH sur le RPi) :

```bash
check         # alias installé par Picoport dans ~/.bashrc
# ou directement :
sudo bash ~/sound-spot/check.sh
```

---

## Picoport — nœud UPlanet intégré

Activé par défaut lors de l'installation (`deploy_on_pi.sh` pose la question).
Transforme le SoundSpot en micro-nœud coopératif : identité IPFS/Nostr/Ğ1, paiements ẑen, accès au swarm de calcul IA.

Commandes disponibles après installation (dans le shell `pi`) :

```bash
pico-status          # état IPFS, BT, snapcast, batterie
pico-power           # Power-Score (🌿 Light sur Zero 2W → délègue au swarm)
asys-swarm           # Brain-Nodes GPU disponibles dans la constellation
ai ollama            # tunnel P2P vers le meilleur nœud Ollama du swarm
clock-bells          # clocher — coups à l'heure
clock-silent         # clocher — heure vocale seule
```

Les paiements Ğ1 (Duniter v2s) sont disponibles via `gcli` (`g1cli` installé dans `/usr/local/bin`).

---

### Description et rôle du Mode Picoport

Le mode **Picoport** est l'épine dorsale web3 et IA du SoundSpot. En l'activant, le RPi Zero 2W devient un micro-nœud de l'essaim "UPlanet". 

Voici ce qu'il accomplit en tâche de fond :
1. **Transmutation Cryptographique (Y-Level)** : À l'installation, il génère une clé SSH (Ed25519) locale. Le hash de cette clé (le *salt & pepper*) sert de graine déterministe pour générer l'identité de son nœud IPFS (`PeerID`), son identité monnaie libre `Ğ1 / ẑen`, et son Multipass Nostr. Le nœud a donc une seule et même identité prouvable mathématiquement sur SSH, IPFS, Duniter et Nostr.
2. **IPFS Isolé en Basse Énergie** : Il installe *Kubo (IPFS)* compilé pour ARM64, purge les nœuds publics, et se branche exclusivement sur la `swarm.key` UPlanet. Il utilise un profil extrême basse consommation (`CPUQuota=40%`, limites de connexions baissées) pour ne pas entraver le flux audio.
3. **Paiements et Monnaie Libre** : Il déploie `g1cli`, le client léger Rust pour la blockchain Duniter v2s, permettant au nœud de recevoir/émettre des pourboires et de signer des contrats.
4. **Découverte et Essaim IA (Swarm)** : Le démon `picoport.sh` sonde ses voisins IPFS P2P. Étant donné que le RPi Zero 2W n'a qu'un *Power-Score* très bas (Score : 1 = "🌿 Nœud Light"), il délègue les tâches d'Intelligence Artificielle. Grâce à `astrosystemctl`, le nœud mappe ses ports P2P vers les "Brain-Nodes" de la constellation (des PC plus puissants qui font tourner `Ollama` ou `Strfry`), lui permettant de générer les requêtes Jukebox ou IA à distance, comme s'il les calculait en local.
5. **Survie Solaire (Le Chrono 20h12)** : Un cron basé sur **l'heure solaire** (calculée avec la longitude GPS via `solar_time.sh`) déclenche le signal de maintenance à `20h12 solaire`. Le nœud envoie alors une balise de survie (Niveau de batterie, Uptime) via Nostr sur `wss://relay.copylaradio.com`.

Le SoundSpot version PicoPort permet de dsposer de zones de diffusion de son multipoints chainable et accesible à distance
il sert à faire la promotion du "Bien Commun Numérique" et physique (AGPL).

La rencontre Homme/Machine qui pour fonctionner a besoin de recharge et changement de batterie, elle connait et annonce le cout de tous ses composants :
 * PiZ2W pour la bouche et les oreilles
 * Pi4/Pi5 pour la vision et le stockage
 * PC Gamer / GPU pour le calcul, la mémoire

+ Client Smartphone "Zelkova" (ẑen) 
+ Parrain ẐEN (historique "ZEN Card") 

- UPlanet ORIGIN & ẐEN - 

Acteurs / Armateurs / Capitaines
Constellations IPFS reliées par NOSTR
NextCloud / uDRIVE / MULTIPASS
IA / GeoKey UMAP / synchro N²

Ce programme fait partie des oeuvres nuémériques libres sélectionnées, reliés et maintenus par les adhérents du G1FabLab 

# Système de logs — /var/log/sound-spot.log

Format du log

```
2026-04-19 14:23:45 [INFO ] [idle        ] annonce h14:00 mode=bells
2026-04-19 14:23:46 [DEBUG] [idle        ] coups de cloche : 2
2026-04-19 14:23:50 [INFO ] [picoport    ] statut modifié — publication IPNS (icecast=true snapcast=true)
2026-04-19 14:24:01 [WARN ] [picoport    ] swarm vide — reconnexion aux bootstraps UPlanet
2026-04-19 14:24:05 [INFO ] [presence    ] picamera2 (libcamera) ouverte — 320x240 @ 15 fps
2026-04-19 14:24:10 [ERROR] [battery     ] Erreur lecture INA219 : I2C bus not found
```

Changer le niveau en live

```
# Éditer soundspot.conf (relu à chaque cycle par idle_announcer)
sed -i 's/LOG_LEVEL=.*/LOG_LEVEL="DEBUG"/' /opt/soundspot/soundspot.conf
# Redémarrer presence et battery (lisent LOG_LEVEL au démarrage)
systemctl restart soundspot-presence soundspot-battery
```

Consulter les logs

```
tail -f /var/log/sound-spot.log          # tous les services
grep '\[ERROR\]' /var/log/sound-spot.log  # erreurs uniquement
grep '\[picoport\]' /var/log/sound-spot.log  # picoport uniquement
```

## Licence

AGPL-3.0 — [G1FabLab](https://opencollective.com/monnaie-libre) / [UPlanet ẐEN](https://qo-op.com) / [zicmama.com](https://zicmama.com)

## External Interface & API Reference
The API HTTP (Port 80) and the Web3 NOSTR Interface (Jukebox) are fully documented for developers in [DEV.md](DEV.md).

*🇬🇧 English speakers: We welcome issues, bug reports, and Pull Requests in English. Please refer to our [CONTRIBUTING.md](CONTRIBUTING.md) file.*