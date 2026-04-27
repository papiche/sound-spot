#!/bin/bash
# api/core/audio_output.sh — Sélecteur de sortie audio PipeWire
# GET  → liste JSON [{name, label, active}, …]
# POST sink=<name> → change la sortie par défaut + redémarre soundspot-client

_SS_SERVICE="portal-audio"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

INSTALL_DIR="${INSTALL_DIR:-/opt/soundspot}"
source "$INSTALL_DIR/soundspot.conf" 2>/dev/null || true
SET_SCRIPT="$INSTALL_DIR/backend/system/set_audio_output.sh"

_sink_label() {
    local s="$1"
    case "$s" in
        bluez_output.*)
            local mac="${s#bluez_output.}"; mac="${mac%%.*}"; mac="${mac//_/:}"
            echo "Bluetooth ${mac}" ;;
        *hdmi*)
            echo "HDMI" ;;
        *seeed*|*respeaker*|*2mic*|*hat*)
            echo "HAT ReSpeaker" ;;
        *analog*|*alsa*)
            echo "Jack 3.5mm" ;;
        *null*|*mute*)
            echo "Silence (désactivé)" ;;
        *)
            echo "${s##*.}" ;;
    esac
}

if [ "${REQUEST_METHOD}" = "POST" ]; then
    read -r _POST
    SINK=$(echo "$_POST" | grep -oP '(?<=sink=)[^&]+' \
        | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g' \
        | xargs -0 printf '%b' 2>/dev/null || echo "")
    # Valider : uniquement caractères autorisés dans les noms de sink PipeWire
    if ! [[ "$SINK" =~ ^[a-zA-Z0-9_.:-]+$ ]]; then
        echo '{"status":"error","message":"nom de sink invalide"}'
        exit 0
    fi
    sudo "$SET_SCRIPT" set "$SINK" 2>/dev/null \
        && echo "{\"status\":\"ok\",\"sink\":\"$(echo "$SINK" | sed 's/"/\\"/g')\"}" \
        || echo '{"status":"error","message":"changement de sortie échoué"}'
    exit 0
fi

# GET : liste des sinks disponibles
SINKS_RAW=$(sudo "$SET_SCRIPT" list 2>/dev/null || echo "")
DEFAULT=$(sudo "$SET_SCRIPT" get-default 2>/dev/null | tr -d '[:space:]' || echo "")

JSON="["
SEP=""
while IFS=$'\t' read -r _idx _name _rest; do
    [ -z "$_name" ] && continue
    _label=$(_sink_label "$_name")
    _active="false"; [ "$_name" = "$DEFAULT" ] && _active="true"
    _nesc=$(echo "$_name"  | sed 's/"/\\"/g')
    _lesc=$(echo "$_label" | sed 's/"/\\"/g')
    JSON="${JSON}${SEP}{\"name\":\"${_nesc}\",\"label\":\"${_lesc}\",\"active\":${_active}}"
    SEP=","
done <<< "$SINKS_RAW"
JSON="${JSON}]"
echo "$JSON"
