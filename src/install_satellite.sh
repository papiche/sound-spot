#!/bin/bash
# ============================================================
#  SoundSpot Satellite — G1FabLab / UPlanet ẐEN
#  Script d'installation pour RPi Zero 2W satellite
#
#  Réseau : uniquement l'AP WiFi du maître (SPOT_NAME, ouvert).
#  Le maître fait le NAT → le satellite a Internet via lui.
#  IP maître toujours fixe : 192.168.10.1
#
#  Pré-requis : le RPi maître doit être allumé et son AP actif.
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Modules d'installation ───────────────────────────────────
source "$SCRIPT_DIR/install/colors.sh"
source "$SCRIPT_DIR/install/bluetooth.sh"
source "$SCRIPT_DIR/install/pipewire.sh"
source "$SCRIPT_DIR/install/snapclient.sh"

# ── Variables configurables ─────────────────────────────────
MASTER_HOST="${MASTER_HOST:-soundspot.local}"  # hostname/IP du maître sur qo-op
SNAPCAST_PORT="${SNAPCAST_PORT:-1704}"
BT_MAC="${BT_MAC:-}"
BT_MACS="${BT_MACS:-${BT_MAC:-}}"           # Liste MACs séparés par espaces (multi-enceintes)
INSTALL_DIR="/opt/soundspot"

# ── Vérifications ────────────────────────────────────────────
hdr "Vérifications"
[ "$(id -u)" -eq 0 ] || err "Lance ce script en root : sudo bash install_satellite.sh"
grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null || warn "Pas un RPi — on continue"
log "Mode satellite → snapserver ${MASTER_HOST}:${SNAPCAST_PORT}"

# ── Paquets ──────────────────────────────────────────────────
# Internet disponible via le NAT du maître (uap0 → wlan0 → qo-op)
hdr "Installation des paquets"
apt update -y
apt install -y --no-install-recommends \
    bluez bluez-alsa-utils \
    pipewire pipewire-alsa pipewire-pulse wireplumber \
    snapcast \
    iw wireless-tools

mkdir -p "$INSTALL_DIR"

# ── Configuration ─────────────────────────────────────────────
setup_bluetooth
setup_pipewire
setup_snapclient satellite

# ── Fichier de configuration central ─────────────────────────
hdr "Fichier de configuration central"
install_template soundspot.conf.satellite "$INSTALL_DIR/soundspot.conf" \
    '${MASTER_HOST} ${SNAPCAST_PORT} ${BT_MAC} ${BT_MACS} ${INSTALL_DIR}'
chmod 600 "$INSTALL_DIR/soundspot.conf"

# ── Résumé ────────────────────────────────────────────────────
hdr "Installation satellite terminée ✓"
echo -e "
${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}
${G}  SoundSpot Satellite installé !${N}
${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}

  Maître Snapcast : ${C}${MASTER_HOST}:${SNAPCAST_PORT}${N}
  Enceinte(s) BT  : ${W}${BT_MACS:-à configurer}${N}

${Y}Si une enceinte BT n'est pas couplée :${N}
  bluetoothctl → power on / scan on / pair / trust / connect
  nano ${INSTALL_DIR}/soundspot.conf   # BT_MACS=\"AA:BB:CC:DD:EE:FF 11:22:33:44:55:66\"
  sudo systemctl enable bt-autoconnect

${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}
"
