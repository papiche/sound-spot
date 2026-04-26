#!/bin/bash
set -e

# Outils Astroport.ONE
ASTRO_TOOLS="$HOME/.zen/Astroport.ONE/tools"
[ -f "$ASTRO_TOOLS/my.sh" ] || { echo "❌ Astroport.ONE introuvable dans $ASTRO_TOOLS"; exit 1; }
set +e ## Certaines variables non initialisées (Astroport.ONE light_installer)
source "$ASTRO_TOOLS/my.sh"
set -e

source "$HOME/.astro/bin/activate"

echo "🔐 [Picoport] Initialisation de l'identité Y-Level..."

mkdir -p ~/.ssh ~/.zen/game

# 1. SSH Key
if [[ ! -s ~/.ssh/id_ed25519 ]]; then
    echo "▶ Génération de la clé SSH..."
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "pico-$(hostname)@qo-op.com"
fi

# 2. Secrets déterministes depuis le hash SHA-512 de la clé SSH privée
SSHASH=$(cat ~/.ssh/id_ed25519 | sha512sum | cut -d ' ' -f 1)
SECRET1=$(echo "$SSHASH" | cut -c 1-64)
SECRET2=$(echo "$SSHASH" | cut -c 65-128)

# 3. secret.june — SALT/PEPPER persistants (source de vérité pour toute re-dérivation)
echo "SALT=$SECRET1; PEPPER=$SECRET2" > ~/.zen/game/secret.june
chmod 600 ~/.zen/game/secret.june

# 4. secret.ipns — clé IPFS au format PEM (pivot de toute la chaîne)
python3 "$ASTRO_TOOLS/keygen" -t ipfs -o ~/.zen/game/secret.ipns "$SECRET1" "$SECRET2"
chmod 600 ~/.zen/game/secret.ipns

# 5. secret.NODE.dunikey — portefeuille Ğ1 du nœud (dérivé de secret.ipns)
python3 "$ASTRO_TOOLS/keygen" -i ~/.zen/game/secret.ipns -t duniter -o ~/.zen/game/secret.NODE.dunikey
chmod 600 ~/.zen/game/secret.NODE.dunikey

# 6. Transmutation IPFS — PeerID/PrivKey dérivés de secret.ipns (cohérence Ylevel.sh)
echo "🧬 Transmutation IPFS..."
if [[ -f ~/.ipfs/config ]]; then
    PEER_ID=$(python3 "$ASTRO_TOOLS/keygen" -i ~/.zen/game/secret.ipns -t ipfs)
    PRIV_KEY=$(python3 "$ASTRO_TOOLS/keygen" -i ~/.zen/game/secret.ipns -t ipfs -s)
    jq ".Identity.PeerID=\"$PEER_ID\" | .Identity.PrivKey=\"$PRIV_KEY\"" \
        ~/.ipfs/config > ~/.ipfs/config.tmp \
        && mv ~/.ipfs/config.tmp ~/.ipfs/config
    echo "✅ PeerID synchronisé : $PEER_ID"
fi

# 7. Lien SSH public — requis par 12345.json (champ SSHPUB) et ssh_to_g1ipfs.py
[[ ! -L ~/.zen/game/id_ssh.pub ]] && ln -sf ~/.ssh/id_ed25519.pub ~/.zen/game/id_ssh.pub

G1PUB=$(grep 'pub:' ~/.zen/game/secret.NODE.dunikey | cut -d ' ' -f 2)
echo "🗝  NODEG1PUB : $G1PUB"
echo "🚀 Identité Y-Level initialisée."
