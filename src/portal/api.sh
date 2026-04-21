#!/bin/bash
# src/portal/api.sh — Routeur API JSON optimisé
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

case "$ACTION" in
    audio_fix)
        # Action de secours pour reconnecter le Bluetooth
        sudo /opt/soundspot/bt_manage.sh connect >/dev/null 2>&1
        echo '{"status":"ok","message":"Reconnexion Bluetooth lancée"}'
        ;;
    status)
        # On injecte les données batterie si disponibles
        BATT_PCT=$(cat /tmp/battery_percent 2>/dev/null || echo "0")
        BATT_VOLT=$(cat /tmp/battery_voltage 2>/dev/null || echo "0")
        DJ_ACTIVE="false"
        curl -s -o /dev/null -w "%{http_code}" --max-time 1 "http://127.0.0.1:8111/live" | grep -q "200" && DJ_ACTIVE="true"
        
        printf '{"spot_name":"%s","dj_active":%s,"batt_pct":%s,"batt_volt":%s,"picoport_active":true}\n' \
            "$SPOT_NAME" "$DJ_ACTIVE" "$BATT_PCT" "$BATT_VOLT"
        ;;
    *)
        # Dispatch classique vers les modules existants
        CORE="${INSTALL_DIR}/portal/api/core/${ACTION}.sh"
        APP="${INSTALL_DIR}/portal/api/apps/${ACTION}/run.sh"
        if [ -f "$CORE" ]; then bash "$CORE"; elif [ -f "$APP" ]; then bash "$APP"; else echo '{"error":"not_found"}'; fi
        ;;
esac