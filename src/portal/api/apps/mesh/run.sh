#!/bin/bash
_SS_SERVICE="portal-mesh"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

# Vérifier si bat0 existe
if ! ip link show bat0 >/dev/null 2>&1; then
    jq -n '{"error": "Mesh non actif"}'
    exit 0
fi

BAT_IP=$(ip -4 addr show bat0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
BAT_MAC=$(cat /sys/class/net/bat0/address 2>/dev/null)

# Voisins directs (Couche 2)
NEIGHBORS=$(sudo batctl n 2>/dev/null | tail -n +3 | awk '{print "{\"mac\":\""$2"\", \"last_seen\":\""$3"\"}"}' | paste -sd "," -)

# Topologie globale (Originators et Qualité de Transmission TQ)
# batctl o affiche : Originator, last-seen, TQ (0-255), Nexthop, IF
ORIGINATORS=$(sudo batctl o 2>/dev/null | tail -n +3 | awk '{
    orig=$1; if(orig=="*") orig=$2;
    seen=$2; if($1=="*") seen=$3;
    tq=$3; if($1=="*") tq=$4;
    gsub(/[\(\)]/, "", tq);
    hop=$4; if($1=="*") hop=$5;
    iface=$5; if($1=="*") iface=$6;
    gsub(/[\[\]]/, "", iface);
    print "{\"originator\":\""orig"\", \"tq\":"tq", \"next_hop\":\""hop"\", \"iface\":\""iface"\"}"
}' | paste -sd "," -)

# Clients Snapcast (JSON-RPC HTTP port 1705)
SNAPCAST_CLIENTS=$(python3 -c "
import json, urllib.request, sys
try:
    req = urllib.request.Request(
        'http://127.0.0.1:1705/jsonrpc',
        data=b'{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"Server.GetStatus\"}',
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    with urllib.request.urlopen(req, timeout=2) as r:
        data = json.load(r)
    clients = []
    for g in data.get('result', {}).get('server', {}).get('groups', []):
        for c in g.get('clients', []):
            clients.append({
                'name': c['host']['name'],
                'ip': c['host']['ip'],
                'connected': c['connected'],
                'volume': c['config']['volume']['percent'],
                'stream': g['stream_id']
            })
    print(json.dumps(clients))
except Exception:
    print('[]')
" 2>/dev/null || echo "[]")

echo "{"
echo "  \"status\": \"ok\","
echo "  \"local\": {\"ip\": \"$BAT_IP\", \"mac\": \"$BAT_MAC\"},"
echo "  \"neighbors\": [${NEIGHBORS}],"
echo "  \"originators\": [${ORIGINATORS}],"
echo "  \"snapcast_clients\": ${SNAPCAST_CLIENTS}"
echo "}"
