#!/bin/bash
# portal_set_clock.sh — CGI : bascule CLOCK_MODE via le portail captif
# Appelé par POST depuis portal_index.sh
read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
MODE=$(printf '%s' "$POST_DATA" | grep -oP '(?<=mode=)[^&]+' | head -1)
[[ "$MODE" =~ ^(bells|silent)$ ]] || MODE="bells"

sudo /opt/soundspot/set_clock_mode.sh "$MODE" 2>/dev/null || true

echo "Status: 302 Found"
echo "Location: /"
echo ""
