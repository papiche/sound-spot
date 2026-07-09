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
#   Sons Homer      : /opt/soundspot/portal/sounds/homer/ (sélectionnés à 50% de probabilité)

CONF="${CONF:-/opt/soundspot/soundspot.conf}"
[ -f "$CONF" ] && source "$CONF"

INSTALL_DIR="${INSTALL_DIR:-/opt/soundspot}"
WAV_DIR="$INSTALL_DIR/wav"
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_ID=$(id -u "${SOUNDSPOT_USER}" 2>/dev/null || echo 1000)
export XDG_RUNTIME_DIR="/run/user/${USER_ID}"

_SS_SERVICE="idle"
[ -f "$INSTALL_DIR/log.sh" ] && source "$INSTALL_DIR/log.sh" || {
    ss_info()  { :; }; ss_warn()  { :; }
    ss_error() { :; }; ss_debug() { :; }
}

TTS_SH="$INSTALL_DIR/backend/audio/tts.sh"
SPEAKER_ACTIVE_FLAG="/dev/shm/soundspot_speaker_active"
AUDIO_LOCK="/dev/shm/soundspot_audio.lock"

# Re-lire la configuration à chaque cycle
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

# ── Audio : mpg123 → paplay → pw-play → aplay ─────────────────────────────
play_audio() {
    local file="$1"
    touch "$SPEAKER_ACTIVE_FLAG" 2>/dev/null
    if [[ "${file,,}" == *.mp3 ]]; then
        mpg123 -q "$file" 2>/dev/null || pw-play "$file" 2>/dev/null || true
    else
        paplay "$file" 2>/dev/null || pw-play "$file" 2>/dev/null || aplay -q "$file" 2>/dev/null || true
    fi
}

# ── Synthèse vocale TTS ───────────────
say() {
    [ "${VOICE_ENABLED:-true}" = "false" ] && return 0
    local wav_paths
    wav_paths=$(bash "$TTS_SH" "$*" "${ORPHEUS_VOICE:-pierre}" 2>/dev/null)
    while IFS= read -r wav; do
        [ -f "$wav" ] || continue
        play_audio "$wav"
        rm -f "$wav"
    done <<< "$wav_paths"
}

# ── Jouer un message collectif depuis wav/ ────────────────────────
play_message_file() {
    local n="$1"
    local id=$(printf '%02d' "$n")
    local mp3="$WAV_DIR/message_${id}.mp3"
    local wav="$WAV_DIR/message_${id}.wav"
    local txt="$WAV_DIR/message_${id}.txt"

    if [ -f "$mp3" ]; then
        ss_info "Lecture message_$id (MP3 utilisateur)"
        play_audio "$mp3"
        return 0
    fi

    local owner=$(stat -c '%U' "$wav" 2>/dev/null || echo "none")

    if [ "${_CYCLE_ORPHEUS:-false}" = "true" ] && { [ "$owner" = "www-data" ] || [ ! -f "$wav" ]; }; then
        ss_info "Promotion Orpheus pour message_$id (Source: $owner)"
        local live_wav=$(bash "$TTS_SH" "$(cat "$txt" 2>/dev/null)" "${ORPHEUS_VOICE:-pierre}" 2>/dev/null | tail -1)
        if [ -f "$live_wav" ]; then
            mv -f "$live_wav" "$wav"
            chown pi:soundspot "$wav" 2>/dev/null || true
            chmod 664 "$wav"
        fi
    fi
    
    [ -f "$wav" ] && play_audio "$wav"
}

