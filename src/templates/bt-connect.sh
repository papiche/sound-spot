#!/bin/bash
source /opt/soundspot/soundspot.conf
# Support multi-enceintes : BT_MACS contient une liste de MACs séparés par espaces
MACS="${BT_MACS:-${BT_MAC:-}}"
[ -z "$MACS" ] && { echo "BT_MACS non défini, skip"; exit 0; }

# S'assurer que l'agent Bluetooth est actif avant toute tentative de connexion
bluetoothctl agent on 2>/dev/null || true
bluetoothctl default-agent 2>/dev/null || true

CONNECTED=0
for mac in $MACS; do
    echo "Connexion BT : $mac"

    # Vérifier si l'appareil est connu (appairé) avant de tenter connect
    if ! bluetoothctl info "$mac" 2>&1 | grep -q "Device $mac"; then
        echo "Appareil $mac non appairé — tentative de scan (8s)..."
        bluetoothctl scan on &
        SCAN_PID=$!
        sleep 8
        kill "$SCAN_PID" 2>/dev/null || true
        wait "$SCAN_PID" 2>/dev/null || true
    fi

    for i in $(seq 1 5); do
        if bluetoothctl connect "$mac" 2>&1 | grep -q "Connection successful"; then
            echo "Enceinte BT connectée : $mac"
            CONNECTED=$((CONNECTED + 1))
            break
        fi
        sleep 5
    done
done

[ "$CONNECTED" -gt 0 ] || { echo "Échec connexion BT pour toutes les enceintes"; exit 1; }

# Si plusieurs enceintes, créer un sink combiné PipeWire/PulseAudio
MAC_COUNT=$(echo "$MACS" | wc -w)
if [ "$MAC_COUNT" -gt 1 ]; then
    sleep 3
    /opt/soundspot/bt-combine-sinks.sh 2>/dev/null || true
fi
exit 0
