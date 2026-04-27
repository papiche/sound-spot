#!/bin/bash
# api/apps/shutdown/run.sh — Extinction ordonnée du Master RPi4
# Accepte uniquement les requêtes POST depuis le réseau local AP (192.168.10.x)
# ou le loopback. Typiquement appelé par le nœud Énergie (INA219 + relais).

_SS_SERVICE="portal-shutdown"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

REMOTE_ADDR="${REMOTE_ADDR:-}"

case "$REMOTE_ADDR" in
    192.168.10.*|127.0.0.1|::1)
        echo '{"status":"shutting_down"}'
        # Flush les tampons audio proprement avant d'éteindre
        systemctl stop soundspot-client snapserver soundspot-decoder 2>/dev/null || true
        sleep 2
        sudo /usr/sbin/poweroff
        ;;
    *)
        echo '{"error":"unauthorized"}'
        ;;
esac
