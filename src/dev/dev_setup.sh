#!/bin/bash
# ════════════════════════════════════════════════════════════════════
#  src/dev/dev_setup.sh — Environnement de développement SoundSpot
#                         sur Picoport (~/.zen/workspace/)
# ════════════════════════════════════════════════════════════════════
#
#  Usage :
#    bash src/dev/dev_setup.sh [nom-de-branche]
#
#  Exemples :
#    bash src/dev/dev_setup.sh                    # branche dev-$(hostname)
#    bash src/dev/dev_setup.sh dev-yt-module      # branche nommée
#    bash src/dev/dev_setup.sh dev-alice-portal   # branche personnelle
#
#  Ce que ça fait :
#    1. Clone (ou met à jour) le dépôt dans ~/.zen/workspace/sound-spot
#    2. Crée / checkout la branche de développement demandée
#    3. Crée le groupe "soundspot" et y ajoute www-data + l'utilisateur courant
#    4. Remplace /opt/soundspot/portal par un symlink vers le workspace
#    5. Les modifications dans src/portal/ sont visibles IMMÉDIATEMENT
#       au prochain rechargement de la page — sans aucun déploiement.
#
#  Prérequis :
#    - Picoport installé (PICOPORT_ENABLED=true lors du deploy)
#    - git configuré (nom + email — ce script le demande si absent)
#    - Accès sudo (pour le symlink /opt/soundspot/portal)
#
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Couleurs (compatibles deploy_on_pi.sh) ───────────────────
G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; W='\033[1;37m'
M='\033[0;35m'; N='\033[0m'; DIM='\033[2m'; R='\033[0;31m'
log()  { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err()  { echo -e "${R}✗${N}  $*" >&2; exit 1; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }
ask()  { echo -ne "${M}?${N}  $*"; }

# ── Paramètres ───────────────────────────────────────────────
SOUNDSPOT_USER="${SUDO_USER:-$(whoami)}"
INSTALL_DIR="/opt/soundspot"
WORKSPACE_DIR="${HOME}/.zen/workspace"
DEV_DIR="${WORKSPACE_DIR}/sound-spot"
REPO_URL="${SOUNDSPOT_REPO:-https://github.com/papiche/sound-spot}"
BRANCH="${1:-dev-$(hostname)}"

# ════════════════════════════════════════════════════════════════
#  1. Git identity (demander si absente)
# ════════════════════════════════════════════════════════════════
hdr "Identité Git"
GIT_NAME=$(git config --global user.name 2>/dev/null || true)
GIT_EMAIL=$(git config --global user.email 2>/dev/null || true)

if [ -z "$GIT_NAME" ]; then
    ask "Votre nom (pour les commits) : "
    read -r GIT_NAME
    git config --global user.name "$GIT_NAME"
fi
if [ -z "$GIT_EMAIL" ]; then
    ask "Votre email : "
    read -r GIT_EMAIL
    git config --global user.email "$GIT_EMAIL"
fi
log "Git : ${W}${GIT_NAME}${N} <${GIT_EMAIL}>"

# ════════════════════════════════════════════════════════════════
#  2. Clone ou mise à jour dans ~/.zen/workspace/sound-spot
# ════════════════════════════════════════════════════════════════
hdr "Dépôt ~/.zen/workspace/sound-spot"
mkdir -p "$WORKSPACE_DIR"

if [ -d "${DEV_DIR}/.git" ]; then
    log "Dépôt existant — mise à jour de main..."
    cd "$DEV_DIR"
    CURRENT_BRANCH=$(git branch --show-current)
    # Sauvegarder la branche courante et syncer main sans la casser
    git fetch origin --quiet
    git checkout main --quiet
    git pull origin main --quiet 2>/dev/null \
        || warn "Impossible de syncer main (pas de remote ?)"
    # Revenir à la branche précédente si différente
    [ "$CURRENT_BRANCH" != "main" ] && git checkout "$CURRENT_BRANCH" --quiet 2>/dev/null || true
else
    log "Clonage de ${C}${REPO_URL}${N}..."
    git clone "$REPO_URL" "$DEV_DIR"
    cd "$DEV_DIR"
fi

# ════════════════════════════════════════════════════════════════
#  3. Créer / checkout la branche de développement
# ════════════════════════════════════════════════════════════════
hdr "Branche de développement : ${W}${BRANCH}${N}"
cd "$DEV_DIR"

if git branch --list "$BRANCH" | grep -q "$BRANCH"; then
    log "Branche locale existante — checkout"
    git checkout "$BRANCH" --quiet
    # Essayer de syncer depuis le remote si elle existe
    git pull origin "$BRANCH" --quiet 2>/dev/null || true
elif git branch -r | grep -q "origin/${BRANCH}"; then
    log "Branche distante trouvée — checkout avec tracking"
    git checkout -b "$BRANCH" "origin/${BRANCH}" --quiet
else
    log "Nouvelle branche créée depuis main"
    git checkout main --quiet
    git checkout -b "$BRANCH" --quiet
fi

log "Branche active : ${W}$(git branch --show-current)${N}"

# ════════════════════════════════════════════════════════════════
#  4. Groupe "soundspot" — www-data + développeur partagent l'accès
#     Évite d'exposer ~/ à www-data via chmod o+rx
# ════════════════════════════════════════════════════════════════
hdr "Permissions (groupe soundspot)"
if ! getent group soundspot >/dev/null 2>&1; then
    sudo groupadd soundspot
    log "Groupe soundspot créé"
fi

sudo usermod -aG soundspot www-data 2>/dev/null || true
sudo usermod -aG soundspot "$SOUNDSPOT_USER" 2>/dev/null || true
log "www-data + ${SOUNDSPOT_USER} → groupe soundspot"

# Appliquer les permissions sur le portal du workspace
find "${DEV_DIR}/src/portal" -type d -exec sudo chmod g+rx {} \;
find "${DEV_DIR}/src/portal" -type f -exec sudo chmod g+r  {} \;
find "${DEV_DIR}/src/portal" -name "*.sh" -exec sudo chmod g+rx {} \;
sudo chgrp -R soundspot "${DEV_DIR}/src/portal"

# S'assurer que les dossiers parents sont traversables par le groupe
for _dir in "$HOME" "${HOME}/.zen" "${WORKSPACE_DIR}" "$DEV_DIR" "${DEV_DIR}/src"; do
    sudo chmod g+x "$_dir" 2>/dev/null || true
    sudo chgrp soundspot "$_dir" 2>/dev/null || true
done

log "Permissions portal workspace : ok"

# ════════════════════════════════════════════════════════════════
#  5. Activer le mode dev : symlink /opt/soundspot/portal → workspace
# ════════════════════════════════════════════════════════════════
hdr "Activation mode DEV"

PORTAL_PROD="${INSTALL_DIR}/portal"
PORTAL_DEV="${DEV_DIR}/src/portal"

# Sauvegarder la version de production si c'est une copie (pas encore un symlink)
if [ -d "$PORTAL_PROD" ] && [ ! -L "$PORTAL_PROD" ]; then
    sudo mv "$PORTAL_PROD" "${INSTALL_DIR}/portal.prod.bak"
    log "Sauvegarde portail prod → portal.prod.bak"
fi

sudo ln -sfn "$PORTAL_DEV" "$PORTAL_PROD"
log "Symlink : ${C}${PORTAL_PROD}${N} → ${W}${PORTAL_DEV}${N}"

# Recharger lighttpd (pas de restart — évite de couper le stream)
sudo systemctl reload lighttpd 2>/dev/null || sudo systemctl restart lighttpd 2>/dev/null || true

# ════════════════════════════════════════════════════════════════
#  6. Résumé et commandes utiles
# ════════════════════════════════════════════════════════════════
SPOT_IP=$(grep "^SPOT_IP=" "${INSTALL_DIR}/soundspot.conf" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "192.168.10.1")

echo -e "
${W}┌─────────────────────────────────────────────────────────────┐
│   Mode DEV SoundSpot activé                                 │
├─────────────────────────────────────────────────────────────┤${N}
  Dépôt    : ${C}${DEV_DIR}${N}
  Branche  : ${W}${BRANCH}${N}
  Portal   : ${C}${PORTAL_PROD}${N} → ${W}${PORTAL_DEV}${N}
  Portail  : ${G}http://${SPOT_IP}/${N}

  ${DIM}Modifier un fichier dans src/portal/ = visible immédiatement.${N}
  ${DIM}Pas de redéploiement. Pas de redémarrage.${N}

  ${W}Commandes utiles :${N}
  ${C}# Changer de branche${N}
    bash ${DEV_DIR}/src/dev/dev_switch.sh <autre-branche>

  ${C}# Committer et pousser${N}
    cd ${DEV_DIR}
    git add src/portal/
    git commit -m 'feat: mon module'
    git push origin ${BRANCH}

  ${C}# Revenir en production (branche main)${N}
    bash ${DEV_DIR}/src/dev/dev_switch.sh main

  ${C}# Désactiver le mode dev (restaurer copie prod)${N}
    bash ${DEV_DIR}/src/dev/dev_restore.sh
${W}└─────────────────────────────────────────────────────────────┘${N}"
