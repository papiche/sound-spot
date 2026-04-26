#!/bin/bash
# set_bells_mode.sh — Active ou coupe le ding 429Hz + coups de cloche
# Exécuté avec sudo par www-data depuis le portail captif.
# Usage : sudo /opt/soundspot/set_bells_mode.sh [true|false]
CONF="/opt/soundspot/soundspot.conf"
MODE="${1:-true}"
[[ "$MODE" =~ ^(true|false)$ ]] || exit 1
[ -f "$CONF" ] || exit 1

if grep -q "^BELLS_ENABLED=" "$CONF"; then
    sed -i "s|^BELLS_ENABLED=.*|BELLS_ENABLED=\"${MODE}\"|" "$CONF"
else
    echo "BELLS_ENABLED=\"${MODE}\"" >> "$CONF"
fi
systemctl restart soundspot-idle 2>/dev/null || true
