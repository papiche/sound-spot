#!/bin/bash
# api/core/voice.sh — Bascule VOICE_ENABLED (true | false)
# Hérite des exports de api.sh.

_SS_SERVICE="portal-voice"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
MODE=$(printf '%s' "$POST_DATA" | grep -oP '(?<=mode=)[^&]+' | head -1)
[[ "$MODE" =~ ^(true|false)$ ]] || MODE="true"

sudo "${INSTALL_DIR}/backend/system/set_voice_mode.sh" "$MODE" 2>/dev/null || true

printf '{"status":"ok","voice_enabled":%s}\n' "$MODE"
