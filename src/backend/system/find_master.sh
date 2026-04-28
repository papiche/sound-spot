#!/bin/bash
# find_master.sh — Résolution dynamique de l'IP du maître Snapcast
# Appelé par ExecStartPre du service soundspot-client (satellite).
# Priorité : AP directe (gateway 192.168.10.1) > mDNS unique > MASTER_HOST > scan port.
# Écrit /run/soundspot_master.env  avec  MASTER_RESOLVED=<ip_ou_nom>

source "${INSTALL_DIR:-/opt/soundspot}/soundspot.conf" 2>/dev/null || true

MASTER_IP=""
CURRENT_SSID=$(iwgetid -r 2>/dev/null || true)

# 1. Connecté à l'AP du maître → gateway = maître (toujours 192.168.10.1)
if [ -n "${SPOT_NAME:-}" ] && [ "$CURRENT_SSID" = "$SPOT_NAME" ]; then
    MASTER_IP=$(ip route 2>/dev/null | awk '/default/{print $3; exit}')
fi

# 2. Résolution via hostname mDNS unique (soundspot-NOM.local)
if [ -z "$MASTER_IP" ] && [ -n "${TARGET_MASTER:-}" ]; then
    MASTER_IP=$(getent hosts "${TARGET_MASTER}.local" 2>/dev/null | awk '{print $1; exit}')
fi

# 3. Fallback : MASTER_HOST (nom mDNS classique ou IP fixe)
if [ -z "$MASTER_IP" ] && [ -n "${MASTER_HOST:-}" ]; then
    MASTER_IP=$(getent hosts "$MASTER_HOST" 2>/dev/null | awk '{print $1; exit}')
fi

# 4. Fallback actif : scan du port 1704 (Snapcast) si mDNS lent ou absent
#    Tente d'abord Icecast :8111 (plus rapide) sur les IPs de la gateway
if [ -z "$MASTER_IP" ]; then
    GATEWAY=$(ip route 2>/dev/null | awk '/default/{print $3; exit}')
    if [ -n "$GATEWAY" ]; then
        SUBNET=$(echo "$GATEWAY" | cut -d. -f1-3)
        logger -t find_master "mDNS échoué — scan port 1704/8111 sur ${SUBNET}.0/24"

        if command -v nmap >/dev/null 2>&1; then
            # nmap rapide : SYN scan sur port 1704, timeout 1s par hôte
            MASTER_IP=$(nmap -p 1704 --open -T4 --host-timeout 1s \
                -oG - "${SUBNET}.0/24" 2>/dev/null \
                | awk '/Ports:.*1704.*open/{print $2; exit}')
        else
            # Fallback curl : sonde les 20 premières IPs sur Icecast :8111
            for i in $(seq 1 20); do
                ip_try="${SUBNET}.${i}"
                if curl -sf --max-time 1 \
                    "http://${ip_try}:${ICECAST_PORT:-8111}/status-json.xsl" \
                    >/dev/null 2>&1; then
                    MASTER_IP="$ip_try"
                    break
                fi
            done
        fi

        if [ -n "$MASTER_IP" ]; then
            logger -t find_master "Maître trouvé par scan de port : $MASTER_IP"
        fi
    fi
fi

MASTER_RESOLVED="${MASTER_IP:-${MASTER_HOST:-soundspot.local}}"
echo "MASTER_RESOLVED=${MASTER_RESOLVED}" > /run/soundspot_master.env
logger -t find_master "Maître résolu : ${MASTER_RESOLVED} (SSID=${CURRENT_SSID:-?})"
