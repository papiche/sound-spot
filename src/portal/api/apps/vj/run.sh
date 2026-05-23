#!/bin/bash
_SS_SERVICE="portal-vj"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
CMD=$(echo "$POST_DATA" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)
[ -z "$CMD" ] && CMD=$(echo "$QUERY_STRING" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)

if [ "$CMD" = "list" ]; then
    STREAMS=$(cat /dev/shm/active_streams.txt 2>/dev/null | awk '{print "\""$0"\""}' | paste -sd "," -)
    CURRENT=$(cat /dev/shm/current_vj 2>/dev/null)
    echo "{\"status\":\"ok\", \"streams\":[${STREAMS:-}], \"current\":\"$CURRENT\"}"
elif [ "$CMD" = "play" ]; then
    NAME=$(echo "$POST_DATA" | grep -oP '(?<=name=)[a-zA-Z0-9_-]+' | head -1)
    echo "$NAME" > /dev/shm/current_vj
    echo "{\"status\":\"ok\", \"playing\":\"$NAME\"}"
elif [ "$CMD" = "stop" ]; then
    echo "" > /dev/shm/current_vj
    echo "{\"status\":\"ok\", \"playing\":\"\"}"
else
    echo "{\"error\":\"unknown_cmd\"}"
fi
