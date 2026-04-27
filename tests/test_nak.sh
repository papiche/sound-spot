#!/bin/bash
# =======================================================================
# test/test_nak.sh — Tests des commandes nak sur SoundSpot
# =======================================================================

# Couleurs
G='\033[0;32m'; R='\033[0;31m'; C='\033[0;36m'; N='\033[0m'

# Vérification présence de nak
if ! command -v nak &>/dev/null; then
    echo -e "${R}❌ L'outil 'nak' n'est pas installé.${N}"
    exit 1
fi
[ -f /opt/soundspot/soundspot.conf ] && source /opt/soundspot/soundspot.conf
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)

KEY_FILE="${USER_HOME}/.zen/game/secret.nostr"
if [ ! -f "$KEY_FILE" ]; then
    echo -e "${R}❌ Clef ${KEY_FILE} introuvable. Picoport n'est pas initialisé.${N}"
    exit 1
fi

# Extraire le NSEC du fichier (format NSEC=nsec1...;)
NSEC=$(grep -oP '(?<=NSEC=)[^;\s]+' "$KEY_FILE" | head -1)

echo -e "${C}═══ 1. Test d'envoi d'un Kind 1 (Message Public) ═══${N}"
MSG="Bonjour ! Test d'envoi via nak depuis le nœud SoundSpot[$(date +%H:%M:%S)]"
echo -e "Envoi sur wss://relay.copylaradio.com..."

# nak event génère, signe et publie. On récupère le JSON et on extrait l'ID avec jq
EVENT_JSON=$(nak event -c "$MSG" -k 1 --sec "$NSEC" wss://relay.copylaradio.com 2>/dev/null)
EID=$(echo "$EVENT_JSON" | jq -r '.id // empty')

if [ -n "$EID" ]; then
    echo -e "${G}✅ Succès ! Event ID : $EID${N}"
else
    echo -e "${R}❌ Échec de la publication Kind 1${N}"
fi

echo -e "\n${C}═══ 2. Test d'écriture d'un Kind 9 (Commande de flotte) ═══${N}"
PAYLOAD='{"cmd":"ping", "info":"test via nak"}'
RELAY_LOCAL="ws://127.0.0.1:9999"

echo "Publication d'une commande fantôme sur le relay local ($RELAY_LOCAL)..."
nak event -c "$PAYLOAD" -k 9 --sec "$NSEC" "$RELAY_LOCAL" >/dev/null
echo -e "${G}✅ Kind 9 posté.${N}"

echo -e "\n${C}═══ 3. Test de lecture (Derniers Kind 9 de la flotte) ═══${N}"
echo "Interrogation du relay local pour les 2 dernières commandes de flotte :"

# nak req permet de faire une requête de filtre Nostr standard :
nak req -k 9 -l 2 "$RELAY_LOCAL"

echo -e "\n${G}✅ Tests terminés.${N}"