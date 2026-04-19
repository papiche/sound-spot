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
#   1. Identité Picoport  : clé Nostr du nœud (~/.zen/game/nostr.keys)
#   2. nsec visiteur      : nsec1xxx passé dans le body (jamais loggé)
#
# Prérequis :
#   - Picoport actif (clés NOSTR dans ~/.zen/game/nostr.keys)
#   - python3 + nostr (pip install nostr)  OU  nak (go install)
#   - Relay local accessible ws://127.0.0.1:9999
#
# Hérite des exports de api.sh.

# ── Relay local (tunnel IPFS P2P vers strfry distant) ────────
RELAY="ws://127.0.0.1:9999"

# ── Lire le body POST ────────────────────────────────────────
read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true

urldecode() {
    python3 -c "import sys,urllib.parse; print(urllib.parse.unquote_plus(sys.stdin.read().strip()))"
}

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

# ── Déterminer la clé de signature ───────────────────────────
NOSTR_KEYS=""
if [ -n "$NSEC" ]; then
    # Clé fournie par le visiteur (mode personnel)
    NSEC_ARG="$NSEC"
    SIGN_MODE="visitor"
else
    # Identité du Picoport
    KEYS_FILE=$(eval echo "~${SOUNDSPOT_USER:-pi}/.zen/game/nostr.keys")
    if [ -f "$KEYS_FILE" ]; then
        # Format attendu : NSEC=nsec1xxx ou nsec=nsec1xxx
        NSEC_ARG=$(grep -oP '(?<=NSEC=|nsec=)[^\s]+' "$KEYS_FILE" | head -1)
        SIGN_MODE="picoport"
    fi
fi

if [ -z "${NSEC_ARG:-}" ]; then
    jq -n '{"error":"no_signing_key","hint":"Picoport requis ou nsec= dans le body"}'
    exit 0
fi

# ── Publication avec `nak` (le plus simple) ──────────────────
# nak : https://github.com/fiatjaf/nak  (go install github.com/fiatjaf/nak@latest)
if command -v nak &>/dev/null; then
    EVENT_ID=$(nak event \
        --sec "$NSEC_ARG" \
        --kind "$KIND" \
        --content "$CONTENT" \
        "$RELAY" 2>/dev/null | jq -r '.id // empty')

    if [ -n "$EVENT_ID" ]; then
        jq -n \
            --arg id      "$EVENT_ID" \
            --arg relay   "$RELAY" \
            --arg mode    "${SIGN_MODE:-unknown}" \
            --argjson kind "$KIND" \
            '{"status":"ok","event_id":$id,"relay":$relay,"sign_mode":$mode,"kind":$kind}'
    else
        jq -n --arg relay "$RELAY" '{"error":"publish_failed","relay":$relay}'
    fi
else
    # TODO : fallback Python nostr library
    jq -n '{"error":"nak_not_installed","hint":"go install github.com/fiatjaf/nak@latest"}'
fi
