#!/bin/bash
################################################################################
# picoport_init_keys.sh — Initialisation cryptographique du Picoport
# Respecte le protocole Y-Level (SSH == IPFS) et génère le MULTIPASS Picoport.
################################################################################
set -e

MY_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Outils Astroport.ONE (clonés par install_astroport_light.sh)
ASTRO_TOOLS="$HOME/.zen/Astroport.ONE/tools"
[ -f "$ASTRO_TOOLS/my.sh" ] || { echo "Astroport.ONE introuvable — lancer install_astroport_light.sh d'abord"; exit 1; }
source "$ASTRO_TOOLS/my.sh"

# ── Venv Python ~/.astro/ (Astroport.ONE compatible) ─────────────
# Astroport.ONE est cloné sans install.sh — créer le venv si absent
if [ ! -s "$HOME/.astro/bin/activate" ]; then
    echo "🐍 Création du venv ~/.astro/ pour les tools Astroport.ONE..."
    python3 -m venv "$HOME/.astro" \
        || { echo "⚠ python3-venv manquant ? sudo apt-get install python3-venv"; exit 1; }
fi
source "$HOME/.astro/bin/activate"
# Packages complets requis par keygen (ipfs, nostr, g1, uDRIVE, paiements ẑen)
# Tous les imports sont top-level dans keygen → aucun ne peut manquer
_PYPACKAGES=(
    "base58:base58"          "cryptography:cryptography"  "duniterpy:duniterpy"
    "python-gnupg:gnupg"     "jwcrypto:jwcrypto"          "PyNaCl:nacl"
    "pynostr:pynostr"        "bech32:bech32"               "ecdsa:ecdsa"
    "pynentry:pynentry"      "websocket-client:websocket"  "requests:requests"
    "monero:monero"          "bitcoin:bitcoin"
    "scrypt:scrypt"
)
for _entry in "${_PYPACKAGES[@]}"; do
    _pip="${_entry%%:*}"; _mod="${_entry##*:}"
    python3 -c "import $_mod" 2>/dev/null \
        || pip install -q "$_pip" 2>/dev/null \
        || echo "⚠  pip install $_pip échoué (connexion ?)"
done

INSTALL_DIR="/opt/soundspot/picoport"
mkdir -p "$INSTALL_DIR/keys"

echo "🔐 [Picoport] Initialisation de l'identité Y-Level..."

# 1. S'assurer qu'une clé SSH existe (id_ed25519)
mkdir -p ~/.ssh
if [[ ! -s ~/.ssh/id_ed25519 ]]; then
    echo "🐣 Génération de la clé SSH initiale..."
    GPS_RAW=$(my_LatLon 2>/dev/null || echo "fr 0.00 0.00")
    # Formatage du suffixe GPS (ex: fr_43.60_1.44)
    GPS_SUFFIX=$(echo $GPS_RAW | awk '{print tolower($1)"_"$2"_"$3}' | sed 's/ /_/g')
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "support+$(hostname)_${GPS_SUFFIX}@qo-op.com"
fi

# 2. Calcul des secrets déterministes (Logique Y-Level)
# On utilise le hash de la clé privée SSH comme SEED
SSHASH=$(cat ~/.ssh/id_ed25519 | sha512sum | cut -d ' ' -f 1)
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

# 4. Génération du MULTIPASS NOSTinstall_soundspotR du Picoport
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