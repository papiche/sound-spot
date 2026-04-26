#!/bin/bash
# ============================================================
#  SoundSpot — G1FabLab / UPlanet ẐEN
#  Script d'installation pour Raspberry Pi Zero 2W (maître)
#  Architecture : Backend métier + Config isolée
# ============================================================
set -e

# Définition du répertoire racine du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Modules d'installation ───────────────────────────────────
# Note : install_template (dans colors.sh) utilise maintenant 'find'
source "$SCRIPT_DIR/install/colors.sh"
source "$SCRIPT_DIR/install/logging.sh"
source "$SCRIPT_DIR/install/networking.sh"
source "$SCRIPT_DIR/install/captive_portal.sh"
source "$SCRIPT_DIR/install/icecast.sh"
source "$SCRIPT_DIR/install/bluetooth.sh"
source "$SCRIPT_DIR/install/pipewire.sh"
source "$SCRIPT_DIR/install/snapserver.sh"
source "$SCRIPT_DIR/install/snapclient.sh"
source "$SCRIPT_DIR/install/channel_sync.sh"
source "$SCRIPT_DIR/install/presence.sh"
source "$SCRIPT_DIR/install/idle.sh"
source "$SCRIPT_DIR/install/jukebox.sh"

# ── Variables configurables ─────────────────────────────────
export SPOT_NAME="${SPOT_NAME:-SoundSpot_Zicmama}"
export DHCP_START="${DHCP_START:-192.168.10.10}"
export DHCP_END="${DHCP_END:-192.168.10.50}"
export SPOT_IP="${SPOT_IP:-192.168.10.1}"
export WIFI_SSID="${WIFI_SSID:-qo-op}"
export WIFI_PASS="${WIFI_PASS:-0penS0urce!}"
export WIFI_CHANNEL="${WIFI_CHANNEL:-6}"
export BT_MAC="${BT_MAC:-}"
export BT_MACS="${BT_MACS:-${BT_MAC:-}}"
export SNAPCAST_PORT="${SNAPCAST_PORT:-1704}"
export PRESENCE_COOLDOWN="${PRESENCE_COOLDOWN:-30}"
export INSTALL_DIR="/opt/soundspot"
export SOUNDSPOT_USER="${SOUNDSPOT_USER:-${SUDO_USER:-pi}}"
export SOUNDSPOT_UID=$(id -u "${SOUNDSPOT_USER}" 2>/dev/null || echo "1000")
export PRESENCE_ENABLED="${PRESENCE_ENABLED:-false}"
export PICOPORT_ENABLED="${PICOPORT_ENABLED:-true}"
export LOG_LEVEL="${LOG_LEVEL:-WARN}"
export SOUNDSPOT_LOG="${SOUNDSPOT_LOG:-/var/log/sound-spot.log}"

# ── Vérifications ────────────────────────────────────────────
hdr "Vérifications préliminaires"
[ "$(id -u)" -eq 0 ] || err "Lance ce script en root : sudo bash $0"

# ── Paquets ──────────────────────────────────────────────────
hdr "Installation des paquets"
export DEBIAN_FRONTEND=noninteractive
echo "icecast2 icecast2/icecast-setup boolean false" | debconf-set-selections

apt_retry update -qq
apt_retry install -y --no-install-recommends \
    hostapd dnsmasq lighttpd ipset mpg123 lsof \
    icecast2 rpicam-apps \
    bluez bluez-alsa-utils libspa-0.2-bluetooth \
    pipewire pipewire-alsa pipewire-pulse wireplumber \
    snapserver snapclient \
    pulseaudio-utils \
    avahi-daemon \
    iptables-persistent netfilter-persistent \
    python3 python3-opencv python3-picamera2 \
    python3-markdown python3-websocket \
    espeak-ng jq \
    curl wget ffmpeg \
    iw wireless-tools socat gettext-base rsyslog \
    zram-tools

# ── Groupe système soundspot (pi + www-data + astro) ────────────
hdr "Groupe système soundspot"
groupadd --system soundspot 2>/dev/null || true
for _u in "${SOUNDSPOT_USER}" www-data astro; do
    id "$_u" &>/dev/null && usermod -aG soundspot "$_u" && log "$_u ajouté au groupe soundspot" || true
