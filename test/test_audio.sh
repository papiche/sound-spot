#!/bin/bash
# ================================================================
#  test_audio.sh — Test de la sortie audio SoundSpot
#  Permet de vérifier si l'enceinte Bluetooth crache du son.
# ================================================================

# On se met en contexte root ou sudoer[ "$(id -u)" -eq 0 ] || exec sudo bash "${BASH_SOURCE[0]}" "$@"

CONF="/opt/soundspot/soundspot.conf"
[ -f "$CONF" ] && source "$CONF"

SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_ID=$(id -u "$SOUNDSPOT_USER" 2>/dev/null || echo 1000)

export XDG_RUNTIME_DIR="/run/user/${USER_ID}"
export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"

TEST_FILE="/opt/soundspot/welcome.wav"

if [ ! -f "$TEST_FILE" ]; then
    echo "Fichier $TEST_FILE introuvable. Lecture d'un bip système..."
    TEST_FILE="/usr/share/sounds/alsa/Front_Center.wav"
fi

echo -e "\n▶ Vérification de l'état PipeWire..."
sudo -u "$SOUNDSPOT_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" wpctl status | grep -iE "bluez|bluetooth|sink"

echo -e "\n▶ Lecture du son de test sur le sink actif..."
if sudo -u "$SOUNDSPOT_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" pw-play "$TEST_FILE" 2>/dev/null; then
    echo -e "✓ Lecture réussie (via pw-play)."
elif sudo -u "$SOUNDSPOT_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" paplay "$TEST_FILE" 2>/dev/null; then
    echo -e "✓ Lecture réussie (via paplay)."
else
    echo -e "✗ Erreur : Impossible de lire le son. Vérifiez que l'enceinte est connectée et que WirePlumber tourne."
    echo -e "  Essayez : sudo journalctl -u wireplumber --user -n 20"
fi