#!/bin/bash
# api/apps/messages/run.sh — Gestion des messages du clocher depuis le portail
#
# GET  ?action=messages&cmd=list
#   → JSON avec id, text, has_wav pour chaque message_NN
#
# POST cmd=set_text&id=01&text=...
#   → Écrit le .txt, supprime le .wav (régénéré par espeak au prochain cycle)
#
# POST cmd=tts_now&id=01&voice=pierre
#   → Génère immédiatement le .wav via Orpheus (si disponible) ou espeak
#
# Hérite des exports de api.sh (INSTALL_DIR, SOUNDSPOT_USER, urldecode).

WAV_DIR="${INSTALL_DIR:-/opt/soundspot}/wav"
TTS_SH="${INSTALL_DIR:-/opt/soundspot}/backend/audio/tts.sh"
PORTAL_LOG="/var/log/soundspot-portal.log"
_log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] [messages] $*" >> "$PORTAL_LOG" 2>/dev/null || true; }

# ── Lecture des paramètres ───────────────────────────────────
CMD=$(echo "$QUERY_STRING" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)
CMD="${CMD:-list}"

if [ "$REQUEST_METHOD" = "POST" ]; then
    read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
    CMD=$(printf '%s' "$POST_DATA"   | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)
    ID=$(printf '%s' "$POST_DATA"    | grep -oP '(?<=id=)[0-9]+' | head -1)
    TEXT=$(printf '%s' "$POST_DATA"  | grep -oP '(?<=text=)[^&]+' | head -1 | urldecode)
    VOICE=$(printf '%s' "$POST_DATA" | grep -oP '(?<=voice=)[a-zA-Z]+' | head -1)
    CMD="${CMD:-list}"
fi

# ── list ─────────────────────────────────────────────────────
if [ "${CMD}" = "list" ]; then
    ITEMS="["
    FIRST=true
    for txt in "$WAV_DIR"/message_*.txt; do
        [ -f "$txt" ] || continue
        num=$(basename "$txt" .txt | sed 's/message_//')
        wav="${WAV_DIR}/message_${num}.wav"
        content=$(cat "$txt" 2>/dev/null | sed 's/\\/\\\\/g; s/"/\\"/g')
        has_wav=false; [ -f "$wav" ] && has_wav=true
        ${FIRST} || ITEMS+=","
        ITEMS+="{\"id\":\"${num}\",\"text\":\"${content}\",\"has_wav\":${has_wav}}"
        FIRST=false
    done
    ITEMS+="]"
    jq -n --argjson items "$ITEMS" '{"status":"ok","messages":$items}'
    exit 0
fi

# ── set_text ─────────────────────────────────────────────────
if [ "${CMD}" = "set_text" ]; then
    [ -z "$ID" ] || [ -z "$TEXT" ] && { jq -n '{"error":"id_and_text_required"}'; exit 0; }
    ID=$(printf '%02d' "$((10#$ID))")
    txt="$WAV_DIR/message_${ID}.txt"
    wav="$WAV_DIR/message_${ID}.wav"
    [ -f "$txt" ] || { jq -n '{"error":"message_not_found"}'; exit 0; }
    printf '%s' "$TEXT" > "$txt"
    rm -f "$wav"
    jq -n --arg id "$ID" --arg text "$TEXT" \
        '{"status":"ok","id":$id,"text":$text,"hint":"wav régénéré au prochain cycle"}'
    exit 0
fi

# ── tts_now ──────────────────────────────────────────────────
if [ "${CMD}" = "tts_now" ]; then
    [ -z "$ID" ] && { jq -n '{"error":"id_required"}'; exit 0; }
    ID=$(printf '%02d' "$((10#$ID))")
    txt="$WAV_DIR/message_${ID}.txt"
    wav="$WAV_DIR/message_${ID}.wav"
    [ -f "$txt" ] || { jq -n '{"error":"message_not_found"}'; exit 0; }
    VOICE="${VOICE:-pierre}"

    USER_HOME=$(getent passwd "${SOUNDSPOT_USER:-pi}" | cut -d: -f6)
    PYTHON="${USER_HOME}/.astro/bin/python3"
    ORPHEUS_PORT="${ORPHEUS_PORT:-5005}"

    WAV_URL="/wav/message_${ID}.wav"
    TXT_CONTENT=$(cat "$txt")
    _log "tts_now id=$ID voice=$VOICE"

    # Essayer Orpheus directement (pas via tts.sh pour éviter le blocage sur picoport.service)
    HTTP_ORPHEUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
        "http://localhost:${ORPHEUS_PORT}/docs" 2>/dev/null || echo "000")
    if [ "$HTTP_ORPHEUS" = "200" ]; then
        TMP_WAV="/dev/shm/tts_portal_$$.wav"
        JSON_TXT=$(python3 -c "import sys,json; print(json.dumps(sys.argv[1]))" "$TXT_CONTENT" 2>/dev/null \
                   || echo "\"${TXT_CONTENT//\"/\\\"}\"")
        if curl -sf --max-time 20 \
            -o "$TMP_WAV" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"orpheus\",\"input\":${JSON_TXT},\"voice\":\"${VOICE}\",\"response_format\":\"wav\",\"speed\":1.0}" \
            "http://localhost:${ORPHEUS_PORT}/v1/audio/speech" 2>>"$PORTAL_LOG" \
            && [ -s "$TMP_WAV" ]; then
            mv "$TMP_WAV" "$wav"
            chown www-data:www-data "$wav" 2>/dev/null || true
            _log "ok source=orpheus voice=$VOICE wav=$wav"
            jq -n --arg id "$ID" --arg voice "$VOICE" --arg url "$WAV_URL" \
                '{"status":"ok","id":$id,"voice":$voice,"source":"orpheus","url":$url}'
            exit 0
        fi
        rm -f "$TMP_WAV"
        _log "Orpheus KO (curl vide) — fallback espeak"
    else
        _log "Orpheus absent (port ${ORPHEUS_PORT}) — fallback espeak"
    fi

    # Fallback espeak
    if espeak-ng -v fr+f3 -s 115 -p 40 "$TXT_CONTENT" -w "$wav" 2>>"$PORTAL_LOG"; then
        chown www-data:www-data "$wav" 2>/dev/null || true
        _log "ok source=espeak wav=$wav"
        jq -n --arg id "$ID" --arg url "$WAV_URL" \
            '{"status":"ok","id":$id,"source":"espeak","url":$url}'
    else
        _log "ERREUR tts_failed"
        jq -n '{"error":"tts_failed"}'
    fi
    exit 0
fi

jq -n --arg cmd "$CMD" '{"error":"unknown_cmd","cmd":$cmd,"available":["list","set_text","tts_now"]}'
