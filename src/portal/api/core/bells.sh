#!/bin/bash
# api/core/bells.sh — Bascule BELLS_ENABLED (true | false)
# Contrôle le bip 429Hz ET les coups de cloche.

read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
MODE=$(printf '%s' "$POST_DATA" | grep -oP '(?<=mode=)[^&]+' | head -1)
[[ "$MODE" =~ ^(true|false)$ ]] || MODE="true"

sudo "${INSTALL_DIR}/set_bells_mode.sh" "$MODE" 2>/dev/null || true

printf '{"status":"ok","bells_enabled":%s}\n' "$MODE"
