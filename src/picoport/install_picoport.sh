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
for _pkg in socat jq curl wget bc gnupg pinentry-curses python3-dev libffi-dev libssl-dev prometheus-node-exporter inotify-tools; do
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
    KUBO_TARBALL="kubo_v0.40.0_linux-${PICO_ARCH}.tar.gz"
    KUBO_URL="https://dist.ipfs.tech/kubo/v0.40.0/${KUBO_TARBALL}"
    wget -q --show-progress "$KUBO_URL"
    # Vérification d'intégrité avant exécution de install.sh en root.
    if wget -q -O "${KUBO_TARBALL}.sha512" "${KUBO_URL}.sha512" 2>/dev/null && [ -s "${KUBO_TARBALL}.sha512" ]; then
        EXPECTED_SHA=$(awk '{print $1}' "${KUBO_TARBALL}.sha512")
        ACTUAL_SHA=$(sha512sum "$KUBO_TARBALL" | awk '{print $1}')
        if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
            echo "❌ Somme de contrôle Kubo invalide (attendu ${EXPECTED_SHA:0:16}…, obtenu ${ACTUAL_SHA:0:16}…) — fichier corrompu ou compromis." >&2
            rm -f "$KUBO_TARBALL" "${KUBO_TARBALL}.sha512"
            exit 1
        fi
        echo "✓ Somme de contrôle Kubo vérifiée (sha512)"
    else
        echo "⚠ Somme de contrôle Kubo indisponible sur dist.ipfs.tech — vérification ignorée"
    fi
    tar -xzf "$KUBO_TARBALL"
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
        ipfs config --json Swarm.ConnMgr.HighWater 25
        ipfs config --json Swarm.ConnMgr.LowWater 5
        ipfs config --json Swarm.ConnMgr.GracePeriod "1m"
        ipfs config --json Datastore.BloomFilterSize 32768 # Réduit l'empreinte mémoire
        ipfs config Datastore.StorageMax '2GB'
        ipfs config Routing.Type 'dhtclient'
        ipfs config --bool AutoConf.Enabled false
        ipfs config --json Experimental.Libp2pStreamMounting true
        ipfs config --json Experimental.FilestoreEnabled true
        ipfs config Logging.Level error
    fi

    # Réappliqué à chaque run (idempotent) : sur les nœuds déjà initialisés
    # avant l'ajout de ce réglage, le bloc ci-dessus ne s'exécute jamais,
    # donc la Gateway restait bloquée sur 127.0.0.1 sans que personne s'en aperçoive.
    ipfs config Addresses.Gateway /ip4/0.0.0.0/tcp/8080

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

# --- 6c. soundspot-strfry-proxy.service (port fixe 7777 → tunnel strfry courant) ---
# x_strfry.sh (Astroport.ONE) choisit un port local dynamique par nœud swarm
# (hash de l'IPFSNODEID distant) ; myRELAY (my.sh, dérivé de myIPFS) suppose
# lui un port fixe 7777. Ce service comble l'écart et se réajuste seul en cas
# de failover vers un autre nœud strfry du swarm.
if [ ! -e "$INSTALL_DIR/strfry_proxy.sh" ] && [ "$(cd "$(dirname "$0")" && pwd)" != "$INSTALL_DIR" ]; then
    cp "$(dirname "$0")/strfry_proxy.sh" "$INSTALL_DIR/strfry_proxy.sh"
fi
chmod +x "$INSTALL_DIR/strfry_proxy.sh"

cat > /etc/systemd/system/soundspot-strfry-proxy.service <<EOF
[Unit]
Description=SoundSpot — Port fixe 7777 vers le tunnel IPFS p2p strfry actif
After=network-online.target picoport.service

[Service]
Type=simple
User=$SOUNDSPOT_USER
Environment="IPFS_PATH=$USER_HOME/.ipfs"
ExecStart=$INSTALL_DIR/strfry_proxy.sh
Restart=on-failure
RestartSec=10
SyslogIdentifier=strfry-proxy

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ipfs
systemctl enable --now picoport
systemctl enable --now soundspot-strfry-proxy
echo "✅ Picoport installé et démarré (ipfs.service CPUQuota=40% + picoport.service + strfry-proxy) !"

echo "=== 6c. Cron de maintenance quotidienne (mise à jour git + heure solaire) ==="
# picoport_20h12.sh (généré par install_astroport_light.sh) contient les
# `git pull --ff-only` pour Astroport.ONE et sound-spot — mais rien ne le
# planifiait jusqu'ici. cron_VRFY.sh ON détecte automatiquement Picoport
# (via /opt/soundspot/picoport/picoport_20h12.sh) et installe l'entrée
# crontab à l'heure solaire 20h12, sans changer l'état déjà actif d'ipfs/picoport.
_CRON_VRFY="$USER_HOME/.zen/Astroport.ONE/admin/system/cron_VRFY.sh"
if [ -x "$_CRON_VRFY" ]; then
    sudo -u "$SOUNDSPOT_USER" bash "$_CRON_VRFY" ON
