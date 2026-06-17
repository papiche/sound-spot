#!/bin/bash
# api/core/nip42.sh — Authentification NIP-42 pour le portail captif SoundSpot
#
# Endpoints (via api.sh?action=nip42&cmd=X&npub=Y) :
#   GET  cmd=challenge  → génère un nonce et le stocke en /dev/shm/
#   POST cmd=verify     → vérifie l'événement kind 22242 signé (nostr_node_intercom.py verify)
#   GET  cmd=status     → vérifie si le marker auth est valide
#   GET  cmd=logout     → supprime le marker auth
#
# Vérification signature : nostr_node_intercom.py verify (Astroport.ONE, venv ~/.astro/)
# Marker de session : /dev/shm/.nip42_auth_PUBKEYHEX (TTL 3600s)

_SSHOME=$(getent passwd "${SOUNDSPOT_USER:-pi}" | cut -d: -f6)
_INTERCOM="${_SSHOME}/.zen/Astroport.ONE/tools/nostr_node_intercom.py"
_PYTHON="${_SSHOME}/.astro/bin/python3"
MARKER_DIR="/dev/shm"
CHALLENGE_TTL=120
AUTH_TTL=3600

# ── Parsing params ───────────────────────────────────────────
CMD=$(echo "$QUERY_STRING"  | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)
NPUB_RAW=$(echo "$QUERY_STRING" | grep -oP '(?<=npub=)[^&]+' | head -1)
NPUB=$(printf '%b' "${NPUB_RAW//+/ }" 2>/dev/null | sed 's/%/\\x/g' || echo "$NPUB_RAW")

# ── npub bech32 → hex ─────────────────────────────────────────
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
    data = data[:-6]  # retire checksum
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

# Accepte npub1... ou hex64
if [[ "${NPUB:-}" == npub1* ]]; then
    PUBKEY_HEX=$(_npub_to_hex "$NPUB")
elif [[ "${NPUB:-}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    PUBKEY_HEX="${NPUB,,}"
fi

if [ -z "${PUBKEY_HEX:-}" ]; then
    echo '{"ok":false,"error":"npub manquant ou invalide"}'
    exit 0
fi

CHALLENGE_FILE="$MARKER_DIR/ss_nip42_ch_${PUBKEY_HEX:0:16}"
AUTH_MARKER="$MARKER_DIR/.nip42_auth_${PUBKEY_HEX}"

# ── Commandes ─────────────────────────────────────────────────
case "$CMD" in

    challenge)
        NONCE=$(openssl rand -hex 32)
        printf '%s' "$NONCE" > "$CHALLENGE_FILE"
        chmod 600 "$CHALLENGE_FILE" 2>/dev/null || true
        printf '{"ok":true,"challenge":"%s","ttl":%d}\n' "$NONCE" "$CHALLENGE_TTL"
        ;;

    verify)
        # Lire le corps POST (événement kind 22242 signé)
        if [ "${REQUEST_METHOD:-GET}" = "POST" ]; then
            read -r -n "${CONTENT_LENGTH:-4096}" EVENT_JSON 2>/dev/null || true
        else
            # Fallback GET param event= (URL-encoded)
            EVENT_JSON=$(echo "$QUERY_STRING" | grep -oP '(?<=event=)[^&]+' | head -1 \
                | python3 -c "import sys,urllib.parse; print(urllib.parse.unquote_plus(sys.stdin.read().strip()))" 2>/dev/null)
        fi
        [ -z "${EVENT_JSON:-}" ] && { echo '{"ok":false,"error":"event manquant"}'; exit 0; }

        # Vérifier que le challenge correspond
        STORED=$(cat "$CHALLENGE_FILE" 2>/dev/null | tr -d '[:space:]')
        [ -z "$STORED" ] && { echo '{"ok":false,"error":"challenge expiré ou inconnu"}'; exit 0; }

        CHALLENGE_IN=$(printf '%s' "$EVENT_JSON" | python3 - <<'PYEOF' 2>/dev/null
import json, sys
try:
    e = json.loads(sys.stdin.read())
    for t in e.get("tags", []):
        if len(t) >= 2 and t[0] == "challenge":
            print(t[1], end=""); break
except Exception:
    pass
PYEOF
)
        if [ "$STORED" != "$CHALLENGE_IN" ]; then
            echo '{"ok":false,"error":"challenge invalide"}'
            exit 0
        fi

        # Vérifier la signature Schnorr via nostr_node_intercom.py (Astroport.ONE)
        if [ -f "$_INTERCOM" ] && [ -x "$_PYTHON" ]; then
            printf '%s' "$EVENT_JSON" | sudo -u "${SOUNDSPOT_USER:-pi}" \
                "$_PYTHON" "$_INTERCOM" verify >/dev/null 2>&1 || {
                echo '{"ok":false,"error":"signature invalide"}'; exit 0
            }
        else
            echo '{"ok":false,"error":"picoport non disponible — Astroport.ONE requis"}'
            exit 0
        fi

        # Vérifier que le pubkey de l'événement correspond au npub fourni
        EPUBKEY=$(printf '%s' "$EVENT_JSON" | python3 -c \
            "import json,sys; print(json.loads(sys.stdin.read()).get('pubkey',''), end='')" 2>/dev/null)
        if [ "${EPUBKEY,,}" != "$PUBKEY_HEX" ]; then
            echo '{"ok":false,"error":"pubkey mismatch"}'; exit 0
        fi

        # Session unique : supprimer tout marker existant avant de créer le nouveau
        find "$MARKER_DIR" -maxdepth 1 -name '.nip42_auth_*' -delete 2>/dev/null || true

        # Créer le marker de session
        NOW=$(date +%s)
        printf '{"pubkey":"%s","npub":"%s","ts":%d}\n' \
            "$PUBKEY_HEX" "${NPUB:-$PUBKEY_HEX}" "$NOW" > "$AUTH_MARKER"
        chmod 600 "$AUTH_MARKER" 2>/dev/null || true
        rm -f "$CHALLENGE_FILE"

        printf '{"ok":true,"pubkey":"%s","expires_in":%d}\n' "$PUBKEY_HEX" "$AUTH_TTL"
        ;;

    status)
        if [ ! -f "$AUTH_MARKER" ]; then
            echo '{"ok":false,"authenticated":false}'
            exit 0
        fi
        NOW=$(date +%s)
        TS=$(python3 -c "import json; d=json.load(open('$AUTH_MARKER')); print(d.get('ts',0))" 2>/dev/null || echo 0)
        AGE=$(( NOW - TS ))
        if [ "$AGE" -gt "$AUTH_TTL" ]; then
            rm -f "$AUTH_MARKER"
            echo '{"ok":false,"authenticated":false,"reason":"session expirée"}'
        else
            REMAINING=$(( AUTH_TTL - AGE ))
            printf '{"ok":true,"authenticated":true,"pubkey":"%s","remaining":%d}\n' \
                "$PUBKEY_HEX" "$REMAINING"
        fi
        ;;

    logout)
        rm -f "$AUTH_MARKER" "$CHALLENGE_FILE"
        echo '{"ok":true}'
        ;;

    *)
        echo '{"ok":false,"error":"cmd inconnu — utiliser: challenge, verify, status, logout"}'
        ;;
esac
