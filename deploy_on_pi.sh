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

export SOUNDSPOT_USER="${SUDO_USER:-pi}"
export SOUNDSPOT_UID=$(id -u "${SOUNDSPOT_USER}" 2>/dev/null || echo "1000")
log "Utilisateur audio : ${W}${SOUNDSPOT_USER}${N} (UID ${SOUNDSPOT_UID})"

if [[ $SCRIPT_DIR != "/home/$SOUNDSPOT_USER/.zen/workspace/sound-spot" ]]; then
    echo "... PLEASE RESPECT ~/.zen CODE LOCATION ... 
mkdir -p /home/$SOUNDSPOT_USER/.zen/workspace
cd /home/$SOUNDSPOT_USER/.zen/workspace
mv $SCRIPT_DIR /home/$SOUNDSPOT_USER/.zen/workspace/

... please..."
    exit 1
fi

# Vérifier si linger est activé pour le VRAI utilisateur
if ! loginctl show-user "$SOUNDSPOT_USER" 2>/dev/null | grep -q "Linger=yes"; then
  sudo loginctl enable-linger "$SOUNDSPOT_USER"
fi

# Vérifier si la config existe déjà
if ! grep -q "^KillUserProcesses=no" /etc/systemd/logind.conf; then
  echo "KillUserProcesses=no" | sudo tee -a /etc/systemd/logind.conf
  sudo systemctl restart systemd-logind
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

    echo ""
    echo -e "  ${DIM}Picoport : nœud IPFS micro-Astroport + keygen + paiements Ğ1/ẑen.${N}"
    echo -e "  ${DIM}Nécessite ~30 Mo supplémentaires (IPFS + env Python keygen).${N}"
    ask "Activer Picoport (nœud UPlanet + paiements ẑen) ? [O/n] : "
    read -r INPUT_PICOPORT
    export PICOPORT_ENABLED="true"
    [[ "${INPUT_PICOPORT,,}" == "n" ]] && export PICOPORT_ENABLED="false" && \
        log "Picoport désactivé" || \
        log "Picoport activé"
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
    hdr "Optimisation du Canal WiFi"
    
    # 1. Détection canal amont
    UPSTREAM_CHAN=$(iw dev wlan0 info 2>/dev/null | awk '/channel/{print $2; exit}' || echo "11")
    UPSTREAM_CHAN=$(echo "$UPSTREAM_CHAN" | tr -d '[:space:]') # Nettoyage strict
    log "Canal Internet (wlan0) : ${C}${UPSTREAM_CHAN}${N}"

    if [ "$IFACE_AP" = "uap0" ]; then
        export WIFI_CHANNEL="$UPSTREAM_CHAN"
        warn "Mode Monocarte : AP forcée sur le canal ${WIFI_CHANNEL} (doit suivre wlan0)."
    else
        log "Mode Dual-WiFi : Recherche du canal le plus calme..."
        
        # Scan sécurisé
        SCAN_RAW=$(sudo iw wlan0 scan dump 2>/dev/null | grep "primary channel" | awk '{print $4}' || true)
        if [ -z "$SCAN_RAW" ]; then
            SCAN_RAW=$(sudo iw wlan0 scan 2>/dev/null | grep "primary channel" | awk '{print $4}' || echo "")
        fi
        
        # Comptage rigoureux (on force une seule ligne en sortie)
        # -w dans grep évite que "1" match "11"
        C1=$(echo "$SCAN_RAW" | grep -w "1" | wc -l)
        C6=$(echo "$SCAN_RAW" | grep -w "6" | wc -l)
        C11=$(echo "$SCAN_RAW" | grep -w "11" | wc -l)
        
        log "Encombrement : CH1:${C1} | CH6:${C6} | CH11:${C11}"
        
        # Choix du meilleur canal
        BEST_CHAN=1
        [ "$UPSTREAM_CHAN" == "1" ] && BEST_CHAN=6
        
        MIN_RESEAUX=999
        for CH in 1 6 11; do
            if [ "$CH" != "$UPSTREAM_CHAN" ]; then
                # On récupère le compteur correspondant au canal testé
                COUNT=$(echo "$SCAN_RAW" | grep -cw "$CH" | head -n 1 || echo 0)
                # On s'assure que COUNT est un entier pur pour le test [ ]
                COUNT=$(echo "$COUNT" | tr -d '[:space:]')
                
                if [ "$COUNT" -lt "$MIN_RESEAUX" ]; then
                    MIN_RESEAUX=$COUNT
                    BEST_CHAN=$CH
                fi
            fi
        done
        
        export WIFI_CHANNEL="$BEST_CHAN"
        # Utilisation de 'log' car 'ok' n'est pas défini dans ce script
        log "${G}✓${N} Choix automatique : ${W}Canal ${WIFI_CHANNEL}${N} (${MIN_RESEAUX} voisins)"
        
        ask "Utiliser ce canal ou saisir manuellement [${WIFI_CHANNEL}] : "
        read -r INPUT_CHAN
        export WIFI_CHANNEL="${INPUT_CHAN:-$WIFI_CHANNEL}"
    fi
