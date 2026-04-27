#!/bin/bash
# restart.sh — Redémarrage des services SoundSpot sans reboot
#
# Usage :
#   sudo bash restart.sh              # tous les services audio + portail
#   sudo bash restart.sh audio        # pipeline audio uniquement
#   sudo bash restart.sh portal       # lighttpd uniquement
#   sudo bash restart.sh picoport     # IPFS + picoport
#   sudo bash restart.sh bt           # Bluetooth + client audio
#   sudo bash restart.sh all          # tout (audio + portail + picoport + bt)

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/soundspot}"
[ -f "$INSTALL_DIR/soundspot.conf" ] && source "$INSTALL_DIR/soundspot.conf"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'
log()  { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }
ok()   { echo -e "  ${G}✓${N} $1"; }
fail() { echo -e "  ${R}✗${N} $1"; }

if [ "$(id -u)" -ne 0 ]; then
    warn "Lancez avec sudo"
    exit 1
fi

# ── Redémarrer un service avec retour visuel ──────────────────
svc_restart() {
    local svc="$1"
    if systemctl is-active --quiet "$svc" 2>/dev/null || systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        if systemctl restart "$svc" 2>/dev/null; then
            ok "$svc"
        else
            fail "$svc (échec restart)"
        fi
    else
        echo -e "  ${Y}–${N} $svc (non installé / désactivé)"
    fi
}

svc_stop()  { systemctl stop  "$1" 2>/dev/null && ok "stop $1"  || true; }
svc_start() { systemctl start "$1" 2>/dev/null && ok "start $1" || fail "start $1"; }

# ── Groupes ───────────────────────────────────────────────────
restart_audio() {
    hdr "Pipeline audio"
    svc_stop  soundspot-client
    svc_restart icecast2
    svc_restart soundspot-decoder
    svc_restart snapserver
    sleep 1
    svc_restart soundspot-client
    svc_restart soundspot-idle
}

restart_portal() {
    hdr "Portail web"
    systemctl reload lighttpd 2>/dev/null && ok "lighttpd (reload)" \
        || { svc_restart lighttpd; }
}

restart_picoport() {
    hdr "Picoport IPFS"
    svc_restart ipfs
    sleep 2
    svc_restart picoport
}

restart_bt() {
    hdr "Bluetooth"
    svc_stop  soundspot-client
    svc_restart bt-autoconnect
    sleep 3
    svc_restart soundspot-client
    svc_restart soundspot-bt-reactive
}

restart_jukebox() {
    hdr "Jukebox"
    svc_restart soundspot-jukebox
}

# ── Statut final ──────────────────────────────────────────────
show_status() {
    echo ""
    hdr "État des services"
    for svc in icecast2 snapserver soundspot-decoder soundspot-client \
                soundspot-idle lighttpd picoport soundspot-bt-reactive; do
        state=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
        case "$state" in
            active)     echo -e "  ${G}✅${N} $svc" ;;
            activating) echo -e "  ${Y}⏳${N} $svc" ;;
            failed)     echo -e "  ${R}❌${N} $svc" ;;
            *)          echo -e "  ${Y}–${N}  $svc ($state)" ;;
        esac
    done
}

# ── Dispatcher ────────────────────────────────────────────────
TARGET="${1:-default}"

case "$TARGET" in
    audio)
        restart_audio
        ;;
    portal)
        restart_portal
        ;;
    picoport|ipfs)
        restart_picoport
        ;;
    bt|bluetooth)
        restart_bt
        ;;
    jukebox)
        restart_jukebox
        ;;
    all)
        restart_audio
        restart_portal
        restart_picoport
        restart_bt
        ;;
    default|"")
        restart_audio
        restart_portal
        ;;
    status)
        show_status
        exit 0
        ;;
    *)
        echo -e "Usage: sudo bash restart.sh [audio|portal|picoport|bt|jukebox|all|status]"
        exit 1
        ;;
esac

show_status
