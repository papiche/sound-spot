#!/bin/bash
WELCOME_WAV="/opt/soundspot/welcome.wav"
[ -f "$WELCOME_WAV" ] || exit 1

[ -f /opt/soundspot/soundspot.conf ] && source /opt/soundspot/soundspot.conf
USER_ID=$(id -u "${SOUNDSPOT_USER:-pi}" 2>/dev/null || echo 1000)
export XDG_RUNTIME_DIR="/run/user/${USER_ID}"
ICECAST_PORT="${ICECAST_PORT:-8111}"

if [ "$1" != "--force" ]; then
    # Ne pas parler si un flux DJ est actif (silence caméra)
    if curl -sf --max-time 1 "http://127.0.0.1:${ICECAST_PORT}/status-json.xsl" 2>/dev/null | grep -q '"source"'; then
        exit 0
    fi
fi

exec 9>"${XDG_RUNTIME_DIR}/soundspot_welcome.lock"
flock -n 9 || exit 0
paplay "$WELCOME_WAV" 2>/dev/null || pw-play "$WELCOME_WAV" 2>/dev/null || aplay "$WELCOME_WAV" 2>/dev/null