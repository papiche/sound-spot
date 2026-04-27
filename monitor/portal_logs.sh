#!/bin/bash
# monitor/portal_logs.sh — Suivi en direct des logs du portail SoundSpot
#
# Usage :
#   bash monitor/portal_logs.sh              # tous les logs (lighttpd + CGI + systemd)
#   bash monitor/portal_logs.sh --cgi        # requêtes CGI uniquement
#   bash monitor/portal_logs.sh --errors     # erreurs uniquement
#   bash monitor/portal_logs.sh --api        # appels API (action=...) uniquement
#
# Fonctionne en local sur le Pi ou depuis la machine de dev via SSH :
#   ssh pi@soundspot.local "sudo bash /opt/soundspot/monitor/portal_logs.sh"

set -euo pipefail

# ── Couleurs ──────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; M='\033[0;35m'; W='\033[1;37m'; N='\033[0m'
B='\033[0;34m'

LIGHTTPD_LOG="/var/log/lighttpd/error.log"
ACCESS_LOG="/var/log/lighttpd/access.log"

MODE="all"
for arg in "$@"; do
    case "$arg" in
        --cgi)    MODE="cgi"    ;;
        --errors) MODE="errors" ;;
        --api)    MODE="api"    ;;
    esac
done

# ── En-tête ───────────────────────────────────────────────────
echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${W}  SoundSpot — Logs portail captif${N}  (mode: ${Y}${MODE}${N})"
echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

# ── Colorisation des lignes ───────────────────────────────────
colorize() {
    while IFS= read -r line; do
        if   echo "$line" | grep -qi 'error\|fatal\|fail\|exception'; then
            echo -e "${R}${line}${N}"
        elif echo "$line" | grep -qi 'warn'; then
            echo -e "${Y}${line}${N}"
        elif echo "$line" | grep -qi 'action='; then
            echo -e "${G}${line}${N}"
        elif echo "$line" | grep -qi '\.sh\|cgi'; then
            echo -e "${M}${line}${N}"
        elif echo "$line" | grep -qi '404\|500\|403'; then
            echo -e "${R}${line}${N}"
        elif echo "$line" | grep -qi '200\|304'; then
            echo -e "${B}${line}${N}"
        else
            echo "$line"
        fi
    done
}

# ── Filtres selon le mode ─────────────────────────────────────
filter() {
    case "$MODE" in
        cgi)    grep --line-buffered -i '\.sh\|cgi\|QUERY_STRING\|action=' ;;
        errors) grep --line-buffered -i 'error\|warn\|fail\|404\|500\|403' ;;
        api)    grep --line-buffered -i 'action='                           ;;
        *)      cat                                                          ;;
    esac
}

# ── Sources disponibles ───────────────────────────────────────
SOURCES=()

if [ -f "$LIGHTTPD_LOG" ]; then
    SOURCES+=("$LIGHTTPD_LOG")
else
    echo -e "${Y}⚠${N}  $LIGHTTPD_LOG absent (lighttpd non installé ?)"
fi

if [ -f "$ACCESS_LOG" ]; then
    SOURCES+=("$ACCESS_LOG")
fi

if [ ${#SOURCES[@]} -eq 0 ] && ! systemctl is-active --quiet lighttpd 2>/dev/null; then
    echo -e "${R}✗${N}  lighttpd n'est pas actif — pas de logs disponibles"
    echo -e "    ${W}sudo systemctl start lighttpd${N}"
    exit 1
fi

# ── Affichage des dernières lignes avant le suivi ─────────────
echo -e "${C}── Dernières entrées ────────────────────────────────────────${N}"
if [ ${#SOURCES[@]} -gt 0 ]; then
    tail -20 "${SOURCES[@]}" 2>/dev/null | filter | colorize
fi

# Logs systemd lighttpd (CGI stderr → journal)
echo ""
echo -e "${C}── Journal systemd lighttpd (20 dernières lignes) ───────────${N}"
journalctl -u lighttpd --no-pager -n 20 2>/dev/null | filter | colorize || true

echo ""
echo -e "${C}── Suivi en direct (Ctrl+C pour quitter) ────────────────────${N}"
echo ""

# ── Suivi en direct : fichiers + journal systemd ─────────────
(
    if [ ${#SOURCES[@]} -gt 0 ]; then
        tail -F "${SOURCES[@]}" 2>/dev/null | filter | colorize &
    fi
    journalctl -u lighttpd -f --no-pager 2>/dev/null | filter | colorize &
    wait
) || true
