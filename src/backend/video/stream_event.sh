#!/bin/bash
# stream_event.sh — Appelé par Nginx-RTMP quand un flux commence ou s'arrête
ACTION=$1
NAME=$2
LIST="/dev/shm/active_streams.txt"
CURRENT="/dev/shm/current_vj"

if [ "$ACTION" = "start" ]; then
    echo "$NAME" >> "$LIST"
    sort -u "$LIST" -o "$LIST"
elif [ "$ACTION" = "stop" ]; then
    sed -i "/^$NAME$/d" "$LIST"
    # Si le flux projeté s'arrête, on coupe le projecteur
    if [ "$(cat "$CURRENT" 2>/dev/null)" = "$NAME" ]; then
        echo "" > "$CURRENT"
    fi
fi
