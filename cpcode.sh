#!/bin/bash
# cpcode.sh — Copie le code SoundSpot dans le presse-papiers (via Astroport.ONE/cpcode)
#
# Usage :
#   ./cpcode.sh GROUP [--json] [--maxfilesize N]
#
# Groupes :
#   --install    Installation du nœud
#   --backend    Pipeline audio & services runtime
#   --frontend   Portail captif web
#   --picoport   Nœud IPFS / Nostr / Ğ1
#   --apps       Applications du portail
#   --config     Templates systemd & configuration
#   --all        Tout le code
#
# ── Convention de nommage src/templates/ ─────────────────────────────────────
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
CPCODE="$(realpath "$SCRIPT_DIR/../Astroport.ONE/cpcode")"

[ -x "$CPCODE" ] || { echo "Erreur : cpcode introuvable → $CPCODE"; exit 1; }

echo "cpcode is an Astroport.ONE - code to IA prompt tool -"

# ── Aide ───────────────────────────────────────────────────────────────────
show_help() {
    cat <<'EOF'

Usage : ./cpcode.sh GROUP [--json] [--maxfilesize N]

Groupes disponibles :
  --install    Installation du nœud
                 deploy_on_pi, install_soundspot, modules src/install/
                 → déploiement et intégration RPi

  --backend    Pipeline audio & services runtime
                 idle, decoder, presence, battery, jukebox, log, firewall, monitor
                 Convention templates : *.sh (hors portal_*), *.py
                 → daemons audio et services système

  --frontend   Portail captif web complet
                 src/portal/ + templates portal_*.sh
                 Convention templates : portal_*.sh
                 → interface web du spot (HTML/JS/CGI)

  --picoport   Nœud IPFS / Nostr / Ğ1 UPlanet
                 src/picoport/ (daemon, clés Y-Level, cron solaire)
                 → nœud P2P UPlanet

  --apps       Applications accessibles depuis le portail
                 src/portal/api/ (router + core + apps/)
                 → développement de nouvelles apps portail

  --config     Templates systemd et fichiers de configuration
                 Convention templates : *.service, *.conf, soundspot-*logrotate*
                 → configuration des services et du réseau

  --all        Tout le code (toutes extensions, tout le répertoire)

Options cpcode (transmises directement) :
  --json                 Sortie JSON compatible LLM
  --maxfilesize N        Limite par fichier en octets

Exemples :
  ./cpcode.sh --frontend
  ./cpcode.sh --apps --json
  ./cpcode.sh --install --maxfilesize 102400
  ./cpcode.sh --all

EOF
    exit 0
}

# ── Parsing des arguments ──────────────────────────────────────────────────
GROUP=""
CPCODE_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --install|--backend|--frontend|--picoport|--apps|--config|--all)
            GROUP="$arg" ;;
        --help|-h)
            show_help ;;
        *)
            CPCODE_ARGS+=("$arg") ;;
    esac
done

[ -z "$GROUP" ] && show_help

# ── --all : tout le code ──────────────────────────────────────────────────
if [ "$GROUP" = "--all" ]; then
    echo "Groupe : ALL"
    exec "$CPCODE" py sh md conf service html json js "${CPCODE_ARGS[@]}" "$SCRIPT_DIR"
fi

