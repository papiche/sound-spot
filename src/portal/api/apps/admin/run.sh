#!/bin/bash
# api/apps/admin/run.sh — Configuration du nœud via le portail
#
# Toutes les actions nécessitent le mot de passe admin (pass=xxxx).
# Mot de passe = 10 derniers caractères de UPLANETNAME (swarm.key IPFS).
# Écrit par picoport.sh dans /dev/shm/soundspot_admin_pass (RAM, 644).
# Fallback si picoport absent : sha256(SPOT_NAME+SPOT_IP)[0:10].
#
# Actions GET :
#   ?action=admin&cmd=status&pass=xxxx
#   ?action=admin&cmd=bt_scan&pass=xxxx
#   ?action=admin&cmd=bt_list_connected&pass=xxxx
#
# Actions POST :
#   body: cmd=bt_connect&mac=AA:BB:CC&pass=xxxx
#   body: cmd=bt_add&mac=AA:BB:CC&pass=xxxx
#   body: cmd=bt_remove&mac=AA:BB:CC&pass=xxxx
#   body: cmd=restart&service=soundspot-idle&pass=xxxx
#
# Hérite des exports de api.sh (SPOT_NAME, SPOT_IP, INSTALL_DIR, urldecode).

# ── Lecture des paramètres ───────────────────────────────────
_SS_SERVICE="portal-admin"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

CMD=$(echo "$QUERY_STRING" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)
PASS_GET=$(echo "$QUERY_STRING" | grep -oP '(?<=pass=)[^&]+' | head -1 | urldecode)

if [ "$REQUEST_METHOD" = "POST" ]; then
    read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
    CMD=$(printf '%s' "$POST_DATA" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)
    VALUE=$(printf '%s' "$POST_DATA" | grep -oP '(?<=value=)[^&]+' | head -1 | urldecode)
    MAC=$(printf '%s' "$POST_DATA" | grep -oP '(?<=mac=)[0-9A-Fa-f:]+' | head -1)
    SERVICE=$(printf '%s' "$POST_DATA" | grep -oP '(?<=service=)[a-zA-Z0-9_-]+' | head -1)
    PASS_POST=$(printf '%s' "$POST_DATA" | grep -oP '(?<=pass=)[^&]+' | head -1 | urldecode)
fi
PASS="${PASS_POST:-$PASS_GET}"

# ── Vérification du mot de passe ─────────────────────────────
ADMIN_PASS=$(cat /dev/shm/soundspot_admin_pass 2>/dev/null | tr -d '[:space:]')
if [ -z "$ADMIN_PASS" ]; then
    # Fallback déterministe si picoport n'a pas encore tourné
    ADMIN_PASS=$(printf '%s%s' "${SPOT_NAME}" "${SPOT_IP}" | sha256sum | cut -c1-10)
fi

if [ -z "$PASS" ] || [ "$PASS" != "$ADMIN_PASS" ]; then
    jq -n '{"error":"unauthorized","hint":"Mot de passe requis (10 derniers caractères UPLANETNAME)"}'
    exit 0
fi

