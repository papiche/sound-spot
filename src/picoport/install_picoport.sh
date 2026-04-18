#!/bin/bash
# =======================================================================
# Picoport — Micro-Astroport pour RPi Zero 2W (SoundSpot)
# Installe IPFS, socat, jq, configure le swarm UPlanet et le service.
# =======================================================================
set -e

INSTALL_DIR="/opt/soundspot/picoport"
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
# Récupération propre du HOME de l'utilisateur (évite les erreurs sudo -E)
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)

echo "=== 1. Installation des dépendances (socat, jq) ==="
_MISSING_PKGS=""
for _pkg in socat jq curl wget bc gnupg pinentry-curses python3-dev; do
    dpkg-query -W -f='${Status}' "$_pkg" 2>/dev/null | grep -q "ok installed" || _MISSING_PKGS="$_MISSING_PKGS $_pkg"
done
if [ -n "$_MISSING_PKGS" ]; then
    apt-get update -qq
    # shellcheck disable=SC2086
    apt-get install -y --no-install-recommends $_MISSING_PKGS
else
    echo "socat jq curl wget bc gnupg pinentry-curses python3-dev déjà installés — ignoré"
fi

echo "=== 2. Installation de Kubo (IPFS) ARM64 ==="
if ! command -v ipfs &>/dev/null; then
    cd /tmp
    wget -q --show-progress https://dist.ipfs.tech/kubo/v0.40.0/kubo_v0.40.0_linux-arm64.tar.gz
    tar -xzf kubo_v0.40.0_linux-arm64.tar.gz
    bash kubo/install.sh
    rm -rf kubo*
    echo "IPFS installé : $(ipfs --version)"
fi

