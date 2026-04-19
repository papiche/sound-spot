#!/bin/bash
# =======================================================================
# Picoport.sh — Version STREAM & SWARM (Optimisée)
# =======================================================================

export IPFS_PATH="${IPFS_PATH:-$HOME/.ipfs}"
TMP_DIR="$HOME/.zen/tmp"
INSTALL_DIR="/opt/soundspot/picoport"
BOOTSTRAP_FILE="$INSTALL_DIR/A_boostrap_nodes.txt"
SWARM_DIR="$TMP_DIR/swarm"

# État pour la publication conditionnelle
LAST_JSON_CONTENT=""
LAST_PUBLISH_TIME=0
FORCE_PUBLISH_INTERVAL=14400 # 4 heures (en secondes)

MY_EXPOSED_SERVICES="icecast:8111 snapcast:1704 snapweb:1780"
AI_SERVICES_TO_CONSUME="ollama:11434 open-webui:8000 strfry:9999"

mkdir -p "$SWARM_DIR"

# Attente IPFS
until ipfs id >/dev/null 2>&1; do sleep 2; done

IPFSNODEID=$(ipfs id -f="<id>")
HOSTNAME=$(hostname)
mkdir -p "$TMP_DIR/$IPFSNODEID"
JSON_FILE="$TMP_DIR/$IPFSNODEID/12345.json"

expose_my_services() {
    for entry in $MY_EXPOSED_SERVICES; do
        SVC_NAME="${entry%%:*}"
        LPORT="${entry##*:}"
        PROTO="/x/$SVC_NAME-$IPFSNODEID"
        if ss -tln | grep -q ":$LPORT "; then
            if ! ipfs p2p ls | grep -q "$PROTO"; then
                ipfs p2p listen "$PROTO" "/ip4/127.0.0.1/tcp/$LPORT"
            fi
        fi
    done
}

# --- NOUVEAU : DÉCOUVERTE DU SWARM (Coherence avec _12345.sh) ---
discover_neighbors() {
    # On récupère les IDs des pairs actuellement connectés
    PEERS=$(ipfs swarm peers | grep -oP 'p2p/\K.*' | sort -u | head -n 10) # Max 10 pour le Pi Zero
    for peer in $PEERS; do
        if [ "$peer" != "$IPFSNODEID" ]; then
            # Si le dossier n'existe pas ou date de plus d'une heure
            if [ ! -f "$SWARM_DIR/$peer/12345.json" ] || [ "$(find "$SWARM_DIR/$peer/12345.json" -mmin +60)" ]; then
                mkdir -p "$SWARM_DIR/$peer"
                # On tente de récupérer la balise de la station voisine
                # Timeout court pour ne pas bloquer le script
                ipfs --timeout 15s get -o "$SWARM_DIR/$peer/12345.json" "/ipns/$peer/12345.json" >/dev/null 2>&1 &
            fi
        fi
    done
}

while true; do
    MOATS=$(date +%s)
    
    # Résilience réseau
    CURRENT_PEERS=$(ipfs swarm peers 2>/dev/null)
    PEERS_COUNT=$(echo "$CURRENT_PEERS" | grep -c "p2p" || echo 0)
    if [ "$PEERS_COUNT" -eq 0 ]; then
        grep -v '^#' "$BOOTSTRAP_FILE" | while read -r node; do ipfs swarm connect "$node" >/dev/null 2>&1 & done
        sleep 5
    fi

    expose_my_services
    discover_neighbors # Capture les stations voisines comme _12345.sh

    # Données système
    GPS_LAT="0"; GPS_LON="0"
    [ -f "$HOME/.zen/GPS" ] && source "$HOME/.zen/GPS"
    ICECAST_UP=$(ss -tln | grep -q ":8111 " && echo "true" || echo "false")
    SNAPCAST_UP=$(ss -tln | grep -q ":1704 " && echo "true" || echo "false")
    
    # Génération du JSON
    NEW_JSON=$(cat << EOF
{
    "version": "picoport-0.5",
    "created": $MOATS,
    "hostname": "$HOSTNAME",
    "ipfsnodeid": "$IPFSNODEID",
    "type": "soundspot",
    "streaming": { "icecast": $ICECAST_UP, "snapcast": $SNAPCAST_UP },
    "gps": { "lat": "${LAT:-0}", "lon": "${LON:-0}" },
    "services": { "ipfs_peers": $PEERS_COUNT }
}
EOF
)

    # --- PUBLICATION CONDITIONNELLE ---
    SHOULD_PUBLISH=false
    if [ "$NEW_JSON" != "$LAST_JSON_CONTENT" ]; then
        echo "📢 Statut modifié, mise à jour..."
        SHOULD_PUBLISH=true
    elif [ $((MOATS - LAST_PUBLISH_TIME)) -gt $FORCE_PUBLISH_INTERVAL ]; then
        echo "🕒 Publication de routine (refresh IPNS)..."
        SHOULD_PUBLISH=true
    fi

    if [ "$SHOULD_PUBLISH" = true ]; then
        echo "$NEW_JSON" > "$JSON_FILE"
        # Ajout du fichier de moats pour la compatibilité _12345.sh
        echo "$MOATS" > "$TMP_DIR/$IPFSNODEID/_MySwarm.moats"
        
        # Publication IPNS (en arrière-plan pour ne pas bloquer la boucle)
        (ipfs add -rwQ "$TMP_DIR/$IPFSNODEID" | tail -n 1 | xargs ipfs name publish --lifetime=24h --ttl=1h >/dev/null 2>&1) &
        
        LAST_JSON_CONTENT="$NEW_JSON"
        LAST_PUBLISH_TIME=$MOATS
    fi

    # Consommation IA Swarm (tunnels entrants)
    OPEN_TUNNELS=$(ipfs p2p ls 2>/dev/null)
    for peer in $(echo "$CURRENT_PEERS" | grep -oP 'p2p/\K.*' | head -n 5); do
        for entry in $AI_SERVICES_TO_CONSUME; do
            SVC_NAME="${entry%%:*}"; LPORT="${entry##*:}"
            if ! echo "$OPEN_TUNNELS" | grep -q "$SVC_NAME"; then
                ipfs p2p forward "/x/$SVC_NAME-$peer" "/ip4/127.0.0.1/tcp/$LPORT" "/p2p/$peer" 2>/dev/null
            fi
        done
    done

    sleep 120
done