#!/bin/bash
# idle_announcer.sh — Clocher numérique SoundSpot
#
# En l'absence de stream DJ actif sur Icecast :
#   • toutes les 15 min : bip 429.62 Hz + heure vocale + messages G1FabLab
#   • à l'heure pile    : N coups de cloche (1–12, comme une église)
#
# Messages personnalisables :
#   Textes sources  : /opt/soundspot/wav/message_NN.txt  (modifier librement)
#   Fichiers audio  : /opt/soundspot/wav/message_NN.wav  (remplacer par vos .wav)
#   Si .wav absent  → régénéré automatiquement depuis le .txt (espeak-ng)
#
# Variables d'environnement (depuis soundspot.conf) :
#   IDLE_ANNOUNCE_INTERVAL  Secondes entre annonces (défaut : 900 = 15 min)
#   ICECAST_PORT            Port Icecast (défaut : 8111)
#   CLOCK_MODE              "bells" (coups de cloche) ou "silent"

CONF="${CONF:-/opt/soundspot/soundspot.conf}"
[ -f "$CONF" ] && source "$CONF"

INSTALL_DIR="${INSTALL_DIR:-/opt/soundspot}"
WAV_DIR="$INSTALL_DIR/wav"
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_ID=$(id -u "${SOUNDSPOT_USER}" 2>/dev/null || echo 1000)
export XDG_RUNTIME_DIR="/run/user/${USER_ID}"

_SS_SERVICE="idle"
# shellcheck source=/opt/soundspot/log.sh
[ -f "$INSTALL_DIR/log.sh" ] && source "$INSTALL_DIR/log.sh" || {
    ss_info()  { :; }; ss_warn()  { :; }
    ss_error() { :; }; ss_debug() { :; }
}

TTS_SH="$INSTALL_DIR/backend/audio/tts.sh"

# Re-lire la configuration à chaque cycle (changements du portail pris en compte à chaud)
reload_conf() {
    [ -f "$CONF" ] && source "$CONF"
    ICECAST_PORT="${ICECAST_PORT:-8111}"
    IDLE_ANNOUNCE_INTERVAL="${IDLE_ANNOUNCE_INTERVAL:-900}"
    CLOCK_MODE="${CLOCK_MODE:-bells}"
    VOICE_ENABLED="${VOICE_ENABLED:-true}"
    BELLS_ENABLED="${BELLS_ENABLED:-true}"
    ORPHEUS_VOICE="${ORPHEUS_VOICE:-pierre}"
    ORPHEUS_PORT="${ORPHEUS_PORT:-5005}"
}

ss_info "démarrage clocher — mode=${CLOCK_MODE:-bells} intervalle=${IDLE_ANNOUNCE_INTERVAL:-900}s"

# ── Audio : paplay → pw-play → aplay ─────────────────────────────
play_wav() {
    paplay "$1" 2>/dev/null || pw-play "$1" 2>/dev/null || aplay -q "$1" 2>/dev/null || true
}

# ── Synthèse vocale TTS → WAV temporaire → lecture ───────────────
# Utilise Orpheus (pierre/amelie) si Picoport est connecté à UPlanet,
# sinon espeak-ng en fallback. Le changement de voix est l'indicateur
# auditif que le nœud est bien relié à sa constellation.
say() {
    [ "${VOICE_ENABLED:-true}" = "false" ] && return 0
    local wav_paths
    # tts.sh peut retourner 2 lignes : intro constellation + message
    wav_paths=$(bash "$TTS_SH" "$*" "${ORPHEUS_VOICE:-pierre}" 2>/dev/null)
    while IFS= read -r wav; do
        [ -f "$wav" ] || continue
        play_wav "$wav"
        rm -f "$wav"
    done <<< "$wav_paths"
}

