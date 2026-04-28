#!/bin/bash
# mic_capture.sh — Capture le micro et l'envoie dans le FIFO Snapcast
# Produit un 2ème stream "SoundSpot_Mic" pour l'ambiance live.
#
# Accès micro via PulseAudio/PipeWire (source par défaut = "default").
# Cela permet le PARTAGE du micro avec sounddevice (presence_detector,
# mon-oeil) sans conflit "Device or resource busy".
#
# Le service soundspot-mic.service doit tourner en tant que SOUNDSPOT_USER
# avec XDG_RUNTIME_DIR et PULSE_SERVER correctement positionnés
# (voir soundspot-mic.service).
#
# Variables d'env :
#   MIC_PULSE_SRC   Source PulseAudio/PipeWire (défaut: "default")
#   MIC_BANDPASS    true → filtre passe-bande 300-3400 Hz (voix téléphonique)

FIFO="/dev/shm/snapfifo_mic"
BANDPASS="${MIC_BANDPASS:-false}"
MIC_SRC="${MIC_PULSE_SRC:-default}"

[ -p "$FIFO" ] || mkfifo -m 0660 "$FIFO"

_SS_SERVICE="soundspot-mic"
[ -f /opt/soundspot/soundspot.conf ] && source /opt/soundspot/soundspot.conf
[ -f /opt/soundspot/backend/system/log.sh ] && source /opt/soundspot/backend/system/log.sh || {
    ss_info()  { echo "[INFO ] [soundspot-mic] $*"; }
    ss_warn()  { echo "[WARN ] [soundspot-mic] $*" >&2; }
    ss_error() { echo "[ERROR] [soundspot-mic] $*" >&2; }
}

# ── Diagnostic micro ALSA (information seulement — PipeWire gère l'accès) ──
CARD_ID=$(arecord -l 2>/dev/null | grep -Ei "Q91|W-KING|USB Audio|seeed|respeaker" | head -n 1 | cut -d' ' -f2 | tr -d ':')
if [ -n "$CARD_ID" ]; then
    ss_info "Micro USB détecté : carte ALSA ${CARD_ID} — accès partagé via PipeWire"
else
    ss_info "Aucun micro USB spécifique détecté — utilisation de la source PipeWire par défaut"
fi

# ── Vérification que PipeWire/PulseAudio est joignable ─────────────────
if ! pactl info >/dev/null 2>&1; then
    ss_error "PipeWire/PulseAudio inaccessible (PULSE_SERVER=${PULSE_SERVER:-non défini})"
    ss_error "Vérifier : XDG_RUNTIME_DIR et PULSE_SERVER dans soundspot-mic.service"
    exit 1
fi

ss_info "Source PipeWire : ${MIC_SRC} — FIFO : ${FIFO}"

# ── Filtre passe-bande optionnel ────────────────────────────────────────
if [ "$BANDPASS" = "true" ]; then
    FILTERS="-af highpass=f=300,lowpass=f=3400"
    ss_info "Filtre passe-bande 300-3400 Hz activé"
else
    FILTERS=""
fi

# ── Boucle de capture (redémarre automatiquement en cas de coupure) ────
ss_info "Démarrage capture micro (ffmpeg pulse → snapfifo_mic)"
while true; do
    ffmpeg -hide_banner -loglevel warning \
        -f pulse -ar 48000 -ac 1 -i "$MIC_SRC" \
        $FILTERS \
        -f s16le -ar 48000 -ac 2 pipe:1 > "$FIFO" 2>&1 | \
        while IFS= read -r line; do ss_warn "ffmpeg: $line"; done
    EXIT_CODE=${PIPESTATUS[0]}
    ss_warn "ffmpeg mic terminé (code ${EXIT_CODE}) — redémarrage dans 2s"
    sleep 2
done
