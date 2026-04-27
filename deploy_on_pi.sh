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
sudo usermod -aG audio ${SOUNDSPOT_USER}

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
TARGET_MASTER=""

# ════════════════════════════════════════════════════════════════
#  2. Paramètres selon le mode
# ════════════════════════════════════════════════════════════════
if [ "$SOUNDSPOT_MODE" = "2" ]; then
    # ── Mode satellite ───────────────────────────────────────────
    hdr "Mode Satellite"
    echo -e "  Le satellite reçoit le stream du maître via Snapcast."
    echo -e "  Il se connecte au réseau WiFi amont ${W}et${N} à l'AP du maître (roaming)."
    echo ""
    ask "Hostname mDNS unique du maître [soundspot-zicmama] : "
    read -r INPUT_TARGET
    TARGET_MASTER="${INPUT_TARGET:-soundspot-zicmama}"
    MASTER_HOST="${TARGET_MASTER}.local"
    export MASTER_HOST TARGET_MASTER
    log "Satellite → maître ${C}${MASTER_HOST}${N}"

    ask "SSID WiFi de l'AP du maître (pour roaming direct) [ZICMAMA] : "
    read -r INPUT_SPOT
    export SPOT_NAME="${INPUT_SPOT:-ZICMAMA}"
    log "AP maître pour roaming : ${W}${SPOT_NAME}${N}"
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
#  3. Réseau et Point d'Accès
# ════════════════════════════════════════════════════════════════
hdr "Réseau et Point d'Accès"

export IFACE_WAN="wlan0"
export IFACE_AP="uap0"
export WIFI_SSID=""
export WIFI_PASS=""

# ── Détection topologie réseau ────────────────────────────────
if [ "$SOUNDSPOT_MODE" != "2" ]; then
    if ip link show eth0 2>/dev/null | grep -q "state UP"; then
        export IFACE_WAN="eth0"
        export IFACE_AP="wlan0"
        log "Ethernet ${C}eth0${N} UP → puce WiFi ${W}100% dédiée à l'AP ${SPOT_NAME:-SoundSpot}${N}"
        log "Pas d'interface virtuelle uap0 — wlan0 = AP directe."
    elif ip link show wlan1 >/dev/null 2>&1; then
        export IFACE_AP="wlan1"
        log "Dongle WiFi USB (${IFACE_AP}) — Mode Dual-WiFi activé."
    else
        log "Un seul module WiFi — interface virtuelle ${IFACE_AP}."
    fi
fi

# ── Réseau WiFi amont (uniquement si pas en Ethernet) ────────
if [ "$IFACE_WAN" != "eth0" ]; then
    hdr "Réseau WiFi amont (connexion Internet)"
    CURRENT_SSID=$(iwgetid -r 2>/dev/null || \
        nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '/^yes:/{print $2}' || true)
    [ -n "$CURRENT_SSID" ] && log "WiFi actuel : ${C}${CURRENT_SSID}${N}"

    ask "SSID du réseau WiFi [${CURRENT_SSID:-qo-op}] : "
    read -r INPUT_WIFI
    export WIFI_SSID="${INPUT_WIFI:-${CURRENT_SSID:-qo-op}}"

    ask "Mot de passe WiFi [0penS0urce!] : "
    read -r INPUT_PASS
    export WIFI_PASS="${INPUT_PASS:-0penS0urce!}"

    # ── Connexion via NetworkManager si le SSID a changé ─────────
    if [ "$WIFI_SSID" != "${CURRENT_SSID:-}" ] && command -v nmcli &>/dev/null; then
        log "Connexion NetworkManager → ${WIFI_SSID}..."
        nmcli dev wifi connect "$WIFI_SSID" password "$WIFI_PASS" ifname wlan0 2>/dev/null \
            && log "wlan0 → ${WIFI_SSID} ✓" \
            || warn "nmcli : échec connexion (vérifier SSID/mdp et relancer)"
    fi
else
    log "Ethernet actif — aucun réseau WiFi amont requis pour le maître."
fi

