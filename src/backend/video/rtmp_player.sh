#!/bin/bash
# rtmp_player.sh — Affiche sur HDMI le flux sélectionné par la Régie VJ
export XDG_RUNTIME_DIR="/run/user/$(id -u ${SOUNDSPOT_USER:-pi} 2>/dev/null || echo 1000)"
CURRENT=""

while true; do
    WANTED=$(cat /dev/shm/current_vj 2>/dev/null || echo "")
    
    if [ "$WANTED" != "$CURRENT" ]; then
        pkill -x mpv 2>/dev/null
        CURRENT="$WANTED"
        
        if [ -n "$CURRENT" ]; then
            echo "Lancement de MPV sur le flux : $CURRENT"
            mpv --vo=drm --hwdec=auto --really-quiet "rtmp://127.0.0.1/live/$CURRENT" &
        fi
    fi
    sleep 2
done