echo "=== 2b. Installation de g1cli (paiements Ğ1 / ẑen) ARM64 ==="
# g1cli = CLI Duniter v2s (gcli-v2s). PAYforSURE.sh attend la commande 'gcli'.
# Téléchargement du binaire arm64 via l'API releases de git.duniter.org.
GCLI_VER="v0.8.0-g1-RC3"
_install_g1cli() {
    if command -v g1cli &>/dev/null; then
        echo "g1cli déjà installé : $(g1cli --version 2>/dev/null || echo 'ok')"
    else
        echo "▶ Résolution URL g1cli ${GCLI_VER} arm64 (git.duniter.org)..."
        local _api_url="https://git.duniter.org/api/v4/projects/clients%2Frust%2Fg1cli/releases/${GCLI_VER}"
        local _bin_url
        _bin_url=$(curl -sf --max-time 15 "$_api_url" 2>/dev/null \
            | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for l in data.get('assets', {}).get('links', []):
        name = l.get('name', '').lower()
        if 'arm64' in name and 'binary' in name:
            print(l['url']); break
except: pass
" 2>/dev/null)

        if [ -n "$_bin_url" ]; then
            wget -q --show-progress "$_bin_url" -O /tmp/g1cli_dl \
                && install -m 755 /tmp/g1cli_dl /usr/local/bin/g1cli \
                && rm -f /tmp/g1cli_dl \
                && echo "✅ g1cli installé : $(g1cli --version 2>/dev/null || echo 'ok')" \
                || { echo "⚠ Téléchargement g1cli échoué"; return 1; }
        else
            echo "⚠ g1cli ${GCLI_VER} : URL non résolue (réseau ?)"
            echo "  → Compiler depuis sources : cd ~/gcli-v2s && cargo build --release"
            return 1
        fi
    fi
    # Symlink gcli → g1cli (PAYforSURE.sh + my.sh utilisent la commande 'gcli')
    local _bin
    _bin=$(command -v g1cli 2>/dev/null || true)
    if [ -n "$_bin" ] && [ ! -e /usr/local/bin/gcli ]; then
        ln -sf "$_bin" /usr/local/bin/gcli
        echo "▶ Symlink gcli → g1cli créé"
    fi
}
_install_g1cli || true   # optionnel : PAYforSURE.sh dégrade gracieusement si absent

echo "=== 3. Mise en place des Bootstraps UPlanet ==="
mkdir -p "$INSTALL_DIR"
cat > "$INSTALL_DIR/A_boostrap_nodes.txt" << 'EOF'
# UPlanet Swarm Bootstrap Stations # ORIGIN DOMAIN - bloc 0.0
# https://ipfs.copylaradio.com ipfs.copylaradio.com
#################################################################
# astroport.libra.copylaradio.com # 
/ip4/149.102.158.67/tcp/4001/p2p/12D3KooWM6jEPqDEgnjmTjnB4vCBkGoQp7rtS5m9mpikSHoDD581

### UPLanet ORIGIN : OFFICIAL ASTROPORT.ONE RELAYS #######################
/dnsaddr/ipfs.sagittarius.copylaradio.com/p2p/12D3KooWAvWWWtscBjFwybk8WSr2tmiwDtvNzJEh8vwyFntbpxPX
/dnsaddr/ipfs.guenoel.fr/p2p/12D3KooWJRBjm6RHfse7oTMkSsvBk7XNKTTWQozoDZAFLSPRKPXt
EOF

echo "=== 4. Initialisation IPFS (Isolation UPlanet) pour $SOUNDSPOT_USER ==="
# On définit IPFS_PATH explicitement pour pointer vers le home de l'utilisateur
export IPFS_PATH="$USER_HOME/.ipfs"

sudo -u "$SOUNDSPOT_USER" bash -c "
    export IPFS_PATH='$IPFS_PATH'
    if [ ! -d \"\$IPFS_PATH\" ]; then
        ipfs init --profile=lowpower
        
        # 1. Purge des nœuds publics
        ipfs bootstrap rm --all
        
        # 2. Ajout exclusif de la constellation UPlanet
        grep -v '^#' '$INSTALL_DIR/A_boostrap_nodes.txt' | grep -v '^[[:space:]]*$' | while read -r node; do
            ipfs bootstrap add \"\$node\"
        done
        
        # 3. Optimisation extrême pour RPi Zero (Low RAM)
        ipfs config Swarm.ConnMgr.HighWater --json 50
        ipfs config Swarm.ConnMgr.LowWater --json 20
        ipfs config Datastore.StorageMax '2GB'
        ipfs config Routing.Type 'dhtclient'
    fi
    
    # 4. Swarm Key UPlanet ORIGIN
    cat > \"\$IPFS_PATH/swarm.key\" <<EOF
/key/swarm/psk/1.0.0/
/base16/
0000000000000000000000000000000000000000000000000000000000000000
EOF
    chmod 600 \"\$IPFS_PATH/swarm.key\"
"

echo "=== 4b. Configuration de l'identité déterministe (Y-Level) ==="
# On s'assure que le script de clé s'exécute aussi avec le bon IPFS_PATH
sudo -u "$SOUNDSPOT_USER" IPFS_PATH="$IPFS_PATH" bash "$INSTALL_DIR/picoport_init_keys.sh"

echo "=== 5. Mise en place de la station Picoport ==="
cp "$(dirname "$0")/picoport.sh" "$INSTALL_DIR/picoport.sh"
chmod +x "$INSTALL_DIR/picoport.sh"

echo "=== 5b. Mise à jour du .bashrc ==="
# On lance l'installateur d'alias en tant qu'utilisateur pi pour modifier son .bashrc
sudo -u "$SOUNDSPOT_USER" bash "$INSTALL_DIR/pico_bashrc_manager.sh" install

echo "=== 6. Service Systemd Picoport ==="
cat > /etc/systemd/system/picoport.service <<EOF
[Unit]
Description=Picoport (Micro-Astroport Node)
After=network-online.target

[Service]
Type=simple
User=$SOUNDSPOT_USER
Environment="IPFS_PATH=$USER_HOME/.ipfs"
ExecStart=$INSTALL_DIR/picoport.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now picoport
echo "✅ Picoport installé et démarré !"