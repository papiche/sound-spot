#!/bin/bash
# =======================================================================
# Picoport.sh — Version DRAGON & SWARM -- :12345
# =======================================================================

export IPFS_PATH="${IPFS_PATH:-$HOME/.ipfs}"
TMP_DIR="$HOME/.zen/tmp"
IPFSNODEID=$(ipfs id -f="<id>")
MY_NODE_DIR="$TMP_DIR/$IPFSNODEID"
SWARM_DIR="$TMP_DIR/swarm"

# Services à exposer (Nom:PortLocal)
MY_SERVICES="icecast:8111 snapcast:1704 upassport:54321 ssh:22"

mkdir -p "$MY_NODE_DIR" "$SWARM_DIR"

# --- CHARGEMENT DES LOGS ---
_SS_SERVICE="picoport"
LOG_LIB="/opt/soundspot/log.sh"

if [ -f "$LOG_LIB" ]; then
    source "$LOG_LIB"
else
    # Fallback si la lib est absente
    ss_info() { echo -e "\e[32m[INFO]\e[0m [\$_SS_SERVICE] \$*"; }
    ss_debug() { echo -e "\e[36m[DEBUG]\e[0m [\$_SS_SERVICE] \$*"; }
    ss_warn() { echo -e "\e[33m[WARN]\e[0m [\$_SS_SERVICE] \$*"; }
fi

# --- FONCTION DRAGON : GÉNÉRATION DES SCRIPTS CLIENTS x_*.sh ---
generate_dragon_scripts() {
    ss_debug "DRAGON: Détection des services locaux..."
    
    for entry in $MY_SERVICES; do
        SVC_NAME="${entry%%:*}"
        LPORT="${entry##*:}"
        PROTO="/x/$SVC_NAME-$IPFSNODEID"
        
        # 1. Vérifier si le service tourne localement
        if ss -tln | grep -q ":$LPORT "; then
            # 2. Ouvrir l'écoute P2P si pas déjà fait
            if ! ipfs p2p ls | grep -q "$PROTO"; then
                ipfs p2p listen "$PROTO" "/ip4/127.0.0.1/tcp/$LPORT"
                ss_info "DRAGON: Service exposé -> $PROTO"
            fi
            
            # 3. Générer le script x_service.sh pour le Swarm
            # Ce script sera téléchargé par les voisins pour se connecter à TOI
            cat > "$MY_NODE_DIR/x_$SVC_NAME.sh" << EOF
#!/bin/bash
# Client tunnel pour $SVC_NAME @ $HOSTNAME
NODE_ID="$IPFSNODEID"
PROTO="$PROTO"
LPORT="$LPORT"
if [[ "\${1,,}" == "off" || "\${1,,}" == "stop" ]]; then
    ipfs p2p close -p "\$PROTO"
    exit 0
fi
echo "Établissement du tunnel vers $SVC_NAME..."
ipfs p2p forward "\$PROTO" "/ip4/127.0.0.1/tcp/\$LPORT" "/p2p/\$NODE_ID"
EOF
            chmod +x "$MY_NODE_DIR/x_$SVC_NAME.sh"
        fi
    done
}

# --- DÉCOUVERTE DU SWARM (Balises complètes) ---
discover_neighbors() {
    PEERS=$(ipfs swarm peers | grep -oP 'p2p/\K.*' | sort -u | head -n 5)
    for peer in $PEERS; do
        if [ "$peer" != "$IPFSNODEID" ]; then
            if [ ! -d "$SWARM_DIR/$peer" ] ||[ "$(find "$SWARM_DIR/$peer" -maxdepth 0 -mmin +60)" ]; then
                ss_debug "Téléchargement balise complète : $peer"
                TMP_GET="/tmp/get_$peer"
                if ipfs --timeout 20s get -o "$TMP_GET" "/ipns/$peer/" >/dev/null 2>&1; then
                    rm -rf "$SWARM_DIR/$peer"
                    mv "$TMP_GET" "$SWARM_DIR/$peer"
                    # Donner les droits d'exécution aux scripts reçus
                    find "$SWARM_DIR/$peer" -name "x_*.sh" -exec chmod +x {} \;
                fi
            fi
        fi
    done

    # --- AUTO-CONNECT AUX RELAIS NOSTR DE L'ESSAIM (Jukebox / IA) ---
    # Si le tunnel strfry (9999) n'est pas déjà actif, on lance le premier x_strfry.sh trouvé
    if ! ss -tln 2>/dev/null | grep -q ":9999 "; then
        local X_STRFRY=$(find "$SWARM_DIR" -name "x_strfry.sh" -type f 2>/dev/null | head -n 1)
        if [ -n "$X_STRFRY" ]; then
            ss_info "Auto-connect au Nostr Relay Swarm via $X_STRFRY"
            bash "$X_STRFRY" &
        fi
    fi
}

# Boucle principale
while true; do
    MOATS=$(date +%s)
    
    generate_dragon_scripts  # Crée les x_*.sh locaux
    discover_neighbors       # Télécharge les x_*.sh voisins

    # Mise à jour du 12345.json (ajoute les services détectés)
    DRAGON_LIST=$(ls "$MY_NODE_DIR"/x_*.sh 2>/dev/null | xargs -I{} basename {} .sh | sed 's/^x_//' | paste -sd',' -)
    
    cat > "$MY_NODE_DIR/12345.json" << EOF
{
    "version": "picoport-0.5-dragon",
    "created": $MOATS,
    "hostname": "$(hostname)",
    "ipfsnodeid": "$IPFSNODEID",
    "type": "soundspot",
    "dragon_services": "$DRAGON_LIST",
    "streaming": { "icecast": true, "snapcast": true }
}
EOF

    # Publication IPNS
    ss_info "Publication de la balise (Services: $DRAGON_LIST)"
    ipfs add -rwQ "$MY_NODE_DIR" | tail -n 1 | xargs ipfs name publish --lifetime=24h --ttl=1h >/dev/null 2>&1 &

    sleep 900
done