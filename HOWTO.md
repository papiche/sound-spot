# HOWTO — SoundSpot Zicmama

Deux scripts, deux rôles. C'est tout ce dont vous avez besoin.

| Script | Où le lancer | Rôle |
|---|---|---|
| `deploy_on_pi.sh` | Sur le **Raspberry Pi** | Installe le nœud (maître ou satellite) |
| `dj_mixxx_setup.sh` | Sur le **PC du DJ** | Installe Snapclient + Mixxx, génère le lanceur |

---

## Installer un nœud SoundSpot maître

### 1 — Flasher la carte SD

Utiliser **[Raspberry Pi Imager](https://www.raspberrypi.com/software/)** :

- OS : **Raspberry Pi OS Lite 64-bit (Bookworm)**
- Dans les options avancées (⚙) :

| Réglage | Valeur |
|---|---|
| Hostname | `soundspot` |
| Utilisateur | `pi` + mot de passe |
| WiFi SSID | `qo-op` |
| WiFi mot de passe | `0penS0urce!` |
| SSH | Activé |
| Pays WiFi | `FR` |

### 2 — Installer SoundSpot

Connecter la nappe caméra, insérer la SD, alimenter le RPi.
Attendre ~60 s puis :

```bash
ssh pi@soundspot.local
git clone https://github.com/papiche/sound-spot
cd sound-spot
sudo bash deploy_on_pi.sh
```

L'assistant pose 5 questions :

```
[1] Mode : Maître  →  répondre 1
[2] Nom du spot (SSID WiFi visiteurs) : ZICMAMA
[3] WiFi amont : qo-op  (Entrée pour confirmer)
[4] Mot de passe WiFi : 0penS0urce!  (Entrée)
[5] Canal WiFi : détecté automatiquement
[6] MAC enceinte BT : XX:XX:XX:XX:XX:XX  (ou Entrée pour plus tard)

? Lancer l'installation ? [oui/Non] :  oui
```

Durée : ~10 minutes. Le RPi redémarre automatiquement.

### 3 — Configurer le poste DJ (PC Linux)

```bash
bash dj_mixxx_setup.sh
# → nom du SoundSpot : ZICMAMA
# → IP du RPi : 192.168.10.1  (Entrée)
# → mot de passe Icecast : 0penS0urce!  (Entrée)
```

Crée `~/zicmama_play.sh` — le lanceur DJ en un clic.

### 4 — Jouer

```bash
~/zicmama_play.sh
```

Ce script se connecte au WiFi `ZICMAMA`, lance Snapclient en retour casque
et ouvre Mixxx avec le rappel de configuration Icecast.

Dans Mixxx : **Options → Live Broadcasting** → icône Antenne.
Le stream part sur toutes les enceintes (BT + visiteurs Snapclient).

> **Latence 1-3 s** — caler les mix sur la **pré-écoute casque (Cue)** de Mixxx,
> pas sur le son de l'espace public.

---

## Ajouter une enceinte satellite

Même procédure, mode différent :

```bash
ssh pi@soundspot-sat.local   # hostname configuré dans l'Imager
git clone https://github.com/papiche/sound-spot
cd sound-spot
sudo bash deploy_on_pi.sh --satellite
# → hostname du maître : soundspot.local
```

Le satellite se connecte au réseau **qo-op** (même canal WiFi que le maître),
reçoit le stream Snapcast et le joue sur son enceinte Bluetooth.

---

## Portail captif (page d'accueil des visiteurs)

Quand un visiteur se connecte au WiFi `ZICMAMA`, il voit une page avec **trois sections** :

- **Visiteur** — comment installer Snapclient et écouter
- **DJ** — paramètres Icecast/Mixxx pour émettre
- **Satellite** — comment ajouter une enceinte RPi supplémentaire

---

## Après l'installation

### Coupler une enceinte Bluetooth

```bash
# Interactif (depuis le PC, via SSH)
bash src/bt_update.sh pi@soundspot.local

# Ou manuellement sur le RPi
ssh pi@soundspot.local
bluetoothctl
  power on
  scan on
  pair XX:XX:XX:XX:XX:XX
  trust XX:XX:XX:XX:XX:XX
  connect XX:XX:XX:XX:XX:XX
  exit

sudo nano /opt/soundspot/soundspot.conf
# BT_MAC="XX:XX:XX:XX:XX:XX"
# BT_MACS="XX:XX:XX:XX:XX:XX"
sudo systemctl enable --now bt-autoconnect
```

### Personnaliser le message d'accueil (caméra)

```bash
ssh pi@soundspot.local
espeak-ng -v fr+f3 -s 120 -p 45 \
  "Bienvenue ! Connectez-vous au WiFi ZICMAMA et lancez Snapclient." \
  -w /opt/soundspot/welcome.wav
```

### Vérifier les services

```bash
ssh pi@soundspot.local
sudo systemctl status soundspot-*
journalctl -fu soundspot-presence    # caméra
journalctl -fu icecast2              # source DJ
journalctl -fu snapserver            # stream
```

### Clients Snapcast connectés

```
http://soundspot.local:1780
```

---

## Architecture réseau

```
[Réseau qo-op — Internet]
    ├── [PC DJ]           → Mixxx Live Broadcasting → soundspot:8111
    ├── [RPi Maître]      → Icecast → Snapserver :1704 → BT A
    ├── [RPi Satellite 1] → Snapclient → soundspot.local:1704 → BT B
    └── [RPi Satellite 2] → Snapclient → soundspot.local:1704 → BT C

[WiFi AP ZICMAMA — visiteurs]  (même canal que qo-op)
    └── [Smartphones/PC]  → Snapclient → 192.168.10.1:1704
```

Le maître crée un AP WiFi (`uap0`) sur le **même canal** que le réseau amont qo-op.
Satellites et visiteurs peuvent tous deux joindre le Snapserver, via qo-op ou via l'AP.

---

## Problèmes courants

| Symptôme | Solution |
|---|---|
| WiFi `ZICMAMA` invisible | Canal différent : `sudo nano /etc/hostapd/hostapd.conf` → `channel=X`, `sudo systemctl restart hostapd` |
| Pas de son sur l'enceinte BT | Vérifier `BT_MAC` dans `soundspot.conf`, relancer `bt-autoconnect` |
| Mixxx joue, pas de son | Live Broadcasting non activé dans Mixxx → icône Antenne |
| Satellite ne reçoit rien | Vérifier `ping soundspot.local` depuis le satellite (doit répondre) |
| Caméra non détectée | Vérifier nappe CSI : `vcgencmd get_camera` |
