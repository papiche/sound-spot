#!/bin/bash
# api/apps/yt_copy/run.sh — Délégation de copie YouTube au nœud Home du MULTIPASS
#
# MULTIPASS requis (NIP-42). Aucun yt-dlp local.
# Le portail publie un événement kind 1 sur le relay public ; le nœud Home
# de l'utilisateur (bro_dm_daemon.sh sur Astroport.ONE) écoute et traite.
#
# GET  ?action=ytcopy&npub=npub1xxx → vérifie l'auth, retourne le relay cible
# POST body: url=https://...&npub=npub1xxx → même réponse (la signature se fait côté JS)

_SS_SERVICE="portal-ytcopy"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

# ── npub → hex ───────────────────────────────────────────────
_npub_to_hex() {
    python3 - "$1" <<'PYEOF'
import sys
CHARSET = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l'
def bech32_to_hex(s):
    s = s.lower()
    pos = s.rfind('1')
    if pos < 1: return ''
    data = []
    for c in s[pos+1:]:
        if c not in CHARSET: return ''
        data.append(CHARSET.index(c))
    data = data[:-6]
    acc, bits, result = 0, 0, []
    for v in data:
        acc = ((acc << 5) | v) & 0x3fffffff
        bits += 5
        while bits >= 8:
            bits -= 8
            result.append((acc >> bits) & 0xff)
    return bytes(result).hex()
try:
    print(bech32_to_hex(sys.argv[1]), end='')
except Exception:
    print('', end='')
PYEOF
}

# ── Lecture des paramètres ───────────────────────────────────
NPUB_GET=$(echo "$QUERY_STRING" | grep -oP '(?<=npub=)[^&]+' | head -1)

if [ "$REQUEST_METHOD" = "POST" ]; then
    read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
    NPUB_POST=$(printf '%s' "$POST_DATA" | grep -oP '(?<=npub=)[^&]+' | head -1)
fi
NPUB="${NPUB_POST:-$NPUB_GET}"

# ── Vérification NIP-42 ──────────────────────────────────────
AUTH_PUBKEY=""
if [[ "${NPUB:-}" == npub1* ]]; then
    AUTH_PUBKEY=$(_npub_to_hex "$NPUB")
elif [[ "${NPUB:-}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    AUTH_PUBKEY="${NPUB,,}"
fi

MULTIPASS_LINK="http://${SPOT_IP:-192.168.10.1}:8080/ipns/copylaradio.com/g1.html"

if [ -z "$AUTH_PUBKEY" ] || [ ! -f "/dev/shm/.nip42_auth_${AUTH_PUBKEY}" ]; then
    ss_warn "ytcopy: NIP-42 requis ip=${REMOTE_ADDR:-?}"
    jq -n \
        --arg link "$MULTIPASS_LINK" \
        '{"error":"unauthorized",
          "hint":"Authentification MULTIPASS requise pour copier depuis YouTube",
          "create_multipass":$link}'
    exit 0
fi

# Vérifier TTL du marker
NOW=$(date +%s)
TS=$(python3 -c "import json; d=json.load(open('/dev/shm/.nip42_auth_${AUTH_PUBKEY}')); print(d.get('ts',0))" 2>/dev/null || echo 0)
AGE=$(( NOW - TS ))
if [ "$AGE" -gt 3600 ]; then
    rm -f "/dev/shm/.nip42_auth_${AUTH_PUBKEY}"
    jq -n '{"error":"session_expired","hint":"Reconnectez-vous avec votre MULTIPASS"}'
    exit 0
fi

ss_info "ytcopy: délégation pubkey=${AUTH_PUBKEY:0:12}… ip=${REMOTE_ADDR:-?}"

# Relay public de la constellation UPlanet
PUBLIC_RELAY="wss://relay.copylaradio.com"

# Répondre : le navigateur signe et publie lui-même le kind 1
jq -n \
    --arg relay "$PUBLIC_RELAY" \
    --arg npub  "${NPUB}" \
    '{"status":"ok",
      "delegate":true,
      "relay":$relay,
      "npub":$npub,
      "hint":"Signez et publiez un kind 1 avec le tag [\"t\",\"ytcopy\"] sur le relay"}'
