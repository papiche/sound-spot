#!/bin/bash
# play_welcome.sh — Joue le message d'accueil SoundSpot
# PipeWire mixe ce flux avec le stream Snapcast en cours.
WELCOME_WAV="/opt/soundspot/welcome.wav"
[ -f "$WELCOME_WAV" ] || exit 1

# Utilisation d'un chemin accessible à l'utilisateur pi (UID 1000)
# /run/user/1000 est un système de fichiers en RAM, rapide et propre.
exec 9>/run/user/1000/soundspot_welcome.lock
flock -n 9 || exit 0

paplay "$WELCOME_WAV" 2>/dev/null || \
pw-play "$WELCOME_WAV" 2>/dev/null || \
aplay  "$WELCOME_WAV" 2>/dev/null