#!/bin/bash
# =======================================================================
# test/test_nak.sh — Tests des commandes nak sur SoundSpot
# =======================================================================

# Couleurs
G='\033[0;32m'; R='\033[0;31m'; C='\033[0;36m'; N='\033[0m'

if ! command -v nak &>/dev/null; then
    echo -e "${R}❌ L'outil 'nak' n'est pas installé.${N}"
    exit 1
fi

[ -f /opt/soundspot/soundspot.conf ] && source /opt/soundspot/soundspot.conf
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)

KEY_FILE="${USER_HOME}/.zen/game/secret.nostr"
if [ ! -f "$KEY_FILE" ]; then
    echo -e "${R}❌ Clef ${KEY_FILE} introuvable. Picoport non initialisé.${N}"
    exit 1
fi

NSEC=$(grep -oP '(?<=NSEC=)[^;\s]+' "$KEY_FILE" | head -1)

echo -e "${C}═══ 1. Test d'envoi d'un Kind 1 (Global) ═══${N}"
MSG="Bonjour ! Test nak depuis le nœud SoundSpot [$(date +%H:%M:%S)]"

# On retire le >/dev/null pour que vous voyiez les erreurs s'il y en a
EVENT_JSON=$(nak event -c "$MSG" -k 1 --sec "$NSEC" wss://relay.copylaradio.com 2>&1)

if [ $? -eq 0 ]; then
    EID=$(echo "$EVENT_JSON" | grep -oP '(?<="id": ")[^"]+' | head -1)
    echo -e "${G}✅ Succès ! Event ID : $EID${N}"
else
    echo -e "${R}❌ Échec de la publication Kind 1${N}"
    echo -e "Détails de l'erreur : $EVENT_JSON"
fi

echo -e "\n${C}═══ 2. Test d'écriture d'un Kind 9 (Flotte locale) ═══${N}"
PAYLOAD='{"cmd":"ping", "info":"test de ping flotte"}'

# PORT 9999 = Le relais local géré par soundspot-fleet-relay.service
RELAY_LOCAL="ws://127.0.0.1:9999"

echo "Publication d'une commande de flotte sur $RELAY_LOCAL..."

# On capture la sortie et le code d'erreur de nak
RES_KIND9=$(nak event -c "$PAYLOAD" -k 9 --sec "$NSEC" "$RELAY_LOCAL" 2>&1)

if [ $? -eq 0 ]; then
    echo -e "${G}✅ Kind 9 posté avec succès sur le relais de flotte local.${N}"
else
    echo -e "${R}❌ Échec de la publication Kind 9 sur le relais local.${N}"
    echo -e "Détails de l'erreur nak :\n$RES_KIND9"
    echo -e "${Y}💡 Astuce: Vérifiez que le service tourne : sudo systemctl status soundspot-fleet-relay${N}"
fi

echo -e "\n${C}═══ Fin des tests ═══${N}"