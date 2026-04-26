#!/bin/bash
# set_audio_output.sh — Sélecteur de sortie PipeWire/PulseAudio
# Appelé en root depuis le portail www-data via sudo
# Usage : set_audio_output.sh list | get-default | set <sink-name>

source /opt/soundspot/soundspot.conf 2>/dev/null || true
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
SOUNDSPOT_UID=$(id -u "$SOUNDSPOT_USER" 2>/dev/null || echo 1000)
PULSE_SOCK="unix:/run/user/${SOUNDSPOT_UID}/pulse/native"

_pactl() {
    sudo -u "$SOUNDSPOT_USER" \
        env XDG_RUNTIME_DIR="/run/user/${SOUNDSPOT_UID}" \
            PULSE_SERVER="$PULSE_SOCK" \
        /usr/bin/pactl "$@" 2>/dev/null
}

case "${1:-list}" in
    list)
        _pactl list sinks short
        ;;
    get-default)
        _pactl get-default-sink
        ;;
    set)
        SINK="$2"
        _pactl set-default-sink "$SINK" \
            && /bin/systemctl restart soundspot-client.service 2>/dev/null || true
        ;;
esac
