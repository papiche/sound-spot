#!/bin/bash
# api/apps/admin/run.sh — Configuration du nœud via le portail
#
# Actions GET :
#   ?action=admin&cmd=status    → état complet (SSID, BT, services)
#   ?action=admin&cmd=bt_scan   → scan Bluetooth (10s), retourne liste JSON
#
# Actions POST :
#   ?action=admin               → body: cmd=set_ssid&value=MON_SPOT
#                               → body: cmd=bt_pair&mac=F4:4E:FC:00:00:01
#                               → body: cmd=restart&service=soundspot-idle
#
# Sécurité : accessible seulement pendant les 15 premières minutes
# après le démarrage (boot_ts stocké dans /tmp/soundspot_boot).
# Hérite des exports de api.sh.

# ── Fenêtre d'accès (15 min après boot) ─────────────────────
BOOT_TS_FILE="/tmp/soundspot_boot_ts"
if [ ! -f "$BOOT_TS_FILE" ]; then
    date +%s > "$BOOT_TS_FILE"
fi
BOOT_TS=$(cat "$BOOT_TS_FILE")
NOW_TS=$(date +%s)
ELAPSED=$(( NOW_TS - BOOT_TS ))

if [ "$ELAPSED" -gt 900 ]; then
    jq -n --argjson elapsed "$ELAPSED" \
        '{"error":"admin_locked","elapsed":$elapsed,"hint":"Disponible seulement dans les 15 min suivant le démarrage"}'
    exit 0
fi

# ── Lecture des paramètres ───────────────────────────────────
CMD=$(echo "$QUERY_STRING" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)

if [ "$REQUEST_METHOD" = "POST" ]; then
    read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
    CMD=$(printf '%s' "$POST_DATA" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)
    VALUE=$(printf '%s' "$POST_DATA" \
        | grep -oP '(?<=value=)[^&]+' | head -1 \
        | python3 -c "import sys,urllib.parse; print(urllib.parse.unquote_plus(sys.stdin.read().strip()))" \
        2>/dev/null)
    MAC=$(printf '%s' "$POST_DATA" | grep -oP '(?<=mac=)[0-9A-Fa-f:]+' | head -1)
    SERVICE=$(printf '%s' "$POST_DATA" | grep -oP '(?<=service=)[a-zA-Z0-9_-]+' | head -1)
fi

# ── Commandes ────────────────────────────────────────────────
case "${CMD:-status}" in

    status)
        SERVICES_JSON=$(systemctl is-active soundspot-idle soundspot-decoder snapserver icecast2 lighttpd \
            | paste - - - - - \
            | awk '{print "{\"idle\":\""$1"\",\"decoder\":\""$2"\",\"snapserver\":\""$3"\",\"icecast\":\""$4"\",\"lighttpd\":\""$5"\"}"}')
        jq -n \
            --arg ssid     "$SPOT_NAME" \
            --arg ip       "$SPOT_IP" \
            --arg bt_mac   "${BT_MAC:-}" \
            --arg clock    "$CLOCK_MODE" \
            --argjson svc  "${SERVICES_JSON:-{}}" \
            --argjson remaining "$(( 900 - ELAPSED ))" \
            '{spot_name:$ssid, spot_ip:$ip, bt_mac:$bt_mac, clock_mode:$clock, services:$svc, admin_window_remaining:$remaining}'
        ;;

    bt_scan)
        # Scan Bluetooth 10s, retourne liste JSON
        SCAN_RAW=$(timeout 12 bash -c '
            bluetoothctl scan on &
            sleep 10
            bluetoothctl scan off
            bluetoothctl devices
        ' 2>/dev/null | grep "Device " | sed "s/.*Device //" | sort -u)

        DEVICES_JSON="["
        while IFS= read -r line; do
            DEV_MAC=$(echo "$line" | cut -d' ' -f1)
            DEV_NAME=$(echo "$line" | cut -d' ' -f2-)
            [ -n "$DEV_MAC" ] || continue
            PAIRED=$(bluetoothctl info "$DEV_MAC" 2>/dev/null | grep -c "Paired: yes" || echo 0)
            DEV_NAME_ESC=$(printf '%s' "$DEV_NAME" | sed 's/"/\\"/g')
            DEVICES_JSON+="{\"mac\":\"${DEV_MAC}\",\"name\":\"${DEV_NAME_ESC}\",\"paired\":$([ "$PAIRED" -gt 0 ] && echo true || echo false)},"
        done <<< "$SCAN_RAW"
        DEVICES_JSON="${DEVICES_JSON%,}]"

        jq -n --argjson devices "${DEVICES_JSON:-[]}" '{"status":"ok","devices":$devices}'
        ;;

    set_ssid)
        # TODO: modifier SPOT_NAME dans soundspot.conf + redémarrer hostapd
        # Implémentation complète à faire (redémarrage hostapd requis)
        jq -n --arg value "${VALUE:-}" '{"status":"not_implemented","hint":"Modifier SPOT_NAME dans soundspot.conf puis redémarrer hostapd","value":$value}'
        ;;

    restart)
        ALLOWED_SERVICES="soundspot-idle soundspot-decoder snapserver icecast2 bt-autoconnect"
        if printf '%s' "$ALLOWED_SERVICES" | grep -qw "$SERVICE"; then
            sudo systemctl restart "$SERVICE" 2>/dev/null || true
            jq -n --arg svc "$SERVICE" '{"status":"ok","restarted":$svc}'
        else
            jq -n --arg svc "${SERVICE:-}" '{"error":"forbidden_service","service":$svc}'
        fi
        ;;

    *)
        jq -n --arg cmd "${CMD:-}" '{"error":"unknown_cmd","cmd":$cmd,"available":["status","bt_scan","set_ssid","restart"]}'
        ;;
esac
