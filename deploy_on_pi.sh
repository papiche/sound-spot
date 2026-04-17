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
fi

# ════════════════════════════════════════════════════════════════
#  3. Réseau WiFi amont (qo-op)
# ════════════════════════════════════════════════════════════════
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

# Préparation du contrôleur
log "Initialisation du Bluetooth..."
rfkill unblock bluetooth 2>/dev/null || true
bluetoothctl power on >/dev/null 2>&1 || true
sleep 1

echo -e "${Y}Veuillez mettre votre enceinte en MODE APPAIRAGE maintenant.${N}"
echo -e "${DIM}(Généralement un appui long sur le bouton Bluetooth jusqu'au clignotement)${N}"
echo ""
ask "Prêt pour le scan ? [Appuyez sur Entrée]"
read -r _READY

log "Scan en cours (15 s)..."
bluetoothctl scan on >/dev/null 2>&1 &
SCAN_PID=$!

# Barre de progression simple
for i in $(seq 1 15); do
    echo -ne "\r  Recherche d'appareils... $i/15s"
    sleep 1
done
echo -e "\n"

kill $SCAN_PID 2>/dev/null || true
bluetoothctl scan off >/dev/null 2>&1 || true

# Récupération et filtrage des appareils
hdr "Appareils détectés"
SPEAKER_PAT="speaker|audio|sound|w-king|jbl|bose|marshall|anker|tribit|jabra|ultimate|beats|sony|philips"
DEVICES=$(bluetoothctl devices | grep -iE "$SPEAKER_PAT" || bluetoothctl devices | head -n 10)

if [ -z "$DEVICES" ]; then
    warn "Aucun appareil trouvé automatiquement."
    ask "Adresse MAC manuelle (ou Entrée pour ignorer) : "
    read -r BT_INPUT
else
    # Affichage d'une liste numérotée
    IFS=$'\n'
    PS3=$(echo -e "\n${M}?${N} Choisissez le numéro de l'enceinte (ou 0 pour ignorer) : ")
    
    # Préparer la liste pour 'select'
    mapfile -t DEV_LIST < <(echo "$DEVICES")
    
    select opt in "${DEV_LIST[@]}"; do
        if [ "$REPLY" = "0" ]; then
            BT_INPUT=""
            break
        elif [ -n "$opt" ]; then
            # Extraire la MAC de la ligne "Device XX:XX:XX:XX:XX:XX Nom"
            BT_INPUT=$(echo "$opt" | awk '{print $2}')
            log "Sélectionné : ${W}$opt${N}"
            break
        else
            warn "Choix invalide."
        fi
    done
fi

export BT_MAC=""
export BT_MACS=""
if [[ "${BT_INPUT:-}" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
    export BT_MAC="$BT_INPUT"
    export BT_MACS="$BT_INPUT"
    
    # Tentative de couplage immédiat pour valider
    log "Tentative d'appairage de ${BT_MAC}..."
    bluetoothctl pair "$BT_MAC" <<EOF
trust $BT_MAC
exit
EOF
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
export SOUNDSPOT_MODE

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
