#!/bin/bash
# src/picoport/swarm_sync.sh — Service de visibilité Picoport (Port 12345)
# Reproduit la logique _12345.sh d'Astroport.ONE

source /opt/soundspot/soundspot.conf 2>/dev/null || true
source $HOME/.astro/bin/activate 2>/dev/null || true
. /opt/soundspot/picoport/tools/my.sh 2>/dev/null || true # Chargement tools Astroport

IPFSNODEID=$(ipfs id -f="<id>")
JSON_FILE="/tmp/12345.json"
HTTP_RES="/dev/shm/picoport_12345.http"

# Initialisation de la clé MySwarm si absente (pour la publication IPNS)
if ! ipfs key list | grep -q "MySwarm"; then
    echo "🔑 Initialisation clé MySwarm..."
    # On utilise une graine basée sur le hardware pour myswarm_secret.june
    FULL_HASH=$(cat /proc/cpuinfo | sha512sum | cut -d ' ' -f 1)
    # Publication simplifiée sans dépendance complexe
    ipfs key gen --type=ed25519 MySwarm
fi

while true; do
    MOATS=$(date +%s)
    
    # Génération du JSON (Version Picoport)
    # On récupère les infos minimales pour être compatible avec la carte mondiale
    cat > "$JSON_FILE" <<EOF
{
    "version": "picoport-12345-v1",
    "created": "$MOATS",
    "hostname": "$(hostname)",
    "ipfsnodeid": "$IPFSNODEID",
    "myIP": "$(hostname -I | awk '{print $1}')",
    "astroport": "http://$(hostname -I | awk '{print $1}'):12345",
    "relay": "ws://127.0.0.1:9999",
    "u.spot": "http://$(hostname -I | awk '{print $1}'):54321",
    "type": "soundspot",
    "services": {
        "audio": "active",
        "p2p_relay": "tunneled"
    }
}
EOF

    # Préparation de la réponse HTTP brute pour socat (ultra rapide)
    cat > "$HTTP_RES" <<EOF
HTTP/1.1 200 OK
Content-Type: application/json
Access-Control-Allow-Origin: *
Connection: close

$(cat $JSON_FILE)
EOF

    # Lancement du serveur HTTP si pas déjà là (via socat)
    if ! pgrep -f "socat TCP4-LISTEN:12345" > /dev/null; then
        socat TCP4-LISTEN:12345,reuseaddr,fork SYSTEM:"cat $HTTP_RES" &
    fi

    # Publication IPNS (notre identité)
    (ipfs name publish --lifetime=24h --ttl=1h /ipfs/$(ipfs add -Q $JSON_FILE) >/dev/null 2>&1 &)

    # Maintenance du cache swarm (téléchargement des voisins)
    # On demande à nos peers IPFS s'ils ont un 12345.json
    PEERS=$(ipfs swarm peers | grep -oP 'p2p/\K.*' | head -n 5)
    for p in $PEERS; do
        mkdir -p ~/.zen/tmp/swarm/$p
        ipfs --timeout 10s get -o ~/.zen/tmp/swarm/$p/12345.json /ipns/$p/12345.json >/dev/null 2>&1 &
    done

    sleep 300 # On boucle toutes les 5 min
done