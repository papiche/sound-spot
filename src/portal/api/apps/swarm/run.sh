#!/bin/bash
# api/apps/swarm/run.sh — Radar de l'essaim UPlanet
#
# Retourne la liste des nœuds Astroport/Picoport voisins visibles
# dans ~/.zen/tmp/swarm/ (géré par Picoport/Astroport.ONE).
#
# GET /api.sh?action=swarm
# Retourne : {"nodes":[{"peer":"QmXXX","name":"...","power":"🌿 Light","battery":...},...]}
#
# Prérequis : Picoport activé + astrosystemctl disponible
# Hérite des exports de api.sh.

SWARM_DIR="${HOME}/.zen/tmp/swarm"

if [ ! -d "$SWARM_DIR" ]; then
    # Essayer depuis l'utilisateur système
    SWARM_DIR=$(eval echo "~${SOUNDSPOT_USER:-pi}/.zen/tmp/swarm")
fi

if [ ! -d "$SWARM_DIR" ]; then
    jq -n '{"error":"swarm_not_available","hint":"Picoport requis. PICOPORT_ENABLED=true dans soundspot.conf"}'
    exit 0
fi

# ── Parser les nœuds du swarm ─────────────────────────────────
# Les fichiers name/power/ip n'existent pas dans le format Astroport.ONE/Picoport.
# La source de vérité est 12345.json (publié par chaque nœud sur /ipns/$IPFSNODEID).
NODES_JSON="["
for NODE_DIR in "$SWARM_DIR"/*/; do
    [ -d "$NODE_DIR" ] || continue
    PEER=$(basename "$NODE_DIR")
    JSON="${NODE_DIR}12345.json"

    # Lire depuis 12345.json si disponible, sinon fichiers legacy (picoport custom)
    if [ -s "$JSON" ] && jq . "$JSON" >/dev/null 2>&1; then
        NAME=$(jq -r '.node_info.hostname // .hostname // ""' "$JSON" 2>/dev/null)
        [ -z "$NAME" ] && NAME="$PEER"
        PS=$(jq -r '.capacities.power_score // 0' "$JSON" 2>/dev/null)
        if   [ "${PS:-0}" -gt 40 ] 2>/dev/null; then POWER="🔥 Brain"
        elif [ "${PS:-0}" -gt 10 ] 2>/dev/null; then POWER="⚡ Std"
        else                                          POWER="🌿 Light"; fi
        IP=$(jq -r '.myIP // .myip // ""' "$JSON" 2>/dev/null)
    else
        NAME=$(cat "${NODE_DIR}name"    2>/dev/null || echo "$PEER")
        POWER=$(cat "${NODE_DIR}power"  2>/dev/null || echo "unknown")
        IP=$(cat "${NODE_DIR}ip"        2>/dev/null || echo "")
    fi
    # battery : fichier dédié (picoport INA219) ou absent (nœuds sans batterie)
    BATTERY=$(cat "${NODE_DIR}battery" 2>/dev/null || echo "")
    LAST_SEEN=$(stat -c%Y "${NODE_DIR}" 2>/dev/null || echo 0)
    AGO=$(( $(date +%s) - LAST_SEEN ))

    NAME_ESC=$(printf '%s' "$NAME" | sed 's/"/\\"/g')
    POWER_ESC=$(printf '%s' "$POWER" | sed 's/"/\\"/g')

    NODES_JSON+="{\"peer\":\"${PEER}\",\"name\":\"${NAME_ESC}\",\"power\":\"${POWER_ESC}\",\"battery\":\"${BATTERY}\",\"ip\":\"${IP}\",\"last_seen_ago\":${AGO}},"
done
NODES_JSON="${NODES_JSON%,}]"

# ── IPFS peers (liste courte) ─────────────────────────────────
IPFS_PEERS=0
if command -v ipfs &>/dev/null; then
    IPFS_PEERS=$(ipfs swarm peers 2>/dev/null | wc -l || echo 0)
elif curl -sX POST "http://127.0.0.1:5001/api/v0/version" >/dev/null 2>&1; then
    IPFS_PEERS=$(curl -sf -X POST "http://127.0.0.1:5001/api/v0/swarm/peers" 2>/dev/null \
        | jq -r '.Peers | length' 2>/dev/null || echo 0)
fi

jq -n \
    --argjson nodes "${NODES_JSON:-[]}" \
    --argjson ipfs_peers "$IPFS_PEERS" \
    --arg spot "$SPOT_NAME" \
    --arg ip "$SPOT_IP" \
    '{
      local_node: {name:$spot, ip:$ip},
      swarm_nodes: $nodes,
      ipfs_peers: $ipfs_peers
    }'