else
    echo "⚠ cron_VRFY.sh introuvable ($_CRON_VRFY) — cron 20h12 non activé"
    echo "  Activable manuellement plus tard : sudo -u $SOUNDSPOT_USER bash $_CRON_VRFY ON"
fi

echo "=== 7. Intégration UPassport ==="
bash "$(dirname "$0")/install_upassport.sh"

echo "=== 8. Démarrage de la visibilité Swarm ==="
# CORRECTION DU CHEMIN DUPLIQUÉ ET PROTECTION CONTRE L'AUTO-COPIE
if [ "$(cd "$(dirname "$0")" && pwd)" != "$INSTALL_DIR" ]; then
    cp "$(dirname "$0")/swarm_sync.sh" "$INSTALL_DIR/swarm_sync.sh"
fi
chmod +x "$INSTALL_DIR/swarm_sync.sh"

echo "=== 9. Tunnels IA Constellation (Qdrant + NextCloud + strfry + orpheus) ==="
# Résolution du chemin astrosystemctl (symlink ~/.local/bin ou script direct)
_ASYS=""
sudo -u "$SOUNDSPOT_USER" bash -c 'command -v astrosystemctl >/dev/null 2>&1' \
    && _ASYS="astrosystemctl"
_ASYS_SCRIPT="$USER_HOME/.zen/Astroport.ONE/admin/system/astrosystemctl.sh"
[[ -z "$_ASYS" && -x "$_ASYS_SCRIPT" ]] && _ASYS="bash $_ASYS_SCRIPT"

_SWARM_DIR="$USER_HOME/.zen/tmp/swarm"

# --- 9a. Qdrant ---
if find "$_SWARM_DIR" -name "x_qdrant.sh" 2>/dev/null | grep -q .; then
    echo "▶ Qdrant détecté dans le swarm — activation du tunnel persistant"
    if [[ -n "$_ASYS" ]]; then
        sudo -u "$SOUNDSPOT_USER" bash -c "$_ASYS enable qdrant 2>/dev/null \
            && echo '✅ Tunnel Qdrant activé (port 6333)'" \
            || echo "⚠ astrosystemctl enable qdrant a échoué (IPFS démarré ?)"
    else
        echo "⚠ astrosystemctl introuvable — relancer après démarrage d'IPFS"
    fi
    # Inscrire QDRANT_URL dans soundspot.conf si absent
    _PICO_CONF="/opt/soundspot/soundspot.conf"
    if [[ -f "$_PICO_CONF" ]] && ! grep -q "^QDRANT_URL=" "$_PICO_CONF"; then
        echo 'QDRANT_URL="http://127.0.0.1:6333"' >> "$_PICO_CONF"
        echo "  → QDRANT_URL ajouté dans soundspot.conf"
    fi

    # Clé API Qdrant = sha256(UPLANETNAME), identique sur toute la constellation
    # (UPLANETNAME = contenu de swarm.key — Astroport.ONE/tools/my.sh:93-96,698-700 —
    # même calcul que install/install-ai-company.docker.sh:127-131). Stockée au même
    # endroit que le reste de l'écosystème IA : ~/.zen/ai-company/.env
    _SWARM_KEY="$USER_HOME/.ipfs/swarm.key"
    if [[ -s "$_SWARM_KEY" ]]; then
        _UPLANETNAME=$(tail -n 1 "$_SWARM_KEY")
        _QDRANT_API_KEY=$(echo -n "$_UPLANETNAME" | openssl dgst -sha256 | sed 's/^.* //')
        _AI_ENV="$USER_HOME/.zen/ai-company/.env"
        sudo -u "$SOUNDSPOT_USER" mkdir -p "$(dirname "$_AI_ENV")"
        if [[ -f "$_AI_ENV" ]] && grep -q "^QDRANT_API_KEY=" "$_AI_ENV"; then
            sudo -u "$SOUNDSPOT_USER" sed -i "s|^QDRANT_API_KEY=.*|QDRANT_API_KEY=${_QDRANT_API_KEY}|" "$_AI_ENV"
        else
            sudo -u "$SOUNDSPOT_USER" bash -c "echo 'QDRANT_API_KEY=${_QDRANT_API_KEY}' >> '$_AI_ENV'"
        fi
        echo "  → QDRANT_API_KEY calculée et inscrite dans $_AI_ENV"
    fi
else
    echo "ℹ Aucun Qdrant disponible dans le swarm pour l'instant"
    echo "  → Activable plus tard : sudo -u $SOUNDSPOT_USER astrosystemctl enable qdrant"
fi

# --- 9b. NextCloud ---
_NC_SVC=""
find "$_SWARM_DIR" -name "x_nextcloud-app.sh"  2>/dev/null | grep -q . && _NC_SVC="nextcloud-app"
[[ -z "$_NC_SVC" ]] && \
    find "$_SWARM_DIR" -name "x_nextcloud-aio.sh" 2>/dev/null | grep -q . && _NC_SVC="nextcloud-aio"

