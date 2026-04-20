#!/bin/bash
set -e

# Outils Astroport.ONE
ASTRO_TOOLS="$HOME/.zen/Astroport.ONE/tools"
[ -f "$ASTRO_TOOLS/my.sh" ] || { echo "❌ Astroport.ONE introuvable dans $ASTRO_TOOLS"; exit 1; }
source "$ASTRO_TOOLS/my.sh"

# On utilise le venv déjà préparé
source "$HOME/.astro/bin/activate"

echo "🔐 [Picoport] Initialisation de l'identité Y-Level..."

# 1. SSH Key
mkdir -p ~/.ssh
if [[ ! -s ~/.ssh/id_ed25519 ]]; then
    echo "▶ Génération de la clé SSH..."
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "pico-$(hostname)@uplanet"
fi

# 2. Secrets déterministes
SSHASH=$(cat ~/.ssh/id_ed25519 | sha512sum | cut -d ' ' -f 1)
SECRET1=$(echo "$SSHASH" | cut -c 1-64)
SECRET2=$(echo "$SSHASH" | cut -c 65-128)

# 3. Transmutation IPFS
echo "🧬 Transmutation IPFS..."
# Utilisation du chemin absolu pour keygen
PEER_ID=$(python3 "$ASTRO_TOOLS/keygen" -t ipfs "$SECRET1" "$SECRET2")
PRIV_KEY=$(python3 "$ASTRO_TOOLS/keygen" -t ipfs -s "$SECRET1" "$SECRET2")

if [[ -f ~/.ipfs/config ]]; then
    # Mise à jour silencieuse du PeerID
    jq ".Identity.PeerID=\"$PEER_ID\" | .Identity.PrivKey=\"$PRIV_KEY\"" ~/.ipfs/config > ~/.ipfs/config.tmp \
    && mv ~/.ipfs/config.tmp ~/.ipfs/config
    echo "✅ PeerID synchronisé : $PEER_ID"
fi

# 4. MULTIPASS Nostr (Version allégée)
PICO_EMAIL="pico-$(hostname)@$(hostname).local"
echo "🎫 Création du MULTIPASS : $PICO_EMAIL"
export NOMAIL=1
bash "$ASTRO_TOOLS/make_NOSTRCARD.sh" "$PICO_EMAIL" "fr" "0.00" "0.00" "$SECRET1" "$SECRET2"

echo "🚀 Identity setup complete."