# ── Jouer un message numéroté depuis wav/ ────────────────────────
# Utilise _CYCLE_ORPHEUS (positionné une fois par cycle dans main()).
# Priorité : Orpheus → espeak fallback.
play_message_file() {
    local n="$1"
    local id; id=$(printf '%02d' "$n")
    local wav="$WAV_DIR/message_${id}.wav"
    local txt="$WAV_DIR/message_${id}.txt"

    # Si voix désactivée depuis le portail : espeak direct
    if [ "${VOICE_ENABLED:-true}" = "false" ]; then
        if [ -f "$txt" ] && { [ ! -f "$wav" ] || [ "$txt" -nt "$wav" ]; }; then
            espeak-ng -v fr+f3 -s 115 -p 40 "$(cat "$txt")" -w "$wav" 2>/dev/null || true
        fi
        [ -f "$wav" ] && play_wav "$wav"
        return
    fi

    # Orpheus en premier (disponibilité vérifiée une fois par cycle)
    if [ "${_CYCLE_ORPHEUS:-false}" = "true" ] && [ -f "$txt" ]; then
        local live_wav
        live_wav=$(bash "$TTS_SH" "$(cat "$txt")" "${ORPHEUS_VOICE:-amelie}" 2>/dev/null | tail -1)
        if [ -f "$live_wav" ]; then
            mv "$live_wav" "$wav" 2>/dev/null || { play_wav "$live_wav"; rm -f "$live_wav"; return; }
            play_wav "$wav"
            return
        fi
    fi

    # Fallback espeak — régénère si le .txt est plus récent (texte modifié depuis le portail)
    if [ -f "$txt" ] && { [ ! -f "$wav" ] || [ "$txt" -nt "$wav" ]; }; then
        espeak-ng -v fr+f3 -s 115 -p 40 "$(cat "$txt")" -w "$wav" 2>/dev/null || true
    fi
    [ -f "$wav" ] && play_wav "$wav"
}

# ── Régénérer tous les .wav espeak au démarrage ──────────────────
# Garantit que chaque boot commence avec les voix espeak (robot).
# Lorsqu'Orpheus se connecte, play_message_file() les remplace par la
# voix naturelle — c'est l'indicateur auditif que UPlanet est joignable.
init_espeak_wavs() {
    for txt in "$WAV_DIR"/message_*.txt; do
        [ -f "$txt" ] || continue
        local wav="${txt%.txt}.wav"
        espeak-ng -v fr+f3 -s 115 -p 40 "$(cat "$txt")" -w "$wav" 2>/dev/null || true
    done
    ss_info "Voix espeak initialisées — Orpheus les remplacera à la connexion UPlanet"
}

# ── Nombre de messages disponibles dans wav/ ─────────────────────
count_messages() {
    ls "$WAV_DIR"/message_*.txt 2>/dev/null | wc -l
}

# ── Vérifier si un DJ diffuse (source active sur Icecast) ────────
is_dj_active() {
    # Vérifie si le montage /live existe (HTTP 200 = DJ présent)
    local code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "http://127.0.0.1:${ICECAST_PORT}/live" 2>/dev/null)
    [ "$code" = "200" ]
}

# ── Coups de cloche (N × bip court avec fondu) ───────────────────
ring_bells() {
    local n="$1" i
    local bell="$WAV_DIR/bell_429hz.wav"
    for i in $(seq 1 "$n"); do
        play_wav "$bell"
        sleep 0.9
    done
}

# ── Longitude depuis ~/.zen/GPS ; fallback méridien du fuseau ────
get_solar_lon() {
    local user_home gps_file lon tz_str tz_sign tz_hh tz_mm tz_min
    user_home=$(getent passwd "${SOUNDSPOT_USER:-pi}" | cut -d: -f6 2>/dev/null || echo "/home/pi")
    gps_file="$user_home/.zen/GPS"
    if [ -f "$gps_file" ]; then
        lon=$(grep -oP '(?<=LON=)[^\s]+' "$gps_file" 2>/dev/null | head -1 || true)
        [ -n "$lon" ] && echo "$lon" && return
    fi
    # Fallback : méridien central du fuseau système
    # (Europe/Paris UTC+2 → 30°E → annonce heure civile si GPS absent)
    tz_str=$(date +%z)
    tz_sign=1; [[ "$tz_str" == -* ]] && tz_sign=-1
    tz_hh=$((10#${tz_str:1:2})); tz_mm=$((10#${tz_str:3:2}))
    tz_min=$(( tz_sign * (tz_hh * 60 + tz_mm) ))
    awk -v tm="$tz_min" 'BEGIN{printf "%.1f\n", tm/4}'
}

# ── Heure solaire vraie : heure_légale + (longitude − méridien_fuseau) × 4min ──
# 1° = 4 min. Retourne "H M" (entiers).
calc_solar_time() {
    local lon="${1:-0}"
    local local_h local_m tz_str tz_sign tz_hh tz_mm tz_min correction_min solar_min
    local_h=$(date +%-H)
    local_m=$(date +%-M)
    # Décalage UTC du fuseau système (ex: +0200 → 120 min → méridien 30°E)
    tz_str=$(date +%z)
    tz_sign=1; [[ "$tz_str" == -* ]] && tz_sign=-1
    tz_hh=$((10#${tz_str:1:2})); tz_mm=$((10#${tz_str:3:2}))
    tz_min=$(( tz_sign * (tz_hh * 60 + tz_mm) ))
    # correction = longitude×4 min − décalage_fuseau
    correction_min=$(awk -v lon="$lon" -v tz="$tz_min" \
        'BEGIN{v=lon*4-tz; printf "%d\n", (v>=0)?int(v+0.5):int(v-0.5)}')
    solar_min=$(( local_h * 60 + local_m + correction_min ))
    solar_min=$(( ((solar_min % 1440) + 1440) % 1440 ))
    echo "$(( solar_min / 60 )) $(( solar_min % 60 ))"
}

# ── Annonce vocale de l'heure solaire ────────────────────────────
announce_time() {
    local lon sol_h sol_m m_str
    lon=$(get_solar_lon)
    read -r sol_h sol_m <<< "$(calc_solar_time "$lon")"
    case "$sol_m" in
        0)  m_str="heures" ;;
        15) m_str="heures quinze" ;;
        30) m_str="heures trente" ;;
        45) m_str="heures quarante-cinq" ;;
        *)  m_str="heures ${sol_m}" ;;
    esac
    say "Il est ${sol_h} ${m_str}"
}

