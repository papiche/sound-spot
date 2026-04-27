#!/bin/bash
# api/apps/nostr_post/run.sh — Publier un événement NOSTR depuis le portail
#
# Le relay strfry local est accessible via tunnel IPFS P2P sur ws://127.0.0.1:9999
# (strfry n'est PAS installé localement — il est distant, tunnel IPFS p2p).
#
# POST /api.sh?action=nostr_post
# Body : text=mon+message&kind=1
#        ou : cid=QmXXX&kind=1    (pour poster une URL IPFS)
#
# Modes de signature :
#   1. Identité Picoport  : ~/.zen/game/secret.nostr (format NSEC=nsec1...; NPUB=...; HEX=...;)
#   2. nsec visiteur      : nsec1xxx passé dans le body (keyfile temporaire /dev/shm, supprimé après)
#
# Prérequis :
#   - Picoport actif (Astroport.ONE light install, venv ~/.astro/)
#   - nostr_send_note.py dans ~/.zen/Astroport.ONE/tools/
#   - Relay local accessible ws://127.0.0.1:9999
#
# Hérite des exports de api.sh.

# ── Relay local (tunnel IPFS P2P vers strfry distant) ────────
_SS_SERVICE="portal-nostr"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

RELAY="ws://127.0.0.1:9999"

# ── Lire le body POST ────────────────────────────────────────
read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true

TEXT=$(printf '%s' "$POST_DATA" | grep -oP '(?<=text=)[^&]+' | head -1 | urldecode)
CID=$(printf '%s' "$POST_DATA"  | grep -oP '(?<=cid=)[^&]+'  | head -1 | urldecode)
KIND=$(printf '%s' "$POST_DATA" | grep -oP '(?<=kind=)[0-9]+' | head -1)
NSEC=$(printf '%s' "$POST_DATA" | grep -oP '(?<=nsec=)[^&]+'  | head -1 | urldecode)
KIND="${KIND:-1}"

# Construire le contenu
CONTENT="$TEXT"
if [ -n "$CID" ]; then
    CONTENT="${CONTENT:+$CONTENT }http://${SPOT_IP}:8080/ipfs/${CID}"
fi

if [ -z "$CONTENT" ]; then
    jq -n '{"error":"empty_content","hint":"Paramètre text= ou cid= requis"}'
    exit 0
fi

# ── Déterminer le keyfile de signature ───────────────────────
USER_HOME=$(getent passwd "${SOUNDSPOT_USER:-pi}" | cut -d: -f6)
KEYFILE=""
SIGN_MODE=""

if [ -n "$NSEC" ]; then
    # Clé visiteur — keyfile temporaire en RAM, supprimé à la sortie
    KEYFILE=$(mktemp -p /dev/shm nostr_kf_XXXXXX 2>/dev/null || mktemp)
    chmod 644 "$KEYFILE"
    trap "rm -f '$KEYFILE'" EXIT
    printf 'NSEC=%s;\n' "$NSEC" > "$KEYFILE"
    SIGN_MODE="visitor"
else
    # Identité Picoport (écrite par picoport_init_keys.sh)
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
    RESULT=$(sudo -u "${SOUNDSPOT_USER:-pi}" "$PYTHON" "$NOSTR_SCRIPT" \
        --keyfile "$KEYFILE" \
        --content "$CONTENT" \
        --kind   "$KIND" \
        --relays "$RELAY" \
        --json 2>/dev/null)

    EVENT_ID=$(printf '%s' "$RESULT" | jq -r '.event_id // empty')
    if [ -n "$EVENT_ID" ]; then
        jq -n \
            --arg id    "$EVENT_ID" \
            --arg relay "$RELAY" \
            --arg mode  "${SIGN_MODE}" \
            --argjson kind "$KIND" \
            '{"status":"ok","event_id":$id,"relay":$relay,"sign_mode":$mode,"kind":$kind}'
    else
        ERR=$(printf '%s' "$RESULT" | jq -r '.errors[0] // "publish_failed"')
        jq -n --arg relay "$RELAY" --arg err "$ERR" '{"error":$err,"relay":$relay}'
    fi

elif command -v nak &>/dev/null; then
    # Fallback nak (optionnel, non installé par défaut)
    NSEC_ARG=$(grep -oP '(?<=NSEC=)[^;\s]+' "$KEYFILE" | head -1)
    EVENT_ID=$(nak event \
        --sec "$NSEC_ARG" \
        --kind "$KIND" \
        --content "$CONTENT" \
        "$RELAY" 2>/dev/null | jq -r '.id // empty')
    if [ -n "$EVENT_ID" ]; then
        jq -n \
            --arg id    "$EVENT_ID" \
            --arg relay "$RELAY" \
            --arg mode  "${SIGN_MODE}" \
            --argjson kind "$KIND" \
            '{"status":"ok","event_id":$id,"relay":$relay,"sign_mode":$mode,"kind":$kind}'
    else
        jq -n --arg relay "$RELAY" '{"error":"publish_failed","relay":$relay}'
    fi

else
    jq -n '{"error":"no_publisher","hint":"Picoport (Astroport.ONE light install) requis"}'
fi
