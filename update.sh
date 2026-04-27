#!/bin/bash
# update.sh — Mise à jour rapide du portail et du backend SoundSpot sur le Pi en cours
#             Sans réinstallation complète (pas de systemd, pas de packages)
#
# Usage :
#   sudo bash update.sh              # portail + backend + picoport
#   sudo bash update.sh --pinout     # + régénération de la page pinout

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/soundspot}"
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Couleurs ──────────────────────────────────────────────────
G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; N='\033[0m'
log()  { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }

# ── Vérifications ─────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    warn "Ce script doit être lancé en root (sudo bash update.sh)"
    exit 1
fi

[ -d "$SCRIPT_DIR/src/portal" ]  || { warn "Répertoire src/portal introuvable — lancez depuis la racine du dépôt"; exit 1; }
[ -d "$INSTALL_DIR" ]            || { warn "$INSTALL_DIR inexistant — faites d'abord l'installation complète"; exit 1; }

WITH_PINOUT=false
for arg in "$@"; do
    [ "$arg" = "--pinout" ] && WITH_PINOUT=true
done

# ── Portail (portal/) ─────────────────────────────────────────
hdr "Mise à jour du portail"
rsync -a --delete \
    --exclude='pinout/' \
    "$SCRIPT_DIR/src/portal/" "$INSTALL_DIR/portal/"
chmod -R a+rX "$INSTALL_DIR/portal/"
log "portal/ synchronisé"

# ── Backend audio ─────────────────────────────────────────────
hdr "Mise à jour du backend"
rsync -a --delete \
    "$SCRIPT_DIR/src/backend/" "$INSTALL_DIR/backend/"
chmod -R a+rX "$INSTALL_DIR/backend/"
find "$INSTALL_DIR/backend/" -name "*.sh" -exec chmod +x {} \;
log "backend/ synchronisé"

# ── Picoport ──────────────────────────────────────────────────
hdr "Mise à jour de picoport"
rsync -a --delete \
    "$SCRIPT_DIR/src/picoport/" "$INSTALL_DIR/picoport/"
chmod -R a+rX "$INSTALL_DIR/picoport/"
find "$INSTALL_DIR/picoport/" -name "*.sh" -exec chmod +x {} \;
log "picoport/ synchronisé"

# ── Pinout (optionnel) ────────────────────────────────────────
if $WITH_PINOUT; then
    hdr "Régénération de la page Pinout"
    PINOUT_REPO="$(eval echo ~${SOUNDSPOT_USER})/.zen/workspace/Pinout.xyz"
    PORTAL_PINOUT="$INSTALL_DIR/portal/pinout"

    if [ ! -d "$PINOUT_REPO" ]; then
        warn "Dépôt Pinout.xyz absent : $PINOUT_REPO"
        warn "Clonez-le d'abord : sudo -u $SOUNDSPOT_USER git clone https://github.com/pinout-xyz/Pinout.xyz $PINOUT_REPO"
    else
        cd "$PINOUT_REPO"

        # Patcher resource_url pour servir sous /pinout/ (chemins absolus → /pinout/resources/)
        sudo -u "$SOUNDSPOT_USER" sed -i \
            's|resource_url: /resources/|resource_url: /pinout/resources/|' \
            "src/en/settings.yaml" 2>/dev/null || true

        if [ -f "generate-html.py" ]; then
            sudo -u "$SOUNDSPOT_USER" python3 generate-html.py en 2>&1 | tail -5 \
                || warn "generate-html.py a retourné une erreur (non fatal)"
        fi

        if [ -d "output/en" ]; then
            rm -rf "$PORTAL_PINOUT"
            mkdir -p "$PORTAL_PINOUT"
            cp -r output/en/* "$PORTAL_PINOUT/"

            if [ -d "resources" ]; then
                cp -r resources "$PORTAL_PINOUT/"
                log "resources/ copié"
            fi

            if [ -d "phatstack" ]; then
                cp -r phatstack "$PORTAL_PINOUT/"
                log "phatstack/ copié"
            fi

            chmod -R a+rX "$PORTAL_PINOUT/"
            log "Pinout → $PORTAL_PINOUT"

            # Snippet lighttpd : URLs propres /pinout/sdio → /pinout/sdio.html
            cat > /etc/lighttpd/conf-available/90-pinout.conf <<'LCONF'
url.rewrite-once += (
    "^/pinout/([^/.]+)$" => "/pinout/$1.html"
)
LCONF
            ln -sf /etc/lighttpd/conf-available/90-pinout.conf \
                   /etc/lighttpd/conf-enabled/90-pinout.conf 2>/dev/null || true
            log "lighttpd : règle pinout URL rewrite activée"
        else
            warn "output/en/ absent — génération peut-être échouée"
        fi
    fi
fi

# ── Permissions wav/ ──────────────────────────────────────────
if [ -d "$INSTALL_DIR/wav" ]; then
    chown -R www-data:www-data "$INSTALL_DIR/wav"
    chmod -R ug+rw "$INSTALL_DIR/wav"
    log "wav/ permissions corrigées (www-data)"
fi

# ── Rechargement lighttpd ─────────────────────────────────────
hdr "Rechargement lighttpd"
if systemctl is-active --quiet lighttpd 2>/dev/null; then
    systemctl reload lighttpd && log "lighttpd rechargé" || warn "reload lighttpd échoué"
else
    warn "lighttpd non actif — démarrage..."
    systemctl start lighttpd || warn "Impossible de démarrer lighttpd"
fi

echo ""
log "Mise à jour terminée."
$WITH_PINOUT && log "Pinout disponible sur http://192.168.10.1/pinout/" || true
