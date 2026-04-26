#!/bin/bash
# set_voice_mode.sh — Active ou coupe les voix dans soundspot.conf
# Exécuté avec sudo par www-data depuis le portail captif.
# Usage : sudo /opt/soundspot/set_voice_mode.sh [true|false]
CONF="/opt/soundspot/soundspot.conf"
MODE="${1:-true}"
[[ "$MODE" =~ ^(true|false)$ ]] || exit 1
[ -f "$CONF" ] || exit 1

if grep -q "^VOICE_ENABLED=" "$CONF"; then
    sed -i "s|^VOICE_ENABLED=.*|VOICE_ENABLED=\"${MODE}\"|" "$CONF"
else
    echo "VOICE_ENABLED=\"${MODE}\"" >> "$CONF"
fi
systemctl restart soundspot-idle 2>/dev/null || true
