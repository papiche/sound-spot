#!/bin/bash
# api/apps/yt_copy/run.sh — Copie YouTube → MP3 → IPFS → Queue Jukebox
#
# POST body : url=https://www.youtube.com/watch?v=XXXXXX
# Retourne  : {"status":"ok","cid":"QmXXX","title":"...","gateway":"http://IP:8080/ipfs/CID"}
#
# Prérequis :
#   - yt-dlp    : sudo apt install yt-dlp
#   - jq        : sudo apt install jq
#   - IPFS      : Picoport actif, API HTTP sur 127.0.0.1:5001
# Hérite des exports de api.sh.

# ── Vérification des prérequis ────────────────────────────────
for _cmd in yt-dlp jq curl; do
    if ! command -v "$_cmd" &>/dev/null; then
        jq -n --arg cmd "$_cmd" '{"error":"missing_dependency","cmd":$cmd,"hint":"sudo apt install \($cmd)"}'
        exit 0
    fi
done

# IPFS API HTTP (port 5001) — contourne le problème des droits www-data vs pi
if ! curl -sf --max-time 1 "http://127.0.0.1:5001/api/v0/version" >/dev/null 2>&1; then
    jq -n '{"error":"ipfs_not_available","hint":"Picoport requis (PICOPORT_ENABLED=true) et IPFS démarré"}'
    exit 0
fi

# ── Lire et décoder l'URL POST ────────────────────────────────
read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true

YT_URL=$(printf '%s' "$POST_DATA" \
    | grep -oP '(?<=url=)[^&]+' | head -1 \
    | python3 -c "import sys,urllib.parse; print(urllib.parse.unquote_plus(sys.stdin.read().strip()))" \
    2>/dev/null)

# ── Validation de l'URL ───────────────────────────────────────
if ! printf '%s' "$YT_URL" | grep -qE '^https://(www\.)?(youtube\.com/watch|youtu\.be)/'; then
    jq -n --arg url "${YT_URL:-}" '{"error":"invalid_url","url":$url,"hint":"https://www.youtube.com/watch?v=... requis"}'
    exit 0
fi

# ── Téléchargement ────────────────────────────────────────────
TMPDIR=$(mktemp -d /tmp/soundspot_yt_XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

TITLE=$(yt-dlp --print title --no-warnings --no-playlist "$YT_URL" 2>/dev/null | head -1)
TITLE="${TITLE:-unknown}"

yt-dlp \
    --no-warnings \
    --no-playlist \
    --extract-audio \
    --audio-format mp3 \
    --audio-quality 5 \
    -o "${TMPDIR}/audio.%(ext)s" \
    "$YT_URL" \
    >/dev/null 2>&1

AUDIO_FILE=$(find "$TMPDIR" -name "*.mp3" | head -1)
if [ -z "$AUDIO_FILE" ]; then
    jq -n --arg url "$YT_URL" '{"error":"download_failed","url":$url}'
    exit 0
fi

# ── Ajout IPFS via API HTTP (fonctionne avec www-data) ────────
IPFS_RESP=$(curl -sf \
    -X POST \
    -F "file=@${AUDIO_FILE}" \
    "http://127.0.0.1:5001/api/v0/add?pin=true" \
    2>/dev/null)

CID=$(printf '%s' "$IPFS_RESP" | jq -r '.Hash // empty')

if [ -z "$CID" ]; then
    jq -n '{"error":"ipfs_add_failed","hint":"Vérifier que IPFS daemon est actif"}'
    exit 0
fi

# ── Ajouter à la queue Jukebox ────────────────────────────────
QUEUE_FILE="/tmp/soundspot_jukebox.queue"
printf 'http://127.0.0.1:8080/ipfs/%s\n' "$CID" >> "$QUEUE_FILE"

# ── Réponse JSON (via jq — 100% sûr contre les caractères spéciaux) ──
GATEWAY="http://${SPOT_IP}:8080/ipfs/${CID}"
jq -n \
    --arg status  "ok" \
    --arg cid     "$CID" \
    --arg title   "$TITLE" \
    --arg gateway "$GATEWAY" \
    --arg source  "$YT_URL" \
    --argjson queued true \
    '{status:$status, cid:$cid, title:$title, gateway:$gateway, source:$source, queued:$queued}'