# ── Commandes ────────────────────────────────────────────────
case "${CMD:-status}" in

    status)
        BT_MACS_CONF="${BT_MACS:-${BT_MAC:-}}"
        BT_CONNECTED=$(bluetoothctl devices Connected 2>/dev/null \
            | grep "Device " | awk '{print $2}' | paste -sd' ' - || echo "")
        SERVICES_JSON=$(systemctl is-active soundspot-idle soundspot-decoder snapserver \
                icecast2 lighttpd soundspot-bt-reactive \
            | paste - - - - - - \
            | awk '{print "{\"idle\":\""$1"\",\"decoder\":\""$2"\",\"snapserver\":\""$3"\",\"icecast\":\""$4"\",\"lighttpd\":\""$5"\",\"bt_reactive\":\""$6"\"}"}')
        jq -n \
            --arg ssid        "$SPOT_NAME" \
            --arg ip          "$SPOT_IP" \
            --arg bt_macs     "${BT_MACS_CONF}" \
            --arg bt_connected "${BT_CONNECTED}" \
            --arg clock       "$CLOCK_MODE" \
            --argjson svc     "${SERVICES_JSON:-{}}" \
            '{spot_name:$ssid, spot_ip:$ip, bt_macs:$bt_macs,
              bt_connected:$bt_connected, clock_mode:$clock, services:$svc}'
        ;;

    bt_scan)
        SCAN_RAW=$(timeout 13 bash -c '
            bluetoothctl scan on &
            sleep 10
            bluetoothctl scan off
            bluetoothctl devices
        ' 2>/dev/null | grep "Device " | sed "s/.*Device //" | sort -u)

        DEVICES_JSON="["
        FIRST=true
        while IFS= read -r line; do
            DEV_MAC=$(echo "$line" | cut -d' ' -f1)
            DEV_NAME=$(echo "$line" | cut -d' ' -f2-)
            [ -n "$DEV_MAC" ] || continue
            PAIRED=$(bluetoothctl info "$DEV_MAC" 2>/dev/null | grep -c "Paired: yes" || echo 0)
            CONNECTED=$(bluetoothctl info "$DEV_MAC" 2>/dev/null | grep -c "Connected: yes" || echo 0)
            DEV_NAME_ESC=$(printf '%s' "$DEV_NAME" | sed 's/"/\\"/g')
            ${FIRST} || DEVICES_JSON+=","
            DEVICES_JSON+="{\"mac\":\"${DEV_MAC}\",\"name\":\"${DEV_NAME_ESC}\","
            DEVICES_JSON+="\"paired\":$([ "$PAIRED" -gt 0 ] && echo true || echo false),"
            DEVICES_JSON+="\"connected\":$([ "$CONNECTED" -gt 0 ] && echo true || echo false)}"
            FIRST=false
        done <<< "$SCAN_RAW"
        DEVICES_JSON+="]"
        jq -n --argjson devices "${DEVICES_JSON:-[]}" '{"status":"ok","devices":$devices}'
        ;;

    bt_list_connected)
        CONNECTED_JSON="["
        FIRST=true
        while IFS= read -r line; do
            MAC=$(echo "$line" | grep -oP '(?<=Device )[0-9A-F:]+')
            NAME=$(echo "$line" | sed "s/.*Device [0-9A-F:]* //")
            [ -n "$MAC" ] || continue
            ${FIRST} || CONNECTED_JSON+=","
            CONNECTED_JSON+="{\"mac\":\"$MAC\",\"name\":\"$(printf '%s' "$NAME" | sed 's/"/\\"/g')\"}"
            FIRST=false
        done < <(bluetoothctl devices Connected 2>/dev/null | grep "Device ")
        CONNECTED_JSON+="]"
        jq -n --argjson devices "${CONNECTED_JSON:-[]}" '{"status":"ok","devices":$devices}'
        ;;

    bt_connect)
        [[ "${MAC:-}" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] \
            || { jq -n '{"error":"invalid_mac"}'; exit 0; }
        sudo "${INSTALL_DIR}/backend/system/bt_connect_mac.sh" "$MAC" 2>/dev/null &
        jq -n --arg mac "$MAC" '{"status":"connecting","mac":$mac,"hint":"Reconnexion en cours (8s)"}'
        ;;

    bt_add)
        [[ "${MAC:-}" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] \
            || { jq -n '{"error":"invalid_mac"}'; exit 0; }
        sudo "${INSTALL_DIR}/backend/system/set_bt_macs.sh" add "$MAC" 2>/dev/null
        jq -n --arg mac "$MAC" '{"status":"ok","action":"added","mac":$mac}'
        ;;

    bt_remove)
        [[ "${MAC:-}" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] \
            || { jq -n '{"error":"invalid_mac"}'; exit 0; }
        sudo "${INSTALL_DIR}/backend/system/set_bt_macs.sh" remove "$MAC" 2>/dev/null
        jq -n --arg mac "$MAC" '{"status":"ok","action":"removed","mac":$mac}'
        ;;

    restart)
        ALLOWED="soundspot-idle soundspot-decoder snapserver icecast2 soundspot-bt-reactive"
        if printf '%s' "$ALLOWED" | grep -qw "${SERVICE:-}"; then
            sudo systemctl restart "$SERVICE" 2>/dev/null || true
            jq -n --arg svc "$SERVICE" '{"status":"ok","restarted":$svc}'
        else
            jq -n --arg svc "${SERVICE:-}" '{"error":"forbidden_service","service":$svc}'
        fi
        ;;

    *)
        jq -n --arg cmd "${CMD:-}" \
            '{"error":"unknown_cmd","cmd":$cmd,
              "available":["status","bt_scan","bt_list_connected","bt_connect","bt_add","bt_remove","restart"]}'
        ;;
esac
