#!/bin/bash
# decoder.sh — Lit le flux Ogg de Mixxx via Icecast,
# le décode en PCM 48 kHz s16le et l'écrit dans le snapfifo.
# ffmpeg est tolérant aux coupures : il attend et relance automatiquement.
FIFO="/dev/shm/snapfifo"
[ -p "$FIFO" ] || mkfifo -m 0660 "$FIFO"

while true; do
    ffmpeg -hide_banner -loglevel error -fflags nobuffer -flags low_delay -rw_timeout 5000000 \
      -reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 \
      -i http://127.0.0.1:8111/live \
      -f s16le -ar 48000 -ac 2 pipe:1 > "$FIFO" 2>/dev/null
    sleep 2
done
