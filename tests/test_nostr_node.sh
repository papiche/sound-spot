#!/bin/bash
# test_nostr_node.sh — Validation des capacités Nostr du nœud

# Couleurs
G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; C='\033[0;36m'; N='\033[0m'

# Chargement config
[ -f /opt/soundspot/soundspot.conf ] && source /opt/soundspot/soundspot.conf
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
ASTRO_TOOLS="${USER_HOME}/.zen/Astroport.ONE/tools"
PYTHON="${USER_HOME}/.astro/bin/python3"
RELAY="ws://127.0.0.1:9999" # Relay local de flotte

echo -e "${C}═══ Test Nostr pour le nœud : $(hostname) ═══${N}"

# 1. Vérification des clefs
KEY_FILE="${USER_HOME}/.zen/game/secret.nostr"
if [ ! -f "$KEY_FILE" ]; then
    echo -e "${R}✗ Clef secret.nostr introuvable.${N}"
    exit 1
fi
source "$KEY_FILE"
echo -e "${G}✓ Clef détectée : ${N}${NPUB}"

# 2. Test Envoi Kind 1 (Message Public)
echo -e "\n${Y}▶ Test 1 : Envoi Kind 1 (Message de vie)...${N}"
MSG="Signal de test depuis le nœud SoundSpot [$(date)]"
RESULT=$($PYTHON "${ASTRO_TOOLS}/nostr_send_note.py" \
    --keyfile "$KEY_FILE" \
    --content "$MSG" \
    --kind 1 \
    --relays "wss://relay.copylaradio.com" --json 2>/dev/null)

if echo "$RESULT" | grep -q "event_id"; then
    EID=$(echo "$RESULT" | jq -r .event_id)
    echo -e "${G}✓ Message envoyé ! ID: ${EID}${N}"
else
    echo -e "${R}✗ Échec de l'envoi Kind 1.${N}"
fi

# 3. Test Écriture Kind 9 (Commande de flotte)
echo -e "\n${Y}▶ Test 2 : Émission Kind 9 (Commande Fantôme)...${N}"
# On envoie une commande bidon "ping" qui ne fera rien mais teste le tunnel
CMD_PAYLOAD='{"cmd":"ping","msg":"test_internal"}'
RESULT_K9=$($PYTHON "${ASTRO_TOOLS}/nostr_send_note.py" \
    --keyfile "$KEY_FILE" \
    --content "$CMD_PAYLOAD" \
    --kind 9 \
    --relays "$RELAY" --json 2>/dev/null)

if echo "$RESULT_K9" | grep -q "event_id"; then
    echo -e "${G}✓ Commande Kind 9 publiée sur le relay local.${N}"
else
    echo -e "${R}✗ Relay local ($RELAY) injoignable ou rejette le Kind 9.${N}"
fi

# 4. Test Lecture via 'nak' (si disponible) ou python simple
echo -e "\n${Y}▶ Test 3 : Écoute du relay de flotte (Kind 9)...${N}"
echo -e "${C}En attente d'un événement (Ctrl+C pour stopper)...${N}"

$PYTHON - <<EOF
import asyncio, json, websockets, sys

async def listen():
    try:
        async with websockets.connect("$RELAY", timeout=5) as ws:
            await ws.send(json.dumps(["REQ", "test_sub", {"kinds": [9], "limit": 1}]))
            # On attend juste un message
            reply = await ws.recv()
            print(f"\n${G}✓ Événement reçu sur la flotte :${N}")
            print(reply)
    except Exception as e:
        print(f"\n${R}✗ Erreur d'écoute : {e}${N}")

asyncio.run(listen())
EOF

echo -e "\n${C}═══ Fin des tests ═══${N}"