#!/bin/bash
# api/core/speak.sh — Synthèse vocale avec file d'attente (RAM uniquement)
# Accepte uniquement les requêtes POST depuis l'IP du maître (SPOT_IP).
#
# Usage CGI :
#   POST /api.sh?action=speak   body: text=Bonjour+les+visiteurs[&voice=pierre]
#
# Sécurité : seul le maître (SPOT_IP) peut déclencher la parole.
# Voix : si Picoport actif → Orpheus (pierre/amelie), sinon espeak-ng.

SPEAK_QUEUE="/dev/shm/soundspot_speak_queue"
SPEAK_LOCK="/dev/shm/soundspot_speak.lock"
MAX_TEXT_LEN=200
TTS_SH="${INSTALL_DIR:-/opt/soundspot}/backend/audio/tts.sh"

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

_url_decode() {
    printf '%s' "$1" | python3 -c \
        "import sys,urllib.parse; print(urllib.parse.unquote_plus(sys.stdin.read().strip()))" \
        2>/dev/null || printf '%s' "$1"
}

RAW_TEXT=$(echo "$BODY" | grep -oP '(?<=text=)[^&]+' | head -1)
RAW_VOICE=$(echo "$BODY" | grep -oP '(?<=voice=)[^&]+' | head -1)

TEXT=$(_url_decode "$RAW_TEXT")
TEXT="${TEXT:0:${MAX_TEXT_LEN}}"
VOICE="${RAW_VOICE:-${ORPHEUS_VOICE:-pierre}}"

if [ -z "$TEXT" ]; then
    echo '{"error":"empty_text"}'
    exit 0
fi

# ── Enqueue : txt + voix demandée ────────────────────────────────
mkdir -p "$SPEAK_QUEUE"
SLOT=$(date +%s%N)
# Format du job : VOICE|TEXT
printf '%s|%s' "$VOICE" "$TEXT" > "${SPEAK_QUEUE}/${SLOT}.job"

# ── Worker non-bloquant via tts.sh ───────────────────────────────
if [ ! -f "$SPEAK_LOCK" ]; then
    (
        flock -n 9 || exit 0
        while IFS= read -r job_file; do
            [ -f "$job_file" ] || continue
            job_content=$(cat "$job_file")
            rm -f "$job_file"
            job_voice="${job_content%%|*}"
            job_text="${job_content#*|}"
            [ -z "$job_text" ] && continue

            # tts.sh retourne 1 ou 2 chemins WAV (intro constellation + message)
            wav_paths=$(bash "$TTS_SH" "$job_text" "$job_voice" 2>/dev/null)
            while IFS= read -r wav; do
                [ -f "$wav" ] || continue
                pw-play "$wav" 2>/dev/null || aplay -q "$wav" 2>/dev/null || true
                rm -f "$wav"
            done <<< "$wav_paths"
        done < <(find "$SPEAK_QUEUE" -maxdepth 1 -name "*.job" -type f | sort)
    ) 9>"$SPEAK_LOCK"
    rm -f "$SPEAK_LOCK"
fi &

ENGINE="espeak"
systemctl is-active --quiet picoport.service 2>/dev/null && ENGINE="orpheus"
printf '{"status":"ok","queued":true,"voice":"%s","engine":"%s"}\n' "$VOICE" "$ENGINE"
