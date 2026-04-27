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

            # Aplatir pinout/pinout/*.html → pinout/[nom]/index.html
            # (évite toute règle URL rewrite dans lighttpd)
            if [ -d "$PORTAL_PINOUT/pinout" ]; then
                for f in "$PORTAL_PINOUT/pinout/"*.html; do
                    [ -f "$f" ] || continue
                    name=$(basename "$f" .html)
                    mkdir -p "$PORTAL_PINOUT/$name"
                    cp "$f" "$PORTAL_PINOUT/$name/index.html"
                done
                log "pages pinout aplaties dans $PORTAL_PINOUT/"
            fi

            # Réécrire les liens absolus Pinout.xyz pour le sous-chemin /pinout/
            python3 - "$PORTAL_PINOUT" <<'PYEOF'
import re, os, sys
root = sys.argv[1]
def fix(t):
    t = t.replace('href="/"', 'href="/pinout/"')
    t = re.sub(r'href="/((?!pinout/)(?!/)[^"]+)"', r'href="/pinout/\1"', t)
    t = re.sub(r'src="/((?!pinout/)(?!/)[^"]+)"',  r'src="/pinout/\1"',  t)
    return t
n = 0
for d, _, files in os.walk(root):
    for f in files:
        if not f.endswith('.html'): continue
        p = os.path.join(d, f)
        orig = open(p).read()
        fixed = fix(orig)
        if fixed != orig:
            open(p,'w').write(fixed)
            n += 1
print(f'{n} fichiers HTML mis à jour')
PYEOF

            chmod -R a+rX "$PORTAL_PINOUT/"
            log "Pinout → $PORTAL_PINOUT"

            # Nettoyer toute règle pinout résiduelle dans lighttpd.conf
            python3 - <<'PYEOF'
import re, sys
f = '/etc/lighttpd/lighttpd.conf'
try:
    t = open(f).read()
    if 'pinout' not in t:
        sys.exit(0)
    block = re.search(r'url\.rewrite-once\s*=\s*\(.*?\n\)', t, re.DOTALL)
    if block:
        new = ('url.rewrite-once = (\n'
               '    "^/(generate_204|hotspot-detect.html|ncsi.txt|success.txt).*$" => "/index.sh"\n'
               ')')
        open(f, 'w').write(t[:block.start()] + new + t[block.end():])
        print('lighttpd.conf : règle pinout supprimée')
except Exception as e:
    print(f'WARN : {e}', file=sys.stderr)
PYEOF
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

# ── Activer accesslog dans lighttpd.conf si absent ───────────
python3 - <<'PYEOF'
import sys
f = '/etc/lighttpd/lighttpd.conf'
try:
    t = open(f).read()
    if 'mod_accesslog' in t:
        sys.exit(0)
    t = t.replace('"mod_cgi"', '"mod_cgi",\n    "mod_accesslog"')
    t = t.replace(
        'server.errorlog',
        'accesslog.filename = "/var/log/lighttpd/access.log"\n'
        'accesslog.format   = "%t %h \\"%r\\" %>s %b"\nserver.errorlog'
    )
    open(f, 'w').write(t)
    print('lighttpd : accesslog activé')
except Exception as e:
    print(f'WARN : {e}', file=sys.stderr)
PYEOF

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
