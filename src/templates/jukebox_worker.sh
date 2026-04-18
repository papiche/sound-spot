#!/bin/bash
# /opt/soundspot/jukebox_worker.sh — Le moteur du Jukebox

QUEUE_FILE="/tmp/soundspot_jukebox.queue"
TMP_DIR="$HOME/.zen/tmp/soundspot"
mkdir -p "$TMP_DIR"

# Variables pour le son (PipeWire)
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_ID=$(id -u "$SOUNDSPOT_USER" 2>/dev/null || echo 1000)
export XDG_RUNTIME_DIR="/run/user/${USER_ID}"

while true; do
    if [ -s "$QUEUE_FILE" ]; then
        # Lire la première ligne
        head -n 1 "$QUEUE_FILE" > /tmp/current_job
        # Supprimer cette ligne de la file
        sed -i '1d' "$QUEUE_FILE"

        JOB=$(cat /tmp/current_job)
        QUERY=$(echo "$JOB" | cut -d'|' -f2-)
        
        echo "▶ Jukebox: Traitement de '$QUERY'..."
        
        cd "$TMP_DIR"
        rm -f jukebox.mp3
        
        # 1. Télécharger (max 20 min)
        yt-dlp "ytsearch1:$QUERY" \
            --extract-audio --audio-format mp3 \
            --match-filter "duration <= 1200" \
            -o "jukebox.%(ext)s" >/dev/null 2>&1
            
        if [ -f "jukebox.mp3" ]; then
            # 2. Copier sur IPFS
            CID=$(ipfs add -Q jukebox.mp3 2>/dev/null)
            echo "▶ Jukebox: IPFS CID = $CID"
            
            # 3. Diffuser à l'antenne (mpg123 est ultra léger et parfait pour RPi)
            echo "▶ Jukebox: Lecture en cours..."
            mpg123 -q jukebox.mp3 2>/dev/null || pw-play jukebox.mp3 2>/dev/null
        else
            echo "⚠ Jukebox: Échec du téléchargement ou durée > 20min"
        fi
    fi
    # Attendre 3 secondes avant de vérifier à nouveau la file
    sleep 3
done