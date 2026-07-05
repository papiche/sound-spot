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
INTERVAL=10

while true; do
    if [ -x "$CORE" ]; then
        bash "$CORE" > /dev/shm/status.json.tmp 2>/dev/null && \
            mv /dev/shm/status.json.tmp "${PORTAL}/status.json"
            chmod 644 "${PORTAL}/status.json" 2>/dev/null
            chown www-data:www-data "${PORTAL}/status.json" 2>/dev/null
    fi
    sleep "$INTERVAL"
    # Watchdog Décodeur — vérifie le service sans consommer d'octets du FIFO PCM
    if [ -f "${PORTAL}/status.json" ]; then
        DJ_ACTIVE=$(jq -r '.dj_active // "false"' "${PORTAL}/status.json")
        if [ "$DJ_ACTIVE" = "true" ]; then
            if ! systemctl is-active --quiet soundspot-decoder 2>/dev/null; then
                ss_warn "Watchdog: Décodeur arrêté"
                (
                    ALERT_TXT="Flux audio gelé. Tentative de redémarrage du décodeur."
                    ALERT_WAV="${INSTALL_DIR}/wav/decoder_frozen_alert.wav"
                    # Pré-enregistré une fois via Orpheus (voix pierre), rejoué en cache
                    # ensuite — pas d'appel TTS en direct (tunnel swarm trop lent/variable)
                    # à chaque déclenchement du watchdog.
                    if [ ! -s "$ALERT_WAV" ]; then
                        TMP_WAV=$(bash "${INSTALL_DIR}/backend/audio/tts.sh" "$ALERT_TXT" "pierre" 2>/dev/null | tail -1)
                        [ -s "$TMP_WAV" ] && cp "$TMP_WAV" "$ALERT_WAV" && rm -f "$TMP_WAV"
                    fi
                    if [ -s "$ALERT_WAV" ]; then
                        paplay "$ALERT_WAV" 2>/dev/null || aplay -q "$ALERT_WAV" 2>/dev/null
                    else
                        espeak-ng -v fr+f3 "$ALERT_TXT" | aplay -q 2>/dev/null
                    fi
                ) &
                systemctl restart soundspot-decoder
            fi
        fi
    fi


done
