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

# Détection automatique du périphérique USB audio si non défini
if [ -z "$MIC_DEV" ]; then
    MIC_DEV=$(arecord -l 2>/dev/null \
        | awk '/USB/{match($0,/card ([0-9]+)/,c); match($0,/device ([0-9]+)/,d); if(c[1]!="" && d[1]!="") print "hw:"c[1]","d[1]; exit}')
fi

if [ -z "$MIC_DEV" ]; then
    echo "mic_capture: aucun micro USB détecté (arecord -l)" >&2
    exit 1
fi

echo "mic_capture: périphérique → $MIC_DEV" >&2

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
