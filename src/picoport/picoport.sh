#!/bin/bash
# =======================================================================
# Picoport.sh — Version STREAM & DRAGON
# Partage le flux DJ (Icecast/Snapcast) et consomme l'IA du Swarm.
# Prérequis : ipfs.service doit être actif (géré séparément, CPUQuota=40%).
# =======================================================================

export IPFS_PATH="${IPFS_PATH:-$HOME/.ipfs}"
TMP_DIR="$HOME/.zen/tmp"
INSTALL_DIR="/opt/soundspot/picoport"
BOOTSTRAP_FILE="$INSTALL_DIR/A_boostrap_nodes.txt"

# 1. SERVICES À PARTAGER (Le monde peut se connecter à moi)
# icecast (8111) : pour que le DJ stream vers moi
# snapcast (1704) : pour que les satellites m'écoutent
# snapweb (1780) : interface de contrôle
MY_EXPOSED_SERVICES="icecast:8111 snapcast:1704 snapweb:1780"

# 2. SERVICES À CONSOMMER (Je veux utiliser l'IA des autres)
AI_SERVICES_TO_CONSUME="ollama:11434 open-webui:8000 strfry:9999"

mkdir -p "$TMP_DIR"

# Attente du daemon IPFS (géré par ipfs.service — CPUQuota=40%)
_ipfs_wait=0
until ipfs id >/dev/null 2>&1; do
    _ipfs_wait=$(( _ipfs_wait + 1 ))
    if [ "$_ipfs_wait" -ge 30 ]; then
        echo "⚠ IPFS daemon non disponible après 30s — Picoport continue sans IPFS" >&2
        break
    fi
    sleep 1
done

IPFSNODEID=$(ipfs id -f="<id>")
HOSTNAME=$(hostname)
# Chemin Astroport.ONE : ~/.zen/tmp/$IPFSNODEID/12345.json
mkdir -p "$TMP_DIR/$IPFSNODEID"
JSON_FILE="$TMP_DIR/$IPFSNODEID/12345.json"

# --- FONCTION : OUVRIR LES PORTES (LISTEN) ---
# Permet au Swarm de voir mes ports locaux 8111, 1704, etc.
expose_my_services() {
    for entry in $MY_EXPOSED_SERVICES; do
        SVC_NAME="${entry%%:*}"
        LPORT="${entry##*:}"
        PROTO="/x/$SVC_NAME-$IPFSNODEID"
        
        # On vérifie si le port local est bien ouvert (le service tourne ?)
        if ss -tln | grep -q ":$LPORT "; then
            # On vérifie si on n'écoute pas déjà
            if ! ipfs p2p ls | grep -q "$PROTO"; then
                ipfs p2p listen "$PROTO" "/ip4/127.0.0.1/tcp/$LPORT"
                echo "🌐 Service Partagé : $SVC_NAME accessible sur le Swarm via $PROTO"
            fi
        fi
    done
}

# --- SERVEUR JSON LOCAL ---
serve_12345() {
    while true; do
        cat > "$TMP_DIR/12345.http" << EOF
HTTP/1.1 200 OK
Access-Control-Allow-Origin: *
Content-Type: application/json
Connection: close

$(cat "$JSON_FILE" 2>/dev/null || echo '{"status":"booting"}')
EOF
        socat TCP4-LISTEN:12345,reuseaddr,fork SYSTEM:"cat $TMP_DIR/12345.http" 2>/dev/null
        sleep 1
    done
}

pkill -f "socat TCP4-LISTEN:12345" 2>/dev/null || true
serve_12345 &

echo "🚀 Picoport STREAM-READY actif [$IPFSNODEID]"

# 3. BOUCLE PRINCIPALE
while true; do
    MOATS=$(date +%s)
    
    # --- RÉSILIENCE RESEAU ---
    CURRENT_PEERS=$(ipfs swarm peers 2>/dev/null)
    PEERS_COUNT=$(echo "$CURRENT_PEERS" | grep -c "p2p" || echo 0)
    
    if [ "$PEERS_COUNT" -eq 0 ]; then
        grep -v '^#' "$BOOTSTRAP_FILE" | grep -v '^[[:space:]]*$' | while read -r node; do
            ipfs swarm connect "$node" >/dev/null 2>&1 &
        done
        sleep 5
    fi

    # --- ACTION 1 : EXPOSER LE STREAM ---
    expose_my_services

    # --- MISE A JOUR DU STATUT (format Astroport.ONE compatible) ---
    # Lecture GPS depuis ~/.zen/GPS si disponible (créé par picoport_init_keys.sh)
    GPS_LAT="0"
    GPS_LON="0"
    if [ -f "$HOME/.zen/GPS" ]; then
        GPS_LAT=$(grep -oP '(?<=LAT=)[^\s]+' "$HOME/.zen/GPS" 2>/dev/null | head -1 || echo "0")
        GPS_LON=$(grep -oP '(?<=LON=)[^\s]+' "$HOME/.zen/GPS" 2>/dev/null | head -1 || echo "0")
    fi
    ICECAST_UP=$(ss -tln | grep -q ":8111 " && echo "true" || echo "false")
    SNAPCAST_UP=$(ss -tln | grep -q ":1704 " && echo "true" || echo "false")
    # Power-score minimal (RPi Zero 2W : 4 cœurs, 512Mo RAM, pas de GPU)
    CPU_CORES=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo 4)
    RAM_GB=$(awk '/MemTotal/{printf "%.0f",$2/1048576}' /proc/meminfo 2>/dev/null || echo 0)
    POWER_SCORE=$(( CPU_CORES * 2 + RAM_GB / 2 ))

    cat > "$JSON_FILE" << EOF
{
    "version": "picoport-stream-0.4",
    "created": $MOATS,
    "hostname": "$HOSTNAME",
    "ipfsnodeid": "$IPFSNODEID",
    "type": "soundspot",
    "capacities": {
        "power_score": $POWER_SCORE,
        "provider_ready": false,
        "soundspot": true
    },
    "streaming": {
        "icecast": $ICECAST_UP,
        "icecast_port": 8111,
        "snapcast": $SNAPCAST_UP,
        "snapcast_port": 1704,
        "snapweb_port": 1780
    },
    "services": {
        "ipfs": {"active": true, "peers": $PEERS_COUNT}
    },
    "gps": {
        "lat": "$GPS_LAT",
        "lon": "$GPS_LON"
    }
}
EOF

    # Publication IPNS
    (ipfs add -Q "$JSON_FILE" | xargs ipfs name publish --lifetime=24h --ttl=1h >/dev/null 2>&1) &

    # --- ACTION 2 : CONSOMMER L'IA DISTANTE ---
    OPEN_TUNNELS=$(ipfs p2p ls 2>/dev/null)
    mapfile -t PEER_IDS < <(echo "$CURRENT_PEERS" | grep -oP 'p2p/\K.*' | sort -u)

    for peer in "${PEER_IDS[@]}"; do
        for entry in $AI_SERVICES_TO_CONSUME; do
            SVC_NAME="${entry%%:*}"
            LPORT="${entry##*:}"
            PROTO_NAME="/x/$SVC_NAME-$peer"
            
            if ! echo "$OPEN_TUNNELS" | grep -q "$SVC_NAME"; then
                if ipfs p2p forward "$PROTO_NAME" "/ip4/127.0.0.1/tcp/$LPORT" "/p2p/$peer" 2>/dev/null; then
                    echo "🔗 IA Distante captée : [$SVC_NAME] sur port $LPORT"
                fi
            fi
        done
    done

    sleep 120
done