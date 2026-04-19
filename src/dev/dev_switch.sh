#!/bin/bash
# ════════════════════════════════════════════════════════════════════
#  src/dev/dev_switch.sh — Changer de branche sur le nœud en live
# ════════════════════════════════════════════════════════════════════
#
#  Usage :
#    bash src/dev/dev_switch.sh <branche>
#    bash src/dev/dev_switch.sh main          # revenir en production
#    bash src/dev/dev_switch.sh dev-ma-chose  # tester une autre branche
#    bash src/dev/dev_switch.sh              # afficher la branche courante
#
#  Prérequis : dev_setup.sh a déjà été exécuté au moins une fois.
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; W='\033[1;37m'
N='\033[0m'; R='\033[0;31m'
log()  { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err()  { echo -e "${R}✗${N}  $*" >&2; exit 1; }

DEV_DIR="${HOME}/.zen/workspace/sound-spot"
INSTALL_DIR="/opt/soundspot"

# ── Vérifier que le workspace existe ─────────────────────────
if [ ! -d "${DEV_DIR}/.git" ]; then
    err "Workspace non initialisé. Exécutez d'abord :
    bash src/dev/dev_setup.sh [nom-de-branche]"
fi

# ── Mode "afficher statut" si pas d'argument ─────────────────
if [ $# -eq 0 ]; then
    cd "$DEV_DIR"
    CURRENT=$(git branch --show-current)
    PORTAL_TARGET=$(readlink -f "${INSTALL_DIR}/portal" 2>/dev/null || echo "(copie prod)")
    echo -e "
  Dépôt   : ${C}${DEV_DIR}${N}
  Branche : ${W}${CURRENT}${N}
  Portal  : ${C}${INSTALL_DIR}/portal${N} → ${W}${PORTAL_TARGET}${N}

  Branches disponibles :"
    git branch -a | sed 's/remotes\/origin\///' | sort -u | while read -r b; do
        [ "${b##\* }" = "$CURRENT" ] \
            && echo -e "    ${G}* ${b}${N}" \
            || echo -e "      ${b}"
    done
    exit 0
fi

TARGET_BRANCH="$1"

# ── Fetch + checkout ──────────────────────────────────────────
cd "$DEV_DIR"
log "Fetch origin..."
git fetch origin --quiet 2>/dev/null || warn "Pas de remote — travail hors-ligne"

# Créer tracking branch si elle n'existe que sur le remote
if ! git branch --list "$TARGET_BRANCH" | grep -q "$TARGET_BRANCH"; then
    if git branch -r | grep -q "origin/${TARGET_BRANCH}"; then
        git checkout -b "$TARGET_BRANCH" "origin/${TARGET_BRANCH}" --quiet
    else
        err "Branche '${TARGET_BRANCH}' introuvable localement ni sur origin.
  Branches disponibles :
$(git branch -a | sed 's/remotes\/origin\///' | sort -u)"
    fi
else
    git checkout "$TARGET_BRANCH" --quiet
fi

# Syncer depuis le remote si la branche existe en amont
if git rev-parse --abbrev-ref "${TARGET_BRANCH}@{upstream}" >/dev/null 2>&1; then
    git pull --ff-only 2>/dev/null || warn "Merge impossible (commits locaux divergents ?)"
fi

ACTUAL=$(git branch --show-current)
log "Branche active : ${W}${ACTUAL}${N}"

# ── Corriger les permissions (nouveau fichier peut manquer g+rx) ──
find "${DEV_DIR}/src/portal" -type d -exec sudo chmod g+rx {} \; 2>/dev/null || true
find "${DEV_DIR}/src/portal" -name "*.sh" -exec sudo chmod g+rx {} \; 2>/dev/null || true
find "${DEV_DIR}/src/portal" -type f ! -name "*.sh" -exec sudo chmod g+r {} \; 2>/dev/null || true

# ── Vérifier que le symlink est en place ─────────────────────
PORTAL="${INSTALL_DIR}/portal"
EXPECTED="${DEV_DIR}/src/portal"

if [ ! -L "$PORTAL" ] || [ "$(readlink -f "$PORTAL")" != "$(readlink -f "$EXPECTED")" ]; then
    warn "Le symlink portal n'est pas actif — réactivation..."
    sudo ln -sfn "$EXPECTED" "$PORTAL"
fi

# Recharger lighttpd sans couper le stream Snapcast
sudo systemctl reload lighttpd 2>/dev/null || true

SPOT_IP=$(grep "^SPOT_IP=" "${INSTALL_DIR}/soundspot.conf" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "192.168.10.1")
echo -e "  ${G}✓${N} Portal sur ${C}http://${SPOT_IP}/${N} sert la branche ${W}${ACTUAL}${N}"
