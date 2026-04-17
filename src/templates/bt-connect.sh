#!/bin/bash
source /opt/soundspot/soundspot.conf
# Support multi-enceintes : BT_MACS contient une liste de MACs séparés par espaces
MACS="${BT_MACS:-${BT_MAC:-}}"
[ -z "$MACS" ] && { echo "BT_MACS non défini, skip"; exit 0; }

CONNECTED=0
for mac in $MACS; do
    echo "Connexion BT : $mac"
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
