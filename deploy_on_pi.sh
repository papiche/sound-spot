#!/bin/bash
# ================================================================
#  deploy_on_pi.sh — SoundSpot Zicmama
#  Programme principal — s'exécute directement sur le RPi Zero 2W
#  G1FabLab / UPlanet ẐEN — zicmama.com
#
#  Utilisation :
#    sudo bash deploy_on_pi.sh              # assistant interactif
#    sudo bash deploy_on_pi.sh --master     # mode maître (force)
#    sudo bash deploy_on_pi.sh --satellite  # mode satellite (force)
#
#  Pré-requis : RPi déjà connecté à Internet (WiFi configuré via
#               Raspberry Pi Imager ou wpa_supplicant.conf au boot).
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"

# ── Couleurs ─────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; M='\033[0;35m'; N='\033[0m'
DIM='\033[2m'

log()  { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err()  { echo -e "${R}✗${N}  $*" >&2; exit 1; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }
ask()  { echo -ne "${M}?${N}  $*"; }

# ── Vérification root ────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    err "Ce script doit être lancé avec sudo : sudo bash $0"
fi

# ── Parse arguments ──────────────────────────────────────────────
SOUNDSPOT_MODE=""
for _arg in "$@"; do
    case "$_arg" in
        --master|-m)    SOUNDSPOT_MODE="1" ;;
        --satellite|-s) SOUNDSPOT_MODE="2" ;;
        --help|-h)
            echo "Usage : sudo bash $0 [--master|--satellite]"
            echo "  --master     Mode maître  (WiFi AP + snapserver + caméra)"
            echo "  --satellite  Mode satellite (enceinte BT reliée au maître)"
            exit 0 ;;
    esac
done

clear
echo -e "${C}
  ░▀▀█░▀█▀░█▀▀░█▄█░█▀█░█▄█░█▀█
  ░▄▀░░░█░░█░░░█░█░█▀█░█░█░█▀█
  ░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀░▀░▀░▀░▀░▀${N}
  SoundSpot — G1FabLab / UPlanet ẐEN
  Installation locale sur Raspberry Pi${N}"

# ════════════════════════════════════════════════════════════════
#  1. Mode de déploiement
# ════════════════════════════════════════════════════════════════
if [ -z "$SOUNDSPOT_MODE" ]; then
    hdr "Mode de déploiement"
    echo -e "  ${C}[1]${N}  ${W}Maître${N}     — crée un réseau WiFi, diffuse la musique"
    echo -e "       ${DIM}Premier RPi : WiFi AP + Icecast + Snapserver + caméra${N}"
    echo -e "  ${C}[2]${N}  ${W}Satellite${N}  — enceinte BT supplémentaire reliée au maître"
    echo -e "       ${DIM}RPi additionnel : Snapclient → reçoit le stream du maître${N}"
    echo ""
    ask "Mode [1] : "
    read -r MODE_INPUT
    SOUNDSPOT_MODE="${MODE_INPUT:-1}"
fi

MASTER_HOST=""
SPOT_NAME=""

# ════════════════════════════════════════════════════════════════
#  2. Paramètres selon le mode
# ════════════════════════════════════════════════════════════════
if [ "$SOUNDSPOT_MODE" = "2" ]; then
    # ── Mode satellite ───────────────────────────────────────────
    hdr "Mode Satellite"
    echo -e "  Le satellite reçoit le stream du maître via Snapcast."
    echo -e "  Le maître doit être allumé et joignable sur le même réseau WiFi."
    echo ""
    ask "Hostname ou IP du maître [soundspot.local] : "
    read -r INPUT_MASTER
    MASTER_HOST="${INPUT_MASTER:-soundspot.local}"
    export MASTER_HOST
    log "Satellite → maître ${C}${MASTER_HOST}${N}"
else
    # ── Mode maître ──────────────────────────────────────────────
    hdr "Identité du SoundSpot maître"
    echo -e "  Ce nom sera le ${W}SSID WiFi${N} visible par les visiteurs."
    echo -e "  Exemples : ${C}ZICMAMA${N}  ${C}ZICMAMA_Jardin${N}  ${C}ZICMAMA_FabLab${N}"
    echo ""
    ask "Nom du spot (SSID public) [ZICMAMA] : "
    read -r INPUT_SPOT
    SPOT_NAME="${INPUT_SPOT:-ZICMAMA}"
    export SPOT_NAME
    log "SSID visiteurs : ${W}${SPOT_NAME}${N}  (réseau ouvert — portail captif)"

    echo ""
    echo -e "  ${DIM}Détecteur de présence caméra : utilise OpenCV (charge CPU élevée).${N}"
    echo -e "  ${DIM}Recommandé : Pi Camera Module 3 + Raspberry Pi 4 minimum.${N}"
    ask "Pi Camera Module 3 connectée ? [o/N] : "
    read -r INPUT_CAMERA
    export PRESENCE_ENABLED="false"
    [[ "${INPUT_CAMERA,,}" == "o" ]] && export PRESENCE_ENABLED="true" && \
        log "Détecteur de présence activé" || \
        log "Détecteur de présence désactivé"
