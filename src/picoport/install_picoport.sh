#!/bin/bash
# =======================================================================
# Picoport — Astroport.ONE pour RPi Zero 2W (SoundSpot)
# Installe IPFS, socat, jq, configure pour joindre sa constellation UPlanet.
# =======================================================================
set -e
[ "$(id -u)" -eq 0 ] || { echo "❌ Veuillez lancer ce script en root (sudo bash ...)"; exit 1; }
INSTALL_DIR="/opt/soundspot/picoport"
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
# Architecture cible — amd64 (PC) ou arm64 (RPi 4/5/Zero 2W)
PICO_ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
# Récupération propre du HOME de l'utilisateur (évite les erreurs sudo -E)
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)

echo "=== 1. Installation des dépendances ==="
_MISSING_PKGS=""
for _pkg in socat jq curl wget bc gnupg pinentry-curses python3-dev libffi-dev libssl-dev prometheus-node-exporter; do
    dpkg-query -W -f='${Status}' "$_pkg" 2>/dev/null | grep -q "ok installed" || _MISSING_PKGS="$_MISSING_PKGS $_pkg"
done
if [ -n "$_MISSING_PKGS" ]; then
    apt-get update -qq
    # shellcheck disable=SC2086
    # prometheus-node-exporter = sonde légère :9100 (heartbox) — PAS le serveur Prometheus
    apt-get install -y --no-install-recommends $_MISSING_PKGS
else
    echo "Dépendances déjà installées — ignoré"
fi

echo "=== 2. Installation de Kubo (IPFS) — ${PICO_ARCH} ==="
if ! command -v ipfs &>/dev/null; then
    cd /tmp
    wget -q --show-progress "https://dist.ipfs.tech/kubo/v0.40.0/kubo_v0.40.0_linux-${PICO_ARCH}.tar.gz"
    tar -xzf "kubo_v0.40.0_linux-${PICO_ARCH}.tar.gz"
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
    arch = '${PICO_ARCH}'
    for l in data.get('assets', {}).get('links', []):
        name = l.get('name', '').lower()
        if arch in name and 'binary' in name:
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

echo "=== 2c. Installation de nak (CLI Nostr) ==="
bash "$(dirname "$0")/install_nak.sh"

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
        ipfs config --json Swarm.ConnMgr.HighWater 50
        ipfs config --json Swarm.ConnMgr.LowWater 20
        ipfs config Datastore.StorageMax '2GB'
        ipfs config Routing.Type 'dhtclient'
        ipfs config --bool AutoConf.Enabled false
        ipfs config --json Experimental.Libp2pStreamMounting true
        ipfs config --json Experimental.FilestoreEnabled true
        ipfs config Logging.Level error
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
chown -R "$SOUNDSPOT_USER:$SOUNDSPOT_USER" "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/picoport_init_keys.sh"
sudo -u "$SOUNDSPOT_USER" IPFS_PATH="$USER_HOME/.ipfs" HOME="$USER_HOME" bash "$INSTALL_DIR/picoport_init_keys.sh"

echo "=== 5. Mise en place de la station Picoport ==="
# PROTECTION CONTRE L'AUTO-COPIE SI ON S'EXÉCUTE DÉJÀ DANS LE DOSSIER DE DESTINATION
if [ "$(cd "$(dirname "$0")" && pwd)" != "$INSTALL_DIR" ]; then
    cp "$(dirname "$0")/picoport.sh" "$INSTALL_DIR/picoport.sh"
fi
chmod +x "$INSTALL_DIR/picoport.sh"

echo "=== 5b. Mise à jour du .bashrc ==="
# On lance l'installateur d'alias en tant qu'utilisateur pi pour modifier son .bashrc
sudo -u "$SOUNDSPOT_USER" bash "$INSTALL_DIR/pico_bashrc_manager.sh" install

echo "=== 6. Services Systemd : ipfs.service + picoport.service ==="

# --- 6a. ipfs.service (daemon IPFS avec CPUQuota=40%) ---
cat > /etc/systemd/system/ipfs.service <<EOF
[Unit]
Description=IPFS Daemon — Picoport UPlanet (CPUQuota 40%%)
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=$SOUNDSPOT_USER
Environment="IPFS_PATH=$USER_HOME/.ipfs"
EnvironmentFile=-/opt/soundspot/soundspot.conf
ExecStart=/usr/local/bin/ipfs daemon --migrate --enable-gc
Restart=on-failure
RestartSec=15
TimeoutStartSec=120
CPUQuota=40%
Nice=10
SyslogIdentifier=ipfs

[Install]
WantedBy=multi-user.target
EOF

# --- 6b. picoport.service (logique Picoport — dépend d'ipfs.service) ---
cat > /etc/systemd/system/picoport.service <<EOF
[Unit]
Description=Picoport (Astroport.ONE Node)
After=network-online.target ipfs.service
Requires=ipfs.service

[Service]
Type=simple
User=$SOUNDSPOT_USER
Environment="IPFS_PATH=$USER_HOME/.ipfs"
EnvironmentFile=-/opt/soundspot/soundspot.conf
ExecStart=$INSTALL_DIR/picoport.sh
Restart=always
RestartSec=10
SyslogIdentifier=picoport
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ipfs
systemctl enable --now picoport
echo "✅ Picoport installé et démarré (ipfs.service CPUQuota=40% + picoport.service) !"

echo "=== 7. Intégration UPassport ==="
bash "$(dirname "$0")/install_upassport.sh"

echo "=== 8. Démarrage de la visibilité Swarm ==="
# CORRECTION DU CHEMIN DUPLIQUÉ ET PROTECTION CONTRE L'AUTO-COPIE
if [ "$(cd "$(dirname "$0")" && pwd)" != "$INSTALL_DIR" ]; then
    cp "$(dirname "$0")/swarm_sync.sh" "$INSTALL_DIR/swarm_sync.sh"
fi
chmod +x "$INSTALL_DIR/swarm_sync.sh"