#!/bin/bash
# /opt/soundspot/jukebox_player.sh — Daemon Jukebox Autonome
# Surveille Nostr (strfry) et joue les mp3 générés par l'IA
QUEUE_DIR="/tmp/soundspot_queue"
mkdir -p "$QUEUE_DIR"

# Configuration PipeWire pour l'utilisateur audio
[ -f /opt/soundspot/soundspot.conf ] && source /opt/soundspot/soundspot.conf
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_ID=$(id -u "$SOUNDSPOT_USER" 2>/dev/null || echo 1000)
export XDG_RUNTIME_DIR="/run/user/${USER_ID}"

# On ne lit que les événements survenus après le démarrage du script
LAST_TIME=$(date +%s)

echo "🎵 Jukebox Player démarré. Écoute de strfry..."

while true; do
    # 1. SCAN NOSTR : On cherche les Kind 1 récents
    if[ -x "$HOME/.zen/strfry/strfry" ]; then
        EVENTS=$(cd ~/.zen/strfry && ./strfry scan '{"since": '$LAST_TIME', "kinds": [1]}' 2>/dev/null)
        
        if [ -n "$EVENTS" ]; then
            LAST_TIME=$(date +%s)
            
            # Extraction des URLs IPFS se terminant par .mp3
            URLS=$(echo "$EVENTS" | jq -r '.content' | grep -oP 'https?://[^ ]+/ipfs/[a-zA-Z0-9]+/[^ ]+\.mp3' || true)
            
            for url in $URLS; do
                # Règle : Max 5 morceaux en file d'attente
                Q_LEN=$(ls -1 "$QUEUE_DIR" 2>/dev/null | wc -l)
                if[ "$Q_LEN" -lt 5 ]; then
                    JOB_ID=$(date +%s%N)
                    echo "$url" > "$QUEUE_DIR/$JOB_ID.job"
                    echo "📥 Jukebox : Morceau ajouté à la file -> $url"
                else
                    echo "⏳ Jukebox : File pleine (5 max). Morceau ignoré."
                fi
            done
        fi
    fi

    # 2. LECTURE : Si la carte son (pw-play) est libre, on joue le morceau suivant
    if ! pgrep -x "pw-play" >/dev/null; then
        NEXT_JOB=$(ls -1 "$QUEUE_DIR"/*.job 2>/dev/null | sort | head -n 1)
        
        if [ -n "$NEXT_JOB" ]; then
            PLAY_URL=$(cat "$NEXT_JOB")
            rm -f "$NEXT_JOB"
            echo "▶ Lecture à l'antenne : $PLAY_URL"
            
            # Téléchargement temp pour éviter les saccades réseau
            wget -qO /tmp/current_juke.mp3 "$PLAY_URL"
            pw-play /tmp/current_juke.mp3 2>/dev/null
            rm -f /tmp/current_juke.mp3
        fi
    fi

    sleep 5
done