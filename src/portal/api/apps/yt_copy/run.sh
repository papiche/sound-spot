#!/bin/bash
# api/apps/yt_copy/run.sh — Copie YouTube → MP3 → IPFS → Queue Jukebox
#
# POST body : url=https://www.youtube.com/watch?v=XXXXXX
# Retourne  : {"status":"ok","cid":"QmXXX","title":"...","gateway":"http://IP:8080/ipfs/CID/nom_du_morceau.mp3"}
#
# Prérequis :
#   - yt-dlp    : sudo apt install yt-dlp
#   - jq        : sudo apt install jq
#   - IPFS      : Picoport actif, API HTTP sur 127.0.0.1:5001
# Hérite des exports de api.sh.

# ── Vérification des prérequis ────────────────────────────────
for _cmd in yt-dlp jq curl; do
    if ! command -v "$_cmd" &>/dev/null; then
        jq -n --arg cmd "$_cmd" '{"error":"missing_dependency","cmd":$cmd,"hint":"sudo apt install $cmd"}'
        exit 0
    fi
done

# IPFS API HTTP (port 5001) — contourne le problème des droits www-data vs pi
if ! curl -sX POST "http://127.0.0.1:5001/api/v0/version" >/dev/null 2>&1; then
    jq -n '{"error":"ipfs_not_available","hint":"Picoport requis (PICOPORT_ENABLED=true) et IPFS démarré"}'
    exit 0
fi

# ── Lire et décoder l'URL POST ────────────────────────────────
read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true

YT_URL=$(printf '%s' "$POST_DATA" \
    | grep -oP '(?<=url=)[^&]+' | head -1 \
    | python3 -c "import sys,urllib.parse; print(urllib.parse.unquote_plus(sys.stdin.read().strip()))" \
    2>/dev/null)

# ── Validation stricte et préparation de la requête ──────────
YT_DOMAIN_RE='^https?://(www\.)?(youtube\.com|youtu\.be|music\.youtube\.com)/'
if [[ "$YT_URL" =~ $YT_DOMAIN_RE ]]; then
    # URL YouTube valide — on conserve telle quelle (yt-dlp reçoit après --)
    TARGET="$YT_URL"
elif [[ "$YT_URL" =~ ^https?:// ]]; then
    # Domaine non-YouTube → refus (prévient l'SSRF via yt-dlp)
    jq -n --arg url "$YT_URL" \
        '{"error":"domain_not_allowed","hint":"Seuls youtube.com et youtu.be sont acceptés","url":$url}'
    exit 0
elif [ -n "$YT_URL" ]; then
    # Recherche textuelle — suppression des caractères dangereux (|;<>&`$)
    SEARCH=$(printf '%s' "$YT_URL" | tr -d '|;<>&`$\\' | cut -c1-100)
    [ -z "$SEARCH" ] && { jq -n '{"error":"empty_search"}'; exit 0; }
    TARGET="ytsearch1:${SEARCH}"
else
    jq -n '{"error":"missing_url","hint":"POST body: url=<youtube_url_ou_texte>"}'
    exit 0
fi

# ── Téléchargement ────────────────────────────────────────────
TMPDIR=$(mktemp -d /tmp/soundspot_yt_XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

TITLE=$(yt-dlp --print title --no-warnings --no-playlist -- "$TARGET" 2>/dev/null | head -1)
TITLE="${TITLE:-unknown}"

# Téléchargement du fichier audio
yt-dlp \
    --no-warnings \
    --embed-thumbnail --add-metadata \
    --no-playlist \
    --extract-audio \
    --audio-format mp3 \
    --audio-quality 5 \
    -o "${TMPDIR}/audio.%(ext)s" \
    -- "$TARGET" \
    >/dev/null 2>&1

# ── Amélioration du nom de fichier pour IPFS ──────────────────
AUDIO_FILE=$(find "$TMPDIR" -name "*.mp3" | head -1)
if [ -z "$AUDIO_FILE" ]; then
    jq -n --arg url "$TARGET" '{"error":"download_failed","url":$url}'
    exit 0
fi

# Nettoyage du titre pour le nom de fichier
SAFE_TITLE=$(printf "%s" "$TITLE" | sed -e "s/[^a-zA-Z0-9._-]/_/g" | tr -s "_" | cut -c1-100)
[ -z "$SAFE_TITLE" ] && SAFE_TITLE="jukebox_track"

# Renommage du fichier
mv "$AUDIO_FILE" "${TMPDIR}/${SAFE_TITLE}.mp3"
AUDIO_FILE="${TMPDIR}/${SAFE_TITLE}.mp3"

# ── Ajout IPFS via API HTTP (en tant que dossier) ─────────────
IPFS_DIR=$(mktemp -d "${TMPDIR}/ipfs_XXXXXX")
mv "$AUDIO_FILE" "$IPFS_DIR/"

# using API
# IPFS_RESP=$(curl -sf \
#     -X POST \
#     -F "file=@${IPFS_DIR}" \
#     "http://127.0.0.1:5001/api/v0/add?pin=true&wrap-with-directory=true" \
#     2>/dev/null)
# CID=$(printf '%s' "$IPFS_RESP" | jq -r '.Hash // empty')

# using command
IPFS_RESP=$(ipfs add -Q -r -w "$IPFS_DIR" 2>/dev/null)
CID=$(echo "$IPFS_RESP" | tail -n 1)

if [ -z "$CID" ]; then
    jq -n '{"error":"ipfs_add_failed","hint":"Vérifier que IPFS daemon est actif"}'
    exit 0
fi

# ── Ajouter à la queue Jukebox ────────────────────────────────
# ── Déduction de l'IPFSNODEID via API (car www-data ne peut pas lire ~/.ipfs) ──
SOUNDSPOT_USER=$(grep "^SOUNDSPOT_USER=" /opt/soundspot/soundspot.conf 2>/dev/null | cut -d= -f2 | tr -d "\"" || echo "pi")
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
IPFSNODEID=$(curl -sX POST http://127.0.0.1:5001/api/v0/id | jq -r ".ID // empty" 2>/dev/null || echo "unknown")
QUEUE_DIR="${USER_HOME}/.zen/tmp/${IPFSNODEID}/soundspot_queue"
mkdir -p "$QUEUE_DIR" 2>/dev/null || true
mkdir -p "$QUEUE_DIR"
JOB_ID=$(date +%s%N)
printf "http://127.0.0.1:8080/ipfs/%s/%s.mp3\n" "$CID" "$SAFE_TITLE" > "$QUEUE_DIR/${JOB_ID}.job"

# ── Réponse JSON (via jq) ──
GATEWAY="http://${SPOT_IP}:8080/ipfs/${CID}/${SAFE_TITLE}.mp3"
jq -n \
    --arg status  "ok" \
    --arg cid     "$CID" \
    --arg title   "$TITLE" \
    --arg gateway "$GATEWAY" \
    --arg source  "$TARGET" \
    --argjson queued true \
    '{status:$status, cid:$cid, title:$title, gateway:$gateway, source:$source, queued:$queued}'