fi

# ════════════════════════════════════════════════════════════════
#  3. Réseau WiFi amont et détection Dual-WiFi
# ════════════════════════════════════════════════════════════════
hdr "Réseau WiFi amont et Point d'Accès"

export IFACE_WAN="wlan0"
if ip link show wlan1 >/dev/null 2>&1; then
    export IFACE_AP="wlan1"
    log "Dongle WiFi USB détecté ($IFACE_AP) ! Mode Dual-WiFi activé (Performances max)."
else
    export IFACE_AP="uap0"
    log "Un seul module WiFi détecté. Utilisation de l'interface virtuelle $IFACE_AP."
fi

hdr "Réseau WiFi amont (connexion Internet)"
CURRENT_SSID=$(iwgetid -r 2>/dev/null || \
    nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '/^yes:/{print $2}' || true)
if [ -n "$CURRENT_SSID" ]; then
    log "WiFi actuel : ${C}${CURRENT_SSID}${N}"
fi

ask "SSID du réseau WiFi [${CURRENT_SSID:-qo-op}] : "
read -r INPUT_WIFI
export WIFI_SSID="${INPUT_WIFI:-${CURRENT_SSID:-qo-op}}"

ask "Mot de passe WiFi [0penS0urce!] : "
read -r INPUT_PASS
export WIFI_PASS="${INPUT_PASS:-0penS0urce!}"

# ── Connexion via NetworkManager si le SSID a changé ─────────
if [ "$WIFI_SSID" != "$CURRENT_SSID" ] && command -v nmcli &>/dev/null; then
    log "Connexion NetworkManager → ${WIFI_SSID}..."
    nmcli dev wifi connect "$WIFI_SSID" password "$WIFI_PASS" ifname wlan0 2>/dev/null \
        && log "wlan0 → ${WIFI_SSID} ✓" \
        || warn "nmcli : échec connexion (vérifier SSID/mdp et relancer)"
fi

# ════════════════════════════════════════════════════════════════
#  4. Canal WiFi (maître seulement)
# ════════════════════════════════════════════════════════════════
export WIFI_CHANNEL="6"
if [ "$SOUNDSPOT_MODE" != "2" ]; then
    hdr "Canal WiFi"
    echo -e "  Le RPi Zero 2W n'a qu'une radio — le canal de l'AP"
    echo -e "  doit correspondre au canal du réseau ${C}${WIFI_SSID}${N}."
    echo ""
    DETECTED_CHAN=$(iw dev wlan0 info 2>/dev/null | awk '/channel/{print $2; exit}' || true)
    if [[ "$DETECTED_CHAN" =~ ^[1-9][0-9]?$ ]]; then
        export WIFI_CHANNEL="$DETECTED_CHAN"
        log "Canal détecté depuis wlan0 : ${W}canal ${WIFI_CHANNEL}${N}"
    else
        ask "Canal WiFi de '${WIFI_SSID}' [6] : "
        read -r INPUT_CHAN
        if [[ "${INPUT_CHAN:-6}" =~ ^[1-9][0-9]?$ ]]; then
            export WIFI_CHANNEL="${INPUT_CHAN}"
        else
            warn "Canal invalide — défaut : 6"
        fi
    fi
    log "Canal configuré : ${W}${WIFI_CHANNEL}${N}"
fi

# ════════════════════════════════════════════════════════════════
#  5. Enceinte Bluetooth
# ════════════════════════════════════════════════════════════════
hdr "Enceinte Bluetooth"

# 1. Vérifier si des appareils sont déjà connus/connectés
log "Vérification des appareils déjà connus..."
KNOWN_DEVICES=$(bluetoothctl devices Paired 2>/dev/null || true)
if [ -n "$KNOWN_DEVICES" ]; then
    echo -e "${DIM}Appareils déjà couplés sur ce Raspberry :${N}"
    echo "$KNOWN_DEVICES" | while read -r line; do
        MAC=$(echo "$line" | awk '{print $2}')
        NAME=$(echo "$line" | cut -d' ' -f3-)
        if bluetoothctl info "$MAC" 2>/dev/null | grep -q "Connected: yes"; then
            echo -e "  - ${C}$MAC${N} ${W}$NAME${N} ${G}[Connecté]${N}"
        else
            echo -e "  - ${C}$MAC${N} ${W}$NAME${N} ${Y}[Couplé]${N}"
        fi
    done
    echo ""
