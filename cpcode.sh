#!/bin/bash
# cpcode.sh — Copie le code SoundSpot dans le presse-papiers (via Astroport.ONE/cpcode)
#
# Usage :
#   ./cpcode.sh [GROUP] [--json] [--maxfilesize N]
#
# Groupes :
#   --install    Installation du nœud (deploy_on_pi, install_soundspot, modules install/)
#   --backend    Pipeline audio & services runtime (idle, decoder, presence, battery, log)
#   --frontend   Portail captif web complet (portal/ : HTML, JS, CGI, API core)
#   --picoport   Nœud IPFS / Nostr / Ğ1 (picoport/)
#   --apps       Ajout d'application au portail (portal/api/apps/ + api.sh)
#   --config     Templates systemd et configuration (*.service, *.conf)
#   (aucun)      Tout le code — comportement d'origine
#
# Exemples :
#   ./cpcode.sh                          # tout le code
#   ./cpcode.sh --frontend               # portail web uniquement
#   ./cpcode.sh --apps --json            # apps du portail en JSON
#   ./cpcode.sh --install --maxfilesize 102400

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/src"
CPCODE="$(realpath "$SCRIPT_DIR/../Astroport.ONE/cpcode")"

if [ ! -x "$CPCODE" ]; then
    echo "Erreur : cpcode introuvable ou non exécutable → $CPCODE"
    exit 1
fi

echo "Tip : unleash forwarding : sudo iptables -I FORWARD -i uap0 -j ACCEPT"
echo "cpcode is an Astroport.ONE - code to IA prompt tool -"

# ── Parsing des arguments ──────────────────────────────────────────────────
GROUP=""
CPCODE_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --install|--backend|--frontend|--picoport|--apps|--config)
            GROUP="$arg" ;;
        *)
            CPCODE_ARGS+=("$arg") ;;
    esac
done

# ── Sans groupe : tout le code (comportement d'origine) ───────────────────
if [ -z "$GROUP" ]; then
    echo "Groupe : ALL"
    exec "$CPCODE" py sh md conf service html "${CPCODE_ARGS[@]}" "$SCRIPT_DIR"
fi

# ── Avec groupe : copie sélective dans un répertoire temporaire ───────────
WORK_DIR=$(mktemp -d /tmp/soundspot_cpcode_XXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

# _add <glob-relatif-à-SCRIPT_DIR>
# Copie les fichiers correspondant au glob dans WORK_DIR (arborescence préservée)
_add() {
    local found=0
    for f in "$SCRIPT_DIR/"$1; do
        [ -f "$f" ] || continue
        rel="${f#"$SCRIPT_DIR/"}"
        dest="$WORK_DIR/$rel"
        mkdir -p "$(dirname "$dest")"
        cp "$f" "$dest"
        found=1
    done
    [ "$found" -eq 0 ] && echo "  [absent] $1" || true
}

# _add_dir <chemin-relatif-à-SCRIPT_DIR>
# Copie récursivement un répertoire entier dans WORK_DIR
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

# ── Groupes ────────────────────────────────────────────────────────────────

case "$GROUP" in

# ──────────────────────────────────────────────────────────────────────────
# INSTALL — Installation du nœud RPi
#   Point d'entrée + installeurs maître/satellite + tous les modules install/
#   + templates de configuration centrale
# ──────────────────────────────────────────────────────────────────────────
--install)
    echo "Groupe : INSTALL (deploy_on_pi + install_soundspot + src/install/)"
    _add "deploy_on_pi.sh"
    _add "dj_mixxx_setup.sh"
    _add "src/install_soundspot.sh"
    _add "src/install_satellite.sh"
    _add "src/install_astroport_light.sh"
    _add "src/install_battery_monitor.sh"
    _add_dir "src/install"
    _add "src/templates/soundspot.conf.master"
    _add "src/templates/soundspot.conf.satellite"
    EXTS="sh conf"
    ;;

