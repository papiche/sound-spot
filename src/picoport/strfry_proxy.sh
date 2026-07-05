#!/bin/bash
# =======================================================================
# strfry_proxy.sh — Port fixe 7777 vers le tunnel IPFS p2p strfry actif
# =======================================================================
# x_strfry.sh (Astroport.ONE) choisit un port local dynamique par station
# (hash de l'IPFSNODEID distant) pour éviter les collisions entre tunnels.
# myRELAY (dérivé par my.sh depuis myIPFS, port 8080→7777) suppose lui un
# port fixe 7777. Ce démon réexpose en permanence le tunnel strfry courant
# sur 7777, et se réajuste automatiquement si astrosystemctl bascule vers
# un autre nœud du swarm (meilleur power_score, ou nœud précédent tombé).
set -u

LISTEN_PORT="${STRFRY_PROXY_PORT:-7777}"
CHECK_INTERVAL="${STRFRY_PROXY_INTERVAL:-30}"
SOCAT_PID=""
CURRENT_TARGET=""

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [strfry-proxy] $*"; }

cleanup() {
    [[ -n "$SOCAT_PID" ]] && kill "$SOCAT_PID" 2>/dev/null
    exit 0
}
trap cleanup TERM INT

# Port local (127.0.0.1) du tunnel /x/strfry-* actuellement actif, s'il existe
current_strfry_port() {
    ipfs p2p ls 2>/dev/null \
        | awk '$1 ~ /^\/x\/strfry-/ && $2 ~ /^\/ip4\/127\.0\.0\.1\//{print $2}' \
        | grep -oP 'tcp/\K[0-9]+' \
        | head -1
}

while true; do
    target_port=$(current_strfry_port)

    if [[ -n "$target_port" && "$target_port" != "$CURRENT_TARGET" ]]; then
        [[ -n "$SOCAT_PID" ]] && kill "$SOCAT_PID" 2>/dev/null
        log "tunnel strfry détecté sur 127.0.0.1:${target_port} — (ré)ouverture du relais ${LISTEN_PORT} → ${target_port}"
        socat TCP-LISTEN:${LISTEN_PORT},fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:${target_port} &
        SOCAT_PID=$!
        CURRENT_TARGET="$target_port"
    elif [[ -z "$target_port" && -n "$CURRENT_TARGET" ]]; then
        log "tunnel strfry disparu (nœud swarm tombé ?) — arrêt du relais"
        kill "$SOCAT_PID" 2>/dev/null
        SOCAT_PID=""
        CURRENT_TARGET=""
    fi

    sleep "$CHECK_INTERVAL"
done
