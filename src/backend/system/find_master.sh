#!/bin/bash
# find_master.sh — Résolution dynamique de l'IP du maître Snapcast
# Appelé par ExecStartPre du service soundspot-client (satellite).
# Priorité : ZICMAMA (si RSSI suffisant) > Mesh bat0 > mDNS > MASTER_HOST > scan port.
# Écrit /run/soundspot_master.env  avec  MASTER_RESOLVED=<ip_ou_nom>
#
# Seuil RSSI : -70 dBm. En-dessous → signal trop faible → préférer le mesh B.A.T.M.A.N.

source "${INSTALL_DIR:-/opt/soundspot}/soundspot.conf" 2>/dev/null || true

MASTER_IP=""
CURRENT_SSID=$(iwgetid -r 2>/dev/null || true)
RSSI_THRESHOLD=-70  # dBm — seuil en-dessous duquel le mesh est préféré

# Mesure du signal ZICMAMA si on y est connecté
ZICMAMA_RSSI=""
ZICMAMA_GOOD=false
if [ -n "${SPOT_NAME:-}" ] && [ "$CURRENT_SSID" = "$SPOT_NAME" ]; then
    ZICMAMA_RSSI=$(iw dev wlan0 link 2>/dev/null | awk '/signal:/{print $2}')
    _RSSI_INT="${ZICMAMA_RSSI%.*}"  # retire la décimale si présente
    # -65 > -70 : signal acceptable ; -80 < -70 : signal trop faible
    if [ -n "$_RSSI_INT" ] && [ "$_RSSI_INT" -ge "$RSSI_THRESHOLD" ] 2>/dev/null; then
        ZICMAMA_GOOD=true
    fi
fi

# 0. ZICMAMA avec signal suffisant — chemin direct le plus simple
if [ "$ZICMAMA_GOOD" = "true" ]; then
    MASTER_IP=$(ip route 2>/dev/null | awk '/default/{print $3; exit}')
    logger -t find_master "ZICMAMA RSSI=${ZICMAMA_RSSI} dBm ≥ ${RSSI_THRESHOLD} → AP directe ${MASTER_IP}"
fi

# 1. Mesh B.A.T.M.A.N. — signal ZICMAMA faible/absent ET bat0 actif
if [ -z "$MASTER_IP" ] && \
   ip link show bat0 >/dev/null 2>&1 && ping -c1 -W1 10.200.0.1 >/dev/null 2>&1; then
    MASTER_IP="10.200.0.1"
    if [ -n "$ZICMAMA_RSSI" ]; then
        logger -t find_master "ZICMAMA RSSI=${ZICMAMA_RSSI} dBm < ${RSSI_THRESHOLD} → Mesh bat0"
    else
        logger -t find_master "ZICMAMA absent → Mesh bat0 (10.200.0.1)"
    fi
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
