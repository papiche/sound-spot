#!/bin/bash
# tts.sh — Synthèse vocale unifiée SoundSpot
#
# Quand Picoport est actif (IPFS + constellation UPlanet) :
#   → Orpheus TTS (voix pierre/amelie) via localhost:5005
#     (connexion locale ou tunnel P2P swarm via orpheus.me.sh)
# Sinon :
#   → espeak-ng (synthèse robot locale, sans réseau)
#
# La qualité de la voix est l'indicateur auditif que le nœud
# est bien relié à sa constellation UPlanet.
#
# Usage :
#   tts.sh TEXT [VOICE] [OUTFILE]
#   TEXT    : texte à synthétiser (obligatoire)
#   VOICE   : pierre | amelie  (défaut: ORPHEUS_VOICE de soundspot.conf ou "pierre")
#   OUTFILE : chemin WAV de sortie (défaut: /dev/shm/tts_<nano>.wav)
#
# Retourne le chemin du WAV généré sur stdout. Exit 0 si succès.
# Le fichier reste après succès — le caller est responsable du nettoyage.
# En cas d'échec, le fichier temporaire est supprimé automatiquement.

[ -f /opt/soundspot/soundspot.conf ] && source /opt/soundspot/soundspot.conf

TEXT="${1:-}"
VOICE="${2:-${ORPHEUS_VOICE:-pierre}}"
OUTFILE="${3:-/dev/shm/tts_$(date +%s%N).wav}"
ORPHEUS_PORT="${ORPHEUS_PORT:-5005}"
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
CACHE_DIR="/opt/soundspot/cache_tts"

if [ -z "$TEXT" ]; then
    echo "tts.sh: TEXT vide" >&2
    exit 1
fi

# ── Nettoyage automatique sur échec (désactivé sur succès via trap -) ─
trap 'rm -f "$OUTFILE" "${OUTFILE}.norm.wav"' EXIT

# ── Cache MD5 : évite de régénérer les phrases répétitives ───────────
mkdir -p "$CACHE_DIR" 2>/dev/null || true

_cache_key() {
    printf '%s' "${TEXT}${VOICE}" | md5sum | cut -d' ' -f1
}

_cache_check() {
    local key cached
    key=$(_cache_key)
    cached="${CACHE_DIR}/${key}_${VOICE}.wav"
    if [ -f "$cached" ] && [ -s "$cached" ]; then
        cp "$cached" "$OUTFILE"
        echo "$OUTFILE"
        trap - EXIT
        exit 0
    fi
}

_cache_store() {
    local key cached
    key=$(_cache_key)
    cached="${CACHE_DIR}/${key}_${VOICE}.wav"
    cp "$OUTFILE" "$cached" 2>/dev/null || true
    # Limiter le cache à 60 fichiers (LRU par date d'accès)
    local count
    count=$(find "$CACHE_DIR" -name "*.wav" 2>/dev/null | wc -l)
    if [ "$count" -gt 60 ]; then
        find "$CACHE_DIR" -name "*.wav" -printf '%A@ %p\n' 2>/dev/null \
            | sort -n | head -n $((count - 60)) \
            | cut -d' ' -f2- | xargs rm -f 2>/dev/null || true
    fi
}

# ── Localiser orpheus.me.sh via le home de SOUNDSPOT_USER ───────────
_user_home=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6 2>/dev/null || echo "/home/$SOUNDSPOT_USER")
ORPHEUS_SH="${_user_home}/.zen/Astroport.ONE/IA/orpheus.me.sh"

# ── Helpers ──────────────────────────────────────────────────────────
_picoport_active() {
    systemctl is-active --quiet picoport.service 2>/dev/null
}

_orpheus_alive() {
    curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
        "http://localhost:${ORPHEUS_PORT}/docs" 2>/dev/null | grep -q "200"
}

_orpheus_connect() {
    [ -x "$ORPHEUS_SH" ] || return 1
    sudo -u "$SOUNDSPOT_USER" bash "$ORPHEUS_SH" >/dev/null 2>&1
}

_json_string() {
    python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" <<< "$1"
}

_generate_orpheus() {
    local json_text
    json_text=$(_json_string "$TEXT")
    curl -sf --max-time 15 \
        -o "$OUTFILE" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"orpheus\",\"input\":${json_text},\"voice\":\"${VOICE}\",\"response_format\":\"wav\",\"speed\":1.0}" \
        "http://localhost:${ORPHEUS_PORT}/v1/audio/speech" 2>/dev/null

    if [ -s "$OUTFILE" ]; then
        # Nettoyage basses fréquences + normalisation volume voix
        ffmpeg -i "$OUTFILE" -af "highpass=f=80, speechnorm=e=12:p=0.9" \
            -y "${OUTFILE}.norm.wav" >/dev/null 2>&1
        [ -f "${OUTFILE}.norm.wav" ] && mv "${OUTFILE}.norm.wav" "$OUTFILE"
    fi
}

_generate_espeak() {
    espeak-ng -v fr+f3 -a 80 -s 115 -p 40 "$TEXT" -w "$OUTFILE" 2>/dev/null
}

# ── Annonce de première connexion constellation ──────────────────────
_constellation_announce() {
    local flag="/dev/shm/orpheus_announced"
    [ -f "$flag" ] && return 0
    touch "$flag"
    local spot="${SPOT_NAME:-SoundSpot}"
    local intro_text="Je suis ${VOICE^}, la voix de ${spot}. Ce nœud est connecté à la constellation UPlanet. Bienvenue."
    local intro_out="/dev/shm/tts_intro_$(date +%s%N).wav"
    if _generate_orpheus_for "$intro_text" "$VOICE" "$intro_out"; then
        echo "$intro_out"
    fi
}

_generate_orpheus_for() {
    local txt="$1" voice="$2" out="$3"
    local json_text
    json_text=$(_json_string "$txt")
    curl -sf --max-time 15 \
        -o "$out" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"orpheus\",\"input\":${json_text},\"voice\":\"${voice}\",\"response_format\":\"wav\",\"speed\":1.0}" \
        "http://localhost:${ORPHEUS_PORT}/v1/audio/speech" 2>/dev/null
    [ -s "$out" ]
}

# ── Logique principale ───────────────────────────────────────────────
if _picoport_active; then
    # Vérifier le cache avant tout appel réseau
    _cache_check

    if ! _orpheus_alive; then
        _orpheus_connect
        sleep 2
    fi

    if _orpheus_alive; then
        intro=$(_constellation_announce)
        [ -n "$intro" ] && echo "$intro"

        if _generate_orpheus && [ -s "$OUTFILE" ]; then
            _cache_store
            trap - EXIT
            echo "$OUTFILE"
            exit 0
        fi
        echo "tts.sh: Orpheus KO → fallback espeak" >&2
    fi
fi

# Fallback espeak-ng (aussi vérifié dans le cache)
_cache_check

if _generate_espeak && [ -s "$OUTFILE" ]; then
    _cache_store
    trap - EXIT
    echo "$OUTFILE"
    exit 0
fi

echo "tts.sh: échec total de la synthèse vocale" >&2
exit 1