# ════════════════════════════════════════════════════════════════
#  4. Canal WiFi (maître seulement)
# ════════════════════════════════════════════════════════════════
export WIFI_CHANNEL="6"
if [ "$SOUNDSPOT_MODE" != "2" ] && [ "$IFACE_WAN" != "eth0" ]; then
    hdr "Optimisation du Canal WiFi"

    # 1. Détection canal amont
    UPSTREAM_CHAN=$(iw dev wlan0 info 2>/dev/null | awk '/channel/{print $2; exit}' || echo "11")
    UPSTREAM_CHAN=$(echo "$UPSTREAM_CHAN" | tr -d '[:space:]') # Nettoyage strict
    log "Canal Internet (wlan0) : ${C}${UPSTREAM_CHAN}${N}"

    if [ "$IFACE_AP" = "uap0" ]; then
        export WIFI_CHANNEL="$UPSTREAM_CHAN"
        warn "Mode Monocarte : AP forcée sur le canal ${WIFI_CHANNEL} (doit suivre wlan0)."
    else
        log "Mode Dual-WiFi : Recherche du canal le plus calme (Nbe réseaux + RSSI)..."
        
        SCAN_DATA=$(sudo iw dev wlan0 scan 2>/dev/null || echo "")
        
        declare -A CH_COUNT=([1]=0 [6]=0 [11]=0)
        declare -A CH_PENALTY=([1]=0 [6]=0 [11]=0)

        CURRENT_SIG=0

        # Machine à états pour parser correctement chaque bloc "BSS"
        while IFS= read -r line; do
            if [[ "$line" =~ ^BSS\ [0-9a-fA-F:]+ ]]; then
                # Nouvelle box détectée, on réinitialise le signal
                CURRENT_SIG=0
            elif [[ "$line" =~ signal:\ -([0-9]+) ]]; then
                # Capture la valeur absolue du signal (ex: 70 pour -70 dBm)
                CURRENT_SIG="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ primary\ channel:\ ([0-9]+) ]] || [[ "$line" =~ DS\ Parameter\ set:\ channel\ ([0-9]+) ]]; then
                CHAN="${BASH_REMATCH[1]}"
                if [[ "$CHAN" =~ ^(1|6|11)$ ]] && [ "$CURRENT_SIG" -gt 0 ]; then
                    CH_COUNT[$CHAN]=$(( CH_COUNT[$CHAN] + 1 ))
                    # Un signal très fort (-30) donne une grosse pénalité (70). 
                    # Un signal faible (-90) donne une petite pénalité (10).
                    PENALTY=$(( 100 - CURRENT_SIG ))
                    [ "$PENALTY" -lt 0 ] && PENALTY=0
                    CH_PENALTY[$CHAN]=$(( CH_PENALTY[$CHAN] + PENALTY ))
                    CURRENT_SIG=0 # Reset pour éviter de compter en double
                fi
            fi
        done <<< "$SCAN_DATA"
        
        # Si l'upstream est sur 5 GHz (canal >= 36), aucun conflit possible en 2,4 GHz
        UPSTREAM_IS_5GHZ=false
        [ "$UPSTREAM_CHAN" -ge 36 ] 2>/dev/null && UPSTREAM_IS_5GHZ=true

        BEST_CHAN=1
        [ "$UPSTREAM_CHAN" == "1" ] && BEST_CHAN=6
        MIN_SCORE=999999

        for CH in 1 6 11; do
            if $UPSTREAM_IS_5GHZ || [ "$CH" != "$UPSTREAM_CHAN" ]; then
                # Score = (Nombre de réseaux * 1000) + Somme des pénalités RSSI
                SCORE=$(( CH_COUNT[$CH] * 1000 + CH_PENALTY[$CH] ))
                log "  CH${CH} : ${CH_COUNT[$CH]} réseau(x), Pénalité RSSI=${CH_PENALTY[$CH]}, Score=${SCORE}"

                if [ "$SCORE" -lt "$MIN_SCORE" ]; then
                    MIN_SCORE=$SCORE
                    BEST_CHAN=$CH
                fi
            fi
        done
        $UPSTREAM_IS_5GHZ && log "Upstream 5 GHz (CH${UPSTREAM_CHAN}) — tous les canaux 2,4 GHz disponibles"
        
        export WIFI_CHANNEL="$BEST_CHAN"
        log "${G}✓${N} Choix automatique : ${W}Canal ${WIFI_CHANNEL}${N} (Score minimal: ${MIN_SCORE})"
        
        ask "Utiliser ce canal ou saisir manuellement [${WIFI_CHANNEL}] : "
        read -r INPUT_CHAN
        export WIFI_CHANNEL="${INPUT_CHAN:-$WIFI_CHANNEL}"
    fi
fi

# ════════════════════════════════════════════════════════════════
#  EXTRA HATS _____ ReSpeaker ---- add your audio HAT here !!
# ════════════════════════════════════════════════════════════════

hdr "Hardware Audio (HAT)"
ask "Utilisez-vous un ReSpeaker 2-Mics HAT (Jack + Micro) ? [o/N] : "
read -r INPUT_RESPEAKER
export USE_RESPEAKER="false"
[[ "${INPUT_RESPEAKER,,}" == "o" ]] && export USE_RESPEAKER="true"

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

# Cache persistant des appareils découverts lors des scans (survit aux récursions)
BT_DISC_CACHE="/tmp/soundspot_bt_found"

