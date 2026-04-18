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

# Re-lire la configuration à chaque cycle (changements du portail pris en compte à chaud)
reload_conf() {
    [ -f "$CONF" ] && source "$CONF"
    ICECAST_PORT="${ICECAST_PORT:-8111}"
    IDLE_ANNOUNCE_INTERVAL="${IDLE_ANNOUNCE_INTERVAL:-900}"
    CLOCK_MODE="${CLOCK_MODE:-bells}"
}

# ── Audio : paplay → pw-play → aplay ─────────────────────────────
play_wav() {
    paplay "$1" 2>/dev/null || pw-play "$1" 2>/dev/null || aplay -q "$1" 2>/dev/null || true
}

# ── Synthèse vocale TTS → WAV temporaire → lecture ───────────────
say() {
    local tmp
    tmp=$(mktemp /tmp/soundspot_say_XXXX.wav)
    espeak-ng -v fr+f3 -s 115 -p 40 "$*" -w "$tmp" 2>/dev/null
    play_wav "$tmp"
    rm -f "$tmp"
}

# ── Jouer un message numéroté depuis wav/ ────────────────────────
# Priorité : .wav existant → régénération depuis .txt → synthèse inline
play_message_file() {
    local n="$1"
    local id; id=$(printf '%02d' "$n")
    local wav="$WAV_DIR/message_${id}.wav"
    local txt="$WAV_DIR/message_${id}.txt"

    # Régénérer le .wav si absent ou .txt plus récent
    if [ -f "$txt" ] && { [ ! -f "$wav" ] || [ "$txt" -nt "$wav" ]; }; then
        espeak-ng -v fr+f3 -s 115 -p 40 "$(cat "$txt")" -w "$wav" 2>/dev/null || true
    fi

    if [ -f "$wav" ]; then
        play_wav "$wav"
    fi
}

# ── Nombre de messages disponibles dans wav/ ─────────────────────
count_messages() {
    ls "$WAV_DIR"/message_*.txt 2>/dev/null | wc -l
}

# ── Vérifier si un DJ diffuse (source active sur Icecast) ────────
is_dj_active() {
    local json
    json=$(curl -sf --max-time 3 \
        "http://127.0.0.1:${ICECAST_PORT}/status-json.xsl" 2>/dev/null) || return 1
    echo "$json" | python3 -c "
import sys, json
try:
    src = json.load(sys.stdin).get('icestats', {}).get('source')
    print('yes' if src else 'no')
except Exception:
    print('no')" 2>/dev/null | grep -q yes
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

# ── Annonce vocale de l'heure ─────────────────────────────────────
announce_time() {
    local h m msg
    h=$(date +%-H)
    m=$(date +%-M 2>/dev/null || date +%M | sed 's/^0*//')
    : "${m:=0}"
    case "$m" in
        0)  msg="${h} heures" ;;
        15) msg="${h} heures et quart" ;;
        30) msg="${h} heures et demie" ;;
        45) msg="${h} heures quarante-cinq" ;;
        *)  msg="${h} heures ${m}" ;;
    esac
    say "$msg"
}

# ── Boucle principale ─────────────────────────────────────────────
main() {
    local last_announce=0
    local msg_index=0

    while true; do
        reload_conf

        local now m elapsed
        now=$(date +%s)
        m=$(date +%-M 2>/dev/null || date +%M | sed 's/^0*//')
        : "${m:=0}"
        elapsed=$(( now - last_announce ))

        if [[ "$m" =~ ^(0|15|30|45)$ ]] && [ "$elapsed" -ge 840 ]; then
            last_announce=$now

            if ! is_dj_active; then
                # 1. Bip 429.62 Hz (signal de vie — non désactivable)
                play_wav "$WAV_DIR/tone_429hz.wav"
                sleep 1

                # 2. Coups de cloche à l'heure pile (configurable via CLOCK_MODE)
                if [ "$m" = "0" ] && [ "${CLOCK_MODE:-bells}" = "bells" ]; then
                    local bells
                    bells=$(date +%-I 2>/dev/null || date +%I | sed 's/^0*//')
                    : "${bells:=12}"
                    ring_bells "$bells"
                    sleep 1
                fi

                # 3. Heure en voix (non désactivable)
                announce_time
                sleep 1

                # 4. Message collectif en rotation depuis wav/ (non désactivable)
                local total; total=$(count_messages)
                if [ "$total" -gt 0 ]; then
                    msg_index=$(( (msg_index % total) + 1 ))
                    play_message_file "$msg_index"
                fi
            fi
        fi

        sleep 20
    done
}

main
