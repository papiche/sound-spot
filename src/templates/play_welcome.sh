#!/bin/bash
# play_welcome.sh — Joue le message d'accueil SoundSpot
# PipeWire mixe ce flux avec le stream Snapcast en cours.
WELCOME_WAV="/opt/soundspot/welcome.wav"
[ -f "$WELCOME_WAV" ] || exit 1

# Récupération de l'UID de l'utilisateur audio de façon dynamique
# pour éviter le chemin /run/user/1000 codé en dur.
[ -f /opt/soundspot/soundspot.conf ] && source /opt/soundspot/soundspot.conf
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_ID=$(id -u "${SOUNDSPOT_USER}" 2>/dev/null || echo 1000)
export XDG_RUNTIME_DIR="/run/user/${USER_ID}"

exec 9>"${XDG_RUNTIME_DIR}/soundspot_welcome.lock"
flock -n 9 || exit 0

paplay "$WELCOME_WAV" 2>/dev/null || \
pw-play "$WELCOME_WAV" 2>/dev/null || \
aplay  "$WELCOME_WAV" 2>/dev/null