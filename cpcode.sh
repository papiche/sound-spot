#!/bin/bash
# ═════════════════════════════════════════════════════════════════════════════
#  cpcode.sh — Extracteur de contexte pour IA (SoundSpot Edition)
# ═════════════════════════════════════════════════════════════════════════════
# ── Convention de nommage src/config/ ─────────────────────────────────────
# Les nouveaux fichiers sont automatiquement routés vers le bon groupe selon :
#
#   portal_*.sh           → --frontend   (CGI web : portail captif)
#   *.service             → --config     (unités systemd)
#   *.conf                → --config     (fichiers de configuration)
#   soundspot.conf.*      → --config     (config centrale master/satellite)
#   soundspot-*logrotate* → --config     (configs logrotate sans extension std)
#   *.sh  (hors portal_*) → --backend    (scripts runtime audio/système)
#   *.py                  → --backend    (daemons Python)
#
# Pour ajouter un nouveau groupe ou modifier le routage, éditez uniquement les
# fonctions _templates_match / _templates_except et les blocs case ci-dessous.
# ─────────────────────────────────────────────────────────────────────────────

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/src"
# Chemin vers l'outil cpcode original d'Astroport
CPCODE="$(realpath "$SCRIPT_DIR/../Astroport.ONE/cpcode" 2>/dev/null || echo "/usr/local/bin/cpcode")"

if [ ! -x "$CPCODE" ]; then
    echo "Erreur : L'outil 'cpcode' est introuvable."
    echo "Assurez-vous qu'Astroport.ONE est cloné à côté de sound-spot."
    exit 1
fi

# ── Aide ───────────────────────────────────────────────────────────────────
show_help() {
    cat <<'EOF'
Usage : ./cpcode.sh GROUP [--json] [--maxfilesize N]

Groupes disponibles :
  --install    Scripts de déploiement, modules d'install et templates initiaux.
  --backend    Logique métier : audio (annonces), system (BT, réseau), video (jukebox).
  --frontend   Interface web (HTML/JS) et scripts CGI du portail.
  --apps       Développement de modules API (core/ + apps/).
  --picoport   Nœud P2P : IPFS, Nostr, Duniter, Swarm Sync.
  --config     Toutes les unités systemd et fichiers de conf réseau.
  --dev        Outils de debug, benchmarks et documentation.
  --all        Extraction totale du projet.

Exemples :
  ./cpcode.sh --backend
  ./cpcode.sh --apps --json
EOF
    exit 0
}

# ── Parsing ────────────────────────────────────────────────────────────────
GROUP=""
CPCODE_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --install|--backend|--frontend|--apps|--picoport|--config|--dev|--all) GROUP="$arg" ;;
        --help|-h) show_help ;;
        *) CPCODE_ARGS+=("$arg") ;;
    esac
done

[ -z "$GROUP" ] && show_help

# ── Dossier temporaire ────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d /tmp/ss_ctx_XXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

# ── Helpers de copie ──────────────────────────────────────────────────────
# _add "chemin/vers/fichier_ou_glob"
_add() {
    for pat in "$@"; do
        # On utilise find pour gérer les globs récursivement si nécessaire
        find "$SCRIPT_DIR" -path "$SCRIPT_DIR/$pat" -type f ! -path "*/.*" | while read -r f; do
            rel="${f#"$SCRIPT_DIR/"}"
            dest="$WORK_DIR/$rel"
            mkdir -p "$(dirname "$dest")"
            cp "$f" "$dest"
        done
    done
}

# _add_dir "nom_dossier"
_add_dir() {
    if [ -d "$SCRIPT_DIR/$1" ]; then
        cp -r "$SCRIPT_DIR/$1" "$WORK_DIR/"
    fi
}

# ── Dispatching ────────────────────────────────────────────────────────────
EXTS="sh py html js json md conf service" # Extensions par défaut

case "$GROUP" in
    --install)
        echo "Cible : Installation & Déploiement"
        _add "deploy_on_pi.sh" "dj_mixxx_setup.sh" "setup_uninstall.sh" "check.sh"
        _add "src/install_*.sh"
        _add_dir "src/install"
        EXTS="sh md"
        ;;

    --backend)
        echo "Cible : Backend (Audio, Video, System)"
        _add "src/log.sh" "src/bt_update.sh"
        _add_dir "src/backend"
        _add_dir "monitor"
        _add "src/config/services/soundspot-idle.service"
        _add "src/config/services/soundspot-decoder.service"
        EXTS="sh py service"
        ;;

    --frontend)
        echo "Cible : Frontend (Portail Captif)"
        _add "src/portal/*.sh" "src/portal/*.html" "src/portal/*.js" "src/portal/*.json"
        _add_dir "src/portal/api/core"
        EXTS="html js sh json"
        ;;

    --apps)
        echo "Cible : API & Apps"
        _add "src/portal/api.sh"
        _add_dir "src/portal/api/apps"
        _add_dir "src/portal/api/core"
        EXTS="sh json"
        ;;

    --picoport)
        echo "Cible : Picoport & Swarm"
        _add_dir "src/picoport"
        _add "src/config/services/picoport.service"
        _add "src/config/services/soundspot-swarm-sync.service"
        EXTS="sh py json service"
        ;;

    --config)
        echo "Cible : Configurations & Systemd"
        _add_dir "src/config"
        _add "src/wpa_supplicant.conf"
        EXTS="conf service sh xml"
        ;;

    --dev)
        echo "Cible : Développement & Docs"
        _add "*.md" "CLAUDE.md"
        _add_dir "src/dev"
        _add_dir "test"
        EXTS="md sh json"
        ;;

    --all)
        echo "Cible : Projet Complet"
        _add_dir "src"
        _add_dir "monitor"
        _add_dir "test"
        _add "*.sh" "*.md"
        ;;
esac

# ── Exécution ──────────────────────────────────────────────────────────────
echo "Extraction des fichiers dans $WORK_DIR..."
cd "$WORK_DIR"

# On transforme la liste d'extensions pour cpcode (ex: "sh py" -> "sh py")
# Note: cpcode attend les extensions comme arguments séparés avant les options
exec "$CPCODE" $EXTS "${CPCODE_ARGS[@]}" .