done

# ── Sudoers portail : www-data peut appeler set_audio_output.sh en root ─
echo "www-data ALL=(root) NOPASSWD: ${INSTALL_DIR}/backend/system/set_audio_output.sh" \
    > /etc/sudoers.d/soundspot-audio
chmod 440 /etc/sudoers.d/soundspot-audio
log "sudoers soundspot-audio configuré"

# ── Préparation de l'arborescence /opt/soundspot ─────────────
hdr "Préparation de l'arborescence"
mkdir -p "$INSTALL_DIR/backend/audio"
mkdir -p "$INSTALL_DIR/backend/video"
mkdir -p "$INSTALL_DIR/backend/system"
mkdir -p "$INSTALL_DIR/portal"
mkdir -p "$INSTALL_DIR/wav"

# ── Déploiement des scripts Backend ──────────────────────────
log "Copie des scripts backend vers $INSTALL_DIR/backend/..."
# Audio
cp "$SCRIPT_DIR"/backend/audio/*.sh "$INSTALL_DIR/backend/audio/" 2>/dev/null || true
# Video
cp "$SCRIPT_DIR"/backend/video/*    "$INSTALL_DIR/backend/video/" 2>/dev/null || true
# System
cp "$SCRIPT_DIR"/backend/system/*   "$INSTALL_DIR/backend/system/" 2>/dev/null || true

# Droits d'exécution
find "$INSTALL_DIR/backend" -name "*.sh" -exec chmod +x {} \;

# Copie des manuels
cp "$SCRIPT_DIR/../README.md" "$INSTALL_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/../HOWTO.md" "$INSTALL_DIR/" 2>/dev/null || true

# ── Configuration des services ───────────────────────────────
setup_logging        # Logs centralisés
setup_networking     # AP + IPSet + Firewall
setup_captive_portal # Lighttpd
setup_icecast        # Flux DJ
# ── install HAT (mic + speakers) ───────────────────────
if [ "$USE_RESPEAKER" = "true" ]; then
    source "$SCRIPT_DIR/install/respeaker.sh"
    setup_respeaker
fi
setup_pipewire       # Audio engine
setup_bluetooth      # BT Autoconnect
setup_snapserver     # Serveur synchro
setup_snapclient master # Client local sur BT
setup_channel_sync   # Synchro WiFi radio
setup_presence       # Caméra + Welcome.wav
setup_idle           # Clocher numérique
setup_jukebox        # Nostr Jukebox

# ── Services Master spécifiques ──────────────────────────────
hdr "Services Master (état JSON + micro USB)"

# Démon cache JSON d'état (remplace les forks CGI par requête)
install_template soundspot-state.service \
    /etc/systemd/system/soundspot-state.service \
    '${INSTALL_DIR}'
systemctl enable soundspot-state
log "soundspot-state activé (cache JSON status.json)"

# Capture micro USB → stream Snapcast_Mic (activé si détecté)
install_template soundspot-mic.service \
    /etc/systemd/system/soundspot-mic.service \
    '${INSTALL_DIR}'
if arecord -l 2>/dev/null | grep -qi "USB"; then
    systemctl enable soundspot-mic
    log "Micro USB détecté → soundspot-mic activé"
else
    log "Micro USB non détecté — soundspot-mic désactivé (activer manuellement si besoin)"
fi

# Service mon-oeil (Cerveau IA / Golem) — activé sur Master RPi4
install_template mon-oeil.service \
    /etc/systemd/system/mon-oeil.service
systemctl enable mon-oeil
log "mon-oeil.service activé (IA Golem — tunnel Ollama P2P)"

# ── Installation Picoport ────────────────────────────────────
if [ "$PICOPORT_ENABLED" = "true" ]; then
    hdr "Installation de Picoport (Astroport.ONE Light)"
    
    # 1. Créer le dossier et donner les droits à l'utilisateur AVANT de continuer
    mkdir -p "$INSTALL_DIR/picoport"
    chown -R "${SOUNDSPOT_USER}:${SOUNDSPOT_USER}" "$INSTALL_DIR/picoport"
    
    # 2. Copier l'installeur light et s'assurer qu'il appartient à l'utilisateur
    cp "$SCRIPT_DIR/picoport/install_astroport_light.sh" "$INSTALL_DIR/picoport/"
    chown "${SOUNDSPOT_USER}:${SOUNDSPOT_USER}" "$INSTALL_DIR/picoport/install_astroport_light.sh"
    
    # 3. Exécuter en tant qu'utilisateur (maintenant il a les droits d'écriture)
    sudo -u "${SOUNDSPOT_USER}" bash "$INSTALL_DIR/picoport/install_astroport_light.sh"
    
    # 4. Continuer l'installation des composants restants
    # On recopie tout le dossier picoport (identité, scripts)
    cp -r "$SCRIPT_DIR/picoport/"* "$INSTALL_DIR/picoport/"
    # On redonne les droits sur tout ce qui vient d'être copié
    chown -R "${SOUNDSPOT_USER}:${SOUNDSPOT_USER}" "$INSTALL_DIR/picoport"
    
    # 5. Lancer l'installation Picoport (IPFS, identité, etc.)
    bash "$INSTALL_DIR/picoport/install_picoport.sh"

    # Limite mémoire Golang IPFS (évite les fuites sur long terme, RPi4 = 4 Go)
    mkdir -p /etc/systemd/system/ipfs.service.d
    cat > /etc/systemd/system/ipfs.service.d/gomemlimit.conf <<'GOEOF'
[Service]
Environment="GOMEMLIMIT=200MiB"
GOEOF
    systemctl daemon-reload
    log "GOMEMLIMIT=200MiB configuré pour IPFS"
    
    # Intégration UPassport et Swarm Sync (Port 12345)
    log "Intégration UPassport & Swarm Sync..."
    bash "$INSTALL_DIR/picoport/install_upassport.sh"

    # Installation du service swarm_sync via template
    install_template soundspot-swarm-sync.service /etc/systemd/system/soundspot-swarm-sync.service '${INSTALL_DIR} ${SOUNDSPOT_USER}'
    systemctl enable --now soundspot-swarm-sync

    # ── Flotte NOSTR Amiral ──────────────────────────────────────
    hdr "Flotte NOSTR — Relay local (port 9999)"
    apt-get install -y -q python3-websockets 2>/dev/null || true

    # Génération clé Amiral (déterministe depuis swarm.key)
    bash "${INSTALL_DIR}/backend/system/amiral_keygen.sh" \
        && log "Clé Amiral générée ✓" \
        || warn "Génération clé Amiral échouée (swarm.key ou pynostr absent)"

    install_template soundspot-fleet-relay.service \
        /etc/systemd/system/soundspot-fleet-relay.service \
        '${INSTALL_DIR}'
    install_template soundspot-fleet.service \
        /etc/systemd/system/soundspot-fleet.service \
        '${INSTALL_DIR}'
    systemctl enable soundspot-fleet-relay soundspot-fleet
    log "Fleet relay (port 9999) + fleet listener activés"
fi

# ── Fichier de configuration final ──────────────────────────
hdr "Finalisation"
install_template soundspot.conf.master.env "$INSTALL_DIR/soundspot.conf" \
    '${SPOT_NAME} ${SPOT_IP} ${WIFI_SSID} ${WIFI_CHANNEL} ${BT_MAC} ${BT_MACS} ${SNAPCAST_PORT} ${PRESENCE_COOLDOWN} ${PRESENCE_ENABLED} ${INSTALL_DIR} ${IFACE_AP} ${IFACE_WAN} ${LOG_LEVEL} ${SOUNDSPOT_LOG}'

# S'assurer que le log est accessible
touch "$SOUNDSPOT_LOG"
chgrp soundspot "$SOUNDSPOT_LOG"
chmod 664 "$SOUNDSPOT_LOG"
# et ~/.zen/tmp aussi
mkdir -p "/home/${SOUNDSPOT_USER}/.zen/tmp"
chgrp soundspot "/home/${SOUNDSPOT_USER}/.zen/tmp"

hdr "Installation terminée ✓"
echo -e "${G}SoundSpot est prêt !${N}"
echo -e "Utilisez la commande ${C}check${N} (alias) pour vérifier l'état des services."
echo -e "Le nœud va redémarrer dans 10s..."
sleep 10
reboot