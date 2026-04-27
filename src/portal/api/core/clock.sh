#!/bin/bash
# api/core/clock.sh — Bascule CLOCK_MODE (bells | silent)
# Hérite des exports de api.sh.

_SS_SERVICE="portal-clock"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
MODE=$(printf '%s' "$POST_DATA" | grep -oP '(?<=mode=)[^&]+' | head -1)
[[ "$MODE" =~ ^(bells|silent)$ ]] || MODE="bells"

sudo "${INSTALL_DIR}/backend/system/set_clock_mode.sh" "$MODE" 2>/dev/null || true

printf '{"status":"ok","clock_mode":"%s"}\n' "$MODE"
