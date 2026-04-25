#!/bin/bash
# fleet_commander.sh — Commande la flotte SoundSpot via NOSTR kind 9 (éphémère)
# Doit être exécuté sur le Maître (accès au relay local + clé Amiral).
#
# Usage :
#   bash fleet_commander.sh shutdown [delay_s=30]
#   bash fleet_commander.sh restart_client
#   bash fleet_commander.sh announce "Texte de l'annonce"

INSTALL_DIR="${INSTALL_DIR:-/opt/soundspot}"
source "$INSTALL_DIR/soundspot.conf" 2>/dev/null || true

SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
ASTRO_TOOLS="${USER_HOME}/.zen/Astroport.ONE/tools"
ASTRO_VENV="${USER_HOME}/.astro/bin/activate"

AMIRAL_KEYFILE="${INSTALL_DIR}/amiral.nostr"
NOSTR_SEND="${ASTRO_TOOLS}/nostr_send_note.py"
RELAY="ws://127.0.0.1:9999"
CMD="${1:-help}"
shift || true

# ── Vérifications ─────────────────────────────────────────────
if [ ! -f "$AMIRAL_KEYFILE" ]; then
    echo "Clé Amiral absente — exécutez d'abord :" >&2
    echo "  sudo bash ${INSTALL_DIR}/backend/system/amiral_keygen.sh" >&2
    exit 1
fi

if [ ! -f "$NOSTR_SEND" ]; then
    echo "nostr_send_note.py introuvable dans ${ASTRO_TOOLS}" >&2
    exit 1
fi

[ -f "$ASTRO_VENV" ] && source "$ASTRO_VENV" 2>/dev/null || true

# ── Construction du payload ────────────────────────────────────
case "$CMD" in
    shutdown)
        DELAY="${1:-30}"
        PAYLOAD=$(printf '{"cmd":"shutdown","spot":"%s","delay_s":%s}' "${SPOT_NAME:-SoundSpot}" "$DELAY")
        ;;
    restart_client)
        PAYLOAD=$(printf '{"cmd":"restart_client","spot":"%s"}' "${SPOT_NAME:-SoundSpot}")
        ;;
    announce)
        TEXT="$*"
        [ -z "$TEXT" ] && { echo "Usage: fleet_commander.sh announce <texte>" >&2; exit 1; }
        PAYLOAD=$(printf '{"cmd":"announce","spot":"%s","text":"%s"}' "${SPOT_NAME:-SoundSpot}" "$TEXT")
        ;;
    *)
        echo "Usage: fleet_commander.sh <shutdown [delay_s]|restart_client|announce <texte>>"
        exit 0
        ;;
esac

# ── Envoi NOSTR kind 9 ────────────────────────────────────────
python3 "$NOSTR_SEND" \
    --keyfile "$AMIRAL_KEYFILE" \
    --kind 9 \
    --content "$PAYLOAD" \
    --relays "$RELAY" \
    2>/dev/null \
    && echo "✓ Commande '${CMD}' envoyée à la flotte (${RELAY})" \
    || { echo "✗ Erreur envoi NOSTR — relay actif ?" >&2; exit 1; }