fi

# ════════════════════════════════════════════════════════════════
#  5. Enceinte Bluetooth
# ════════════════════════════════════════════════════════════════
hdr "Enceinte Bluetooth"

# Heuristique : noms d'appareils qui ressemblent à une enceinte audio
SPEAKER_PATTERN="speaker|enceinte|audio|sound|music|headset|headphone|earphone|buds"
SPEAKER_PATTERN="${SPEAKER_PATTERN}|soundbar|jbl|bose|sony|marshall|harman|anker"
SPEAKER_PATTERN="${SPEAKER_PATTERN}|ultimate|tribit|w-king|jabra|sennheiser|plantronics"
SPEAKER_PATTERN="${SPEAKER_PATTERN}|soundlink|flip|charge|pulse|pill|roam|clip|boom"
SPEAKER_PATTERN="${SPEAKER_PATTERN}|wonder|mega|party|bass|stereo|mini|go|loud|beats"
# ---------------------------

ask_bt_selection() {
    local BT_RAW=$(bluetoothctl devices 2>/dev/null || true)
    declare -A BT_MAP
    local IDX=1
    
    echo -e "Appareils Bluetooth connus (déjà couplés/scannés) :\n"
    
    if [ -n "$BT_RAW" ]; then
        while IFS= read -r line; do
            MAC=$(echo "$line" | awk '{print $2}')
            NAME=$(echo "$line" | cut -d' ' -f3-)
            [[ "$MAC" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || continue
            BT_MAP[$IDX]="${MAC}|${NAME}"
            
            STATUS=""
            if bluetoothctl info "$MAC" 2>/dev/null | grep -q "Connected: yes"; then
                STATUS=" ${G}[Connecté]${N}"
            elif bluetoothctl info "$MAC" 2>/dev/null | grep -q "Paired: yes"; then
                STATUS=" ${Y}[Couplé]${N}"
            fi

            if echo "$NAME" | grep -qiE "$SPEAKER_PATTERN"; then
                echo -e "  ${C}[$IDX]${N} ${W}${NAME}${N} ${MAC}${STATUS} ${G}← recommandé${N}"
            else
                echo -e "  ${C}[$IDX]${N} ${NAME} ${MAC}${STATUS}"
            fi
            ((IDX++))
        done <<< "$BT_RAW"
    else
        echo "  (Aucun appareil en mémoire)"
    fi
    
    echo ""
    echo -e "  ${C}[S]${N} Lancer un scan pour trouver une nouvelle enceinte (15s)"
    echo -e "  ${C}[M]${N} Saisie manuelle de l'adresse MAC"
    echo -e "  ${C}[0]${N} Ignorer / Plus tard"
    echo ""
    
    ask "Votre choix : "
    read -r CHOICE
    
    if [[ "${CHOICE,,}" == "s" ]]; then
        log "Allumez vos enceintes en mode appairage maintenant..."
        rfkill unblock bluetooth 2>/dev/null || true
        bluetoothctl power on >/dev/null 2>&1 || true
        bluetoothctl agent on >/dev/null 2>&1 || true
        bluetoothctl default-agent >/dev/null 2>&1 || true
        bluetoothctl scan on >/dev/null 2>&1 &
        SCAN_PID=$!
        for i in $(seq 1 15); do
            echo -ne "\r  Recherche active... $i/15s "
            sleep 1
        done
        echo -e "\n"
        kill "$SCAN_PID" 2>/dev/null || true
        bluetoothctl scan off >/dev/null 2>&1 || true
        # On relance le menu, qui affichera la liste mise à jour !
        ask_bt_selection
    elif [[ "${CHOICE,,}" == "m" ]]; then
        ask "Adresse MAC (ex: F4:4E:FC:E9:C6:15) : "
        read -r BT_INPUT
        export BT_INPUT
    elif [[ "$CHOICE" == "0" || -z "$CHOICE" ]]; then
        log "Configuration Bluetooth ignorée."
        export BT_INPUT=""
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] &&[ "$CHOICE" -gt 0 ] && [ "$CHOICE" -lt "$IDX" ]; then
        SELECTED="${BT_MAP[$CHOICE]}"
        export BT_INPUT=$(echo "$SELECTED" | cut -d'|' -f1)
        log "Sélectionné : ${W}$BT_INPUT${N}"
    else
        warn "Choix invalide."
        ask_bt_selection
    fi
}

# Lancer le menu interactif
ask_bt_selection

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
#  7. Dépendances minimales et fuseau horaire
# ════════════════════════════════════════════════════════════════
log "Mise à jour et dépendances minimales..."
apt-get update -qq
apt-get install -y -q gettext-base iw bluetooth

# ── Fuseau horaire (critique pour l'heure solaire annoncée) ────
CURRENT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null \
    || cat /etc/timezone 2>/dev/null || echo "UTC")