if [[ -n "$_NC_SVC" ]]; then
    echo "▶ NextCloud détecté dans le swarm ($_NC_SVC) — activation du tunnel persistant"
    if [[ -n "$_ASYS" ]]; then
        sudo -u "$SOUNDSPOT_USER" bash -c "$_ASYS enable $_NC_SVC 2>/dev/null \
            && echo '✅ Tunnel NextCloud activé'" \
            || echo "⚠ astrosystemctl enable $_NC_SVC a échoué"
    fi
else
    echo "ℹ Aucun NextCloud disponible dans le swarm pour l'instant"
    echo "  → Activable plus tard : sudo -u $SOUNDSPOT_USER astrosystemctl enable nextcloud-app"
fi

# --- 9c. strfry (relay Nostr requis par myRELAY / UPassport) ---
# Mode "closest" : la latence prime sur la puissance de calcul pour un relay.
# soundspot-strfry-proxy.service (voir 6c) réexpose le tunnel sur le port fixe
# 7777 attendu par myRELAY, quel que soit le port dynamique choisi par le nœud.
if find "$_SWARM_DIR" -name "x_strfry.sh" 2>/dev/null | grep -q .; then
    echo "▶ strfry détecté dans le swarm — activation du tunnel persistant (mode closest)"
    if [[ -n "$_ASYS" ]]; then
        sudo -u "$SOUNDSPOT_USER" bash -c "$_ASYS enable strfry closest 2>/dev/null \
            && echo '✅ Tunnel strfry activé'" \
            || echo "⚠ astrosystemctl enable strfry closest a échoué (IPFS démarré ?)"
    else
        echo "⚠ astrosystemctl introuvable — relancer après démarrage d'IPFS"
    fi
else
    echo "ℹ Aucun strfry disponible dans le swarm pour l'instant"
    echo "  → Activable plus tard : sudo -u $SOUNDSPOT_USER astrosystemctl enable strfry closest"
fi

# --- 9d. orpheus (TTS — utilisé par idle_announcer.sh pour l'heure solaire/messages) ---
# Mode "random" : génération TTS = calcul GPU comme ollama/comfyui, on répartit
# la charge entre les nœuds du swarm plutôt que de toujours viser le plus puissant.
if find "$_SWARM_DIR" -name "x_orpheus.sh" 2>/dev/null | grep -q .; then
    echo "▶ orpheus détecté dans le swarm — activation du tunnel persistant (mode random)"
    if [[ -n "$_ASYS" ]]; then
        sudo -u "$SOUNDSPOT_USER" bash -c "$_ASYS enable orpheus random 2>/dev/null \
            && echo '✅ Tunnel orpheus activé (port 5005)'" \
            || echo "⚠ astrosystemctl enable orpheus random a échoué (IPFS démarré ?)"
    else
        echo "⚠ astrosystemctl introuvable — relancer après démarrage d'IPFS"
    fi
else
    echo "ℹ Aucun orpheus disponible dans le swarm pour l'instant"
    echo "  → Activable plus tard : sudo -u $SOUNDSPOT_USER astrosystemctl enable orpheus random"
fi

# --- 9e. Aide astrosystemctl ---
cat << 'ASTROSYS_HELP'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  astrosystemctl — Cloud P2P de Puissance UPlanet
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Ce Picoport est un nœud 🌿 Light (RPi Zero 2W).
  Il délègue le calcul IA aux Brain-Nodes de la constellation.

  Commandes clés (alias disponibles dans le shell) :
  ──────────────────────────────────────────────────
  asys-swarm              → Lister les Brain-Nodes du swarm
  asys-list               → Services locaux disponibles
  ai <service>            → Connexion rapide (ex: ai ollama)
  asys-qdrant             → Activer le tunnel Qdrant (port 6333)
  asys-nc                 → Activer le tunnel NextCloud
  astrosystemctl status   → État des tunnels actifs
  astrosystemctl connect <svc>   → Connexion ponctuelle

  Fonctionnement :
  ──────────────────────────────────────────────────
  • Les Brain-Nodes publient leurs services via IPFS P2P
  • "enable" crée un tunnel persistant (watchdog 20h12.process.sh)
  • Le tunnel local utilise le même port que le service distant :
      qdrant       → 127.0.0.1:6333
      ollama       → 127.0.0.1:11434
      comfyui      → 127.0.0.1:8188
      nextcloud    → 127.0.0.1:8002
  • Clé API Qdrant = sha256(UPLANETNAME) — identique sur toute la constellation

  Exemple de session IA sur Picoport :
  ──────────────────────────────────────────────────
  $ asys-swarm                    # Voir les Brain-Nodes disponibles
  $ asys-qdrant                   # Activer l'accès à la base vectorielle
  $ ai ollama                     # Se connecter à Ollama distant
  $ astrosystemctl status         # Vérifier les tunnels actifs

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ASTROSYS_HELP