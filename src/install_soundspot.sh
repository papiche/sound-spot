#!/bin/bash
# ============================================================
#  SoundSpot — G1FabLab / UPlanet ẐEN
#  Script d'installation pour Raspberry Pi Zero 2W (maître)
#  https://github.com/papiche/sound-spot
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Modules d'installation ───────────────────────────────────
source "$SCRIPT_DIR/install/colors.sh"
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

# ── Variables configurables ─────────────────────────────────
export SPOT_NAME="${SPOT_NAME:-SoundSpot_Pont}"      # SSID WiFi visible (réseau ouvert)
export DHCP_START="${DHCP_START:-192.168.10.10}"
export DHCP_END="${DHCP_END:-192.168.10.50}"
export SPOT_IP="${SPOT_IP:-192.168.10.1}"
export WIFI_SSID="${WIFI_SSID:-qo-op}"              # Réseau WiFi amont
export WIFI_PASS="${WIFI_PASS:-0penS0urce!}"
export WIFI_CHANNEL="${WIFI_CHANNEL:-6}"            # Doit correspondre au canal de WIFI_SSID
export BT_MAC="${BT_MAC:-}"                         # Adresse MAC principale (rétrocompat)
export BT_MACS="${BT_MACS:-${BT_MAC:-}}"           # Liste MACs séparés par espaces (multi-enceintes)
export SNAPCAST_PORT="${SNAPCAST_PORT:-1704}"
export PRESENCE_COOLDOWN="${PRESENCE_COOLDOWN:-30}" # Secondes entre deux messages d'accueil
export INSTALL_DIR="/opt/soundspot"
export SOUNDSPOT_USER="${SOUNDSPOT_USER:-${SUDO_USER:-pi}}"  # Utilisateur qui exécute les services audio
export SOUNDSPOT_UID=$(id -u "${SOUNDSPOT_USER}" 2>/dev/null || echo "1000")
# ── Vérifications préliminaires ──────────────────────────────
hdr "Vérifications"
[ "$(id -u)" -eq 0 ] || err "Lance ce script en root : sudo bash install_soundspot.sh"
grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null || warn "Pas un RPi détecté — on continue quand même"
log "RPi Zero 2W détecté — profil minimal activé"

# ── Paquets ──────────────────────────────────────────────────
hdr "Installation des paquets"
export DEBIAN_FRONTEND=noninteractive
echo "icecast2 icecast2/icecast-setup boolean false" | debconf-set-selections

apt_retry update -qq
apt_retry install -y --no-install-recommends \
    hostapd dnsmasq lighttpd ipset \
    icecast2 rpicam-apps \
    bluez bluez-alsa-utils libspa-0.2-bluetooth \
    pipewire pipewire-alsa pipewire-pulse wireplumber \
    snapserver snapclient \
    pulseaudio-utils \
    avahi-daemon \
    iptables-persistent netfilter-persistent \
    python3 python3-opencv python3-picamera2 \
    python3-markdown \
    espeak-ng \
    curl wget ffmpeg \
    iw wireless-tools

mkdir -p "$INSTALL_DIR"

# ── Scripts Python → INSTALL_DIR (si appelé sans deploy_on_pi.sh) ──
for _py in presence_detector.py battery_monitor.py; do
    [ -f "$INSTALL_DIR/$_py" ] && continue
    [ -f "$SCRIPT_DIR/$_py" ] && cp "$SCRIPT_DIR/$_py" "$INSTALL_DIR/" && \
        log "$_py copié depuis $SCRIPT_DIR" || true
done

# Copie des manuels
cp "$SCRIPT_DIR/../README.md" "$INSTALL_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/../HOWTO.md" "$INSTALL_DIR/" 2>/dev/null || true

# ── Configuration ─────────────────────────────────────────────
setup_networking
setup_captive_portal
setup_icecast
setup_bluetooth
setup_pipewire
setup_snapserver
setup_snapclient master
setup_channel_sync
setup_presence
setup_idle

# ── Fichier de configuration central ─────────────────────────
hdr "Fichier de configuration central"
install_template soundspot.conf.master "$INSTALL_DIR/soundspot.conf" \
    '${SPOT_NAME} ${SPOT_IP} ${WIFI_SSID} ${WIFI_CHANNEL} ${BT_MAC} ${BT_MACS} ${SNAPCAST_PORT} ${PRESENCE_COOLDOWN} ${INSTALL_DIR}'
chmod 644 "$INSTALL_DIR/soundspot.conf"

# ── Résumé final ──────────────────────────────────────────────
hdr "Installation terminée ✓"

echo -e "
${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}
${G}  SoundSpot installé avec succès !${N}
${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}

  WiFi AP  : ${C}${SPOT_NAME}${N}  (pass: ${SPOT_PASS})
  Canal    : ${WIFI_CHANNEL}  (doit = canal de ${WIFI_SSID})
  IP RPi   : ${C}${SPOT_IP}${N}
  Snapcast : ${C}${SPOT_IP}:${SNAPCAST_PORT}${N}
  Client BT : snapclient localhost → ${C}journalctl -fu soundspot-client${N}
  Présence  : cooldown ${PRESENCE_COOLDOWN}s — ${C}journalctl -fu soundspot-presence${N}

${Y}Actions manuelles restantes :${N}

  1. Coupler l'enceinte BT :
     ${C}bluetoothctl${N}
       power on / scan on / pair XX:XX / trust XX:XX

  2. Mettre à jour BT_MACS dans :
     ${C}${INSTALL_DIR}/soundspot.conf${N}
     (liste de MACs séparés par espaces, ex: BT_MACS=\"AA:BB:CC:DD:EE:FF 11:22:33:44:55:66\")
     puis : ${C}sudo systemctl enable bt-autoconnect${N}

  3. Vérifier le canal de ${WIFI_SSID} :
     ${C}iwlist wlan0 scan | grep -A2 '${WIFI_SSID}'${N}
     Modifier 'channel=' dans /etc/hostapd/hostapd.conf
     si différent de ${WIFI_CHANNEL}

  4. Personnaliser le message d'accueil si besoin :
     ${C}espeak-ng -v fr+f3 -s 120 -p 45 \"Votre texte...\" -w ${INSTALL_DIR}/welcome.wav${N}

  5. Redémarrer :
     ${C}sudo reboot${N}

${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}
"