if [ "$CURRENT_TZ" = "UTC" ] || [ -z "$CURRENT_TZ" ]; then
    ask "Fuseau horaire [Europe/Paris] (ex: Europe/Paris, America/Montreal) : "
    read -r INPUT_TZ
    INPUT_TZ="${INPUT_TZ:-Europe/Paris}"
    timedatectl set-timezone "$INPUT_TZ" 2>/dev/null \
        && log "Fuseau → ${W}${INPUT_TZ}${N} ✓" \
        || warn "timedatectl set-timezone échoué — fuseau UTC conservé"
else
    log "Fuseau horaire : ${C}${CURRENT_TZ}${N} (déjà configuré)"
fi

# ════════════════════════════════════════════════════════════════
#  8. Copie des scripts Python vers INSTALL_DIR
# ════════════════════════════════════════════════════════════════
export INSTALL_DIR="/opt/soundspot"
export SPOT_IP="192.168.10.1"
export SNAPCAST_PORT="1704"
export PRESENCE_COOLDOWN="${PRESENCE_COOLDOWN:-30}"
export PRESENCE_ENABLED="${PRESENCE_ENABLED:-false}"
export SOUNDSPOT_MODE

mkdir -p "$INSTALL_DIR"

# Portail captif (sources live — /var/www/html sera un lien symbolique)
if [ -d "$SRC_DIR/portal" ]; then
    cp -r "$SRC_DIR/portal" "$INSTALL_DIR/"
    chown -R www-data:www-data "$INSTALL_DIR/portal"
    log "portal/ → $INSTALL_DIR/ ✓"
else
    warn "src/portal/ introuvable — le portail captif ne sera pas déployé"
fi

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
