#!/bin/bash
SPOT_NAME="ZICMAMA"
SPOT_IP="192.168.10.1"
SNAP_PORT="1704"
ICECAST_PORT="8111"
ICECAST_PASS="0penS0urce!"

G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; W='\033[1;37m'; R='\033[0;31m'; N='\033[0m'

clear
echo -e "\n${C}  ZICMAMA SoundSpot — Session DJ${N}\n"

# ── 1. Connexion WiFi ───────────────────────────────────────
CURRENT=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2 || echo "")

if [ "$CURRENT" != "$SPOT_NAME" ]; then
    log "Connexion à ${W}${SPOT_NAME}${N}..."
    nmcli dev wifi connect "$SPOT_NAME" || {
        echo -e "${R}✗${N} Échec WiFi. Vérifie que le SoundSpot est allumé."; exit 1
    }
    echo -e "   Attente stabilisation réseau (3s)..."
    sleep 3
fi
echo -e "${G}▶${N} WiFi : ${C}${SPOT_NAME}${N}"

# ── 2. Test de Joignabilité (Boucle de 15s) ─────────────────
echo -ne "${G}▶${N} Attente du RPi (${SPOT_IP}) "
CONNECTED=false
for i in {1..15}; do
    if ping -c1 -W1 "$SPOT_IP" &>/dev/null; then
        # On teste aussi si le port Snapcast répond
        if (echo > /dev/tcp/$SPOT_IP/$SNAP_PORT) >/dev/null 2>&1; then
            CONNECTED=true
            echo -e " ${G}[PRÊT]${N}"
            break
        fi
    fi
    echo -ne "."
    sleep 1
done

if [ "$CONNECTED" = false ]; then
    echo -e "\n${R}✗${N} Impossible de joindre l'audio sur ${SPOT_IP}."
    echo -e "   Note: Si tu as un câble Ethernet branché, débranche-le ou désactive-le."
    exit 1
fi

# ── 3. Lancement Audio ──────────────────────────────────────
pkill snapclient 2>/dev/null || true
snapclient -h "$SPOT_IP" -p "$SNAP_PORT" > /dev/null 2>&1 &
SPID=$!
trap "kill $SPID 2>/dev/null; exit 0" INT TERM

echo -e "${G}▶${N} Snapclient (retour casque) actif [PID $SPID]"
echo -e "${Y}   INFO : Configure Mixxx sur Icecast2 -> ${SPOT_IP}:${ICECAST_PORT}${N}"

mixxx
kill "$SPID" 2>/dev/null
