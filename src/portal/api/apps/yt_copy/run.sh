#!/bin/bash
# api/apps/yt_copy/run.sh — YouTube → MP3 → IPFS (upload2ipfs.sh) → NOSTR NIP-A0
#
# POST body : url=https://www.youtube.com/watch?v=XXXXXX
# Retourne  : {"status":"ok","cid":"QmXXX","title":"...","gateway":"...","nostr_kind":1222,...}
#
# Pipeline UPlanet complet (si disponible) :
#   1. yt-dlp          → MP3 local
#   2. upload2ipfs.sh  → IPFS + info.json v2.1.0 + thumbnail + provenance
#   3. nostr_send_note.py (kind 1222/1244 NIP-A0) → relay NOSTR
#   Fallback : ipfs add brut + kind 1 nak si pipeline indisponible
#
# Prérequis :
#   - yt-dlp, jq, curl, ipfs (Picoport)
#   - upload2ipfs.sh  : ~/.zen/UPassport/upload2ipfs.sh  (optionnel, améliore la qualité)
#   - nostr_send_note.py : Astroport.ONE tools             (optionnel)
# Hérite des exports de api.sh.

_SS_SERVICE="portal-ytcopy"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

# ── Prérequis obligatoires ────────────────────────────────────
for _cmd in yt-dlp jq curl; do
    if ! command -v "$_cmd" &>/dev/null; then
        jq -n --arg cmd "$_cmd" '{"error":"missing_dependency","cmd":$cmd}'
        exit 0
    fi
done

if ! curl -sX POST "http://127.0.0.1:5001/api/v0/version" >/dev/null 2>&1; then
    jq -n '{"error":"ipfs_not_available","hint":"Picoport requis (PICOPORT_ENABLED=true)"}'
    exit 0
fi

# ── Résolution des chemins UPlanet ───────────────────────────
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
NOSTR_KEY="${USER_HOME}/.zen/game/secret.nostr"
ASTRO_TOOLS="${USER_HOME}/.zen/Astroport.ONE/tools"
PYTHON="${USER_HOME}/.astro/bin/python3"
NOSTR_SCRIPT="${ASTRO_TOOLS}/nostr_send_note.py"

# Lire les chemins publiés par picoport.sh (via /dev/shm)
UPLOAD_SCRIPT=$(cat /dev/shm/soundspot_env/upload2ipfs_path 2>/dev/null || echo "")
[ -z "$UPLOAD_SCRIPT" ] && UPLOAD_SCRIPT="${USER_HOME}/.zen/UPassport/upload2ipfs.sh"
[ -f "$UPLOAD_SCRIPT" ] || UPLOAD_SCRIPT=""

NOSTR_RELAYS="ws://127.0.0.1:9999,wss://relay.copylaradio.com"

# ── Lecture et validation de l'URL POST ──────────────────────
read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true

YT_URL=$(printf '%s' "$POST_DATA" | grep -oP '(?<=url=)[^&]+' | head -1 | urldecode)

YT_DOMAIN_RE='^https?://(www\.)?(youtube\.com|youtu\.be|music\.youtube\.com)/'
if [[ "$YT_URL" =~ $YT_DOMAIN_RE ]]; then
    TARGET="$YT_URL"
