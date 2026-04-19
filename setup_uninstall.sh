#!/bin/bash
# ================================================================
#  setup_uninstall.sh — Gestion, Reset et Purge SoundSpot
# ================================================================
set -euo pipefail

# ── Couleurs ─────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; N='\033[0m'; W='\033[1;37m'
hdr() { echo -e "\n${C}━━━  $*  ━━━${N}"; }
log() { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err() { echo -e "${R}✗${N}  $*" >&2; exit 1; }

# ── Aide ─────────────────────────────────────────────────────────
show_help() {
    echo -e "${W}SoundSpot Uninstall Tool${N}"
    echo -e "Usage: sudo $0 [OPTION]"
    echo ""
    echo -e "${C}Options:${N}"
    echo -e "  ${G}--reset${N}   Factory Reset : Supprime la config et relance l'installateur global."
    echo -e "  ${G}--ipfs${N}    Reset Identité : Supprime les clés Picoport et régénère un ID propre."
    echo -e "  ${G}--force${N}   Purge Totale : Supprime absolument tout."
    echo ""
}

if [ "$(id -u)" -ne 0 ]; then err "Ce script doit être lancé avec sudo"; fi

# Configuration
INSTALL_DIR="/opt/soundspot"
CONF="/opt/soundspot/soundspot.conf"
# On mémorise le chemin actuel avant toute suppression
ORIGINAL_PWD=$(pwd)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Charger le user
SOUNDSPOT_USER=$(grep "SOUNDSPOT_USER" "$CONF" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "pi")
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)

SERVICES=("soundspot-ap" "hostapd" "dnsmasq" "soundspot-firewall" "ipset-soundspot" "icecast2" "soundspot-decoder" "snapserver" "soundspot-client" "soundspot-idle" "soundspot-presence" "soundspot-battery" "picoport" "ipfs" "bt-autoconnect")

# ── Fonctions ────────────────────────────────────────────────────

uninstall_service() {
    local svc=$1
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
    rm -f "/etc/systemd/system/$svc.service"
}

# Fonction CRITIQUE : Sauvegarde les scripts de réinstall dans /tmp
# pour éviter de les perdre lors du rm -rf ~/.zen
bootstrap_recovery() {
    local tmp_bootstrap="/tmp/soundspot_reinstall"
    log "Préparation du bootstrap de secours dans $tmp_bootstrap..."
    rm -rf "$tmp_bootstrap"
    mkdir -p "$tmp_bootstrap/src"
    
    # Copie des scripts essentiels
    cp "$SCRIPT_DIR/deploy_on_pi.sh" "$tmp_bootstrap/" 2>/dev/null || true
    cp -r "$SCRIPT_DIR/src/"* "$tmp_bootstrap/src/" 2>/dev/null || true
    
    # On bascule l'exécution sur le dossier temporaire
    cd /tmp
    echo "$tmp_bootstrap"
}

purge_data() {
    log "Suppression des données utilisateur (.ipfs, .zen, .astro)..."
    # On évite de supprimer le répertoire si on est dedans (cd /tmp fait avant)
    rm -rf "$USER_HOME/.ipfs" "$USER_HOME/.zen" "$USER_HOME/.astro"
}

purge_system() {
    log "Nettoyage système (/opt/soundspot, configurations)..."
    rm -rf "$INSTALL_DIR"
    rm -f "$CONF"
    rm -f "/etc/lighttpd/lighttpd.conf"
    rm -rf "/var/www/html" && mkdir -p "/var/www/html"
}

# ── Analyse des arguments ────────────────────────────────────────
ACTION=""
[ $# -eq 0 ] && ACTION="MENU" || ACTION="NONE"

for arg in "$@"; do
    case "$arg" in
        --reset) ACTION="RESET" ;;
        --ipfs)  ACTION="IPFS"  ;;
        --force) ACTION="FORCE" ;;
        --help|-h) show_help; exit 0 ;;
    esac
done

if [ "$ACTION" = "MENU" ] && [ ! -t 0 ]; then show_help; exit 0; fi

# ── Exécution ────────────────────────────────────────────────────

case "$ACTION" in
    FORCE)
        hdr "PURGE TOTALE"
        cd /tmp
        for svc in "${SERVICES[@]}"; do uninstall_service "$svc"; done
        purge_data
        purge_system
        systemctl daemon-reload
        log "✅ Purge terminée."
        ;;

    RESET)
        hdr "FACTORY RESET"
        BOOT_DIR=$(bootstrap_recovery)
        for svc in "${SERVICES[@]}"; do uninstall_service "$svc"; done
        purge_data
        purge_system
        systemctl daemon-reload
        log "Relance du setup depuis le bootstrap..."
        exec bash "${BOOT_DIR}/deploy_on_pi.sh"
        ;;

    IPFS)
        hdr "RESET IDENTITÉ PICOPORT"
        BOOT_DIR=$(bootstrap_recovery)
        systemctl stop picoport ipfs 2>/dev/null || true
        purge_data
        
        log "Régénération de l'environnement..."
        # On utilise les scripts copiés dans /tmp pour la réinstallation
        sudo -u "$SOUNDSPOT_USER" HOME="$USER_HOME" bash "${BOOT_DIR}/src/install_astroport_light.sh"
        
        # On s'assure que le dossier picoport est présent dans /opt
        mkdir -p "$INSTALL_DIR"
        cp -r "${BOOT_DIR}/src/picoport" "$INSTALL_DIR/"
        chown -R "$SOUNDSPOT_USER:$SOUNDSPOT_USER" "$INSTALL_DIR/picoport"
        
        bash "$INSTALL_DIR/picoport/install_picoport.sh"
        log "✅ Identité réinitialisée."
        ;;

    MENU)
        if command -v whiptail >/dev/null; then
            OPTIONS=()
            for svc in "${SERVICES[@]}"; do OPTIONS+=("$svc" "Service" "OFF"); done
            CHOICES=$(whiptail --title "Désinstallation" --checklist "Services à supprimer :" 20 78 12 "${OPTIONS[@]}" 3>&1 1>&2 2>&3) || exit 0
            for svc in $CHOICES; do uninstall_service "$(echo "$svc" | tr -d '"')"; done
            log "Fait."
        else
            show_help
        fi
        ;;
esac