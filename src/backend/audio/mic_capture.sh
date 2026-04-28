#!/bin/bash
# mic_capture.sh — Capture le micro USB et l'envoie dans le FIFO Snapcast
# Produit un 2ème stream "SoundSpot_Mic" pour l'ambiance live.
#
# Détection automatique du périphérique USB audio (card "USB") ou
# fallback sur la variable d'env MIC_ALSA_DEV.
# Passe-bande optionnel : MIC_BANDPASS=true active un filtre 300-3400 Hz
# pour la téléphonie / voix (économise de la bande passante Snapcast).

FIFO="/dev/shm/snapfifo_mic"
MIC_DEV="${MIC_ALSA_DEV:-}"
BANDPASS="${MIC_BANDPASS:-false}"

[ -p "$FIFO" ] || mkfifo -m 0660 "$FIFO"

# 1. Recherche dynamique du micro
# On cherche les patterns connus dans arecord -l
# card 3: Q91 [Q9-1], device 0 ... -> on veut le '3'
CARD_ID=$(arecord -l | grep -Ei "Q91|W-KING|USB Audio|seeed|respeaker" | head -n 1 | cut -d' ' -f2 | tr -d ':')

if [ -z "$CARD_ID" ]; then
    # Fallback si rien n'est trouvé, on prend la carte 0 par défaut
    MIC_ALSA_DEV="hw:0,0"
    echo "WARN: Aucun micro spécifique détecté, essai sur hw:0,0" >&2
else
    MIC_ALSA_DEV="hw:${CARD_ID},0"
    echo "INFO: Micro détecté automatiquement sur ${MIC_ALSA_DEV}" >&2
fi

# Détection automatique du périphérique USB audio si non défini
if [ -z "$MIC_DEV" ]; then
    log "Recherche d'un périphérique audio..."
    # Cherche ReSpeaker d'abord, puis USB
    MIC_DEV=$(arecord -l | grep -Ei "seeed|respeaker|USB" | head -n1 | awk '{print "hw:"$2",0"}')
fi

if [ -z "$MIC_DEV" ]; then
    ss_error "Aucun micro trouvé (arecord -l est vide). Le stream Mic sera silencieux."
    exit 1
else
    ss_info "Micro sélectionné : $MIC_DEV"
fi


# Construction du pipeline ffmpeg selon passe-bande
if [ "$BANDPASS" = "true" ]; then
    FILTERS="-af highpass=f=300,lowpass=f=3400"
else
    FILTERS=""
fi

while true; do
    ffmpeg -hide_banner -loglevel error \
        -f alsa -ar 48000 -ac 1 -i "$MIC_DEV" \
        $FILTERS \
        -f s16le -ar 48000 -ac 2 pipe:1 > "$FIFO" 2>/dev/null
    sleep 1
done
