#!/bin/bash
# api/core/projector.sh — Contrôle du Relais Projecteur (Branché sur GPIO 18 par ex)
# Réseau AP visiteurs isolé (portail captif) — pas d'authentification requise,
# au même titre que les autres actions matérielles locales du portail.
_SS_SERVICE="portal-projector"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

PROJECTOR_PIN="${PROJECTOR_PIN:-18}" # PIN GPIO sur lequel le relais est branché

# ── Lecture des paramètres ───────────────────────────────────
if [ "$REQUEST_METHOD" = "POST" ]; then
    read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
    MODE=$(printf '%s' "$POST_DATA" | grep -oP '(?<=mode=)[^&]+' | head -1)
else
    MODE=$(echo "$QUERY_STRING" | grep -oP '(?<=mode=)[^&]+' | head -1)
fi

ss_info "projector: cmd=${MODE:-status} ip=${REMOTE_ADDR:-?}"

# Initialisation du GPIO (Sysfs)
if [ ! -d /sys/class/gpio/gpio${PROJECTOR_PIN} ]; then
    echo "${PROJECTOR_PIN}" > /sys/class/gpio/export 2>/dev/null || true
    echo "out" > /sys/class/gpio/gpio${PROJECTOR_PIN}/direction 2>/dev/null || true
fi

if [ "$MODE" = "on" ]; then
    echo "1" > /sys/class/gpio/gpio${PROJECTOR_PIN}/value
    ss_info "Projecteur Nebula allumé (GPIO ${PROJECTOR_PIN} HIGH)"
    printf '{"status":"ok","projector":"on"}\n'
elif [ "$MODE" = "off" ]; then
    echo "0" > /sys/class/gpio/gpio${PROJECTOR_PIN}/value
    ss_info "Projecteur Nebula éteint (GPIO ${PROJECTOR_PIN} LOW)"
    printf '{"status":"ok","projector":"off"}\n'
else
    VAL=$(cat /sys/class/gpio/gpio${PROJECTOR_PIN}/value 2>/dev/null || echo "0")
    if [ "$VAL" = "1" ]; then
        printf '{"status":"ok","projector":"on"}\n'
    else
        printf '{"status":"ok","projector":"off"}\n'
    fi
fi