elif [[ "$YT_URL" =~ ^https?:// ]]; then
    jq -n --arg url "$YT_URL" \
        '{"error":"domain_not_allowed","hint":"Seuls youtube.com et youtu.be sont acceptés","url":$url}'
    exit 0
elif [ -n "$YT_URL" ]; then
    SEARCH=$(printf '%s' "$YT_URL" | tr -d '|;<>&`$\\' | cut -c1-100)
    [ -z "$SEARCH" ] && { jq -n '{"error":"empty_search"}'; exit 0; }
    TARGET="ytsearch1:${SEARCH}"
else
    jq -n '{"error":"missing_url","hint":"POST body: url=<youtube_url_ou_texte>"}'
    exit 0
fi

# ── Téléchargement ────────────────────────────────────────────
TMPDIR=$(mktemp -d /tmp/soundspot_yt_XXXXXX)
UPLOAD_JSON=$(mktemp /tmp/ss_upload_XXXXXX.json)
trap 'rm -rf "$TMPDIR" "$UPLOAD_JSON"' EXIT

TITLE=$(yt-dlp --print title --no-warnings --no-playlist -- "$TARGET" 2>/dev/null | head -1)
TITLE="${TITLE:-unknown}"

yt-dlp --max-filesize 50M --match-filter "duration < 600" \
    --no-warnings \
    --embed-thumbnail --add-metadata \
    --no-playlist \
    --extract-audio \
    --audio-format mp3 \
    --audio-quality 5 \
    -o "${TMPDIR}/audio.%(ext)s" \
    -- "$TARGET" \
    >/dev/null 2>&1

AUDIO_FILE=$(find "$TMPDIR" -name "*.mp3" | head -1)
if [ -z "$AUDIO_FILE" ]; then
    jq -n --arg url "$TARGET" '{"error":"download_failed","url":$url}'
    exit 0
fi

SAFE_TITLE=$(printf "%s" "$TITLE" | sed -e "s/[^a-zA-Z0-9._-]/_/g" | tr -s "_" | cut -c1-100)
[ -z "$SAFE_TITLE" ] && SAFE_TITLE="jukebox_track"
mv "$AUDIO_FILE" "${TMPDIR}/${SAFE_TITLE}.mp3"
AUDIO_FILE="${TMPDIR}/${SAFE_TITLE}.mp3"

# ── Phase 1 : Upload IPFS ─────────────────────────────────────
# Priorité : upload2ipfs.sh (info.json + NIP-94 + provenance) → ipfs add brut
CID="" INFO_CID="" THUMBNAIL_CID="" FILE_HASH=""
MIME_TYPE="audio/mpeg" DURATION=0
UPLOAD_METHOD="raw"

if [ -n "$UPLOAD_SCRIPT" ]; then
    NPUB_HEX=$(grep -oP '(?<=HEX=)[^;[:space:]]+' "$NOSTR_KEY" 2>/dev/null || echo "")
    sudo -u "$SOUNDSPOT_USER" bash "$UPLOAD_SCRIPT" \
        "$AUDIO_FILE" "$UPLOAD_JSON" "${NPUB_HEX}" >/dev/null 2>&1

    if jq -e '.status == "success"' "$UPLOAD_JSON" >/dev/null 2>&1; then
        CID=$(jq -r '.cid'                        "$UPLOAD_JSON")
        INFO_CID=$(jq -r '.info         // empty' "$UPLOAD_JSON")
        THUMBNAIL_CID=$(jq -r '.thumbnail_ipfs // empty' "$UPLOAD_JSON")
        FILE_HASH=$(jq -r '.fileHash    // empty' "$UPLOAD_JSON")
        MIME_TYPE=$(jq -r '.mimeType    // "audio/mpeg"' "$UPLOAD_JSON")
        DURATION=$(jq -r '.duration     // 0'     "$UPLOAD_JSON")
        UPLOAD_METHOD="upload2ipfs"
        ss_info "upload2ipfs.sh OK — CID=${CID:0:16}..."
    else
        ss_warn "upload2ipfs.sh indisponible ou erreur — fallback ipfs add"
    fi
fi

# Fallback : ipfs add brut
if [ -z "$CID" ]; then
    IPFS_DIR=$(mktemp -d "${TMPDIR}/ipfs_XXXXXX")
    cp "$AUDIO_FILE" "$IPFS_DIR/"
    CID=$(ipfs add -Q -r -w "$IPFS_DIR" 2>/dev/null | tail -n 1)
fi

if [ -z "$CID" ]; then
    jq -n '{"error":"ipfs_add_failed","hint":"Vérifier que IPFS daemon est actif"}'
    exit 0
fi

GATEWAY="http://${SPOT_IP}:8080/ipfs/${CID}/${SAFE_TITLE}.mp3"

# ── Phase 2 : Publication NOSTR NIP-A0 ───────────────────────
# kind 1222 : audio court (< 5 min)  /  kind 1244 : audio long
# Utilise nostr_send_note.py (Astroport.ONE) si disponible, sinon nak, sinon queue locale.
EVENT_ID="" NOSTR_PUBLISHED=false
AUDIO_KIND=1222
[ "${DURATION:-0}" -gt 300 ] && AUDIO_KIND=1244

if [ -f "$NOSTR_SCRIPT" ] && [ -x "$PYTHON" ] && [ -f "$NOSTR_KEY" ]; then
    # Construire les tags NIP-A0 + NIP-94
    AUDIO_TAGS=$(jq -cn \
        --arg url  "/ipfs/${CID}/${SAFE_TITLE}.mp3" \
        --arg mime "$MIME_TYPE" \
        --arg hash "${FILE_HASH:-}" \
        --arg title "$TITLE" \
        --arg info  "${INFO_CID:-}" \
        --arg thumb "${THUMBNAIL_CID:-}" \
        '[
            ["url",   $url],
            ["m",     $mime],
            ["title", $title],
            (if $hash  != "" then ["x",    $hash]  else empty end),
            (if $info  != "" then ["info", $info]  else empty end),
            (if $thumb != "" then ["image","/ipfs/"+$thumb] else empty end)
        ]')

    PUB_RESULT=$(sudo -u "$SOUNDSPOT_USER" "$PYTHON" "$NOSTR_SCRIPT" \
        --keyfile "$NOSTR_KEY" \
        --content "🎵 ${TITLE}" \
        --kind    "$AUDIO_KIND" \
        --tags    "$AUDIO_TAGS" \
        --relays  "$NOSTR_RELAYS" \
        --json 2>/dev/null)

    EVENT_ID=$(printf '%s' "$PUB_RESULT" | jq -r '.event_id // empty' 2>/dev/null)
    [ -n "$EVENT_ID" ] && NOSTR_PUBLISHED=true && \
        ss_info "NOSTR kind ${AUDIO_KIND} publié — event=${EVENT_ID:0:16}..."
fi

# Fallback nak
if [ "$NOSTR_PUBLISHED" = "false" ] && command -v nak >/dev/null 2>&1 && [ -f "$NOSTR_KEY" ]; then
    _NSEC=$(grep -oP '(?<=NSEC=)[^;[:space:]]+' "$NOSTR_KEY" | head -1)
    if [ -n "$_NSEC" ]; then
        for _relay in "ws://127.0.0.1:9999" "wss://relay.copylaradio.com"; do
            if timeout 6 nak event --sec "$_NSEC" \
               -k "$AUDIO_KIND" -c "🎵 ${TITLE}
/ipfs/${CID}/${SAFE_TITLE}.mp3" \
               "$_relay" >/dev/null 2>&1; then
                NOSTR_PUBLISHED=true
                break
            fi
        done
    fi
fi

# File d'attente locale si NOSTR indisponible
if [ "$NOSTR_PUBLISHED" = "false" ]; then
    QUEUE_DIR="/dev/shm/soundspot_queue"
    mkdir -p "$QUEUE_DIR"
    printf '%s\n' "http://127.0.0.1:8080/ipfs/${CID}/${SAFE_TITLE}.mp3" \
        > "${QUEUE_DIR}/$(date +%s%N).job"
    ss_warn "NOSTR indisponible — audio ajouté à la queue jukebox"
fi

# ── Réponse JSON ──────────────────────────────────────────────
jq -n \
    --arg  status          "ok" \
    --arg  cid             "$CID" \
    --arg  info_cid        "${INFO_CID:-}" \
    --arg  thumbnail_cid   "${THUMBNAIL_CID:-}" \
    --arg  title           "$TITLE" \
    --arg  gateway         "$GATEWAY" \
    --arg  source          "$TARGET" \
    --arg  upload_method   "$UPLOAD_METHOD" \
    --arg  event_id        "${EVENT_ID:-}" \
    --argjson nostr_kind   "$AUDIO_KIND" \
    --argjson nostr_published "$NOSTR_PUBLISHED" \
    '{
        status:           $status,
        cid:              $cid,
        info_cid:         $info_cid,
        thumbnail_cid:    $thumbnail_cid,
        title:            $title,
        gateway:          $gateway,
        source:           $source,
        upload_method:    $upload_method,
        nostr_event_id:   $event_id,
        nostr_kind:       $nostr_kind,
        nostr_published:  $nostr_published
    }'