# ──────────────────────────────────────────────────────────────────────────
# BACKEND — Pipeline audio & services runtime
#   Scripts déployés sur le RPi : décodeur, clocher, présence, batterie,
#   jukebox, pare-feu, Bluetooth, bibliothèque de logs
# ──────────────────────────────────────────────────────────────────────────
--backend)
    echo "Groupe : BACKEND (idle, decoder, presence, battery, jukebox, log, firewall)"
    _add "src/idle_announcer.sh"
    _add "src/presence_detector.py"
    _add "src/battery_monitor.py"
    _add "src/bt_update.sh"
    _add "src/templates/log.sh"
    _add "src/templates/decoder.sh"
    _add "src/templates/sync_channel.sh"
    _add "src/templates/play_welcome.sh"
    _add "src/templates/soundspot-firewall.sh"
    _add "src/templates/dhcp_trigger.sh"
    _add "src/templates/bt-combine-sinks.sh"
    _add "src/templates/bt-connect.sh"
    _add "src/templates/wait-pw-socket.sh"
    _add "src/templates/wait-bt-sink.sh"
    _add "src/templates/jukebox_player.sh"
    _add "src/templates/jukebox_worker.sh"
    _add "src/templates/theme_soundspot.sh"
    EXTS="sh py"
    ;;

# ──────────────────────────────────────────────────────────────────────────
# FRONTEND — Portail captif web
#   Interface HTML5/PWA + Service Worker + scripts CGI + API core
#   (auth, status, clock, config)
# ──────────────────────────────────────────────────────────────────────────
--frontend)
    echo "Groupe : FRONTEND (portal/ HTML/JS/CGI + API core)"
    _add_dir "src/portal"
    _add "src/templates/portal_index.sh"
    _add "src/templates/portal_auth.sh"
    _add "src/templates/portal_set_clock.sh"
    _add "src/templates/portal_docs.sh"
    _add "src/templates/set_clock_mode.sh"
    EXTS="sh html js json"
    ;;

# ──────────────────────────────────────────────────────────────────────────
# PICOPORT — Nœud IPFS / Nostr / Ğ1 UPlanet
#   Daemon principal, gestion des clés Y-Level, alias shell, cron solaire
# ──────────────────────────────────────────────────────────────────────────
--picoport)
    echo "Groupe : PICOPORT (src/picoport/)"
    _add_dir "src/picoport"
    EXTS="sh"
    ;;

# ──────────────────────────────────────────────────────────────────────────
# APPS — Applications accessibles depuis le portail captif
#   Routeur api.sh + API core (auth/status/clock/config) + apps/ (hello,
#   admin, nostr_post, yt_copy, swarm)
# ──────────────────────────────────────────────────────────────────────────
--apps)
    echo "Groupe : APPS (portal/api.sh + api/core/ + api/apps/)"
    _add "src/portal/api.sh"
    _add "src/portal/docs.sh"
    _add_dir "src/portal/api/core"
    _add_dir "src/portal/api/apps"
    EXTS="sh html"
    ;;

# ──────────────────────────────────────────────────────────────────────────
# CONFIG — Templates systemd et fichiers de configuration
#   Tous les *.service + *.conf (hostapd, dnsmasq, snapserver, soundspot.conf)
# ──────────────────────────────────────────────────────────────────────────
--config)
    echo "Groupe : CONFIG (templates *.service + *.conf + soundspot.conf)"
    for f in "$SRC/templates/"*.service "$SRC/templates/"*.conf; do
        [ -f "$f" ] || continue
        rel="${f#"$SCRIPT_DIR/"}"
        dest="$WORK_DIR/$rel"
        mkdir -p "$(dirname "$dest")"
        cp "$f" "$dest"
    done
    _add "src/templates/soundspot.conf.master"
    _add "src/templates/soundspot.conf.satellite"
    _add "src/templates/pipewire-soundspot-null.conf"
    EXTS="service conf"
    ;;

*)
    echo "Groupe inconnu : $GROUP"
    echo "Groupes disponibles : --install --backend --frontend --picoport --apps --config"
    exit 1
    ;;

esac

# ── Lancement de cpcode sur le répertoire temporaire ─────────────────────
# shellcheck disable=SC2086
exec "$CPCODE" $EXTS "${CPCODE_ARGS[@]}" "$WORK_DIR"
