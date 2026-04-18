#!/bin/bash
# =======================================================================
# Picoport — Micro-Astroport pour RPi Zero 2W (SoundSpot)
# Installe IPFS, socat, jq, configure le swarm UPlanet et le service.
# =======================================================================
set -e

INSTALL_DIR="/opt/soundspot/picoport"
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"

echo "=== 1. Installation des dépendances (socat, jq) ==="
apt-get update -qq
apt-get install -y --no-install-recommends socat jq curl wget

echo "=== 2. Installation de Kubo (IPFS) ARM64 ==="
if ! command -v ipfs &>/dev/null; then
    cd /tmp
    wget -q --show-progress https://dist.ipfs.tech/kubo/v0.40.0/kubo_v0.40.0_linux-arm64.tar.gz
    tar -xzf kubo_v0.40.0_linux-arm64.tar.gz
    bash kubo/install.sh
    rm -rf kubo*
    echo "IPFS installé : $(ipfs --version)"
fi

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
# On passe INSTALL_DIR en variable d'environnement pour le sudo
sudo -E -u "$SOUNDSPOT_USER" bash -c '
    export IPFS_PATH="$HOME/.ipfs"
    if [ ! -d "$IPFS_PATH" ]; then
        ipfs init --profile=lowpower
        
        # 1. Purge des nœuds publics
        ipfs bootstrap rm --all
        
        # 2. Ajout exclusif de la constellation UPlanet
        grep -v "^#" "'$INSTALL_DIR'/A_boostrap_nodes.txt" | grep -v "^$" | while read -r node; do
            ipfs bootstrap add "$node"
        done
        
        # 3. Optimisation extrême pour RPi Zero (Low RAM)
        ipfs config Swarm.ConnMgr.HighWater --json 50
        ipfs config Swarm.ConnMgr.LowWater --json 20
        ipfs config Datastore.StorageMax "2GB"
        ipfs config Routing.Type "dhtclient"
    fi
    
    # 4. Swarm Key UPlanet ORIGIN (0000...)
    cat > "$IPFS_PATH/swarm.key" <<EOF
/key/swarm/psk/1.0.0/
/base16/
0000000000000000000000000000000000000000000000000000000000000000
EOF
    chmod 600 "$IPFS_PATH/swarm.key"
'

echo "=== 4b. Configuration de l'identité déterministe (Y-Level) ==="
bash "$INSTALL_DIR/picoport_init_keys.sh"

echo "=== 5. Mise en place de la boucle Picoport ==="
cp "$(dirname "$0")/picoport.sh" "$INSTALL_DIR/picoport.sh"
chmod +x "$INSTALL_DIR/picoport.sh"

echo "=== 6. Service Systemd Picoport ==="
cat > /etc/systemd/system/picoport.service <<EOF
[Unit]
Description=Picoport (Micro-Astroport Node)
After=network-online.target

[Service]
Type=simple
User=$SOUNDSPOT_USER
Environment="IPFS_PATH=/home/$SOUNDSPOT_USER/.ipfs"
ExecStart=$INSTALL_DIR/picoport.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now picoport
echo "✅ Picoport installé et démarré !"