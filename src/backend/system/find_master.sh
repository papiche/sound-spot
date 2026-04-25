#!/bin/bash
# find_master.sh — Résolution dynamique de l'IP du maître Snapcast
# Appelé par ExecStartPre du service soundspot-client (satellite).
# Priorité : AP directe (gateway 192.168.10.1) > mDNS unique > MASTER_HOST.
# Écrit /run/soundspot_master.env  avec  MASTER_RESOLVED=<ip_ou_nom>

source "${INSTALL_DIR:-/opt/soundspot}/soundspot.conf" 2>/dev/null || true

MASTER_IP=""
CURRENT_SSID=$(iwgetid -r 2>/dev/null || true)

# Connecté à l'AP du maître → gateway = maître (toujours 192.168.10.1)
if [ -n "${SPOT_NAME:-}" ] && [ "$CURRENT_SSID" = "$SPOT_NAME" ]; then
    MASTER_IP=$(ip route 2>/dev/null | awk '/default/{print $3; exit}')
fi

# Résolution via hostname mDNS unique (soundspot-NOM.local)
if [ -z "$MASTER_IP" ] && [ -n "${TARGET_MASTER:-}" ]; then
    MASTER_IP=$(getent hosts "${TARGET_MASTER}.local" 2>/dev/null | awk '{print $1; exit}')
fi

# Fallback : MASTER_HOST (nom mDNS classique ou IP)
if [ -z "$MASTER_IP" ] && [ -n "${MASTER_HOST:-}" ]; then
    MASTER_IP=$(getent hosts "$MASTER_HOST" 2>/dev/null | awk '{print $1; exit}')
fi

MASTER_RESOLVED="${MASTER_IP:-${MASTER_HOST:-soundspot.local}}"
echo "MASTER_RESOLVED=${MASTER_RESOLVED}" > /run/soundspot_master.env
logger -t find_master "Maître résolu : ${MASTER_RESOLVED} (SSID=${CURRENT_SSID:-?})"
