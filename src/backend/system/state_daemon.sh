#!/bin/bash
# state_daemon.sh — Génère status.json toutes les 5s en RAM
# Élimine le fork-par-visiteur sur l'action status de api.sh.
# Le frontend lit /status.json (fichier statique, zéro overhead CGI).

source /opt/soundspot/soundspot.conf 2>/dev/null || true

export SPOT_NAME="${SPOT_NAME:-SoundSpot}"
export SPOT_IP="${SPOT_IP:-192.168.10.1}"
export SNAPCAST_PORT="${SNAPCAST_PORT:-1704}"
export ICECAST_PORT="${ICECAST_PORT:-8111}"
export CLOCK_MODE="${CLOCK_MODE:-bells}"
export INSTALL_DIR="${INSTALL_DIR:-/opt/soundspot}"

PORTAL="${INSTALL_DIR}/portal"
CORE="${PORTAL}/api/core/status.sh"
INTERVAL=5

while true; do
    if [ -x "$CORE" ]; then
        bash "$CORE" > /dev/shm/status.json.tmp 2>/dev/null && \
            mv /dev/shm/status.json.tmp "${PORTAL}/status.json"
    fi
    sleep "$INTERVAL"
    # Watchdog Décodeur

    # Vérification sécurisée du watchdog
    if [ -f "${PORTAL}/status.json" ]; then
        DJ_ACTIVE=$(jq -r '.dj_active // "false"' "${PORTAL}/status.json")
        if [ "$DJ_ACTIVE" = "true" ]; then
            # Test de flux : on essaie de lire 1 octet avec un timeout de 1s
            if ! timeout 1 dd if=/dev/shm/snapfifo bs=1 count=1 >/dev/null 2>&1; then
                ss_warn "Watchdog: Flux DJ actif mais aucun flux dans la FIFO (FFmpeg gelé ?)"
                systemctl restart soundspot-decoder
            fi
        fi
    fi
done
