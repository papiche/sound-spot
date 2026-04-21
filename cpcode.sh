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
Usage : ./cpcode.sh GROUP1 [GROUP2 ...] [--json] [--maxfilesize N]

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
  ./cpcode.sh --apps --frontend --config
EOF
    exit 0
}

# ── Parsing ────────────────────────────────────────────────────────────────
GROUPS=()
CPCODE_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --install|--backend|--frontend|--apps|--picoport|--config|--dev|--all) GROUPS+=("$arg") ;;
        --help|-h) show_help ;;
        *) CPCODE_ARGS+=("$arg") ;;
    esac
done

[ ${#GROUPS[@]} -eq 0 ] && show_help

# ── Dossier temporaire ────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d /tmp/ss_ctx_XXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

# ── Helpers de copie ──────────────────────────────────────────────────────
# _add "chemin/vers/fichier_ou_glob"
_add() {
    for pat in "$@"; do
        echo "Recherche de fichiers pour le motif : $pat"
        if [[ "$pat" == *"*"* ]]; then
            dirname=$(dirname "$pat")
            basename=$(basename "$pat")
            echo "  Recherche dans : $SCRIPT_DIR/$dirname avec le motif : $basename"
            find "$SCRIPT_DIR/$dirname" -maxdepth 1 -type f -name "$basename" | while read -r f; do
                echo "  Trouvé : $f"
                rel="${f#"$SCRIPT_DIR/"}"
                dest="$WORK_DIR/$rel"
                echo "  Copie de $f vers $dest"
                mkdir -p "$(dirname "$dest")"
                cp "$f" "$dest"
            done
        else
            if [ -f "$SCRIPT_DIR/$pat" ]; then
                echo "  Trouvé : $SCRIPT_DIR/$pat"
                rel="${pat}"
                dest="$WORK_DIR/$rel"
                echo "  Copie de $SCRIPT_DIR/$pat vers $dest"
                mkdir -p "$(dirname "$dest")"
                cp "$SCRIPT_DIR/$pat" "$dest"
            else
                echo "  Avertissement : $SCRIPT_DIR/$pat introuvable."
            fi
        fi
    done
}

_add_dir() {
    local dir="$1"
    if [ -d "$SCRIPT_DIR/$dir" ]; then
        echo "Copie du dossier : $SCRIPT_DIR/$dir"
        cp -r "$SCRIPT_DIR/$dir" "$WORK_DIR/"
    else
        echo "Avertissement : Le dossier $SCRIPT_DIR/$dir n'existe pas."
    fi
}

# ── Dispatching ────────────────────────────────────────────────────────────
EXTS="sh py html js json md conf service" # Extensions par défaut

for GROUP in "${GROUPS[@]}"; do
    case "$GROUP" in
        --install)
            echo "Cible : Installation & Déploiement"
            _add "deploy_on_pi.sh" "dj_mixxx_setup.sh" "setup_uninstall.sh" "check.sh"
            _add "src/install_*.sh"
            _add_dir "src/install"
            EXTS="$EXTS md"
            ;;

        --backend)
            echo "Cible : Backend (Audio, Video, System)"
            _add "src/backend/log.sh" "src/backend/bt_update.sh"
            _add_dir "src/backend"
            _add_dir "monitor"
            _add "src/config/services/soundspot-idle.service"
            _add "src/config/services/soundspot-decoder.service"
            EXTS="$EXTS service"
            ;;

        --frontend)
            echo "Cible : Frontend (Portail Captif)"
            _add "src/portal/*.sh" "src/portal/*.html" "src/portal/*.js" "src/portal/*.json"
            _add_dir "src/portal/api/core"
            EXTS="$EXTS html js json"
            ;;

        --apps)
            echo "Cible : API & Apps"
            _add "src/portal/api.sh"
            _add_dir "src/portal/api/apps"
            _add_dir "src/portal/api/core"
            EXTS="$EXTS json"
            ;;

        --picoport)
            echo "Cible : Picoport & Swarm"
            _add_dir "src/picoport"
            _add "src/config/services/picoport.service"
            _add "src/config/services/soundspot-swarm-sync.service"
            EXTS="$EXTS service"
            ;;

        --config)
            echo "Cible : Configurations & Systemd"
            _add_dir "src/config"
            _add "src/wpa_supplicant.conf"
            EXTS="$EXTS conf xml"
            ;;

        --dev)
            echo "Cible : Développement & Docs"
            _add "*.md" "CLAUDE.md"
            _add_dir "src/dev"
            _add_dir "test"
            EXTS="$EXTS md json"
            ;;

        --all)
            echo "Cible : Projet Complet"
            _add_dir "src"
            _add_dir "monitor"
            _add_dir "test"
            _add "*.sh" "*.md"
            ;;
    esac
done

# ── Exécution ──────────────────────────────────────────────────────────────
echo "Extraction des fichiers dans $WORK_DIR..."
cd "$WORK_DIR"
echo "SCRIPT_DIR est défini à : $SCRIPT_DIR"
# Afficher le contenu du dossier temporaire pour débogage
echo "Contenu de $WORK_DIR :"
find . -type f | sort

# On transforme la liste d'extensions pour cpcode (ex: "sh py" -> "sh py")
# Note: cpcode attend les extensions comme arguments séparés avant les options
echo "Extensions passées à cpcode : $EXTS"
exec "$CPCODE" $EXTS "${CPCODE_ARGS[@]}" .