#!/bin/bash
# api/core/speak.sh — Synthèse vocale avec file d'attente (RAM uniquement)
# Accepte uniquement les requêtes POST depuis l'IP du maître (SPOT_IP).
#
# Usage CGI :
#   POST /api.sh?action=speak   body: text=Bonjour+les+visiteurs
#
# Sécurité : seul le maître (SPOT_IP) peut déclencher la parole,
# pour éviter qu'un visiteur WiFi n'injecte du texte arbitraire.

SPEAK_QUEUE="/dev/shm/soundspot_speak_queue"
SPEAK_LOCK="/dev/shm/soundspot_speak.lock"
MAX_TEXT_LEN=200

# ── Vérification IP source ────────────────────────────────────────
REMOTE_ADDR="${REMOTE_ADDR:-}"
if [ -z "$REMOTE_ADDR" ]; then
    echo '{"error":"no_remote_addr"}'
    exit 0
fi
if [ "$REMOTE_ADDR" != "$SPOT_IP" ] && [ "$REMOTE_ADDR" != "127.0.0.1" ]; then
    echo '{"error":"forbidden","hint":"speak only accepted from master"}'
    exit 0
fi

# ── Lecture du corps POST ─────────────────────────────────────────
BODY=""
if [ "$REQUEST_METHOD" = "POST" ] && [ "${CONTENT_LENGTH:-0}" -gt 0 ]; then
    BODY=$(dd bs=1 count="${CONTENT_LENGTH}" 2>/dev/null | tr -d '\r')
fi

RAW_TEXT=$(echo "$BODY" | grep -oP '(?<=text=)[^&]+' | head -1)
# Décodage URL sécurisé via Python (évite l'injection de commandes via xargs printf)
TEXT=$(printf '%s' "$RAW_TEXT" | python3 -c \
    "import sys,urllib.parse; print(urllib.parse.unquote_plus(sys.stdin.read().strip()))" \
    2>/dev/null || printf '%s' "$RAW_TEXT")
TEXT="${TEXT:0:${MAX_TEXT_LEN}}"

if [ -z "$TEXT" ]; then
    echo '{"error":"empty_text"}'
    exit 0
fi

# ── Enqueue dans /dev/shm ─────────────────────────────────────────
mkdir -p "$SPEAK_QUEUE"
SLOT=$(date +%s%N)
echo "$TEXT" > "${SPEAK_QUEUE}/${SLOT}.txt"

# ── Déclenchement du worker (non-bloquant) ───────────────────────
# Le worker consomme la queue et évite les chevauchements via le lock.
if [ ! -f "$SPEAK_LOCK" ]; then
    (
        flock -n 9 || exit 0
        while IFS= read -r job; do
            [ -f "$job" ] || continue
            txt=$(cat "$job")
            rm -f "$job"
            espeak-ng -v fr -s 140 "$txt" \
                --stdout 2>/dev/null | \
                pw-play --target=bluez_output - 2>/dev/null || \
                espeak-ng -v fr -s 140 "$txt" 2>/dev/null || true
        done < <(find "$SPEAK_QUEUE" -maxdepth 1 -name "*.txt" -type f | sort)
    ) 9>"$SPEAK_LOCK"
    rm -f "$SPEAK_LOCK"
fi &

echo '{"status":"ok","queued":true}'
