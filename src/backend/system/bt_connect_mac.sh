#!/bin/bash
# bt_connect_mac.sh — Connexion BT one-shot depuis le portail admin
# Exécuté via sudo par www-data. Valide le MAC avant toute action.
# Usage : sudo /opt/soundspot/backend/system/bt_connect_mac.sh AA:BB:CC:DD:EE:FF

MAC="${1:-}"
INSTALL_DIR="${INSTALL_DIR:-/opt/soundspot}"

# Validation format MAC (prévient l'injection de commande)
[[ "$MAC" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || { echo '{"error":"invalid_mac"}'; exit 1; }

bluetoothctl connect "$MAC" 2>/dev/null &
BT_PID=$!
sleep 8
wait "$BT_PID" 2>/dev/null

# Recombiner les sinks PipeWire si multi-enceintes
COMBINE="$INSTALL_DIR/backend/system/bt-combine-sinks.sh"
[ -x "$COMBINE" ] && bash "$COMBINE" 2>/dev/null || true

systemctl restart soundspot-client 2>/dev/null || true
