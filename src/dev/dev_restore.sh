#!/bin/bash
# ════════════════════════════════════════════════════════════════════
#  src/dev/dev_restore.sh — Restaurer le portail en production
# ════════════════════════════════════════════════════════════════════
#
#  Remet /opt/soundspot/portal en mode "copie depuis main" :
#    - checkout main + pull
#    - copie src/portal/ → /opt/soundspot/portal/ (plus de symlink)
#    - chown www-data
#
#  Utiliser quand :
#    - On passe le nœud en production complète (sans dépendance au workspace)
#    - On veut que l'accès www-data ne dépende plus du home directory
#    - On prépare un nœud pour une installation fraîche
#
#  Pour simplement revenir à main tout en gardant le mode dev :
#    bash src/dev/dev_switch.sh main    ← plus rapide
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

G='\033[0;32m'; C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'; R='\033[0;31m'
log() { echo -e "${G}▶${N} $*"; }
err() { echo -e "${R}✗${N}  $*" >&2; exit 1; }

DEV_DIR="${HOME}/.zen/workspace/sound-spot"
INSTALL_DIR="/opt/soundspot"
PORTAL_DEST="${INSTALL_DIR}/portal"

# ── Choisir la source ─────────────────────────────────────────
# Priorité 1 : workspace local (main)
# Priorité 2 : sauvegarde portal.prod.bak
# Priorité 3 : erreur (indiquer deploy_on_pi.sh)

if [ -d "${DEV_DIR}/.git" ]; then
    log "Checkout main + pull..."
    cd "$DEV_DIR"
    git fetch origin --quiet 2>/dev/null || true
    git checkout main --quiet
    git pull --ff-only 2>/dev/null || true
    SRC="${DEV_DIR}/src/portal"
elif [ -d "${INSTALL_DIR}/portal.prod.bak" ]; then
    log "Utilisation de la sauvegarde portal.prod.bak"
    SRC="${INSTALL_DIR}/portal.prod.bak"
else
    err "Aucune source trouvée.
  Options :
    - Exécuter dev_setup.sh (clone le dépôt)
    - Relancer deploy_on_pi.sh (installation fraîche)"
fi

# ── Remplacer le symlink/dossier par une copie réelle ─────────
log "Copie ${SRC} → ${PORTAL_DEST}..."
sudo rm -rf "$PORTAL_DEST"
sudo cp -r "$SRC" "$PORTAL_DEST"
sudo chown -R www-data:www-data "$PORTAL_DEST"
sudo find "$PORTAL_DEST" -name "*.sh" -exec chmod +x {} \;
sudo find "$PORTAL_DEST" -name "*.sh" -path "*/api/*" -exec chmod +x {} \;

log "Portail restauré en mode production"

# Nettoyer la sauvegarde si elle existe maintenant qu'on a le workspace
if [ -d "${INSTALL_DIR}/portal.prod.bak" ] && [ -d "${DEV_DIR}/.git" ]; then
    sudo rm -rf "${INSTALL_DIR}/portal.prod.bak"
    log "Sauvegarde portal.prod.bak supprimée"
fi

sudo systemctl reload lighttpd 2>/dev/null || sudo systemctl restart lighttpd 2>/dev/null || true

SPOT_IP=$(grep "^SPOT_IP=" "${INSTALL_DIR}/soundspot.conf" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "192.168.10.1")
echo -e "  Portal ${C}http://${SPOT_IP}/${N} → copie prod ${W}(main)${N}"
