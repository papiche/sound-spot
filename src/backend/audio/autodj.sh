#!/bin/bash
# Moteur AutoDJ pour SoundSpot
source /opt/soundspot/soundspot.conf 2>/dev/null || true
MUSIC_DIR="/home/${SOUNDSPOT_USER:-pi}/Music"
PASS="${WIFI_PASS:-0penS0urce!}"

mkdir -p "$MUSIC_DIR"
echo "Démarrage de l'AutoDJ. Dossier : $MUSIC_DIR"

while true; do
    FILES=$(find "$MUSIC_DIR" -type f -iregex '.*\.\(mp3\|ogg\|flac\|wav\)$' | shuf)
    if [ -z "$FILES" ]; then
        echo "Aucune musique trouvée dans $MUSIC_DIR. Attente 10s..."
        sleep 10
        continue
    fi
    while IFS= read -r f; do
        echo "🎵 Lecture : $f"
        ffmpeg -re -hide_banner -loglevel error -i "$f" \
               -c:a libvorbis -b:a 128k -content_type application/ogg \
               -f ogg "icecast://source:${PASS}@127.0.0.1:8111/live"
        sleep 1
    done <<< "$FILES"
done