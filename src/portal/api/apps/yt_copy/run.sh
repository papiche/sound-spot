#!/bin/bash
_SS_SERVICE="portal-ytcopy"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
YT_URL=$(printf '%s' "$POST_DATA" | grep -oP '(?<=url=)[^&]+' | head -1 | urldecode)
[ -z "$YT_URL" ] && { jq -n '{"error":"missing_url"}'; exit 0; }

# On répond instantanément au navigateur
jq -n '{"status":"ok","message":"Téléchargement asynchrone démarré. Il s'\''ajoutera à la file d'\''attente."}'

# On détache le processus lourd en arrière-plan (fermeture de stdout pour le serveur web)
(
    exec 1>&-
    exec 2>&-
    
    TARGET="$YT_URL"
    if ! [[ "$YT_URL" =~ ^https?:// ]]; then
        TARGET="ytsearch1:${YT_URL}"
    fi

    TMPDIR=$(mktemp -d /tmp/soundspot_yt_XXXXXX)
    TITLE=$(yt-dlp --print title --no-warnings --no-playlist -- "$TARGET" 2>/dev/null | head -1 || echo "jukebox_track")
    SAFE_TITLE=$(printf "%s" "$TITLE" | sed -e "s/[^a-zA-Z0-9._-]/_/g" | tr -s "_" | cut -c1-100)
    
    yt-dlp --max-filesize 50M --match-filter "duration < 600" \
        --extract-audio --audio-format mp3 --audio-quality 5 \
        -o "${TMPDIR}/${SAFE_TITLE}.mp3" -- "$TARGET" >/dev/null 2>&1

    AUDIO_FILE=$(find "$TMPDIR" -name "*.mp3" | head -1)
    if [ -n "$AUDIO_FILE" ]; then
        # On passe directement à l'ajout IPFS local pour la simplicité et rapidité
        CID=$(ipfs add -Q -w "$AUDIO_FILE" 2>/dev/null | tail -n 1)
        if [ -n "$CID" ]; then
            mkdir -p /dev/shm/soundspot_queue
            echo "http://127.0.0.1:8080/ipfs/${CID}/${SAFE_TITLE}.mp3" > "/dev/shm/soundspot_queue/$(date +%s%N).job"
            ss_info "Jukebox asynchrone : $TITLE téléchargé et mis en file d'attente (CID: $CID)."
        fi
    fi
    rm -rf "$TMPDIR"
) &
exit 0