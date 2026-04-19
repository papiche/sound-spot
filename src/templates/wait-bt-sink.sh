#!/bin/bash
# wait-bt-sink.sh — Attend qu'un sink Bluetooth (A2DP) soit disponible dans WirePlumber.
# Utilisé en ExecStartPre par soundspot-client.service.
# Timeout : 60 secondes ; sort avec code 0 si trouvé, code 1 sinon.

TIMEOUT=60
INTERVAL=2
elapsed=0

while [ "$elapsed" -lt "$TIMEOUT" ]; do
    if wpctl status 2>/dev/null | grep -qiE "bluez|bluetooth|a2dp"; then
        echo "wait-bt-sink: sink Bluetooth détecté après ${elapsed}s"
        exit 0
    fi
    sleep "$INTERVAL"
    elapsed=$((elapsed + INTERVAL))
done

echo "wait-bt-sink: aucun sink Bluetooth après ${TIMEOUT}s — on continue quand même" >&2
exit 0
