#!/bin/bash
# ================================================================
#  bt_update.sh — Gestion des enceintes Bluetooth SoundSpot
#  G1FabLab / UPlanet ẐEN — zicmama.com
#
#  Met à jour la liste des enceintes BT sans reflasher la carte SD.
#  Fonctionne sur un maître ou un satellite, local ou à distance.
#
#  Usage :
#    bash bt_update.sh                       # sur le RPi (local)
#    bash bt_update.sh pi@soundspot.local    # SSH → maître
#    bash bt_update.sh pi@192.168.10.2       # SSH → satellite
# ================================================================
set -euo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; M='\033[0;35m'
DIM='\033[2m'; N='\033[0m'
log()  { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err()  { echo -e "${R}✗${N}  $*" >&2; exit 1; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }
ask()  { echo -ne "${M}?${N}  $*"; }

CONF="/opt/soundspot/soundspot.conf"
INSTALL_DIR="/opt/soundspot"

# Heuristique : noms d'appareils qui ressemblent à une enceinte audio
SPEAKER_PATTERN="speaker|enceinte|audio|sound|music|headset|headphone|earphone|buds"
SPEAKER_PATTERN="${SPEAKER_PATTERN}|soundbar|jbl|bose|sony|marshall|harman|anker"
SPEAKER_PATTERN="${SPEAKER_PATTERN}|ultimate|tribit|w-king|jabra|sennheiser|plantronics"
SPEAKER_PATTERN="${SPEAKER_PATTERN}|soundlink|flip|charge|pulse|pill|roam|clip|boom"
SPEAKER_PATTERN="${SPEAKER_PATTERN}|wonder|mega|party|bass|stereo|mini|go|loud|beats"

# ════════════════════════════════════════════════════════════════
#  Mode distant : transfert SSH + exécution interactive
# ════════════════════════════════════════════════════════════════
REMOTE_HOST="${1:-}"
if [ -n "$REMOTE_HOST" ] && [ "$REMOTE_HOST" != "--rpi" ]; then
    command -v scp &>/dev/null || err "scp requis (paquet openssh-client)"
    REMOTE_SCRIPT="/tmp/soundspot_bt_update_$$.sh"

    echo -e "
${C}  ░▀▀█░▀█▀░█▀▀░█▄█░█▀█░█▄█░█▀█
  ░▄▀░░░█░░█░░░█░█░█▀█░█░█░█▀█
  ░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀░▀░▀░▀░▀░▀${N}
${DIM}  SoundSpot BT Update — G1FabLab / UPlanet ẐEN${N}
"
    hdr "Mise à jour Bluetooth distante → ${REMOTE_HOST}"
    log "Transfert du script vers ${REMOTE_HOST}..."
    scp -q "${BASH_SOURCE[0]}" "${REMOTE_HOST}:${REMOTE_SCRIPT}" \
        || err "Échec du transfert. SSH configuré ? (clé autorisée, RPi joignable ?)"
    log "Exécution interactive sur le SoundSpot..."
    ssh -t "$REMOTE_HOST" "sudo bash ${REMOTE_SCRIPT} --rpi; rm -f ${REMOTE_SCRIPT}"
    exit $?
fi

# ════════════════════════════════════════════════════════════════
#  Mode local / RPi — doit tourner en root
# ════════════════════════════════════════════════════════════════
[ "$(id -u)" -eq 0 ] || exec sudo bash "${BASH_SOURCE[0]}" --rpi

echo -e "
${C}  ░▀▀█░▀█▀░█▀▀░█▄█░█▀█░█▄█░█▀█
  ░▄▀░░░█░░█░░░█░█░█▀█░█░█░█▀█
  ░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀░▀░▀░▀░▀░▀${N}
${DIM}  SoundSpot BT Update — G1FabLab / UPlanet ẐEN${N}
"
hdr "Gestion des enceintes Bluetooth"

# ── Configuration actuelle ─────────────────────────────────────
if [ -f "$CONF" ]; then
    CURRENT_MACS=$(grep "^BT_MACS=" "$CONF" 2>/dev/null | cut -d'"' -f2 || true)
    [ -z "$CURRENT_MACS" ] && \
        CURRENT_MACS=$(grep "^BT_MAC=" "$CONF" 2>/dev/null | cut -d'"' -f2 || true)
    if [ -n "$CURRENT_MACS" ]; then
        log "Enceintes actuellement configurées :"
        for mac in $CURRENT_MACS; do
            DEV_NAME=$(bluetoothctl info "$mac" 2>/dev/null \
                | grep "Name:" | sed 's/.*Name: //' || echo "?")
            if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
                STATUS="${G}connectée${N}"
            else
                STATUS="${Y}non connectée${N}"
            fi
            echo -e "  ${C}${mac}${N}  ${W}${DEV_NAME}${N}  (${STATUS})"
        done
    else
        warn "Aucune enceinte configurée dans ${CONF}"
    fi
else
    warn "${CONF} introuvable — ce SoundSpot est-il installé ?"
fi

# ── Scan optionnel ────────────────────────────────────────────
echo ""
ask "Scanner de nouveaux appareils Bluetooth ? [o/N] : "
read -r DO_SCAN
if [[ "${DO_SCAN,,}" == "o" ]]; then
    log "Allumez vos enceintes maintenant — scan pendant 15 secondes..."
    bluetoothctl power on >/dev/null 2>&1 || true
    bluetoothctl scan on &>/dev/null &
    SCAN_PID=$!
    for i in $(seq 15 -1 1); do
        printf "\r  ${DIM}%2d s restantes...${N}" "$i"
        sleep 1
    done
    echo ""
    kill "$SCAN_PID" 2>/dev/null || true
    bluetoothctl scan off >/dev/null 2>&1 || true
    log "Scan terminé"
fi

# ── Liste des appareils disponibles ───────────────────────────
hdr "Appareils Bluetooth disponibles"
echo ""

# Cartes audio déjà actives (PipeWire/PulseAudio)
PI_UID=$(id -u pi 2>/dev/null || echo 1000)
PACTL_CARDS=""
command -v pactl &>/dev/null && \
    PACTL_CARDS=$(XDG_RUNTIME_DIR="/run/user/${PI_UID}" \
        pactl list cards short 2>/dev/null \
        | grep -i "bluez" | awk '{print $2}' || true)

BT_RAW=$(bluetoothctl devices 2>/dev/null || true)
if [ -z "$BT_RAW" ]; then
    err "Aucun appareil Bluetooth trouvé. Vérifiez : bluetoothctl power on / scan on"
fi

declare -A BT_MAP
IDX=1
while IFS= read -r line; do
    MAC=$(echo "$line" | awk '{print $2}')
    NAME=$(echo "$line" | cut -d' ' -f3-)
    [[ "$MAC" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || continue
    BT_MAP[$IDX]="${MAC}|${NAME}"

    # Marqueurs audio
    HINT=""
    MAC_NORM=$(echo "$MAC" | tr ':' '_')
    if echo "$PACTL_CARDS" | grep -qi "$MAC_NORM"; then
        HINT="  ${G}♪ audio actif${N}"
    elif echo "$NAME" | grep -qiE "$SPEAKER_PATTERN"; then
        HINT="  ${G}♪ enceinte probable${N}"
    fi

    echo -e "  ${C}[$IDX]${N}  $MAC  ${W}$NAME${N}${HINT}"
    ((IDX++))
done <<< "$BT_RAW"

echo ""
ask "Numéro(s) des enceintes à configurer (ex: 1 3) ou Entrée pour annuler : "
read -r CHOICES

[ -z "$CHOICES" ] && { warn "Annulé — aucune modification."; exit 0; }

# ── Validation de la sélection ────────────────────────────────
NEW_MACS=""
NEW_MAC=""
for c in $CHOICES; do
    if [ -z "${BT_MAP[$c]:-}" ]; then
        warn "Numéro $c invalide, ignoré."
        continue
    fi
    _MAC=$(echo "${BT_MAP[$c]}" | cut -d'|' -f1)
    NEW_MACS="${NEW_MACS:+$NEW_MACS }$_MAC"
    [ -z "$NEW_MAC" ] && NEW_MAC="$_MAC"
done

[ -z "$NEW_MACS" ] && { warn "Aucune sélection valide."; exit 0; }

# ── Couplage des nouveaux appareils ──────────────────────────
for mac in $NEW_MACS; do
    if ! bluetoothctl info "$mac" 2>/dev/null | grep -q "Trusted: yes"; then
        log "Couplage de $mac (pair + trust)..."
        bluetoothctl pair  "$mac" 2>/dev/null || warn "Pair échoué (déjà couplé ?)"
        bluetoothctl trust "$mac" 2>/dev/null || true
    fi
done

# ── Mise à jour de soundspot.conf ────────────────────────────
[ -f "$CONF" ] || err "${CONF} introuvable — SoundSpot installé ?"

# BT_MAC = premier MAC (rétrocompat)
if grep -q "^BT_MAC=" "$CONF"; then
    sed -i "s|^BT_MAC=.*|BT_MAC=\"${NEW_MAC}\"|" "$CONF"
else
    echo "BT_MAC=\"${NEW_MAC}\"" >> "$CONF"
fi

# BT_MACS = liste complète
if grep -q "^BT_MACS=" "$CONF"; then
    sed -i "s|^BT_MACS=.*|BT_MACS=\"${NEW_MACS}\"|" "$CONF"
else
    echo "BT_MACS=\"${NEW_MACS}\"" >> "$CONF"
fi

log "soundspot.conf mis à jour"

# ── Redémarrage du service + connexion immédiate ──────────────
if systemctl is-enabled bt-autoconnect &>/dev/null; then
    systemctl restart bt-autoconnect \
        && log "Service bt-autoconnect redémarré" \
        || warn "Redémarrage du service échoué"
else
    systemctl enable bt-autoconnect 2>/dev/null || true
    log "Service bt-autoconnect activé"
fi

if [ -x "$INSTALL_DIR/bt-connect.sh" ]; then
    log "Connexion BT immédiate..."
    bash "$INSTALL_DIR/bt-connect.sh" \
        && log "Connexion réussie ✓" \
        || warn "Connexion partielle — vérifier journalctl -fu bt-autoconnect"
fi

# ── Résumé ────────────────────────────────────────────────────
hdr "Mise à jour terminée ✓"
echo -e ""
for mac in $NEW_MACS; do
    DEV_NAME=$(bluetoothctl info "$mac" 2>/dev/null \
        | grep "Name:" | sed 's/.*Name: //' || echo "$mac")
    echo -e "  ${G}✓${N}  ${C}${mac}${N}  ${W}${DEV_NAME}${N}"
done
echo -e "
  Suivi   : ${Y}journalctl -fu bt-autoconnect${N}
  Config  : ${Y}${CONF}${N}

${DIM}  Pour reconfigurer ultérieurement :
  bash bt_update.sh [pi@soundspot.local]${N}
"
