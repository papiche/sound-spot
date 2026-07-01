#!/bin/bash
# api/core/clock.sh — Bascule CLOCK_MODE (bells | silent)
# Hérite des exports de api.sh.

_SS_SERVICE="portal-clock"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

MODE_GET=$(echo "$QUERY_STRING" | grep -oP '(?<=mode=)[^&]+' | head -1)
if [ "${REQUEST_METHOD:-GET}" = "POST" ]; then
    read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
    MODE_POST=$(printf '%s' "$POST_DATA" | grep -oP '(?<=mode=)[^&]+' | head -1)
fi
MODE="${MODE_POST:-$MODE_GET}"
[[ "$MODE" =~ ^(bells|silent)$ ]] || MODE="bells"

sudo "${INSTALL_DIR}/backend/system/set_clock_mode.sh" "$MODE" 2>/dev/null || true

printf '{"status":"ok","clock_mode":"%s"}\n' "$MODE"
