#!/bin/bash
# ════════════════════════════════════════════════════════════════════
#  dev_reload.sh — Application des modifications Backend en live
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    warn "Ce script ne doit pas être exécuté en root. Utilisez un utilisateur standard (du groupe sudo)."
    exit 1
fi

G='\033[0;32m'; C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'; R='\033[0;31m'; Y='\033[1;33m'
log() { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err() { echo -e "${R}✗${N}  $*" >&2; exit 1; }[ "$(id -u)" -eq 0 ] || exec sudo bash "${BASH_SOURCE[0]}" "$@"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_DIR="$(cd "${SCRIPT_DIR}" && pwd)"
INSTALL_DIR="/opt/soundspot"

if[ ! -d "${DEV_DIR}/src/backend" ]; then
    err "Dossier src/backend introuvable dans ${DEV_DIR}"
fi

log "Synchronisation du code backend vers ${INSTALL_DIR}..."

# Copie de l'arborescence backend
cp -r "${DEV_DIR}/src/backend/audio/"*.sh "${INSTALL_DIR}/backend/audio/" 2>/dev/null || true
cp -r "${DEV_DIR}/src/backend/video/"* "${INSTALL_DIR}/backend/video/" 2>/dev/null || true
cp -r "${DEV_DIR}/src/backend/system/"* "${INSTALL_DIR}/backend/system/" 2>/dev/null || true

# Copie des daemons Python et scripts root (ex: presence_detector, battery_monitor)
find "${DEV_DIR}/src/backend" -maxdepth 2 -type f \( -name "*.py" -o -name "*.sh" \) -exec cp {} "${INSTALL_DIR}/" \; 2>/dev/null || true

# Copies additionnelles (log, utilitaires BT, check)
cp "${DEV_DIR}/check.sh" "${INSTALL_DIR}/check.sh" 2>/dev/null || true
cp "${DEV_DIR}/src/bt_manage.sh" "${INSTALL_DIR}/bt_manage.sh" 2>/dev/null || true
cp "${DEV_DIR}/src/log.sh" "${INSTALL_DIR}/log.sh" 2>/dev/null || true

# Droits d'exécution
chmod +x "${INSTALL_DIR}"/backend/*/*.sh 2>/dev/null || true
chmod +x "${INSTALL_DIR}"/*.sh 2>/dev/null || true

log "Redémarrage des services systemd (runtime hot-reload)..."
sudo systemctl daemon-reload

SERVICES="soundspot-idle soundspot-decoder soundspot-presence soundspot-battery soundspot-jukebox soundspot-channel-sync bt-autoconnect"

for svc in $SERVICES; do
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        sudo systemctl restart "$svc"
        echo -e "  ${G}✓${N} $svc"
    fi
done

sudo systemctl reload lighttpd 2>/dev/null || true

echo ""
log "Hot-reload terminé avec succès ! Le backend de ${DEV_DIR} est en live."
