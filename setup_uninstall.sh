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
    echo -e "  ${G}--force${N}   Purge Totale : Supprime absolument tout (services, données, configs)."
    echo -e "            Remet le système dans l'état pré-installation."
    echo ""
    echo -e "Sans option : Ouvre un menu interactif pour choisir les services à arrêter."
}

if [ "$(id -u)" -ne 0 ]; then err "Ce script doit être lancé avec sudo"; fi
if [ $# -eq 0 ] && [ ! -t 0 ]; then show_help; exit 0; fi # Protection non-interactif

# Configuration
INSTALL_DIR="/opt/soundspot"
CONF="/opt/soundspot/soundspot.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy_on_pi.sh"

# Charger le user (pi par défaut)
SOUNDSPOT_USER=$(grep "SOUNDSPOT_USER" "$CONF" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "pi")
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)

# Liste des services (pour la suppression)
SERVICES=(
    "soundspot-ap" "hostapd" "dnsmasq" "soundspot-firewall" "ipset-soundspot"
    "icecast2" "soundspot-decoder" "snapserver" "soundspot-client"
    "soundspot-idle" "soundspot-presence" "soundspot-battery"
    "picoport" "ipfs" "bt-autoconnect"
)

# ── Fonctions ────────────────────────────────────────────────────

uninstall_service() {
    local svc=$1
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
    rm -f "/etc/systemd/system/$svc.service"
    rm -rf "/etc/systemd/system/$svc.service.d"
}

purge_data() {
    log "Suppression des dossiers de données de $SOUNDSPOT_USER..."
    rm -rf "$USER_HOME/.ipfs" "$USER_HOME/.zen" "$USER_HOME/.astro"
}

purge_system() {
    log "Suppression de l'arborescence SoundSpot..."
    rm -rf "$INSTALL_DIR"
    rm -f "$CONF"
    rm -f "/etc/lighttpd/lighttpd.conf"
    rm -rf "/var/www/html" && mkdir -p "/var/www/html"
    rm -f "/etc/sudoers.d/soundspot-www"
}

# ── Analyse des arguments ────────────────────────────────────────
ACTION=""
for arg in "$@"; do
    case "$arg" in
        --reset) ACTION="RESET" ;;
        --ipfs)  ACTION="IPFS"  ;;
        --force) ACTION="FORCE" ;;
        --help|-h) show_help; exit 0 ;;
    esac
done

# Si aucune commande, on vérifie si on peut lancer le menu interactif
if [ -z "$ACTION" ]; then
    if [ -t 0 ] && command -v whiptail >/dev/null; then
        ACTION="MENU"
    else
        show_help; exit 0
    fi
fi

# ── Exécution ────────────────────────────────────────────────────

case "$ACTION" in
    FORCE)
        hdr "PURGE TOTALE DU SYSTÈME"
        warn "Cette action est irréversible."
        for svc in "${SERVICES[@]}"; do uninstall_service "$svc"; done
        purge_data
        purge_system
        systemctl daemon-reload
        log "✅ Tout a été supprimé. Le système est propre."
        ;;

    RESET)
        hdr "FACTORY RESET & RELANCE"
        for svc in "${SERVICES[@]}"; do uninstall_service "$svc"; done
        purge_system
        # Note: On garde les données IPFS sauf si --ipfs est aussi présent
        if [[ "$*" == *"--ipfs"* ]]; then purge_data; fi
        systemctl daemon-reload
        log "Système nettoyé. Relance de l'installation..."
        exec bash "$DEPLOY_SCRIPT"
        ;;

    IPFS)
        hdr "RESET IDENTITÉ PICOPORT"
        systemctl stop picoport ipfs 2>/dev/null || true
        purge_data
        log "Régénération de l'environnement..."
        sudo -u "$SOUNDSPOT_USER" HOME="$USER_HOME" bash "$SRC_DIR/install_astroport_light.sh"
        bash "$INSTALL_DIR/picoport/install_picoport.sh"
        log "✅ Identité Picoport réinitialisée."
        ;;

    MENU)
        # Menu interactif existant
        OPTIONS=()
        # On définit ici les descriptions pour le menu
        DESC_soundspot_ap="Interface WiFi Virtuelle"
        DESC_hostapd="Point d'Accès WiFi"
        DESC_picoport="Nœud UPlanet"
        # ... etc (simplifié pour l'exemple)
        
        for svc in "${SERVICES[@]}"; do
            OPTIONS+=("$svc" "Service SoundSpot" "OFF")
        done

        CHOICES=$(whiptail --title "Désinstallation SoundSpot" --checklist \
        "Espace pour cocher, Entrée pour valider :" 20 78 12 \
        "${OPTIONS[@]}" 3>&1 1>&2 2>&3) || exit 0
        
        for svc in $CHOICES; do
            uninstall_service "$(echo "$svc" | tr -d '"')"
        done
        systemctl daemon-reload
        log "✅ Services sélectionnés supprimés."
        ;;
esac

exit 0