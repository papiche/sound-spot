#!/bin/bash
# Moteur AutoDJ pour SoundSpot
# Priorité : uDRIVE/manifest.json du MULTIPASS connecté → fallback ~/Music local
source /opt/soundspot/soundspot.conf 2>/dev/null || true
MUSIC_DIR="/home/${SOUNDSPOT_USER:-pi}/Music"
PASS="${WIFI_PASS:-0penS0urce!}"
IPFS_GW="http://127.0.0.1:8080"
QUEUE_DIR="/dev/shm/soundspot_queue"
MARKER_DIR="/dev/shm"

mkdir -p "$MUSIC_DIR" "$QUEUE_DIR"
echo "Démarrage de l'AutoDJ."

# Récupère le npub du MULTIPASS actuellement connecté (1 seule session)
_get_connected_npub() {
    local marker
    marker=$(find "$MARKER_DIR" -maxdepth 1 -name '.nip42_auth_*' | head -1)
    [ -z "$marker" ] && return 1
    python3 -c "import json; d=json.load(open('$marker')); print(d.get('npub',''))" 2>/dev/null
}

# Récupère la liste des fichiers audio depuis le manifest uDRIVE du MULTIPASS
_fetch_udrive_audio() {
    local npub="$1"
    local manifest_url="${IPFS_GW}/ipns/${npub}/APP/uDRIVE/manifest.json"
    local manifest
    manifest=$(curl -sf --max-time 10 "$manifest_url" 2>/dev/null) || return 1
    # Extraire les ipfs_link des fichiers de type audio
    printf '%s' "$manifest" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for f in d.get('files', []):
        if f.get('type') == 'audio' and f.get('ipfs_link'):
            print(f['ipfs_link'])
except Exception:
    pass
" 2>/dev/null
}

while true; do
    # ── Tentative uDRIVE ────────────────────────────────────────
    NPUB=$(_get_connected_npub 2>/dev/null)
    UDRIVE_TRACKS=""
    if [ -n "$NPUB" ]; then
        UDRIVE_TRACKS=$(_fetch_udrive_audio "$NPUB")
    fi

    if [ -n "$UDRIVE_TRACKS" ]; then
        echo "🎵 AutoDJ uDRIVE : $(echo "$UDRIVE_TRACKS" | wc -l) pistes pour $NPUB"
        # Mélanger et jouer
        while IFS= read -r ipfs_url; do
            [ -z "$ipfs_url" ] && continue
            FULL_URL="${IPFS_GW}/ipfs/${ipfs_url}"
            echo "🎵 Lecture uDRIVE : $ipfs_url"
            ffmpeg -re -hide_banner -loglevel error \
                   -i "$FULL_URL" \
                   -c:a libvorbis -b:a 128k -content_type application/ogg \
                   -f ogg "icecast://source:${PASS}@127.0.0.1:8111/live"
            sleep 1
        done < <(echo "$UDRIVE_TRACKS" | shuf)
        continue
    fi

    # ── Fallback : fichiers locaux ───────────────────────────────
    FILES=$(find "$MUSIC_DIR" -type f -iregex '.*\.\(mp3\|ogg\|flac\|wav\)$' | shuf)
    if [ -z "$FILES" ]; then
        echo "Aucune musique disponible (uDRIVE vide, ~/Music vide). Attente 30s..."
        sleep 30
        continue
    fi
    echo "🎵 AutoDJ local : $(echo "$FILES" | wc -l) fichiers"
    while IFS= read -r f; do
        echo "🎵 Lecture locale : $f"
        ffmpeg -re -hide_banner -loglevel error -i "$f" \
               -c:a libvorbis -b:a 128k -content_type application/ogg \
               -f ogg "icecast://source:${PASS}@127.0.0.1:8111/live"
        sleep 1
    done <<< "$FILES"
done
