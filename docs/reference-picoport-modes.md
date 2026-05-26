# Référence : Modes Picoport — Rôles et Capacités

Le **Picoport** est un nœud [Astroport.ONE](https://astroport.one) embarqué dans chaque SoundSpot.
Il fournit une identité décentralisée (IPFS + NOSTR + G1), un accès à l'IA collective (BRO),
et permet à chaque appareil du réseau — enceinte satellite, smartphone visiteur, laptop DJ,
drone — de rejoindre la **constellation UPlanet**.

---

## Mode MAÎTRE

**Matériel cible :** RPi 4 / RPi 5 (recommandé) — RPi Zero 2W (possible, limité)

Le nœud maître est le cœur du dispositif. Il crée le réseau WiFi et orchestre tous les services.

### Services actifs

| Service | Port | Rôle |
|---------|------|------|
| Hostapd (AP `uap0`) | — | Réseau WiFi visiteurs ouvert |
| Icecast2 | 8111 | Réception du flux DJ |
| Snapserver | 1704 | Diffusion audio synchronisée |
| Lighttpd (portail) | 80 | Portail captif visiteurs |
| IPFS Kubo | 4001/8080 | Stockage décentralisé |
| Picoport daemon | — | Identité NOSTR + G1 + publication IPNS |
| BRO DM daemon | — | IA conversationnelle par DM NOSTR |
| strfry tunnel | 9999 | Relay NOSTR du swarm |

### Capacités augmentées (tunnels swarm)

Grâce à `astrosystemctl enable`, le maître accède aux Brain-Nodes de la constellation :

- **Ollama** (`:11434`) → IA générative locale ou distante (BRO, commentateur vidéo)
- **Orpheus TTS** (`:5005`) → Voix naturelle pierre/amelie (vs robot espeak-ng)
- **Qdrant** (`:6333`) → Mémoire vectorielle partagée (KB nextcloud, mémoires MULTIPASS)
- **NextCloud** (`:8001`) → Stockage documents synchronized avec la KB BRO

### Fonctionnalités portail

- Streaming audio en direct (Snapcast over WiFi)
- **Jukebox** : visiteurs votent pour les morceaux NOSTR via smartphone
- **uDRIVE** : upload photos/vidéos chiffrés sur IPFS + NOSTR
- **Régie VJ** : sélection flux vidéo drone, commentateur IA live
- **BRO** : assistant IA par DM NOSTR (questions, mémoire, craft)
- **Paiements G1** : QR code Ğ1 pour services, contributions ẑen

### Lancer en mode maître

```bash
sudo bash deploy_on_pi.sh --master
# ou en interactif :
sudo bash deploy_on_pi.sh
```

---

## Mode SATELLITE

**Matériel cible :** RPi Zero 2W (idéal — faible consommation, WiFi intégré)

Un satellite reçoit le flux audio du maître et le diffuse sur une enceinte Bluetooth déportée.
Il rejoignit automatiquement la constellation UPlanet via Picoport.

### Services actifs

| Service | Rôle |
|---------|------|
| Snapclient | Réception audio synchronisée depuis le maître |
| PipeWire | Routage audio local → enceinte BT |
| Picoport daemon | Identité NOSTR + G1 + swarm IPFS |
| BRO DM daemon | IA via tunnels swarm (pas d'Ollama local) |

### Connexion réseau

```
WiFi qo-op (wlan0)  →  Snapserver maître (192.168.X.X:1704)
WiFi qo-op (wlan0)  →  IPFS swarm constellation
WiFi qo-op (wlan0)  →  Relay NOSTR (tunnel x_strfry.sh)
```

Le satellite n'ouvre **pas** de point d'accès WiFi propre. Il consomme le réseau upstream.

### Lancer en mode satellite

```bash
sudo bash deploy_on_pi.sh --satellite
```

### Capacités BRO sur satellite

Via `astrosystemctl enable qdrant` + `astrosystemctl enable ollama` (activé en step 9 de install_picoport.sh) :
- BRO répond aux DMs NOSTR adressés à ce nœud
- Qdrant et Ollama sont fournis par le Brain-Node du swarm
- L'identité G1 permet les paiements ẑen même hors ligne (mode dégradé)

---

## Mode SMARTPHONE

**Matériel :** Tout smartphone iOS / Android avec WiFi + navigateur

Le smartphone devient un **participant actif** de l'écosystème SoundSpot — pas un simple écouteur.

### Connexion

```
WiFi AP SoundSpot (ex: ZICMAMA)  →  portail captif (192.168.10.1)
```

### Fonctionnalités

| Fonctionnalité | Comment |
|----------------|---------|
| **Écoute audio** | Snapcast.js ou VLC pointé sur `http://192.168.10.1:8111/live` |
| **Jukebox** | Depuis le portail : proposer + voter des morceaux (NOSTR kind 9) |
| **uDRIVE upload** | Photos, vidéos → IPFS → publication NOSTR automatique |
| **MULTIPASS** | Authentification NIP-07 ou clé partagée (NIP-42) |
| **BRO par DM** | Via une app NOSTR (Amethyst, Damus) → DM au node npub |
| **Paiements G1** | Scan QR code, payer en Ğ1 via portefeuille Silkaj / Tikka |
| **Internet** | 4h d'accès après validation portail (ipset timeout 14400s) |

### Devenir MULTIPASS sur smartphone

1. Connectez-vous au WiFi SoundSpot
2. Accédez au portail → cliquez **MULTIPASS**
3. Ou visitez `http://192.168.10.1:8080/ipns/copylaradio.com/` pour créer votre compte UPlanet

---

## Mode LAPTOP DJ

**Matériel :** Laptop (Linux/Mac/Windows) avec Mixxx + WiFi

Le laptop DJ est la **source du son**. Mixxx diffuse en live, Snapcast distribue aux enceintes.

### Installation DJ

```bash
bash dj_mixxx_setup.sh    # Installe Snapclient + Mixxx + génère ~/zicmama_play.sh
```

### Flow audio

```
Mixxx (Live Broadcasting)
  → Ogg Vorbis → Icecast2 :8111/live
    → ffmpeg decoder (PCM 48kHz) → /dev/shm/snapfifo
      → Snapserver :1704
        → Snapclient (casque DJ, latence 1-3s)
        → Visiteurs WiFi (smartphone, satellite)
        → Enceintes BT maître + satellites
```

### Fonctionnalités augmentées

| Fonctionnalité | Détail |
|----------------|--------|
| **Casque monitor** | Snapclient local pour écoute en retard (synchronisation BPM via Mixxx CUE) |
| **BRO curation** | DM NOSTR au node → suggestions de playlist, analyse ambiance |
| **uDRIVE** | Upload setlist, artwork, visuels depuis le portail |
| **Régie VJ** | Contrôle projecteur vidéo en parallèle du mix audio |
| **Paiements** | Accepter des dons G1 en live via QR code affiché sur le portail |

### Démarrer une session DJ

```bash
~/zicmama_play.sh      # Lance Snapclient monitoring + ouvre Mixxx
```

Dans Mixxx : **Préférences → Live Broadcasting** → configurer `127.0.0.1:8111` mount `/live`.

---

## Mode DRONE / CAMÉRA

**Matériel :** DJI (RTMP), GoPro, caméra IP WiFi, RPi Camera Module 3

Le drone enrichit le SoundSpot d'une **dimension visuelle** : stream RTMP en direct,
commentaire IA automatique, projection sur écran HDMI.

### Connexion

```
Drone DJI / GoPro
  → WiFi SoundSpot AP
    → RTMP rtmp://192.168.10.1/live/<nom_stream>
      → stream_event.sh notifie le VJ
        → Régie VJ (vj.html) → sélection → MPV --vo=drm HDMI
```

### Commentateur IA en temps réel

Via le **Commentateur IA** (portail VJ) activé sur le flux sélectionné :

```
Flux RTMP actif
  → ffmpeg capture frame JPEG
    → Ollama llava (tunnel swarm :11434)
      → description IA (styles: Concert / Accueil / Poétique / Libre)
        → Orpheus TTS (tunnel swarm :5005)
          → pw-play → enceintes SoundSpot
```

Fréquence réglable : 15s → 5min. Activation/désactivation depuis `vj.html`.

### NOSTR et GPS

Si la caméra supporte les métadonnées GPS :
- Position publiée en kind 1 NOSTR avec tag `g` (géolocalisation)
- Visible sur la carte UPlanet (`/ipns/copylaradio.com`)

### Streaming depuis drone DJI

Dans l'app DJI Go / DJI Fly :
- Custom RTMP : `rtmp://192.168.10.1/live/drone1`
- Le VJ voit apparaître `drone1` dans la liste des flux

---

## Mode INTER MESH

**Matériel :** Plusieurs RPi Zero 2W ou RPi 4/5 en réseau

Le mode Inter Mesh connecte plusieurs SoundSpots en une **constellation partagée** :
même swarm IPFS, même relay NOSTR, même base de connaissance BRO.

### Infrastructure

```
SoundSpot A (Maître Paris)
  ├── IPFS swarm /key/0000…0000
  ├── Relay NOSTR relay.copylaradio.com
  ├── Brain-Node GPU : Ollama + Qdrant
  └── astrosystemctl : publie x_ollama.sh, x_qdrant.sh

SoundSpot B (Satellite Lyon)
  ├── IPFS swarm /key/0000…0000  (même swarm key = même constellation)
  ├── tunnel x_ollama.sh → :11434 (délègue au Brain Paris)
  ├── tunnel x_qdrant.sh → :6333
  └── BRO répond avec la KB de Paris !
```

### Partage de ressources IA

| Ressource | Brain-Node → Light-Node | Mécanisme |
|-----------|------------------------|-----------|
| Ollama (LLM) | Paris → Lyon | IPFS P2P `/x/ollama-NODEID` |
| Qdrant (mémoire) | Paris → Lyon | IPFS P2P `/x/qdrant-NODEID` |
| Orpheus (voix) | Paris → Lyon | IPFS P2P `/x/orpheus-NODEID` |
| nextcloud_kb | Partagée | Même API-key UPLANETNAME |

### Actions coordonnées (Fleet)

```bash
# Depuis le maître (fleet_commander.sh) :
./fleet_commander.sh announce "Concert dans 5 minutes !"
./fleet_commander.sh shutdown   # Arrêt propre de toute la flotte
```

- Protocole : Kind 9 NOSTR local (port 9999)
- Chiffrement : clé de flotte partagée (`FLEET_KEY`)
- Portée : tous les nœuds connectés au même relay NOSTR

### Synchronisation musicale multi-sites

Si deux SoundSpots partagent la même connexion Internet (ex: Festival multi-scènes) :
- **Maître A** diffuse sur Icecast `:8111`
- **Maître B** pointe son `ffmpeg decoder` sur `http://A:8111/live`
- Les visiteurs des deux sites entendent le même mix au même instant

### Activer un tunnel entre deux sites

```bash
# Sur le Light-Node Lyon :
asys-swarm              # Voir les Brain-Nodes disponibles (Paris visible ?)
asys-qdrant             # Activer tunnel Qdrant → Brain Paris
asys-ollama             # Activer tunnel Ollama → Brain Paris

# Statut :
astrosystemctl status
```

---

## Tableau récapitulatif

| Mode | Hardware | AP WiFi | Audio Out | IA locale | BRO | Paiements G1 |
|------|----------|---------|-----------|-----------|-----|--------------|
| **Maître** | RPi 4/5 | ✅ | Icecast+Snap | via tunnels | ✅ full | ✅ |
| **Satellite** | RPi Zero 2W | ❌ | Snapclient | via tunnels | ✅ light | ✅ |
| **Smartphone** | iOS/Android | ❌ | Snap/VLC | ❌ | via DM | QR seulement |
| **Laptop DJ** | PC/Mac | ❌ | Snapclient | ❌ | via DM | ✅ |
| **Drone** | DJI/GoPro | ❌ | ❌ | Ollama vision | ❌ | ❌ |
| **Inter Mesh** | Multi-RPi | ✅ par nœud | Sync inter-sites | partagée | ✅ constellation | ✅ |

---

## Architecture Y-Level (identité picoport)

Chaque picoport génère une identité déterministe depuis sa clé SSH :

```
id_ed25519 (SSH)
  → sha512sum → SECRET1 + SECRET2
    → keygen -t ipfs   → IPFS PeerID (identité swarm)
    → keygen -t nostr  → NPUB/NSEC (identité BRO + DMs)
    → keygen -t g1     → G1PUB/dunikey (portefeuille Ğ1)
```

**Propriété clé :** si la clé SSH est sauvegardée, toute l'identité est restaurable.
Stocker `~/.ssh/id_ed25519` + `~/.ssh/id_ed25519.pub` dans un lieu sûr.

---

## Voir aussi

- [Architecture générale](explanation-architecture.md)
- [Premier nœud maître](tutorial-premier-noeud.md)
- [Mesh satellite](howto-mesh-satellite.md)
- [Configuration DJ](howto-dj-configuration.md)
- [Régie VJ drone](howto-vj-drone.md)
- [Survie festival](howto-festival-survival.md)
- [API et configuration](reference-api-config.md)
