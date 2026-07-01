#!/bin/bash
# api/core/projector.sh — Contrôle du Relais Projecteur (Branché sur GPIO 18 par ex)
# Action physique sur le matériel → authentification NIP-42 requise, comme admin/*.
_SS_SERVICE="portal-projector"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

PROJECTOR_PIN="${PROJECTOR_PIN:-18}" # PIN GPIO sur lequel le relais est branché

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
    MODE=$(printf '%s' "$POST_DATA" | grep -oP '(?<=mode=)[^&]+' | head -1)
    NPUB_POST=$(printf '%s' "$POST_DATA" | grep -oP '(?<=npub=)[^&]+' | head -1)
else
    MODE=$(echo "$QUERY_STRING" | grep -oP '(?<=mode=)[^&]+' | head -1)
fi
NPUB="${NPUB_POST:-$NPUB_GET}"

# ── Vérification NIP-42 ──────────────────────────────────────
AUTH_PUBKEY=""
if [[ "${NPUB:-}" == npub1* ]]; then
    AUTH_PUBKEY=$(_npub_to_hex "$NPUB")
elif [[ "${NPUB:-}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    AUTH_PUBKEY="${NPUB,,}"
fi

if [ -z "$AUTH_PUBKEY" ] || [ ! -f "/dev/shm/.nip42_auth_${AUTH_PUBKEY}" ]; then
    ss_warn "projector: NIP-42 requis ip=${REMOTE_ADDR:-?}"
    jq -n '{"error":"unauthorized","hint":"Authentification NIP-42 MULTIPASS requise"}'
    exit 0
fi

NOW=$(date +%s)
TS=$(python3 -c "import json; d=json.load(open('/dev/shm/.nip42_auth_${AUTH_PUBKEY}')); print(d.get('ts',0))" 2>/dev/null || echo 0)
AGE=$(( NOW - TS ))
if [ "$AGE" -gt 3600 ]; then
    rm -f "/dev/shm/.nip42_auth_${AUTH_PUBKEY}"
    jq -n '{"error":"session_expired","hint":"Reconnectez-vous avec votre identité NOSTR"}'
    exit 0
fi
ss_info "projector: cmd=${MODE:-status} pubkey=${AUTH_PUBKEY:0:12}… ip=${REMOTE_ADDR:-?}"

# Initialisation du GPIO (Sysfs)
if [ ! -d /sys/class/gpio/gpio${PROJECTOR_PIN} ]; then
    echo "${PROJECTOR_PIN}" > /sys/class/gpio/export 2>/dev/null || true
    echo "out" > /sys/class/gpio/gpio${PROJECTOR_PIN}/direction 2>/dev/null || true
fi

if [ "$MODE" = "on" ]; then
    echo "1" > /sys/class/gpio/gpio${PROJECTOR_PIN}/value
    ss_info "Projecteur Nebula allumé (GPIO ${PROJECTOR_PIN} HIGH)"
    printf '{"status":"ok","projector":"on"}\n'
elif [ "$MODE" = "off" ]; then
    echo "0" > /sys/class/gpio/gpio${PROJECTOR_PIN}/value
    ss_info "Projecteur Nebula éteint (GPIO ${PROJECTOR_PIN} LOW)"
    printf '{"status":"ok","projector":"off"}\n'
else
    VAL=$(cat /sys/class/gpio/gpio${PROJECTOR_PIN}/value 2>/dev/null || echo "0")
    if [ "$VAL" = "1" ]; then
        printf '{"status":"ok","projector":"on"}\n'
    else
        printf '{"status":"ok","projector":"off"}\n'
    fi
fi
