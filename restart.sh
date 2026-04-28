#!/bin/bash
# restart.sh — Redémarrage GLOBAL SoundSpot

set -euo pipefail
INSTALL_DIR="${INSTALL_DIR:-/opt/soundspot}"
[ -f "$INSTALL_DIR/soundspot.conf" ] && source "$INSTALL_DIR/soundspot.conf"

# Couleurs
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; C='\033[0;36m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N} $1"; }

[ "$(id -u)" -eq 0 ] || exec sudo bash "$0" "$@"

hdr() { echo -e "\n${C}━━━  $1  ━━━${N}"; }

svc_restart() {
    local svc=$1
    if systemctl is-enabled "$svc" &>/dev/null; then
        systemctl restart "$svc" && ok "$svc" || echo -e "  ${R}✗${N} $svc"
    fi
}

# 1. Chaîne Audio de base
hdr "Pipeline Audio & Radio"
systemctl stop soundspot-client 2>/dev/null || true
svc_restart icecast2
svc_restart soundspot-decoder
svc_restart snapserver
sleep 1
svc_restart soundspot-client
svc_restart soundspot-mic     # <--- RÉTABLI : Capture Micro USB

# 2. Intelligence & Capteurs (Le Golem)
hdr "Capteurs & Intelligence (Constellation UPlanet)"
svc_restart soundspot-presence # <--- RÉTABLI : Caméra
svc_restart mon-oeil          # <--- RÉTABLI : IA Swarm
svc_restart soundspot-idle     # Clocher
svc_restart soundspot-battery  # Énergie

# 3. Réseau & Web
hdr "Portail & Connectivité"
systemctl reload lighttpd && ok "lighttpd"
svc_restart picoport
svc_restart soundspot-bt-reactive

# Résumé final
echo ""
hdr "État des services"
for svc in icecast2 snapserver soundspot-decoder soundspot-client \
           soundspot-mic soundspot-presence mon-oeil soundspot-idle \
           lighttpd picoport soundspot-bt-reactive; do
    if systemctl is-active --quiet "$svc"; then
        echo -e "  ${G}✅${N} $svc"
    else
        echo -e "  ${Y}–${N}  $svc (inactif)"
    fi
done