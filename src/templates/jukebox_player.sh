#!/bin/bash
# /opt/soundspot/jukebox_player.sh
QUEUE_DIR="/tmp/soundspot_queue"
mkdir -p "$QUEUE_DIR"[ -f /opt/soundspot/soundspot.conf ] && source /opt/soundspot/soundspot.conf
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_ID=$(id -u "$SOUNDSPOT_USER" 2>/dev/null || echo 1000)
export XDG_RUNTIME_DIR="/run/user/${USER_ID}"

# Lancement du listener Python en tâche de fond via l'environnement ~/.astro
PYTHON_BIN="$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)/.astro/bin/python3"
"$PYTHON_BIN" /opt/soundspot/jukebox_listener.py &
LISTENER_PID=$!
trap "kill $LISTENER_PID 2>/dev/null" EXIT

echo "🎵 Jukebox Player démarré (PipeWire Queue Manager)."

while true; do
    # Si PipeWire ne lit rien
    if ! pgrep -x "pw-play" >/dev/null; then
        NEXT_JOB=$(ls -1 "$QUEUE_DIR"/*.job 2>/dev/null | sort | head -n 1)
        if[ -n "$NEXT_JOB" ]; then
            PLAY_URL=$(cat "$NEXT_JOB")
            rm -f "$NEXT_JOB"
            echo "▶ Lecture à l'antenne : $PLAY_URL"
            wget -qO /tmp/current_juke.mp3 "$PLAY_URL"
            pw-play /tmp/current_juke.mp3 2>/dev/null
            rm -f /tmp/current_juke.mp3
        fi
    fi
    sleep 3
done