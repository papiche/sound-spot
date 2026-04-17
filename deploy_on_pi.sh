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

# --- DEBUG INFO ---
log "Vérification de l'état du contrôleur..."
BT_STATE=$(bluetoothctl show || echo "ERREUR: bluetoothctl ne répond pas")
echo -e "${DIM}$BT_STATE${N}"

log "Réinitialisation complète..."
rfkill unblock bluetooth 2>/dev/null || true
bluetoothctl power on >/dev/null 2>&1 || true
bluetoothctl agent on >/dev/null 2>&1 || true
bluetoothctl default-agent >/dev/null 2>&1 || true

echo -e "${Y}Veuillez mettre votre enceinte en MODE APPAIRAGE maintenant.${N}"
echo -e "${DIM}(Appui long sur le bouton Bluetooth jusqu'au clignotement)${N}"
echo ""
ask "Prêt pour le scan ? [Appuyez sur Entrée]"
read -r _READY

log "Scan en cours (15 s)..."
BT_LOG="/tmp/bt_scan.log"
rm -f "$BT_LOG"

# On utilise la commande 'timeout' qui est plus fiable pour capturer la sortie
# On simule un terminal avec 'script' pour forcer bluetoothctl à cracher ses infos
# C'est la méthode la plus proche du mode interactif que tu as testé
stdbuf -oL script -q -c "timeout 15s bluetoothctl scan on" /dev/null > "$BT_LOG" 2>&1 &
SCAN_PID=$!

# Affichage de la progression
for i in $(seq 1 15); do
    # On compte les devices dans le log de debug
    COUNT=$(grep -c "Device " "$BT_LOG" || echo "0")
    echo -ne "\r  Recherche... $i/15s  (Appareils vus : ${G}$COUNT${N})"
    sleep 1
done
echo -e "\n"

# Nettoyage
kill $SCAN_PID 2>/dev/null || true
bluetoothctl scan off >/dev/null 2>&1 || true
sleep 1

log "Analyse des résultats..."
# On regarde dans DEUX sources : le log du scan ET la base interne
DEVICES_LOG=$(grep "Device " "$BT_LOG" | sed 's/.*Device //' | sort -u || true)
DEVICES_INT=$(bluetoothctl devices | grep -v "Scanning" || true)

# Fusion des deux sources
DEVICES=$(echo -e "$DEVICES_LOG\n$DEVICES_INT" | sort -u | grep -v "^$" || true)

if [ -z "$DEVICES" ]; then
    warn "ÉCHEC DE DÉTECTION AUTOMATIQUE"
    echo -e "${R}--- LOG DE DEBUG (10 dernières lignes) ---${N}"
    tail -n 10 "$BT_LOG"
    echo -e "${R}------------------------------------------${N}"
    echo ""
    ask "Saisir la MAC manuellement (ex: F4:4E:FC:E9:C6:15) ou Entrée : "
    read -r BT_INPUT
else
    hdr "Appareils détectés"
    echo -e "Sélectionnez votre enceinte :\n"
    
    # Création du menu
    IFS=$'\n'
    DEV_ARRAY=($DEVICES)
    
    for i in "${!DEV_ARRAY[@]}"; do
        echo -e "  ${C}[$((i+1))]${N} ${DEV_ARRAY[$i]}"
    done
    echo -e "  ${C}[0]${N} Saisie manuelle / Ignorer"
    echo ""
    ask "Votre choix : "
    read -r CHOICE
    
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -gt 0 ] && [ "$CHOICE" -le "${#DEV_ARRAY[@]}" ]; then
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
    log "Tentative d'appairage forcée..."
    # On utilise un pipe vers bluetoothctl pour simuler la frappe clavier
    echo -e "pair $BT_MAC\ntrust $BT_MAC\nquit" | bluetoothctl > /tmp/bt_pair.log 2>&1
    if bluetoothctl info "$BT_MAC" | grep -q "Paired: yes"; then
        log "Succès : ${G}Enceinte appairée !${N}"
    else
        warn "L'appairage a échoué (voir /tmp/bt_pair.log). On continue l'install..."
    fi
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