# ── Répertoire de travail temporaire ─────────────────────────────────────
WORK_DIR=$(mktemp -d /tmp/soundspot_cpcode_XXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

# ── Fonctions helpers ─────────────────────────────────────────────────────

# _add GLOB [GLOB...]
# Copie les fichiers correspondant aux globs (relatifs à SCRIPT_DIR) dans WORK_DIR.
_add() {
    local found=0
    for pat in "$@"; do
        for f in "$SCRIPT_DIR/"$pat; do
            [ -f "$f" ] || continue
            rel="${f#"$SCRIPT_DIR/"}"
            dest="$WORK_DIR/$rel"
            mkdir -p "$(dirname "$dest")"
            cp "$f" "$dest"
            (( found++ )) || true
        done
    done
    [ "$found" -eq 0 ] && echo "  [aucun fichier] $*" || true
}

# _add_dir DIR
# Copie récursivement un répertoire entier (relatif à SCRIPT_DIR) dans WORK_DIR.
_add_dir() {
    local dir="$SCRIPT_DIR/$1"
    [ -d "$dir" ] || { echo "  [absent] $1/"; return; }
    find "$dir" -type f ! -path "*/.git/*" | while IFS= read -r f; do
        rel="${f#"$SCRIPT_DIR/"}"
        dest="$WORK_DIR/$rel"
        mkdir -p "$(dirname "$dest")"
        cp "$f" "$dest"
    done
}

# _templates_match PAT [PAT...]
# Copie les fichiers de src/templates/ dont le basename correspond à AU MOINS UN pattern bash.
_templates_match() {
    while IFS= read -r -d '' f; do
        local base; base=$(basename "$f")
        local match=0
        for pat in "$@"; do
            [[ "$base" == $pat ]] && match=1 && break
        done
        [ "$match" -eq 0 ] && continue
        rel="${f#"$SCRIPT_DIR/"}"
        dest="$WORK_DIR/$rel"
        mkdir -p "$(dirname "$dest")"
        cp "$f" "$dest"
    done < <(find "$SRC/templates" -maxdepth 1 -type f -print0)
}

# _templates_except PAT [PAT...]
# Copie les fichiers de src/templates/ qui ne correspondent à AUCUN des patterns.
_templates_except() {
    while IFS= read -r -d '' f; do
        local base; base=$(basename "$f")
        local skip=0
        for pat in "$@"; do
            [[ "$base" == $pat ]] && skip=1 && break
        done
        [ "$skip" -eq 1 ] && continue
        rel="${f#"$SCRIPT_DIR/"}"
        dest="$WORK_DIR/$rel"
        mkdir -p "$(dirname "$dest")"
        cp "$f" "$dest"
    done < <(find "$SRC/templates" -maxdepth 1 -type f -print0)
}

# Patterns de routage src/templates/ (utilisés par plusieurs groupes)
_PAT_FRONTEND=("portal_*.sh")
_PAT_CONFIG=("*.service" "*.conf" "soundspot.conf.*" "soundspot-*logrotate*")
_PAT_BACKEND=("*.sh" "*.py")   # tout le reste après exclusion frontend+config

# ── Groupes ────────────────────────────────────────────────────────────────

case "$GROUP" in

# ──────────────────────────────────────────────────────────────────────────
# INSTALL — Installation et déploiement du nœud RPi
#   Tous les scripts d'entrée + modules src/install/ (auto-discovery)
#   + templates de configuration centrale
# ──────────────────────────────────────────────────────────────────────────
--install)
    echo "Groupe : INSTALL"
    _add_dir "src/install"           # modules install/*.sh — auto-discovery
    _add "deploy_on_pi.sh" \
         "dj_mixxx_setup.sh" \
         "src/install_*.sh"          # install_soundspot.sh, install_satellite.sh, etc.
    _add "check.sh"
    _add "src/wpa_supplicant.conf"
    _templates_match "soundspot.conf.*" "${_PAT_CONFIG[@]}"
    EXTS="sh conf service"
    ;;

# ──────────────────────────────────────────────────────────────────────────
# BACKEND — Pipeline audio & services runtime
#   Scripts audio déployés sur le RPi + monitoring
#   Convention templates : *.sh (hors portal_*) + *.py
# ──────────────────────────────────────────────────────────────────────────
--backend)
    echo "Groupe : BACKEND"
    _add "src/idle_announcer.sh" \
         "src/presence_detector.py" \
         "src/battery_monitor.py" \
         "src/bt_update.sh"
    _add_dir "monitor"               # scripts de monitoring — auto-discovery
    # templates : tout sauf portail (portal_*) et config (*.service, *.conf, etc.)
    _templates_except "${_PAT_FRONTEND[@]}" "${_PAT_CONFIG[@]}"
    EXTS="sh py"
    ;;

# ──────────────────────────────────────────────────────────────────────────
# FRONTEND — Portail captif web
#   src/portal/ complet (auto-discovery) + templates CGI portail
#   Convention templates : portal_*.sh
# ──────────────────────────────────────────────────────────────────────────
--frontend)
    echo "Groupe : FRONTEND"
    _add_dir "src/portal"            # tout le portail — auto-discovery
    _templates_match "${_PAT_FRONTEND[@]}"
    EXTS="sh html js json"
    ;;

# ──────────────────────────────────────────────────────────────────────────
# PICOPORT — Nœud IPFS / Nostr / Ğ1 UPlanet
#   src/picoport/ complet — auto-discovery
# ──────────────────────────────────────────────────────────────────────────
--picoport)
    echo "Groupe : PICOPORT"
    _add_dir "src/picoport"          # tout picoport — auto-discovery
    EXTS="sh"
    ;;

# ──────────────────────────────────────────────────────────────────────────
# APPS — Applications accessibles depuis le portail
#   Routeur api.sh + API core + apps/ — auto-discovery dans api/
# ──────────────────────────────────────────────────────────────────────────
--apps)
    echo "Groupe : APPS"
    _add "src/portal/api.sh" \
         "src/portal/docs.sh"
    _add_dir "src/portal/api"        # core/ + apps/ — auto-discovery
    EXTS="sh html"
    ;;

# ──────────────────────────────────────────────────────────────────────────
# CONFIG — Templates systemd et fichiers de configuration
#   Convention templates : *.service, *.conf, soundspot-*logrotate*
# ──────────────────────────────────────────────────────────────────────────
--config)
    echo "Groupe : CONFIG"
    _templates_match "${_PAT_CONFIG[@]}"
    EXTS="service conf"
    ;;

*)
    echo "Groupe inconnu : $GROUP"
    show_help
    ;;

esac

# ── Lancement de cpcode sur le répertoire temporaire ─────────────────────
# shellcheck disable=SC2086
exec "$CPCODE" $EXTS "${CPCODE_ARGS[@]}" "$WORK_DIR"
