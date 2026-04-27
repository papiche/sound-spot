#!/bin/bash
# src/portal/api.sh — Routeur API JSON
source /opt/soundspot/soundspot.conf 2>/dev/null || true

export SPOT_NAME="${SPOT_NAME:-SoundSpot}"
export SPOT_IP="${SPOT_IP:-192.168.10.1}"
export SNAPCAST_PORT="${SNAPCAST_PORT:-1704}"
export ICECAST_PORT="${ICECAST_PORT:-8111}"
export CLOCK_MODE="${CLOCK_MODE:-bells}"
export INSTALL_DIR="${INSTALL_DIR:-/opt/soundspot}"
export SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
export ORPHEUS_PORT="${ORPHEUS_PORT:-5005}"

# urldecode — pur Bash, remplace python3 -c "urllib.parse..." (~200ms sur Pi Zero)
# Utilisation : urldecode "str%20enc%2B" OU echo "str" | urldecode
urldecode() {
    local s="${1:-$(cat)}"
    s="${s//+/ }"
    printf '%b\n' "${s//%/\\x}"
}
export -f urldecode

echo "Content-Type: application/json; charset=utf-8"
echo "Access-Control-Allow-Origin: *"
echo "Cache-Control: no-cache"
echo ""

ACTION=$(echo "$QUERY_STRING" | grep -oP '(?<=action=)[a-zA-Z0-9_]+' | head -1)
echo "[$(date '+%Y-%m-%dT%H:%M:%S')] [api] action=${ACTION} method=${REQUEST_METHOD:-GET} ip=${REMOTE_ADDR:-?}" \
    >> /var/log/soundspot-portal.log 2>/dev/null || true

CORE="${INSTALL_DIR}/portal/api/core/${ACTION}.sh"
APP="${INSTALL_DIR}/portal/api/apps/${ACTION}/run.sh"

if [ -f "$CORE" ]; then
    bash "$CORE"
elif [ -f "$APP" ]; then
    bash "$APP"
else
    echo '{"error":"not_found"}'
fi
