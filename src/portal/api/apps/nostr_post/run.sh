#!/bin/bash
# api/apps/nostr_post/run.sh — Publier un événement NOSTR depuis le portail
#
# POST /api.sh?action=nostr_post
# Body :
#   text=mon+message[&kind=1]            → note kind 1 (défaut)
#   cid=QmXXX[&text=...]                 → URL /ipfs/CID ajoutée au contenu
#   audio_cid=QmXXX[&title=...&mime=...] → kind 1222 NIP-A0 + tags NIP-94
#   video_cid=QmXXX[&title=...&mime=...] → kind 21 NIP-71 + tags NIP-94
#   &kind=N                              → override explicite du kind
#   &nsec=nsec1xxx                       → clé visiteur (keyfile RAM, supprimé après)
#
# Relay local : ws://127.0.0.1:9999 (tunnel IPFS P2P → strfry distant)
# Hérite des exports de api.sh.

_SS_SERVICE="portal-nostr"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

RELAY="ws://127.0.0.1:9999"

# ── Lire le body POST ────────────────────────────────────────
read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true

TEXT=$(printf '%s' "$POST_DATA"      | grep -oP '(?<=text=)[^&]+'      | head -1 | urldecode)
CID=$(printf '%s' "$POST_DATA"       | grep -oP '(?<=cid=)[^&]+'       | head -1 | urldecode)
AUDIO_CID=$(printf '%s' "$POST_DATA" | grep -oP '(?<=audio_cid=)[^&]+' | head -1 | urldecode)
VIDEO_CID=$(printf '%s' "$POST_DATA" | grep -oP '(?<=video_cid=)[^&]+' | head -1 | urldecode)
TITLE=$(printf '%s' "$POST_DATA"     | grep -oP '(?<=title=)[^&]+'     | head -1 | urldecode)
MIME=$(printf '%s' "$POST_DATA"      | grep -oP '(?<=mime=)[^&]+'      | head -1 | urldecode)
KIND=$(printf '%s' "$POST_DATA"      | grep -oP '(?<=kind=)[0-9]+'     | head -1)
NSEC=$(printf '%s' "$POST_DATA"      | grep -oP '(?<=nsec=)[^&]+'      | head -1 | urldecode)

# ── Sélection du kind, du contenu et des tags NIP-94 ─────────
TAGS='[]'

if [ -n "$VIDEO_CID" ]; then
    # NIP-71 — kind 21 (vidéo long) par défaut
    KIND="${KIND:-21}"
    _MIME="${MIME:-video/mp4}"
    _LABEL="${TITLE:-🎬 /ipfs/${VIDEO_CID}}"
    CONTENT="${TEXT:-$_LABEL}"
    TAGS=$(jq -cn \
        --arg url  "/ipfs/${VIDEO_CID}" \
        --arg mime "$_MIME" \
        --arg title "${TITLE:-}" \
        '[
            ["url",  $url],
            ["m",    $mime],
            (if $title != "" then ["title", $title] else empty end)
        ]')

elif [ -n "$AUDIO_CID" ]; then
    # NIP-A0 — kind 1222 (audio court, <5 min) par défaut
    KIND="${KIND:-1222}"
    _MIME="${MIME:-audio/mpeg}"
    _LABEL="${TITLE:-🎵 /ipfs/${AUDIO_CID}}"
    CONTENT="${TEXT:-$_LABEL}"
    TAGS=$(jq -cn \
        --arg url  "/ipfs/${AUDIO_CID}" \
        --arg mime "$_MIME" \
        --arg title "${TITLE:-}" \
        '[
            ["url",  $url],
            ["m",    $mime],
            (if $title != "" then ["title", $title] else empty end)
        ]')

elif [ -n "$CID" ]; then
    # CID générique — URL relative /ipfs/ ajoutée au texte
    KIND="${KIND:-1}"
    CONTENT="${TEXT:+$TEXT }/ipfs/${CID}"

else
    KIND="${KIND:-1}"
    CONTENT="$TEXT"
fi

if [ -z "$CONTENT" ]; then
    jq -n '{"error":"empty_content","hint":"Paramètre text=, cid=, audio_cid= ou video_cid= requis"}'
    exit 0
fi

# ── Déterminer le keyfile de signature ───────────────────────
USER_HOME=$(getent passwd "${SOUNDSPOT_USER:-pi}" | cut -d: -f6)
KEYFILE=""
SIGN_MODE=""

if [ -n "$NSEC" ]; then
    KEYFILE=$(mktemp -p /dev/shm nostr_kf_XXXXXX 2>/dev/null || mktemp)
    chmod 644 "$KEYFILE"
    trap "rm -f '$KEYFILE'" EXIT
    printf 'NSEC=%s;\n' "$NSEC" > "$KEYFILE"
    SIGN_MODE="visitor"
else
    KEYFILE="${USER_HOME}/.zen/game/secret.nostr"
    SIGN_MODE="picoport"
fi

if [ ! -f "$KEYFILE" ]; then
    jq -n '{"error":"no_signing_key","hint":"Picoport requis ou nsec= dans le body"}'
    exit 0
fi

# ── Publication via nostr_send_note.py ───────────────────────
NOSTR_SCRIPT="${USER_HOME}/.zen/Astroport.ONE/tools/nostr_send_note.py"
PYTHON="${USER_HOME}/.astro/bin/python3"

if [ -f "$NOSTR_SCRIPT" ] && [ -x "$PYTHON" ]; then
    if [ "$TAGS" != '[]' ]; then
        RESULT=$(sudo -u "${SOUNDSPOT_USER:-pi}" "$PYTHON" "$NOSTR_SCRIPT" \
            --keyfile "$KEYFILE" \
            --content "$CONTENT" \
            --kind    "$KIND" \
            --tags    "$TAGS" \
            --relays  "$RELAY" \
            --json 2>/dev/null)
    else
        RESULT=$(sudo -u "${SOUNDSPOT_USER:-pi}" "$PYTHON" "$NOSTR_SCRIPT" \
            --keyfile "$KEYFILE" \
            --content "$CONTENT" \
            --kind    "$KIND" \
            --relays  "$RELAY" \
            --json 2>/dev/null)
    fi

    EVENT_ID=$(printf '%s' "$RESULT" | jq -r '.event_id // empty')
    if [ -n "$EVENT_ID" ]; then
        jq -n \
            --arg id   "$EVENT_ID" \
            --arg relay "$RELAY" \
            --arg mode  "$SIGN_MODE" \
            --argjson kind "$KIND" \
            '{"status":"ok","event_id":$id,"relay":$relay,"sign_mode":$mode,"kind":$kind}'
    else
        ERR=$(printf '%s' "$RESULT" | jq -r '.errors[0] // "publish_failed"')
        jq -n --arg relay "$RELAY" --arg err "$ERR" '{"error":$err,"relay":$relay}'
    fi

else
    jq -n '{"error":"no_publisher","hint":"Picoport (Astroport.ONE light install) requis"}'
fi
