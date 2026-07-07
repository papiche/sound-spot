#!/bin/bash
# /opt/soundspot/portal/api/apps/homer/run.sh — Soundboard de gags publique
#
# Clips courts servis depuis ${INSTALL_DIR}/portal/sounds/homer/*.mp3
# (aussi accessibles en direct par le navigateur via /sounds/homer/<fichier>).
# Ouvert à tous les visiteurs : joue localement sur le nœud (PipeWire → BT),
# même mécanisme que apps/speak et play_welcome.sh (lock partagé pour ne
# pas superposer les sons locaux).
#
# cmd=list          → liste des clips disponibles
# cmd=play&file=... → joue un clip

SOUNDS_DIR="${INSTALL_DIR:-/opt/soundspot}/portal/sounds/homer"

CMD=$(echo "$QUERY_STRING" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)
FILE=$(echo "$QUERY_STRING" | grep -oP '(?<=file=)[^&]+' | head -1 | urldecode)

case "${CMD:-list}" in
    list)
        SOUNDS="["
        FIRST=1
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            [ "$FIRST" -eq 1 ] && FIRST=0 || SOUNDS+=","
            SOUNDS+="\"${f}\""
        done < <(find "$SOUNDS_DIR" -maxdepth 1 -type f -iname '*.mp3' -printf '%f\n' 2>/dev/null | sort)
        SOUNDS+="]"
        echo "{\"status\":\"ok\",\"sounds\":${SOUNDS}}"
        ;;
    play)
        SAFE_FILE=$(basename -- "$FILE")
        TARGET="${SOUNDS_DIR}/${SAFE_FILE}"
        if [[ ! "$SAFE_FILE" =~ ^[A-Za-z0-9_.-]+\.mp3$ ]] || [ ! -f "$TARGET" ]; then
            echo '{"error":"not_found"}'
            exit 0
        fi
        (
            USER_ID=$(id -u "${SOUNDSPOT_USER:-pi}" 2>/dev/null || echo 1000)
            export XDG_RUNTIME_DIR="/run/user/${USER_ID}"
            exec 9>"${XDG_RUNTIME_DIR}/soundspot_welcome.lock"
            flock -n 9 || exit 0
            paplay "$TARGET" 2>/dev/null || pw-play "$TARGET" 2>/dev/null || aplay "$TARGET" 2>/dev/null
        ) &
        echo "{\"status\":\"ok\",\"playing\":\"${SAFE_FILE}\"}"
        ;;
    *)
        echo '{"error":"unknown_cmd"}'
        ;;
esac
