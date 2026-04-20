#!/bin/bash
# ════════════════════════════════════════════════════════════════════
#  dev_reload.sh — Application des modifications Backend en live
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

G='\033[0;32m'; C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'; R='\033[0;31m'; Y='\033[1;33m'
log() { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err() { echo -e "${R}✗${N}  $*" >&2; exit 1; }

# Ce script a BESOIN d'être root pour modifier /opt et relancer systemd
[ "$(id -u)" -eq 0 ] || exec sudo bash "${BASH_SOURCE[0]}" "$@"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Correction du chemin DEV_DIR : on remonte à la racine du dépôt (depuis src/dev/)
DEV_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_DIR="/opt/soundspot"
SOUNDSPOT_USER=$(grep "SOUNDSPOT_USER" "$INSTALL_DIR/soundspot.conf" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "pi")

if[ ! -d "${DEV_DIR}/src/backend" ]; then
    err "Dossier src/backend introuvable dans ${DEV_DIR}"
fi

log "Synchronisation du code backend vers ${INSTALL_DIR}..."

# Copie de l'arborescence backend
cp -r "${DEV_DIR}/src/backend/audio/"*.sh "${INSTALL_DIR}/backend/audio/" 2>/dev/null || true
cp -r "${DEV_DIR}/src/backend/video/"* "${INSTALL_DIR}/backend/video/" 2>/dev/null || true
cp -r "${DEV_DIR}/src/backend/system/"* "${INSTALL_DIR}/backend/system/" 2>/dev/null || true

# Copie de l'arborescence picoport (Très important pour les tests IA Swarm !)
if [ -d "${DEV_DIR}/src/picoport" ]; then
    log "Synchronisation du code picoport..."
    cp -r "${DEV_DIR}/src/picoport/"* "${INSTALL_DIR}/picoport/" 2>/dev/null || true
    chown -R ${SOUNDSPOT_USER}:${SOUNDSPOT_USER} "${INSTALL_DIR}/picoport/"
fi

# Copie des daemons Python et scripts root
find "${DEV_DIR}/src/backend" -maxdepth 2 -type f \( -name "*.py" -o -name "*.sh" \) -exec cp {} "${INSTALL_DIR}/" \; 2>/dev/null || true

# Copies additionnelles (log, utilitaires BT, check)
cp "${DEV_DIR}/check.sh" "${INSTALL_DIR}/check.sh" 2>/dev/null || true
cp "${DEV_DIR}/src/bt_manage.sh" "${INSTALL_DIR}/bt_manage.sh" 2>/dev/null || true
cp "${DEV_DIR}/src/bt_update.sh" "${INSTALL_DIR}/bt_update.sh" 2>/dev/null || true
cp "${DEV_DIR}/src/log.sh" "${INSTALL_DIR}/log.sh" 2>/dev/null || true

# Droits d'exécution
find "${INSTALL_DIR}" -maxdepth 3 -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

log "Redémarrage des services systemd (runtime hot-reload)..."
sudo systemctl daemon-reload

# Ajout des services UPlanet pour le reload (picoport, upassport...)
SERVICES="soundspot-idle soundspot-decoder soundspot-presence soundspot-battery soundspot-jukebox soundspot-channel-sync bt-autoconnect picoport upassport soundspot-swarm-sync"

for svc in $SERVICES; do
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        sudo systemctl restart "$svc"
        echo -e "  ${G}✓${N} $svc"
    fi
done

sudo systemctl reload lighttpd 2>/dev/null || true

echo ""
log "Hot-reload terminé avec succès ! Le backend de ${DEV_DIR} est en live."