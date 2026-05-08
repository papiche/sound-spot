#!/bin/bash
# API Controlleur de l'AutoDJ
read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
CMD=$(echo "$POST_DATA" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)
[ -z "$CMD" ] && CMD=$(echo "$QUERY_STRING" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)

case "${CMD:-status}" in
    start)
        sudo /usr/bin/systemctl start soundspot-autodj
        echo '{"status":"ok", "state":"playing"}'
        ;;
    stop)
        sudo /usr/bin/systemctl stop soundspot-autodj
        echo '{"status":"ok", "state":"stopped"}'
        ;;
    status)
        if systemctl is-active --quiet soundspot-autodj; then
            echo '{"status":"ok", "state":"playing"}'
        else
            echo '{"status":"ok", "state":"stopped"}'
        fi
        ;;
    *)
        echo '{"error":"unknown_cmd"}'
        ;;
esac