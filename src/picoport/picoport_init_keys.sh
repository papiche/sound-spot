#!/bin/bash
################################################################################
# picoport_init_keys.sh — Initialisation cryptographique du Picoport
# Respecte le protocole Y-Level (SSH == IPFS) et génère le MULTIPASS Picoport.
################################################################################
set -e

MY_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# On remonte pour trouver les outils Astroport
ASTRO_TOOLS="$HOME/.zen/Astoport.ONE/tools"
source "$ASTRO_TOOLS/my.sh"



INSTALL_DIR="/opt/soundspot/picoport"
mkdir -p "$INSTALL_DIR/keys"

echo "🔐 [Picoport] Initialisation de l'identité Y-Level..."

# 1. S'assurer qu'une clé SSH existe (id_ed25519)
if [[ ! -s ~/.ssh/id_ed25519 ]]; then
    echo "🐣 Génération de la clé SSH initiale..."
    GPS_RAW=$(my_LatLon 2>/dev/null || echo "fr 0.00 0.00")
    # Formatage du suffixe GPS (ex: fr_43.60_1.44)
    GPS_SUFFIX=$(echo $GPS_RAW | awk '{print tolower($1)"_"$2"_"$3}' | sed 's/ /_/g')
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "support+$(hostname)_${GPS_SUFFIX}@qo-op.com"
fi

# 2. Calcul des secrets déterministes (Logique Y-Level)
# On utilise le hash de la clé privée SSH comme SEED
SSHASH=$(sudo cat ~/.ssh/id_ed25519 | sha512sum | cut -d ' ' -f 1)
SECRET1=$(echo "$SSHASH" | cut -c 1-64)
SECRET2=$(echo "$SSHASH" | cut -c 65-128)

# Sauvegarde des secrets pour le Picoport
echo "SALT=$SECRET1; PEPPER=$SECRET2" > "$INSTALL_DIR/keys/secret.picoport"
chmod 600 "$INSTALL_DIR/keys/secret.picoport"

# 3. Génération du PeerID IPFS correspondant (Transmutation)
echo "🧬 Transmutation IPFS vers Y-Level..."
PEER_ID=$("$ASTRO_TOOLS/keygen" -t ipfs "$SECRET1" "$SECRET2")
PRIV_KEY=$("$ASTRO_TOOLS/keygen" -t ipfs -s "$SECRET1" "$SECRET2")

# Mise à jour de la config IPFS pour que le Picoport "devienne" sa clé SSH
if [[ -f ~/.ipfs/config ]]; then
    cp ~/.ipfs/config ~/.ipfs/config.bak
    jq ".Identity.PeerID=\"$PEER_ID\" | .Identity.PrivKey=\"$PRIV_KEY\"" ~/.ipfs/config > ~/.ipfs/config.tmp \
    && mv ~/.ipfs/config.tmp ~/.ipfs/config
    echo "✅ IPFS PeerID synchronisé avec SSH : $PEER_ID"
fi

# 4. Génération du MULTIPASS NOSTR du Picoport
# (Permet de publier son état Kind 0, Kind 30311 et recevoir des likes Ẑen)
PICO_EMAIL="picoport+$(hostname | tr '-' '_')@$(hostname -d 2>/dev/null || echo 'local')"
echo "🎫 Création du MULTIPASS Picoport : $PICO_EMAIL"

# On utilise make_NOSTRCARD.sh avec les secrets déterministes
# NOMAIL=1 pour éviter l'envoi d'email pendant le boot/install
export NOMAIL=1
bash "$ASTRO_TOOLS/../make_NOSTRCARD.sh" "$PICO_EMAIL" "fr" "0.00" "0.00" "$SECRET1" "$SECRET2"

# 5. Publication de la Swarm Key (ORIGIN par défaut)
if [[ ! -s ~/.ipfs/swarm.key ]]; then
    cat > ~/.ipfs/swarm.key <<EOF
/key/swarm/psk/1.0.0/
/base16/
0000000000000000000000000000000000000000000000000000000000000000
EOF
    chmod 600 ~/.ipfs/swarm.key
fi

echo "🚀 Identity setup complete for Picoport."