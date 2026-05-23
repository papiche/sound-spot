#!/bin/bash
# api/apps/admin/run.sh — Configuration du nœud via le portail (NIP-42 auth)
#
# Toutes les actions requièrent une authentification NIP-42 MULTIPASS.
# Le marker de session est créé par api/core/nip42.sh dans /dev/shm/.nip42_auth_PUBKEYHEX
# (TTL 3600s). Passer le npub en paramètre GET ou dans le body POST.
#
# Actions GET :
#   ?action=admin&cmd=status&npub=npub1xxx
#   ?action=admin&cmd=bt_scan&npub=npub1xxx
#   ?action=admin&cmd=bt_list_connected&npub=npub1xxx
#
# Actions POST :
#   body: cmd=bt_connect&mac=AA:BB:CC&npub=npub1xxx
#   body: cmd=bt_add&mac=AA:BB:CC&npub=npub1xxx
#   body: cmd=bt_remove&mac=AA:BB:CC&npub=npub1xxx
#   body: cmd=restart&service=soundspot-idle&npub=npub1xxx
#   body: cmd=reset_audio&npub=npub1xxx
#
# Hérite des exports de api.sh (SPOT_NAME, SPOT_IP, INSTALL_DIR, urldecode).

_SS_SERVICE="portal-admin"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

# ── Lecture des paramètres ───────────────────────────────────
CMD=$(echo "$QUERY_STRING" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)
NPUB_GET=$(echo "$QUERY_STRING" | grep -oP '(?<=npub=)[^&]+' | head -1)

if [ "$REQUEST_METHOD" = "POST" ]; then
    read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
    CMD=$(printf '%s' "$POST_DATA" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)
    VALUE=$(printf '%s' "$POST_DATA" | grep -oP '(?<=value=)[^&]+' | head -1 | urldecode)
    MAC=$(printf '%s' "$POST_DATA" | grep -oP '(?<=mac=)[0-9A-Fa-f:]+' | head -1)
    SERVICE=$(printf '%s' "$POST_DATA" | grep -oP '(?<=service=)[a-zA-Z0-9_-]+' | head -1)
    NPUB_POST=$(printf '%s' "$POST_DATA" | grep -oP '(?<=npub=)[^&]+' | head -1)
fi
NPUB="${NPUB_POST:-$NPUB_GET}"

# ── NIP-42 auth — npub → hex → marker check ─────────────────
_npub_to_hex() {
    python3 - "$1" <<'PYEOF'
import sys
CHARSET = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l'
def bech32_to_hex(s):
    s = s.lower()
    pos = s.rfind('1')
    if pos < 1: return ''
    data = []
    for c in s[pos+1:]:
        if c not in CHARSET: return ''
        data.append(CHARSET.index(c))
    data = data[:-6]
    acc, bits, result = 0, 0, []
    for v in data:
        acc = ((acc << 5) | v) & 0x3fffffff
        bits += 5
        while bits >= 8:
            bits -= 8
            result.append((acc >> bits) & 0xff)
    return bytes(result).hex()
try:
    print(bech32_to_hex(sys.argv[1]), end='')
except Exception:
    print('', end='')
PYEOF
}

AUTH_PUBKEY=""
if [[ "${NPUB:-}" == npub1* ]]; then
    AUTH_PUBKEY=$(_npub_to_hex "$NPUB")
elif [[ "${NPUB:-}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    AUTH_PUBKEY="${NPUB,,}"
fi

AUTH_MARKER="/dev/shm/.nip42_auth_${AUTH_PUBKEY}"
AUTH_TTL=3600

if [ -z "$AUTH_PUBKEY" ] || [ ! -f "$AUTH_MARKER" ]; then
    ss_warn "auth NIP-42 requise cmd=${CMD:-?} ip=${REMOTE_ADDR:-?}"
    jq -n '{"error":"unauthorized","hint":"Authentification NIP-42 MULTIPASS requise"}'
    exit 0
fi

# Vérifier la TTL du marker
NOW=$(date +%s)
TS=$(python3 -c "import json; d=json.load(open('$AUTH_MARKER')); print(d.get('ts',0))" 2>/dev/null || echo 0)
AGE=$(( NOW - TS ))
if [ "$AGE" -gt "$AUTH_TTL" ]; then
    rm -f "$AUTH_MARKER"
    jq -n '{"error":"session_expired","hint":"Reconnectez-vous avec votre identité NOSTR"}'
    exit 0
fi

ss_info "cmd=${CMD:-status} pubkey=${AUTH_PUBKEY:0:12}… ip=${REMOTE_ADDR:-?}"

# ── Commandes ────────────────────────────────────────────────
case "${CMD:-status}" in

    status)
        BT_MACS_CONF="${BT_MACS:-${BT_MAC:-}}"
        BT_CONNECTED=$(bluetoothctl devices Connected 2>/dev/null \
            | grep "Device " | awk '{print $2}' | paste -sd' ' - || echo "")
        SERVICES_JSON=$(systemctl is-active \
                soundspot-idle soundspot-decoder snapserver \
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

    reset_audio)
        ss_info "reset_audio: restart audio chain"
        sudo systemctl restart soundspot-decoder snapserver 2>/dev/null || true
        sleep 1
        sudo systemctl restart soundspot-client-master 2>/dev/null || true
        sudo "${INSTALL_DIR}/backend/system/bt-connect.sh" 2>/dev/null || true
        jq -n '{"status":"ok","message":"Chaîne audio réinitialisée"}'
        ;;

    *)
        jq -n --arg cmd "${CMD:-}" \
            '{"error":"unknown_cmd","cmd":$cmd,
              "available":["status","bt_scan","bt_list_connected","bt_connect","bt_add","bt_remove","restart","reset_audio"]}'
        ;;
esac
