#!/bin/bash
# play_welcome.sh — Joue le message d'accueil SoundSpot
# PipeWire mixe ce flux avec le stream Snapcast en cours.
WELCOME_WAV="/opt/soundspot/welcome.wav"

[ -f "$WELCOME_WAV" ] || exit 1

# Verrouillage atomique via le noyau (flock sur fd 9).
# Contrairement à un fichier .lock, flock est libéré instantanément
# si le script meurt (coupure courant, SIGKILL) — jamais de verrou fantôme.
exec 9>/tmp/soundspot_welcome.lock
flock -n 9 || exit 0   # Une autre instance joue déjà → on abandonne

paplay "$WELCOME_WAV" 2>/dev/null || \
pw-play "$WELCOME_WAV" 2>/dev/null || \
aplay  "$WELCOME_WAV" 2>/dev/null
