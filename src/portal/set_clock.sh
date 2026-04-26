#!/bin/bash
# src/portal/set_clock.sh — CGI : bascule CLOCK_MODE via le portail captif
# Appelé par POST depuis index.sh
# Configuration lue depuis soundspot.conf à chaque requête (hot-reload).

source /opt/soundspot/soundspot.conf 2>/dev/null || true
INSTALL_DIR="${INSTALL_DIR:-/opt/soundspot}"

read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
MODE=$(printf '%s' "$POST_DATA" | grep -oP '(?<=mode=)[^&]+' | head -1)
[[ "$MODE" =~ ^(bells|silent)$ ]] || MODE="bells"

sudo "${INSTALL_DIR}/backend/system/set_clock_mode.sh" "$MODE" 2>/dev/null || true

echo "Status: 302 Found"
echo "Location: /"
echo ""
