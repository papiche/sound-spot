#!/bin/bash
# set_clock_mode.sh — Modifie CLOCK_MODE dans soundspot.conf
# Exécuté avec sudo par www-data depuis le portail captif.
# Usage : sudo /opt/soundspot/set_clock_mode.sh [bells|silent]
CONF="/opt/soundspot/soundspot.conf"
MODE="${1:-bells}"
[[ "$MODE" =~ ^(bells|silent)$ ]] || exit 1
[ -f "$CONF" ] || exit 1

sed -i "s|^CLOCK_MODE=.*|CLOCK_MODE=\"${MODE}\"|" "$CONF"
systemctl restart soundspot-idle 2>/dev/null || true
