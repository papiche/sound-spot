#!/bin/bash
set -euo pipefail

# ── Couleurs ─────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; N='\033[0m'; W='\033[1;37m'
log() { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err() { echo -e "${R}✗${N}  $*" >&2; exit 1; }

# Configuration
INSTALL_DIR="/opt/soundspot"
CONF="/opt/soundspot/soundspot.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Détection utilisateur
SOUNDSPOT_USER=$(grep "SOUNDSPOT_USER" "$CONF" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "${SUDO_USER:-pi}")
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)

SERVICES=("soundspot-ap" "hostapd" "dnsmasq" "soundspot-firewall" "icecast2" "soundspot-decoder" "snapserver" "soundspot-client" "soundspot-idle" "soundspot-presence" "soundspot-battery" "picoport" "ipfs" "bt-autoconnect" "upassport" "soundspot-swarm-sync")

# ── Fonctions ────────────────────────────────────────────────────

stop_services() {
    log "Arrêt des services..."
    for svc in "${SERVICES[@]}"; do
        systemctl stop "$svc" 2>/dev/null || true
    done
}

# Suppression des services systemd
remove_services() {
    log "Suppression des unités systemd..."
    for svc in "${SERVICES[@]}"; do
        systemctl disable "$svc" 2>/dev/null || true
        rm -f "/etc/systemd/system/$svc.service"
    done
    systemctl daemon-reload
}

# ── Analyse des arguments ────────────────────────────────────────
ACTION="${1:-MENU}"

case "$ACTION" in
    --force)
        log "${R}PURGE TOTALE EN COURS...${N}"
        stop_services
        remove_services
        log "Nettoyage des dossiers système..."
        rm -rf "$INSTALL_DIR"
        rm -f "$CONF"
        log "Nettoyage des données utilisateur (TOUT)..."
        rm -rf "$USER_HOME/.ipfs" "$USER_HOME/.zen" "$USER_HOME/.astro"
        log "✅ Système totalement vierge."
        ;;

    --ipfs)
        log "${C}RESET IDENTITÉ PICOPORT (Y-Level)${N}"
        # On ne touche pas au workspace !
        systemctl stop picoport ipfs upassport 2>/dev/null || true
        
        log "Suppression de l'ancienne identité..."
        rm -rf "$USER_HOME/.ipfs"
        rm -rf "$USER_HOME/.zen/game" # Contient les clés Nostr/G1
        rm -rf "$USER_HOME/.zen/tmp"  # Cache du swarm
        
        log "Régénération de l'identité déterministe..."
        # On utilise les scripts directement depuis SCRIPT_DIR (ton workspace)
        sudo -u "$SOUNDSPOT_USER" IPFS_PATH="$USER_HOME/.ipfs" bash "$SCRIPT_DIR/src/picoport/picoport_init_keys.sh"
        
        log "Redémarrage des services..."
        systemctl start ipfs
        sleep 2
        systemctl start picoport
        log "✅ Identité réinitialisée. Nouveau PeerID généré via SSH."
        ;;

    --reset)
        log "${Y}FACTORY RESET (Conservation du code)${N}"
        stop_services
        log "Nettoyage runtime /opt..."
        rm -rf "$INSTALL_DIR"
        log "Nettoyage configs utilisateur (hors workspace)..."
        rm -rf "$USER_HOME/.ipfs" "$USER_HOME/.astro"
        # On nettoie .zen mais on GARDE le workspace
        find "$USER_HOME/.zen" -maxdepth 1 ! -name 'workspace' ! -name '.zen' -exec rm -rf {} + 2>/dev/null || true
        
        log "Relance de l'installation depuis le workspace local..."
        exec bash "$SCRIPT_DIR/deploy_on_pi.sh"
        ;;

    *)
        echo "Usage: sudo $0 {--ipfs|--reset|--force}"
        echo "  --ipfs  : Reset identité (PeerID/Nostr) sans toucher au code."
        echo "  --reset : Supprime le runtime et relance deploy_on_pi.sh."
        echo "  --force : Supprime TOUT (y compris le workspace)."
        exit 1
        ;;
esac