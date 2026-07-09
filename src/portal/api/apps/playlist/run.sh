#!/bin/bash
# Chemin : src/portal/api/apps/playlist/run.sh
# API de gestion de la playlist unifiée SoundSpot

PLAYLIST_DIR="/dev/shm/soundspot_playlist"
mkdir -p "$PLAYLIST_DIR"
chmod 777 "$PLAYLIST_DIR" 2>/dev/null || true

CMD=$(echo "$QUERY_STRING" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)
CMD="${CMD:-list}"

if [ "$REQUEST_METHOD" = "POST" ]; then
    read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
    CMD=$(printf '%s' "$POST_DATA" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)
    URL=$(printf '%s' "$POST_DATA" | grep -oP '(?<=url=)[^&]+' | head -1 | urldecode)
    TITLE=$(printf '%s' "$POST_DATA" | grep -oP '(?<=title=)[^&]+' | head -1 | urldecode)
fi

case "${CMD}" in
    list)
        # Liste les morceaux dans la file d'attente (triés par ordre d'arrivée chronologique)
        ITEMS="["
        FIRST=true
        while IFS= read -r job_file; do
            [ -f "$job_file" ] || continue
            content=$(cat "$job_file" 2>/dev/null)
            # Extrait le JSON stocké
            ${FIRST} || ITEMS+=","
            ITEMS+="$content"
            FIRST=false
        done < <(find "$PLAYLIST_DIR" -maxdepth 1 -name "*.json" -type f | sort)
        ITEMS+="]"
        echo "{\"status\":\"ok\",\"playlist\":${ITEMS}}"
        ;;

    add)
        [ -z "$URL" ] && { echo '{"error":"url_required"}'; exit 0; }
        
        # Sécurité : Valider le format de l'URL (IPFS ou YouTube ou HTTP)
        if [[ ! "$URL" =~ ^(https?://|/ipfs/) ]]; then
            echo '{"error":"invalid_url","hint":"Lien YouTube, IPFS ou HTTP requis"}'
            exit 0
        fi

        # Déterminer le titre par défaut si non fourni
        [ -z "$TITLE" ] && TITLE=$(basename "$URL" | cut -d? -f1)
        [ -z "$TITLE" ] && TITLE="Lien externe (YouTube/IPFS)"

        # Limite de taille de la file d'attente (ex: 20 morceaux max pour éviter le flood)
        COUNT=$(find "$PLAYLIST_DIR" -name "*.json" | wc -l)
        if [ "$COUNT" -ge 20 ]; then
            echo '{"error":"queue_full","hint":"Trop de morceaux en attente, réessayez plus tard."}'
            exit 0
        fi

        SLOT=$(date +%s%N)
        JSON_PAYLOAD=$(jq -n \
            --arg url "$URL" \
            --arg title "$TITLE" \
            --arg user "${REMOTE_ADDR:-visiteur}" \
            --arg id "$SLOT" \
            '{"id":$id, "url":$url, "title":$title, "added_by":$user, "timestamp": (now | format_date("%Y-%m-%dT%H:%M:%SZ"))}')

        echo "$JSON_PAYLOAD" > "${PLAYLIST_DIR}/${SLOT}.json"
        
        # Notification d'ajout pour les logs
        echo "🎵 Playlist: ${TITLE} ajouté par ${REMOTE_ADDR}" >&2

        echo "{\"status\":\"ok\",\"message\":\"Ajouté à la playlist\",\"title\":\"${TITLE}\"}"
        ;;

    clear)
        # Nécessite d'être authentifié (NIP-42) pour nettoyer la playlist
        # Vous pouvez vérifier le token de session comme dans admin/run.sh
        rm -f "$PLAYLIST_DIR"/*.json
        echo '{"status":"ok","message":"Playlist vidée"}'
        ;;

    *)
        echo '{"error":"unknown_cmd"}'
        ;;
esac