# ── Boucle principale ─────────────────────────────────────────────
main() {
    reload_conf
    init_espeak_wavs   # boot = espeak ; remplacement progressif par Orpheus si connecté

    local last_announce=0
    local msg_index=0

    while true; do
        reload_conf

        local now sol_h sol_m lon elapsed
        now=$(date +%s)
        elapsed=$(( now - last_announce ))
        lon=$(get_solar_lon)
        read -r sol_h sol_m <<< "$(calc_solar_time "$lon")"

        if [[ "$sol_m" =~ ^(0|15|30|45)$ ]] && [ "$elapsed" -ge 840 ]; then
            last_announce=$now

            # Vérifier Orpheus UNE FOIS par cycle (évite espeak/Orpheus dans le même cycle)
            _CYCLE_ORPHEUS=false
            if systemctl is-active --quiet picoport.service 2>/dev/null; then
                if curl -s -o /dev/null -w "%{http_code}" --max-time 2 \
                    "http://localhost:${ORPHEUS_PORT:-5005}/docs" 2>/dev/null | grep -q "200"; then
                    _CYCLE_ORPHEUS=true
                else
                    # Tentative de connexion (tunnel P2P Orpheus)
                    local _user_home; _user_home=$(getent passwd "${SOUNDSPOT_USER:-pi}" | cut -d: -f6)
                    local _orpheus_sh="${_user_home}/.zen/Astroport.ONE/IA/orpheus.me.sh"
                    [ -x "$_orpheus_sh" ] && sudo -u "$SOUNDSPOT_USER" bash "$_orpheus_sh" \
                        >/dev/null 2>&1 && sleep 8
                    curl -s -o /dev/null -w "%{http_code}" --max-time 2 \
                        "http://localhost:${ORPHEUS_PORT:-5005}/docs" 2>/dev/null | grep -q "200" \
                        && _CYCLE_ORPHEUS=true
                fi
            fi
            ss_debug "Orpheus cycle=${_CYCLE_ORPHEUS}"

            if is_dj_active; then
                ss_debug "DJ actif sur Icecast — annonce ignorée"
            else
                ss_info "annonce h${sol_h}:$(printf '%02d' "$sol_m") mode=${CLOCK_MODE:-bells} orpheus=${_CYCLE_ORPHEUS}"

                # 1. Bip 429.62 Hz — inhibé si BELLS_ENABLED=false
                if [ "${BELLS_ENABLED:-true}" = "true" ]; then
                    play_wav "$WAV_DIR/tone_429hz.wav"
                    sleep 1
                fi

                # 2. Coups de cloche à l'heure solaire pile (configurable via CLOCK_MODE + BELLS_ENABLED)
                if [ "$sol_m" = "0" ] && [ "${CLOCK_MODE:-bells}" = "bells" ] && [ "${BELLS_ENABLED:-true}" = "true" ]; then
                    local bells=$(( sol_h % 12 ))
                    [ "$bells" -eq 0 ] && bells=12
                    ss_debug "coups de cloche : ${bells}"
                    ring_bells "$bells"
                    sleep 1
                fi

                # 3. Heure solaire en voix (non désactivable)
                announce_time
                sleep 1

                # 4. Message collectif en rotation depuis wav/ (non désactivable)
                local total; total=$(count_messages)
                if [ "$total" -gt 0 ]; then
                    msg_index=$(( (msg_index % total) + 1 ))
                    ss_debug "lecture message_$(printf '%02d' "$msg_index")"
                    play_message_file "$msg_index"
                fi
            fi
        fi

        sleep 20
    done
}

main
