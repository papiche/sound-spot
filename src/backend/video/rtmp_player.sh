#!/bin/bash
# rtmp_player.sh — Affiche sur HDMI le flux sélectionné par la Régie VJ,
# ou à défaut la dernière photo de mon-oeil.py (priorité systématique au VJ).
# Nécessite un DRM libre : pas d'X/lightdm actif (systemctl set-default
# multi-user.target), sinon --vo=drm ne peut pas prendre la main.
export XDG_RUNTIME_DIR="/run/user/$(id -u ${SOUNDSPOT_USER:-pi} 2>/dev/null || echo 1000)"
CURRENT=""
LAST_PHOTO_TS=0
PHOTO_PATH="/dev/shm/eye_capture.jpg"

while true; do
    WANTED=$(cat /dev/shm/current_vj 2>/dev/null || echo "")

    # Écran libre (pas de flux VJ) : montre la dernière photo si nouvelle
    if [ -z "$WANTED" ]; then
        PHOTO_TS=$(stat -c %Y "$PHOTO_PATH" 2>/dev/null || echo 0)
        if [ "$PHOTO_TS" -gt 0 ] && [ "$PHOTO_TS" != "$LAST_PHOTO_TS" ]; then
            LAST_PHOTO_TS="$PHOTO_TS"
            pkill -x mpv 2>/dev/null
            CURRENT=""
            echo "Affichage photo mon-oeil ($PHOTO_PATH)"
            mpv --vo=drm --image-display-duration=8 --really-quiet "$PHOTO_PATH"
        fi
    fi

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