fi

# 2. Option de scanner ou de sauter directement à la sélection
ask "Faire un scan Bluetooth (15s) pour chercher une enceinte ?[O/n] : "
read -r DO_SCAN
if [[ "${DO_SCAN,,}" != "n" ]]; then
    log "Préparation du contrôleur (Power ON + Pairable)..."
    rfkill unblock bluetooth 2>/dev/null || true
    {
      echo "power on"
      echo "pairable on"
      echo "discoverable on"
      echo "agent on"
      echo "default-agent"
      echo "quit"
    } | bluetoothctl >/dev/null 2>&1
    sleep 1

    echo -e "${Y}Veuillez mettre votre enceinte en MODE APPAIRAGE maintenant.${N}"
    echo -e "${DIM}(Appui long sur le bouton Bluetooth jusqu'au clignotement)${N}"
    echo ""
    ask "Prêt pour le scan ?[Appuyez sur Entrée]"
    read -r _READY

    log "Scan en cours (15 s)..."
    coproc BT { bluetoothctl; }
    echo "scan on" >&${BT[1]}

    for i in $(seq 1 15); do
        echo -ne "\r  Recherche active... $i/15s "
        sleep 1
    done
    echo -e "\n"

    echo "devices" >&${BT[1]}
    echo "quit" >&${BT[1]}
    BT_OUT=$(cat <&${BT[0]})
else
    BT_OUT=""
fi

log "Analyse des résultats..."
DEVICES=$(echo "$BT_OUT" | grep "Device " | sed 's/.*Device //' | sort -u || true)
if [ -z "$DEVICES" ]; then
    DEVICES=$(bluetoothctl devices | grep -v "Scanning" || true)
fi

if [ -z "$DEVICES" ]; then
    warn "Aucun appareil détecté ou mémorisé."
    if ! bluetoothctl show | grep -q "Powered: yes"; then
        err "Le contrôleur Bluetooth est éteint. Problème matériel ?"
    fi
    ask "Saisir la MAC manuellement (ex: F4:4E:FC:E9:C6:15) ou Entrée : "
    read -r BT_INPUT
else
    hdr "Appareils disponibles"
    echo -e "Sélectionnez votre enceinte :\n"
    
    IFS=$'\n'
    DEV_ARRAY=($DEVICES)
    
    for i in "${!DEV_ARRAY[@]}"; do
        DISPLAY_NAME="${DEV_ARRAY[$i]}"
        MAC=$(echo "$DISPLAY_NAME" | grep -oE "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}" || true)
        
        # Ajouter le statut visuel
        STATUS=""
        if [ -n "$MAC" ]; then
            if bluetoothctl info "$MAC" 2>/dev/null | grep -q "Connected: yes"; then
                STATUS=" ${G}[Connecté]${N}"
            elif bluetoothctl info "$MAC" 2>/dev/null | grep -q "Paired: yes"; then
                STATUS=" ${Y}[Couplé]${N}"
            fi
        fi

        if echo "$DISPLAY_NAME" | grep -qiE "audio|speaker|w-king|jbl|sound"; then
            echo -e "  ${C}[$((i+1))]${N} ${W}${DISPLAY_NAME}${N}${STATUS} ${G}← recommandé${N}"
        else
            echo -e "  ${C}[$((i+1))]${N} ${DISPLAY_NAME}${STATUS}"
        fi
    done
    echo -e "  ${C}[0]${N} Saisie manuelle / Ignorer"
    echo ""
    ask "Votre choix : "
    read -r CHOICE
    
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] &&[ "$CHOICE" -gt 0 ] && [ "$CHOICE" -le "${#DEV_ARRAY[@]}" ]; then
        SELECTED="${DEV_ARRAY[$((CHOICE-1))]}"
        BT_INPUT=$(echo "$SELECTED" | grep -oE "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}")
        log "Sélectionné : ${W}$BT_INPUT${N}"
    else
        ask "Adresse MAC manuelle ou Entrée : "
        read -r BT_INPUT
    fi
fi