ask_bt_selection() {
    # Fusionner le cache BlueZ courant + appareils accumulés lors des scans précédents
    declare -A _BT_SEEN
    local BT_RAW="" _line _mac _name
    while IFS= read -r _line; do
        _mac=$(echo "$_line" | awk '{print $2}')
        [[ "$_mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || continue
        _BT_SEEN[$_mac]=1
        BT_RAW="${BT_RAW}${BT_RAW:+$'\n'}$_line"
    done <<< "$(bluetoothctl devices 2>/dev/null || true)"
    if [ -f "$BT_DISC_CACHE" ]; then
        while IFS= read -r _line; do
            _mac=$(echo "$_line" | awk '{print $2}')
            [[ "$_mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || continue
            [ "${_BT_SEEN[$_mac]+x}" ] && continue
            _BT_SEEN[$_mac]=1
            BT_RAW="${BT_RAW}${BT_RAW:+$'\n'}$_line"
        done < "$BT_DISC_CACHE"
    fi

    declare -A BT_MAP
    local IDX=1

    echo -e "Appareils Bluetooth connus (déjà couplés/scannés) :\n"

    if [ -n "$BT_RAW" ]; then
        while IFS= read -r _line; do
            MAC=$(echo "$_line" | awk '{print $2}')
            NAME=$(echo "$_line" | cut -d' ' -f3-)
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
        # Pipe synchrone : évite le SIGTTIN qui suspend bluetoothctl backgroundé
        {
            echo "power on"
            echo "agent on"
            echo "default-agent"
            echo "scan on"
            sleep 15
            echo "scan off"
            echo "quit"
        } | bluetoothctl > /tmp/bt_scan.log 2>&1 &
        SCAN_PID=$!
        for i in $(seq 1 15); do
            echo -ne "\r  Recherche active... $i/15s "
            sleep 1
        done
        wait "$SCAN_PID" 2>/dev/null || true
        echo -e "\n"
        # Accumuler les nouveaux appareils détectés dans le cache persistant
        while IFS= read -r _line; do
            if [[ "$_line" =~ \[NEW\]\ Device\ ([0-9A-Fa-f:]{17})\ (.+) ]]; then
                _mac="${BASH_REMATCH[1]}"; _name="${BASH_REMATCH[2]}"
                grep -qF "$_mac" "$BT_DISC_CACHE" 2>/dev/null \
                    || echo "Device $_mac $_name" >> "$BT_DISC_CACHE"
            fi
        done < /tmp/bt_scan.log
        # Relancer le menu — la liste inclut maintenant les appareils accumulés
        ask_bt_selection
    elif [[ "${CHOICE,,}" == "m" ]]; then
        ask "Adresse MAC (ex: F4:4E:FC:E9:C6:15) : "
        read -r BT_INPUT
        export BT_INPUT
    elif [[ "$CHOICE" == "0" || -z "$CHOICE" ]]; then
        log "Configuration Bluetooth ignorée."
        export BT_INPUT=""
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -gt 0 ] && [ "$CHOICE" -lt "$IDX" ]; then
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
  Maître mDNS     : ${C}${MASTER_HOST}${N}
  AP maître (roam): ${C}${SPOT_NAME}${N}
  Réseau amont    : ${WIFI_SSID}
  Enceinte BT     : ${W}${BT_MAC:-non configurée}${N}
${W}└────────────────────────────────────────────┘${N}"
else
    _CLEAN=$(echo "${SPOT_NAME:-}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
echo -e "
${W}┌────────────────────────────────────────────┐
│   Récapitulatif — SoundSpot Maître         │
├────────────────────────────────────────────┤${N}
  Hostname unique : ${C}soundspot-${_CLEAN}.local${N}
  SSID visiteurs  : ${C}${SPOT_NAME}${N}  (réseau ouvert)
  Interface AP    : ${W}${IFACE_AP}${N}  (WAN: ${IFACE_WAN})
  Réseau amont    : ${WIFI_SSID:-Ethernet eth0}  (canal ${WIFI_CHANNEL})
  Enceinte BT     : ${W}${BT_MAC:-non configurée}${N}
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

# ── Hostname unique (Master uniquement) ──────────────────────
if [ "$SOUNDSPOT_MODE" != "2" ] && [ -n "${SPOT_NAME:-}" ]; then
    CLEAN_NAME=$(echo "$SPOT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
    NEW_HOSTNAME="soundspot-${CLEAN_NAME}"
    hostnamectl set-hostname "$NEW_HOSTNAME" 2>/dev/null || true
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${NEW_HOSTNAME}/" /etc/hosts 2>/dev/null || true
    log "Hostname → ${C}${NEW_HOSTNAME}.local${N}"
fi

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
#  10. Pinout.xyz — référence GPIO locale (RPi)
#  Disponible hors-ligne via le portail : http://192.168.10.1/pinout/
# ════════════════════════════════════════════════════════════════
hdr "Pinout.xyz (référence GPIO hors-ligne)"
USER_HOME_DEPLOY=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
PINOUT_DIR="$USER_HOME_DEPLOY/.zen/workspace/Pinout.xyz"

if [ "$SOUNDSPOT_MODE" != "2" ]; then
    if [ ! -d "$PINOUT_DIR/.git" ]; then
        log "Clonage de Pinout.xyz → ${PINOUT_DIR}..."
        mkdir -p "$USER_HOME_DEPLOY/.zen/workspace"
        sudo -u "$SOUNDSPOT_USER" git clone --depth=1 \
            https://github.com/pinout-xyz/Pinout.xyz "$PINOUT_DIR" 2>/dev/null \
            && log "Pinout.xyz cloné ✓" \
            || warn "Clone Pinout.xyz échoué (Internet requis). À relancer plus tard."
    else
        log "Pinout.xyz déjà présent — mise à jour..."
        sudo -u "$SOUNDSPOT_USER" git -C "$PINOUT_DIR" pull --ff-only 2>/dev/null || true
    fi

    # Générer les pages HTML statiques via generate-html.py
    if [ -d "$PINOUT_DIR" ] && [ -f "$PINOUT_DIR/generate-html.py" ]; then
        log "Génération des pages Pinout.xyz (generate-html.py)..."
        # Dépendances : python3-markdown + python3-yaml suffisent (Flask/sass non requis)
        apt-get install -y -q python3 python3-markdown python3-yaml 2>/dev/null || true

        # Patcher resource_url pour servir sous /pinout/ (chemins absolus → /pinout/resources/)
        sudo -u "$SOUNDSPOT_USER" sed -i \
            's|resource_url: /resources/|resource_url: /pinout/resources/|' \
            "$PINOUT_DIR/src/en/settings.yaml" 2>/dev/null || true

        if sudo -u "$SOUNDSPOT_USER" bash -c "cd '$PINOUT_DIR' && python3 generate-html.py en" 2>&1; then
            log "Pinout.xyz HTML généré ✓"
        else
            warn "generate-html.py échoué — vérifier python3-markdown python3-yaml"
        fi

        # Copier les assets statiques dans output/en/ (phatstack optionnel selon version du repo)
        sudo -u "$SOUNDSPOT_USER" bash -c "
            [ -d '$PINOUT_DIR/resources' ] && cp -r '$PINOUT_DIR/resources' '$PINOUT_DIR/output/en/' 2>/dev/null
            [ -d '$PINOUT_DIR/phatstack' ] && cp -r '$PINOUT_DIR/phatstack' '$PINOUT_DIR/output/en/' 2>/dev/null
            true
        " && log "Assets Pinout copiés ✓"
    fi

    # Copie directe dans portal/pinout/ — évite les chaînes de symlinks inaccessibles à www-data
    PORTAL_PINOUT="$INSTALL_DIR/portal/pinout"
    if [ -d "$PINOUT_DIR/output/en" ]; then
        rm -rf "$PORTAL_PINOUT"
        mkdir -p "$PORTAL_PINOUT"
        cp -r "$PINOUT_DIR/output/en/"* "$PORTAL_PINOUT/" 2>/dev/null || true
        # Aplatir pinout/pinout/*.html → pinout/[nom]/index.html (URLs sans extension ni réécriture)
        if [ -d "$PORTAL_PINOUT/pinout" ]; then
            for _f in "$PORTAL_PINOUT/pinout/"*.html; do
                [ -f "$_f" ] || continue
                _name=$(basename "$_f" .html)
                mkdir -p "$PORTAL_PINOUT/$_name"
                cp "$_f" "$PORTAL_PINOUT/$_name/index.html"
            done
        fi
        chmod -R a+rX "$PORTAL_PINOUT/"
        log "Pinout.xyz copié → portal/pinout/ ✓  (http://$(hostname -I | awk '{print $1}')/pinout/)"
    elif [ -d "$PINOUT_DIR" ]; then
        warn "output/en/ absent — génération Pinout échouée (vérifier logs ci-dessus)"
    fi

fi

# ════════════════════════════════════════════════════════════════
#  Fin
# ════════════════════════════════════════════════════════════════
echo -e "\n${G}Installation terminée !${N}"
echo -e "Redémarrage dans 10 secondes — ${Y}Ctrl+C pour annuler${N}"
sleep 10
sync
reboot