# ── Recherche d'un message Homer au hasard ────────────────────────
get_random_homer() {
    local homer_dirs=(
        "$INSTALL_DIR/portal/sounds/homer"
        "$WAV_DIR/Homer"
        "$INSTALL_DIR/wav/Homer"
    )
    local files=()
    for d in "${homer_dirs[@]}"; do
        if [ -d "$d" ]; then
            while IFS= read -r f; do
                [ -f "$f" ] && files+=("$f")
            done < <(find "$d" -maxdepth 1 -type f -name "*.mp3" 2>/dev/null)
        fi
    done
    if [ ${#files[@]} -gt 0 ]; then
        echo "${files[RANDOM % ${#files[@]}]}"
    fi
}

count_messages() {
    ls "$WAV_DIR"/message_*.* 2>/dev/null | grep -oP 'message_[0-9]+' | sort -u | wc -l
}

is_dj_active() {
    local code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "http://127.0.0.1:${ICECAST_PORT}/live" 2>/dev/null)
    [ "$code" = "200" ]
}

ring_bells() {
    local n="$1" i
    local bell="$WAV_DIR/bell_429hz.wav"
    for i in $(seq 1 "$n"); do
        play_audio "$bell"
        sleep 0.9
    done
}

get_solar_lon() {
    local user_home gps_file lon tz_str tz_sign tz_hh tz_mm tz_min
    user_home=$(getent passwd "${SOUNDSPOT_USER:-pi}" | cut -d: -f6 2>/dev/null || echo "/home/pi")
    gps_file="$user_home/.zen/GPS"
    if [ -f "$gps_file" ]; then
        lon=$(grep -oP '(?<=LON=)[^\s]+' "$gps_file" 2>/dev/null | head -1 || true)
        [ -n "$lon" ] && echo "$lon" && return
    fi
    tz_str=$(date +%z)
    tz_sign=1; [[ "$tz_str" == -* ]] && tz_sign=-1
    tz_hh=$((10#${tz_str:1:2})); tz_mm=$((10#${tz_str:3:2}))
    tz_min=$(( tz_sign * (tz_hh * 60 + tz_mm) ))
    awk -v tm="$tz_min" 'BEGIN{printf "%.1f\n", tm/4}'
}

calc_solar_time() {
    local lon="${1:-0}"
    local local_h local_m tz_str tz_sign tz_hh tz_mm tz_min correction_min solar_min
    local_h=$(date +%-H)
    local_m=$(date +%-M)
    tz_str=$(date +%z)
    tz_sign=1; [[ "$tz_str" == -* ]] && tz_sign=-1
    tz_hh=$((10#${tz_str:1:2})); tz_mm=$((10#${tz_str:3:2}))
    tz_min=$(( tz_sign * (tz_hh * 60 + tz_mm) ))
    correction_min=$(awk -v lon="$lon" -v tz="$tz_min" \
        'BEGIN{v=lon*4-tz; printf "%d\n", (v>=0)?int(v+0.5):int(v-0.5)}')
    solar_min=$(( local_h * 60 + local_m + correction_min ))
    solar_min=$(( ((solar_min % 1440) + 1440) % 1440 ))
    echo "$(( solar_min / 60 )) $(( solar_min % 60 ))"
}

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

main() {
    reload_conf
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

            _CYCLE_ORPHEUS=false
            if curl -s -o /dev/null -w "%{http_code}" --max-time 2 \
                "http://localhost:${ORPHEUS_PORT:-5005}/docs" 2>/dev/null | grep -q "200"; then
                _CYCLE_ORPHEUS=true
            else
                # Tentative de connexion (tunnel P2P Orpheus)
                local _user_home; _user_home=$(getent passwd "${SOUNDSPOT_USER:-pi}" | cut -d: -f6)
                local _orpheus_sh="${_user_home}/.zen/Astroport.ONE/IA/services/orpheus.me.sh"
                [ -x "$_orpheus_sh" ] && sudo -u "$SOUNDSPOT_USER" bash "$_orpheus_sh" \
                    >/dev/null 2>&1 && sleep 8
                curl -s -o /dev/null -w "%{http_code}" --max-time 2 \
                    "http://localhost:${ORPHEUS_PORT:-5005}/docs" 2>/dev/null | grep -q "200" \
                    && _CYCLE_ORPHEUS=true
            fi
            ss_debug "Orpheus cycle=${_CYCLE_ORPHEUS}"

            if is_dj_active; then
                ss_debug "DJ actif sur Icecast — annonce ignorée"
            else
                # ── SÉCURITÉ ANTI-CHEVAUCHEMENT : Verrouillage non-bloquant ──
                # Si le Jukebox joue une chanson, l'annonce du clocher est annulée proprement.
                (
                    flock -n 9 || { ss_debug "Canal audio occupé (Jukebox ou welcome en cours). Annonce sautée."; exit 0; }
                    
                    ss_info "annonce h${sol_h}:$(printf '%02d' "$sol_m") mode=${CLOCK_MODE:-bells} orpheus=${_CYCLE_ORPHEUS}"

                    # 1. Bip 429.62 Hz
                    if [ "${BELLS_ENABLED:-true}" = "true" ]; then
                        play_audio "$WAV_DIR/tone_429hz.wav"
                        sleep 1
                    fi

                    # 2. Coups de cloche à l'heure pile
                    if [ "$sol_m" = "0" ] && [ "${CLOCK_MODE:-bells}" = "bells" ] && [ "${BELLS_ENABLED:-true}" = "true" ]; then
                        local bells=$(( sol_h % 12 ))
                        [ "$bells" -eq 0 ] && bells=12
                        ring_bells "$bells"
                        sleep 1
                    fi

                    # 3. Heure solaire vocale
                    announce_time
                    sleep 1

                    # 4. Message ou gag Homer (50/50 de probabilité)
                    local total; total=$(count_messages)
                    if [ "$total" -gt 0 ]; then
                        if [ $((RANDOM % 2)) -eq 0 ]; then
                            local homer_sound=$(get_random_homer)
                            if [ -n "$homer_sound" ]; then
                                ss_info "Lecture d'un gag de Homer : $(basename "$homer_sound")"
                                play_audio "$homer_sound"
                            else
                                # Fallback si le dossier Homer est vide ou introuvable
                                msg_index=$(( (msg_index % total) + 1 ))
                                play_message_file "$msg_index"
                            fi
                        else
                            msg_index=$(( (msg_index % total) + 1 ))
                            play_message_file "$msg_index"
                        fi
                    fi
                ) 9>"$AUDIO_LOCK"
            fi
        fi

        sleep 20
    done
}

main