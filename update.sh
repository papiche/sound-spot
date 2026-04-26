
#!/bin/bash
# =========================================================================
#  update.sh — Mise à jour dynamique SoundSpot (Synchronisé avec le code)
#  G1FabLab / UPlanet ẐEN — zicmama.com
# =========================================================================
set -euo pipefail

# ── Couleurs ─────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'
log()  { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err()  { echo -e "${R}✗${N}  $*" >&2; exit 1; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }

[ "$(id -u)" -ne 0 ] && err "Ce script doit être lancé avec sudo : sudo bash $0"

# ── Chemins ──────────────────────────────────────────────────────
INSTALL_DIR="/opt/soundspot"
CONF_FILE="${INSTALL_DIR}/soundspot.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/src"

[ ! -f "$CONF_FILE" ] && err "SoundSpot non installé dans ${INSTALL_DIR}."

# Charger la config
source "$CONF_FILE"
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
SOUNDSPOT_UID=$(id -u "${SOUNDSPOT_USER}")

hdr "Mise à jour SoundSpot Dynamique"

# ════════════════════════════════════════════════════════════════
#  1. Extraction des dépendances depuis le code source
# ════════════════════════════════════════════════════════════════
log "Extraction des dépendances depuis le code source..."

PKGS=""

# Détection du mode (Master ou Satellite) via la présence de hostapd
if [ -f /etc/hostapd/hostapd.conf ]; then
    log "  Mode détecté : Maître"
    # Extrait les paquets entre 'apt_retry install' et 'zram-tools' dans install_soundspot.sh
    PKGS=$(sed -n '/apt_retry install/,/zram-tools/p' "${SRC_DIR}/install_soundspot.sh" \
           | grep -v "apt_retry" | tr -d '\\' | xargs)
else
    log "  Mode détecté : Satellite"
    # Extrait la variable PKGS dans install_satellite.sh
    PKGS=$(grep -oP '(?<=PKGS=").*?(?=")' "${SRC_DIR}/install_satellite.sh")
fi

# Si Picoport est activé, on ajoute ses dépendances spécifiques
if [ "${PICOPORT_ENABLED:-false}" = "true" ]; then
    log "  Ajout des dépendances Picoport..."
    PICO_PKGS=$(grep -oP '(?<=for _pkg in ).*?(?=; do)' "${SRC_DIR}/picoport/install_picoport.sh" | tr -d '"')
    PKGS="$PKGS $PICO_PKGS"
fi

# Nettoyage et dédoublonnage de la liste
PKGS_LIST=$(echo "$PKGS" | tr ' ' '\n' | sort -u | xargs)

if [ -n "$PKGS_LIST" ]; then
    log "Installation/Mise à jour des paquets : ${W}${PKGS_LIST}${N}"
    apt-get update -qq
    apt-get install -y -q --no-install-recommends $PKGS_LIST
else
    warn "Aucun paquet trouvé à installer."
fi

# ════════════════════════════════════════════════════════════════
#  2. Synchronisation du Code (Backend + Frontend)
# ════════════════════════════════════════════════════════════════
log "Synchronisation des fichiers..."

# Backend
mkdir -p "$INSTALL_DIR/backend/audio" "$INSTALL_DIR/backend/video" "$INSTALL_DIR/backend/system"
cp -r "${SRC_DIR}/backend/audio/"* "${INSTALL_DIR}/backend/audio/" 2>/dev/null || true
cp -r "${SRC_DIR}/backend/video/"* "${INSTALL_DIR}/backend/video/" 2>/dev/null || true
cp -r "${SRC_DIR}/backend/system/"* "${INSTALL_DIR}/backend/system/" 2>/dev/null || true

# Daemons et scripts racines
find "${SRC_DIR}/backend" -maxdepth 2 -type f \( -name "*.py" -o -name "*.sh" \) -exec cp {} "${INSTALL_DIR}/" \; 2>/dev/null || true
cp "${SCRIPT_DIR}/check.sh" "${INSTALL_DIR}/check.sh" 2>/dev/null || true
chmod +x "${INSTALL_DIR}/"*.sh "${INSTALL_DIR}/backend/"*/*.sh 2>/dev/null || true

# Portail (Frontend)
if [ -L "${INSTALL_DIR}/portal" ]; then
    log "  Mode DEV (symlink) conservé."
else
    cp -r "${SRC_DIR}/portal/"* "${INSTALL_DIR}/portal/" 2>/dev/null || true
    chown -R www-data:www-data "${INSTALL_DIR}/portal/"
fi

# ════════════════════════════════════════════════════════════════
#  3. Mise à jour des services Systemd
# ════════════════════════════════════════════════════════════════
log "Régénération des unités Systemd..."

# Export des variables pour envsubst
export INSTALL_DIR SOUNDSPOT_USER SOUNDSPOT_UID SPOT_IP IFACE_AP IFACE_WAN SNAPCAST_PORT SPOT_NAME WIFI_CHANNEL

for svc_template in "${SRC_DIR}/config/services/"*.service; do
    svc_name=$(basename "$svc_template")
    # On applique les variables actuelles aux fichiers .service
    envsubst '${INSTALL_DIR} ${SOUNDSPOT_USER} ${SOUNDSPOT_UID} ${SPOT_IP} ${IFACE_AP} ${IFACE_WAN} ${SNAPCAST_PORT} ${SPOT_NAME} ${WIFI_CHANNEL}' \
        < "$svc_template" > "/etc/systemd/system/${svc_name}"
done

systemctl daemon-reload

# ════════════════════════════════════════════════════════════════
#  4. Redémarrage des services
# ════════════════════════════════════════════════════════════════
log "Redémarrage des services..."

SERVICES="soundspot-ap hostapd dnsmasq soundspot-firewall icecast2 soundspot-decoder snapserver soundspot-client soundspot-idle picoport upassport soundspot-swarm-sync soundspot-state bt-autoconnect"

for svc in $SERVICES; do
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        systemctl restart "$svc"
        echo -e "  ${G}✓${N} $svc"
    fi
done

systemctl reload lighttpd 2>/dev/null || true

hdr "SoundSpot mis à jour avec succès !"