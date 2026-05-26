# 🐷 SoundSpot (CyberCochon) – Guide de Fabrication Complet  
**Nœud coopératif audio UPlanet ẐEN – Infrastructure décentralisée off-grid**  
(Solaire / 5G / IA / Mesh B.A.T.M.A.N.)

🔗 **Wishlist Amazon centrale :** [https://www.amazon.fr/hz/wishlist/ls/1SGWKRK1Q1WHA](https://www.amazon.fr/hz/wishlist/ls/1SGWKRK1Q1WHA)

---

## 1. Nomenclature Matérielle et Budget

Chaque composant est relié à son rôle exact dans les scripts (ex. `battery_monitor.py`, `mesh_batman.sh`, `mon-oeil.py`).

### 🔋 A. Énergie Solaire et Survie (Bus 12V)

| Composant | Réf. Amazon recommandée | Usage dans le code / projet | Prix estimé |
|:---|:---|:---|:---|
| **Panneau solaire** | Borrow Power 100W pliable (18V) | Alimentation primaire off-grid – `howto-festival-survival.md` | 139,95 € |
| **Contrôleur MPPT** | Victron Energy SmartSolar 75/15 | Gestion intelligente de charge batterie (Bluetooth) | 130 € (ou ~63 € selon promo) |
| **Batterie LiFePO₄** | ECO-WORTHY 12V 30 Ah | Stockage – profil tension géré dans `battery_monitor.py` | 99,00 € |
| **Sac ignifuge** | Lipo Sac de protection | Sécurité incendie pour transport / stockage batterie | 22,10 € |
| **Boîtier à fusibles** | Vaskula 4 voies (10–30 A) | Sécurisation bus 12V vers convertisseurs | 9,99 € |
| **Moniteur de puissance** | Binghe INA219 I²C | Mesure tension batterie → shutdown si <20% (`battery_monitor.py`) | 9,99 € |
| **Relais interrupteur** | Giantdeer 3V optocoupleur | Branché sur **GPIO 17** (survie) – coupe tout le système | ~10 € |
| **StepDown DC-DC 12V→5V** | QIQIAZI / Zorblix 12V→5V 5A | Alimente le Raspberry Pi via ses pins 5V/GND | 11,99 € |
| **Alimentation accessoires** | Thlevel 65W PD USB-C | Alimente projecteur ou routeur 5G via relais | 12,99 € |

### 🧠 B. Cœur Informatique, Connectique & Refroidissement

| Composant | Réf. Amazon recommandée | Usage dans le code / projet | Prix estimé |
|:---|:---|:---|:---|
| **Nœud maître** | Raspberry Pi 4 – Modèle B 2 Go | Cerveau : audio, picoport, caméra, portail captif | ~100 € |
| **Nœud énergie / satellite** | Raspberry Pi Zero 2 W | Satellite audio + contrôleur batterie (`IS_ENERGY=True`) | ~20 € |
| **Boîtier passif** | Geekworm boîtier radiateur | Évite l’étranglement thermique (lu par `check.sh`) | ~12 € |
| **Carte SD endurance** | SanDisk MAX ENDURANCE 32 Go | Protégée par `zram.sh` & `log2ram` | 35,49 € |
| **Câblage GPIO** | FULARR 120pcs DuPont + ZDE 40 pins | Branchements INA219 (I²C) et relais | 20,98 € |

### 🎬 C. Réseau, Audiovisuel, IA & VJ

| Composant | Réf. Amazon recommandée | Usage dans le code / projet | Prix estimé |
|:---|:---|:---|:---|
| **Routeur 5G Internet** | ZTE 5G CPE MC888 | Accès amont (wlan0/eth0) pour le swarm UPlanet | 208,19 € |
| **Dongle Wi‑Fi 5GHz mesh** | Vemfay RTL88x2bu *(ou voir tableau compatibilité)* | Interface `wlan1` → mode ad‑hoc → `mesh_batman.sh` | ~15-30 € |
| **Caméra IA** | Raspberry Pi Camera Module 3 (SC1223) | Détection mouvement – `mon-oeil.py` / `presence_detector.py` | 32,98 € |
| **Micro ambiance** | ReSpeaker 2‑Mics Pi HAT | Capture son live → `/dev/shm/snapfifo_mic` | ~15 € |
| **Enceinte Bluetooth** | W‑KING D9‑1 | Gérée par PipeWire + `bt-autoconnect.sh` (BlueZ) | ~85 € |
| **Émetteur FM** | Bewinner FM 0.5W | Branché sur jack 3,5 mm – `split_audio.sh` | 37,90 € |
| **Vidéoprojecteur** | Nebula Capsule 3 1080p | Régie VJ (HDMI) – relais sur GPIO 18 (`projector.sh`) | 419,99 € |
| **Relais projecteur** | Giantdeer 3V (même lot que survie) | Coupe l’alimentation du projecteur depuis l’API Web | inclus ci‑dessus |
| **Drone VJ** | DJI Neo Mini Drone 4K | Flux RTMP → portail captif → `rtmp_player.sh` | 169,94 € |

*Budget total : version audio de base (sans routeur 5G, sans vidéo) ≈ 300–400 € ; version festival complète (solaire + 5G + projecteur + drone) ≈ 1300–1500 €.*

---

## 2. Enchaînement Détaillé des Séquences de Fabrication

Le montage suit 5 étapes, de l’électronique à la gestion d’énergie.

### SÉQUENCE 1 : Montage Électronique et Câblage Énergie (Hardware)

1. **Bus solaire 12V**  
   - Panneau **Borrow Power 100W** → entrée PV du **Victron MPPT 75/15**.  
   - Batterie **ECO‑WORTHY 30 Ah** (dans le **sac ignifuge**) → sortie batterie du MPPT.  
   - Positif batterie → **boîtier à fusibles Vaskula** (fusibles 5A/10A).

2. **Câblage du nœud maître (RPi 4)**  
   - RPi 4 dans **boîtier Geekworm**.  
   - Convertisseur **QIQIAZI 12V→5V** : entrée 12V sur fusible Vaskula, sortie 5V sur **pin 2 (5V)** et **pin 6 (GND)** du RPi (via câbles DuPont).  
   - Caméra **Module 3** sur port CSI.

3. **Câblage I²C (INA219) et relais**  
   - **INA219** :  
     - `VCC` → pin 1 (3,3V)  
     - `GND` → pin 9 (GND)  
     - `SDA` → pin 3 (GPIO 2)  
     - `SCL` → pin 5 (GPIO 3)  
     - `VIN+` → pôle **positif batterie 12V** (mesure tension).  
   - **Relais de survie** (GPIO 17) : commande l’alimentation générale.  
   - **Relais projecteur** (GPIO 18) : commande l’alimentation du **Nebula Capsule 3** via le **Thlevel 65W PD**.

### SÉQUENCE 2 : Flashage et Déploiement Système (Software)

1. **Préparation carte SD**  
   - Utiliser **SanDisk MAX ENDURANCE 32 Go**.  
   - Flasher **Raspberry Pi OS Lite 64‑bit (Bookworm)** avec *Raspberry Pi Imager*.  
   - Configurer hostname (`soundspot`), utilisateur (`pi`), Wi‑Fi amont (routeur ZTE 5G – SSID `qo-op`, mot de passe `0penS0urce!`).

2. **Installation automatique**  
   ```bash
   ssh pi@soundspot.local
   git clone https://github.com/papiche/sound-spot
   cd sound-spot
   sudo bash deploy_on_pi.sh --master   # pour le nœud principal
   # Pour un nœud énergie/satellite : --satellite
   ```

3. **Ce que fait le script**  
   - Active `zram.sh` : désactive le swap sur SD, monte un swap compressé en RAM (lz4/zstd).  
   - Configure `log2ram` : `/var/log` en RAM → préserve la carte SD.  
   - Installe les drivers `libcamera` pour le module SC1223.  
   - Installe les dépendances Python pour l’INA219 (`pi-ina219`).  
   - Met en place les services systemd (snapserver, snapclient, mon-oeil, etc.).

### SÉQUENCE 3 : Topologie Réseau et Routage (Network)

Le système gère trois réseaux simultanément :

| Interface | Rôle | Script associé |
|:---|:---|:---|
| `wlan0` ou `eth0` | Accès Internet (routeur ZTE 5G) | `networking.sh` |
| `uap0` (virtuelle) | AP public **ZICMAMA** (portail captif) | `hostapd` + `soundspot-firewall.sh` |
| `wlan1` (dongle 5GHz) | Réseau maillé **CYBERCOCHON_MESH** (B.A.T.M.A.N.) | `mesh_batman.sh` |

- **Portail captif** : redirection `iptables` de tout le trafic HTTP vers Lighttpd (port 80). L’utilisateur accepte les CGU → ajout à `ipset soundspot_auth` (bail 4h).  
- **Mesh** : `wifi_driver.sh` détecte automatiquement le chipset du dongle USB branché (via `lsusb`) et installe le driver approprié. `bat0` permet la découverte multicast (`soundspot.local`) sans DHCP central. Voir le tableau de compatibilité ci-dessous.

#### Dongles Wi-Fi 5GHz compatibles avec le mesh

Le critère décisif est le **mode IBSS (ad-hoc)**, requis par B.A.T.M.A.N.-adv.
Le script `wifi_driver.sh` détecte le chipset via `lsusb` et installe automatiquement
le bon driver.

| Chipset | Driver | Compilation | Exemples de clés | Prix indicatif |
|---------|--------|:-----------:|-----------------|---------------|
| **RTL88x2bu** | DKMS morrownr | ⏱ 5-20 min | Vemfay (référence), Netgear A8000 | ~15-30 € |
| **RTL8812AU** | DKMS morrownr | ⏱ 5-20 min | TP-Link Archer T4U, ASUS USB-AC56 | ~20-40 € |
| **MT7612U** | in-kernel `mt76` | ✅ aucune | COMFAST CF-926AC, BrosTrend AC3L | ~15-25 € |
| **MT7921AU** | in-kernel `mt7921u` | ✅ aucune | Linksys WUSB6400M | ~20-35 € |

> **Recommandation** : préférer un dongle **MT7612U ou MT7921AU** (driver in-kernel,
> aucune compilation, plus stable à long terme). Les dongles Realtek nécessitent
> une recompilation DKMS à chaque mise à jour du noyau.

> **Avertissement compilation DKMS** : sur RPi Zero 2W, la compilation prend jusqu'à
> **20 minutes**. Le système est opérationnel pendant ce temps, mais ne pas débrancher
> le RPi ni la clé USB.

Pour vérifier que le mesh est actif après installation :
```bash
ip link show wlan1   # doit apparaître
ip link show bat0    # doit apparaître après démarrage de soundspot-mesh
batctl n             # liste les voisins mesh détectés
```

### SÉQUENCE 4 : Audiovisuel, IA et Régie (Services)

#### 🔊 Pipeline audio (Snapcast + PipeWire)
- Un DJ envoie un flux Ogg Vorbis vers **Icecast (port 8111)**.  
- `soundspot-decoder.service` (FFmpeg) décompresse le flux en PCM brut dans `/dev/shm/snapfifo`.  
- **Snapserver** (port 1704) lit ce FIFO et synchronise l’audio.  
- **Snapclient** local envoie le son à **PipeWire**, qui le diffuse sur l’enceinte **W‑KING** (`bt-autoconnect.sh`).  
- En l’absence de DJ, `idle_announcer.sh` prend le relais : bip à 429,62 Hz, annonce vocale de l’heure solaire (GPS) via `espeak-ng`.

#### 🎥 Régie VJ (projecteur + drone)
- Vidéoprojecteur **Nebula Capsule 3** connecté en HDMI.  
- `soundspot-rtmp-player.service` lance `mpv` pour afficher un flux RTMP.  
- **Drone DJI Neo** → diffuse vers `rtmp://192.168.10.1/live/drone`.  
- Interface web du SoundSpot (onglet “VJ”) : un clic “Projeter” déclenche l’affichage sur le Nebula.

#### 👁️ IA et détection de présence
- `mon-oeil.service` scrute la caméra (1 frame/5). Détection de mouvement (OpenCV).  
- Si mouvement + son (micro **ReSpeaker**), capture d’une image (`/dev/shm/latest_frame.jpg`).  
- Envoi de l’image via **Picoport** (IPFS P2P) vers le swarm UPlanet (Ollama/LLaVA).  
- La description humoristique générée est synthétisée vocalement (Orpheus) → diffusée sur enceinte et FM.

#### 🌐 Web3 & P2P
- `picoport_init_keys.sh` génère l’identité cryptographique (hash de la clé SSH).  
- IPFS tourne (`CPUQuota=40%`) pour la synchronisation des bases de données et le **jukebox local** : un visiteur envoie une URL YouTube → `yt_copy` télécharge le MP3, l’épingle sur IPFS et l’ajoute à la queue de `jukebox_player.sh`.

### SÉQUENCE 5 : Gestion de l’Énergie – Survie de l’Essaim

1. **Surveillance batterie**  
   - `battery_monitor.py` lit l’**INA219** toutes les X secondes.  
   - Seuil critique : tension batterie < 12,8 V (≈20 % pour LiFePO₄ 12V).

2. **Déclenchement de l’arrêt**  
   - Alerte vocale “Survie batterie”.  
   - `fleet_commander.sh shutdown` est appelé.  
   - Un événement NOSTR (kind 9 éphémère) est publié sur le relais local `ws://127.0.0.1:9999`.

3. **Propagation dans le mesh**  
   - Tous les satellites (RPi Zero 2W, autres nœuds audio) reçoivent l’ordre et exécutent `poweroff`.  
   - Le nœud maître ou le nœud énergie attend 15 secondes supplémentaires, puis ouvre le **relais GPIO 17** → coupure physique de l’alimentation générale (convertisseur QIQIAZI).
