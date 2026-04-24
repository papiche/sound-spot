#!/bin/bash
# /opt/soundspot/jukebox_player.sh

[ -f /opt/soundspot/soundspot.conf ] && source /opt/soundspot/soundspot.conf
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
USER_ID=$(id -u "$SOUNDSPOT_USER" 2>/dev/null || echo 1000)
export XDG_RUNTIME_DIR="/run/user/${USER_ID}"

# ── Identification Astroport (Optimisée : lecture directe config IPFS) ──
myIpfsPeerId() {
    local config="${USER_HOME}/.ipfs/config"
    [ ! -f "$config" ] && return 0
    local myIpfsPeerId=$(jq -r .Identity.PeerID "$config" 2>/dev/null)
    [ -n "$myIpfsPeerId" ] && [ "$myIpfsPeerId" != "null" ] && echo "$myIpfsPeerId"
}

IPFSNODEID=$(myIpfsPeerId || echo "unknown")
QUEUE_DIR="${USER_HOME}/.zen/tmp/${IPFSNODEID}/soundspot_queue"

# Création du dossier IPC avec permissions partagées (pour l'utilisateur web www-data)
mkdir -p "$QUEUE_DIR"
chmod 775 "$QUEUE_DIR"

# Lancement du listener Python en tâche de fond via l'environnement ~/.astro
PYTHON_BIN="${USER_HOME}/.astro/bin/python3"
"$PYTHON_BIN" /opt/soundspot/backend/audio/jukebox_listener.py &
LISTENER_PID=$!
trap "kill $LISTENER_PID 2>/dev/null" EXIT

echo "🎵 Jukebox Player démarré (PipeWire Queue Manager) -> $QUEUE_DIR"

while true; do
    # Si PipeWire ne lit rien (aucun son en cours)
    if ! pgrep -x "pw-play" >/dev/null; then
        # On prend le fichier .job le plus ancien
        NEXT_JOB=$(find "$QUEUE_DIR" -maxdepth 1 -name "*.job" -type f | sort | head -n 1)
        if [ -n "$NEXT_JOB" ]; then
            PLAY_URL=$(cat "$NEXT_JOB")
            rm -f "$NEXT_JOB"
            echo "▶ Lecture à l'antenne : $PLAY_URL"
            # On télécharge temporairement le MP3 depuis la gateway IPFS locale
            wget -qO /dev/shm/current_juke.mp3 "$PLAY_URL"
            pw-play /dev/shm/current_juke.mp3 2>/dev/null
            rm -f /dev/shm/current_juke.mp3
        fi
    fi
    sleep 3
done