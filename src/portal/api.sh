#!/bin/bash
# src/portal/api.sh — Routeur API JSON du portail captif SoundSpot
#
# Usage CGI : /api.sh?action=<nom>
#
# Résolution des modules (dans l'ordre) :
#   1. api/core/<action>.sh      — fonctions essentielles (status, auth, clock)
#   2. api/apps/<action>/run.sh  — applications optionnelles (yt_copy, …)
#
# Ajouter une app : créer src/portal/api/apps/<nom>/run.sh
# Elle hérite des exports : SPOT_NAME, SPOT_IP, ICECAST_PORT, INSTALL_DIR, …

source /opt/soundspot/soundspot.conf 2>/dev/null || true

export SPOT_NAME="${SPOT_NAME:-SoundSpot}"
export SPOT_IP="${SPOT_IP:-192.168.10.1}"
export SNAPCAST_PORT="${SNAPCAST_PORT:-1704}"
export ICECAST_PORT="${ICECAST_PORT:-8111}"
export CLOCK_MODE="${CLOCK_MODE:-bells}"
export INSTALL_DIR="${INSTALL_DIR:-/opt/soundspot}"

echo "Content-Type: application/json; charset=utf-8"
echo "Access-Control-Allow-Origin: *"
echo "Cache-Control: no-cache"
echo ""

ACTION=$(echo "$QUERY_STRING" | grep -oP '(?<=action=)[a-zA-Z0-9_]+' | head -1)

PORTAL_API="${INSTALL_DIR}/portal/api"
CORE="${PORTAL_API}/core/${ACTION}.sh"
APP="${PORTAL_API}/apps/${ACTION}/run.sh"

if   [ -n "$ACTION" ] && [ -f "$CORE" ]; then bash "$CORE"
elif [ -n "$ACTION" ] && [ -f "$APP"  ]; then bash "$APP"
else
    # Liste dynamique des actions disponibles
    CORE_LIST=$(ls "${PORTAL_API}/core/"*.sh 2>/dev/null | xargs -r -I{} basename {} .sh | tr '\n' ',' | sed 's/,$//')
    APP_LIST=$(ls -d "${PORTAL_API}/apps/"*/  2>/dev/null | xargs -r -I{} basename {} | tr '\n' ',' | sed 's/,$//')
    printf '{"error":"unknown_action","action":"%s","core":[%s],"apps":[%s]}\n' \
        "${ACTION:-}" \
        "$(echo "$CORE_LIST" | sed 's/,/","/g; s/^/"/; s/$/"/')" \
        "$(echo "$APP_LIST"  | sed 's/,/","/g; s/^/"/; s/$/"/')"
fi