# ── Appairage final ────────────────────────────────────────────
export BT_MAC=""
export BT_MACS=""
if [[ "${BT_INPUT:-}" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
    export BT_MAC="$BT_INPUT"
    export BT_MACS="$BT_INPUT"
    
    # On vérifie si elle est déjà couplée
    if bluetoothctl info "$BT_MAC" 2>/dev/null | grep -q "Paired: yes"; then
        log "L'enceinte ${W}${BT_MAC}${N} est déjà couplée. Tentative de reconnexion..."
        bluetoothctl connect "$BT_MAC" >/dev/null 2>&1 || true
    else
        log "Tentative d'appairage de ${BT_MAC}..."
        {
          echo "pair $BT_MAC"
          sleep 5
          echo "trust $BT_MAC"
          sleep 2
          echo "connect $BT_MAC"
          sleep 3
          echo "quit"
        } | bluetoothctl > /tmp/bt_pair_result.log 2>&1
        
        if bluetoothctl info "$BT_MAC" | grep -q "Paired: yes"; then
            log "Succès : ${G}Enceinte appairée et mémorisée !${N}"
        else
            warn "Appairage automatique incomplet (se finalisera souvent au premier son)."
        fi
    fi
    log "${DIM}Note : L'audio (PipeWire) n'étant pas encore installé, le vrai test sonore aura lieu après le redémarrage automatique.${N}"
fi

# ════════════════════════════════════════════════════════════════
#  6. Récapitulatif et confirmation
# ════════════════════════════════════════════════════════════════
echo ""
if [ "$SOUNDSPOT_MODE" = "2" ]; then
echo -e "
${W}┌────────────────────────────────────────────┐
│   Récapitulatif — SoundSpot Satellite      │
├────────────────────────────────────────────┤${N}
  Maître Snapcast : ${C}${MASTER_HOST}${N}
  Réseau amont    : ${WIFI_SSID}
  Enceinte BT     : ${W}${BT_MAC:-non configurée}${N}
${W}└────────────────────────────────────────────┘${N}"
else
echo -e "
${W}┌────────────────────────────────────────────┐
│   Récapitulatif — SoundSpot Maître         │
├────────────────────────────────────────────┤${N}
  SSID visiteurs : ${C}${SPOT_NAME}${N}  (réseau ouvert)
  Réseau amont   : ${WIFI_SSID}  (canal ${WIFI_CHANNEL})
  Enceinte BT    : ${W}${BT_MAC:-non configurée}${N}
${W}└────────────────────────────────────────────┘${N}"
fi

echo ""
ask "Lancer l'installation ? [oui/Non] : "
read -r CONFIRM
[[ "$CONFIRM" == "oui" ]] || err "Installation annulée."

# ════════════════════════════════════════════════════════════════
#  7. Dépendances minimales
# ════════════════════════════════════════════════════════════════
log "Mise à jour et dépendances minimales..."
apt-get update -qq
apt-get install -y -q gettext-base iw bluetooth

# ════════════════════════════════════════════════════════════════
#  8. Copie des scripts Python vers INSTALL_DIR
# ════════════════════════════════════════════════════════════════
export INSTALL_DIR="/opt/soundspot"
export SPOT_IP="192.168.10.1"
export SNAPCAST_PORT="1704"
export PRESENCE_COOLDOWN="${PRESENCE_COOLDOWN:-30}"
export PRESENCE_ENABLED="${PRESENCE_ENABLED:-false}"
export SOUNDSPOT_MODE
export SOUNDSPOT_USER="${SUDO_USER:-pi}"
export SOUNDSPOT_UID=$(id -u "${SOUNDSPOT_USER}" 2>/dev/null || echo "1000")
log "Utilisateur audio : ${W}${SOUNDSPOT_USER}${N} (UID ${SOUNDSPOT_UID})"

mkdir -p "$INSTALL_DIR"

# Les fichiers Python sont dans src/ (sous-répertoire de deploy_on_pi.sh)
for _py in presence_detector.py battery_monitor.py; do
    if [ -f "$SRC_DIR/$_py" ]; then
        cp "$SRC_DIR/$_py" "$INSTALL_DIR/"
        log "$_py → $INSTALL_DIR/ ✓"
    else
        warn "$_py introuvable dans $SRC_DIR — le service correspondant sera ignoré"
    fi
done

# ════════════════════════════════════════════════════════════════
#  9. Installation
# ════════════════════════════════════════════════════════════════
if [ "$SOUNDSPOT_MODE" = "2" ]; then
    log "Lancement de install_satellite.sh..."
    bash "$SRC_DIR/install_satellite.sh"
else
    log "Lancement de install_soundspot.sh..."
    bash "$SRC_DIR/install_soundspot.sh"
fi

# ════════════════════════════════════════════════════════════════
#  Fin
# ════════════════════════════════════════════════════════════════
echo -e "\n${G}Installation terminée !${N}"
echo -e "Redémarrage dans 10 secondes — ${Y}Ctrl+C pour annuler${N}"
sleep 10
sync
reboot
