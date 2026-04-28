#!/bin/bash
# set_bt_macs.sh — Ajoute ou retire un MAC de BT_MACS dans soundspot.conf
# Exécuté via sudo par www-data depuis le portail admin.
# Usage : sudo /opt/soundspot/backend/system/set_bt_macs.sh add AA:BB:CC:DD:EE:FF
#         sudo /opt/soundspot/backend/system/set_bt_macs.sh remove AA:BB:CC:DD:EE:FF

ACTION="${1:-}"
MAC="${2:-}"
CONF="/opt/soundspot/soundspot.conf"

[[ "$ACTION" =~ ^(add|remove)$ ]]               || { echo '{"error":"invalid_action"}'; exit 1; }
[[ "$MAC" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || { echo '{"error":"invalid_mac"}';    exit 1; }
[ -f "$CONF" ]                                   || { echo '{"error":"conf_missing"}';    exit 1; }

source "$CONF" 2>/dev/null || true
CURRENT="${BT_MACS:-${BT_MAC:-}}"

if [ "$ACTION" = "add" ]; then
    if echo "$CURRENT" | grep -q "$MAC"; then
        NEW_MACS="$CURRENT"
    else
        NEW_MACS="${CURRENT:+$CURRENT }${MAC}"
    fi
else
    NEW_MACS=$(echo "$CURRENT" | sed "s|${MAC}||g" | tr -s ' ' | xargs)
fi

if grep -q "^BT_MACS=" "$CONF"; then
    sed -i "s|^BT_MACS=.*|BT_MACS=\"${NEW_MACS}\"|" "$CONF"
else
    echo "BT_MACS=\"${NEW_MACS}\"" >> "$CONF"
fi

# Redémarrer le service réactif pour prendre en compte les nouveaux MACs
systemctl restart soundspot-bt-reactive 2>/dev/null || true
[ -n "$NEW_MACS" ] && systemctl enable  soundspot-bt-reactive 2>/dev/null || true
