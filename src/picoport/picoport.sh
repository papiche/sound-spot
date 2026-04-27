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

# ── heartbox_analysis.sh (Astroport.ONE light install) ──────────────────────
# Fournit capacities.power_score, capacities.crypto_score, provider_ready…
# Cohérent avec astrosystemctl list-remote et le format 12345.json du swarm.
HB_SCRIPT="$HOME/.zen/Astroport.ONE/tools/heartbox_analysis.sh"

mkdir -p "$MY_NODE_DIR" "$SWARM_DIR"

# ── NOSTR Identity (Y-Level) ────────────────────────────────────────────────
# Dérive ou charge le HEX NOSTR depuis secret.june / secret.nostr.
# Publié dans MY_NODE_DIR/HEX → téléchargé par la constellation via swarm IPNS.
# Permet à all_but_blacklist.sh du relay de reconnaître ce nœud.
NODEHEX=""
ASTRO_TOOLS="$HOME/.zen/Astroport.ONE/tools"
if [[ -s ~/.zen/game/secret.nostr ]]; then
    source ~/.zen/game/secret.nostr
    NODEHEX="${HEX:-}"
elif [[ -s ~/.zen/game/secret.june && -f "$ASTRO_TOOLS/keygen" ]]; then
    source ~/.zen/game/secret.june
    source "$HOME/.astro/bin/activate" 2>/dev/null || true
    _CRED_PICO=$(mktemp -p /dev/shm 2>/dev/null || mktemp)
    chmod 600 "$_CRED_PICO"
    trap "rm -f '$_CRED_PICO'" EXIT INT TERM
    printf '%s\n%s\n' "$SALT" "$PEPPER" > "$_CRED_PICO"
    _npub=$(python3 "$ASTRO_TOOLS/keygen" -t nostr -i "$_CRED_PICO" 2>/dev/null)
    NODEHEX=$(python3 "$ASTRO_TOOLS/nostr2hex.py" "$_npub" 2>/dev/null)
    _nsec=$(python3  "$ASTRO_TOOLS/keygen" -t nostr -s -i "$_CRED_PICO" 2>/dev/null)
    [[ -n "$NODEHEX" ]] && echo "NSEC=$_nsec; NPUB=$_npub; HEX=$NODEHEX" > ~/.zen/game/secret.nostr
    rm -f "$_CRED_PICO"
fi
# Publier HEX dans la balise IPNS (lu par all_but_blacklist.sh via swarm cache)
[[ -n "$NODEHEX" ]] && echo "$NODEHEX" > "$MY_NODE_DIR/HEX"

# Mot de passe admin portail = 10 derniers caractères de UPLANETNAME (swarm.key)
# Écrit en RAM (/dev/shm) pour www-data (CGI lighttpd).
_UPLANETNAME=$(tail -n 1 ~/.ipfs/swarm.key 2>/dev/null || echo "")
if [ -n "$_UPLANETNAME" ]; then
    echo "${_UPLANETNAME: -10}" > /dev/shm/soundspot_admin_pass
    chmod 644 /dev/shm/soundspot_admin_pass
fi

# --- CHARGEMENT DES LOGS ---
_SS_SERVICE="picoport"
source /opt/soundspot/backend/system/log.sh 2>/dev/null || {
    ss_info()  { echo "[INFO]  [picoport] $*"; }
    ss_debug() { echo "[DEBUG] [picoport] $*"; }
    ss_warn()  { echo "[WARN]  [picoport] $*"; }
    ss_error() { echo "[ERROR] [picoport] $*" >&2; }
}

# Clé IPNS secondaire MySwarm (initialisée par swarm_sync.sh) — lue sans secrets
CHAN=$(ipfs key list -l 2>/dev/null | grep "MySwarm_${IPFSNODEID}" | awk '{print $1}' || echo "")

# --- CONFIGURATION DES PORTS ALTERNATIFS (Logique DRAGON) ---
# Calcule un offset unique (0-499) pour cette station pour éviter les collisions entre voisins
NODE_OFFSET=$(( $(echo -n "$IPFSNODEID" | cksum | awk '{print $1}') % 500 ))
ALT_BASE=31300 ## TODO: could be related to "Zone In Place"

generate_dragon_scripts() {
    ss_debug "DRAGON: Détection et génération des scripts intelligents..."
    
    for entry in $MY_SERVICES; do
        SVC_NAME="${entry%%:*}"
        NATIVE_PORT="${entry##*:}"
        PROTO="/x/$SVC_NAME-$IPFSNODEID"
        
        # Calcul du port alternatif unique pour ce service sur cette station
        local SLUG_ID=$(echo -n "$SVC_NAME" | cksum | awk '{print $1}')
        local ALT_PORT=$(( ALT_BASE + NODE_OFFSET + (SLUG_ID % 100) ))

        # 1. Vérifier si le service tourne localement (Service NATIF)
        if ss -tln | grep -q ":$NATIVE_PORT "; then
            
            # 2. Ouvrir l'écoute P2P si pas déjà fait
            if ! ipfs p2p ls | grep -q "$PROTO"; then
                ipfs p2p listen "$PROTO" "/ip4/127.0.0.1/tcp/$NATIVE_PORT"
                ss_info "DRAGON: Service exposé -> $PROTO (Port: $NATIVE_PORT)"
            fi
            
            # 3. Génération du script client x_*.sh avec gestion de conflit
            # NB: identique à Astoport.ONE/RUNTIME/DRAGON_p2p_ssh
            cat > "$MY_NODE_DIR/x_$SVC_NAME.sh" << EOF
#!/bin/bash
### Fichier : x_$SVC_NAME.sh
NODE_ID="$IPFSNODEID"
PROTO="$PROTO"
NATIVE_PORT="$NATIVE_PORT"
ALT_PORT="$ALT_PORT"

# --- Logique de choix du port (Anti-conflit) ---
if [[ "\${NATIVE_PORT}" -lt 1024 ]]; then
    # Ports réservés root : on bascule direct sur l'alternatif
    LPORT="\${ALT_PORT}"
elif ss -tln 2>/dev/null | grep -qE ":\${NATIVE_PORT} "; then
    # Si le port est déjà pris, on vérifie si c'est déjà par un tunnel identique
    if ipfs p2p ls 2>/dev/null | grep "\${PROTO}" | grep -q "tcp/\${NATIVE_PORT}"; then
        LPORT="\${NATIVE_PORT}"
    else
        LPORT="\${ALT_PORT}"
    fi
else
    LPORT="\${NATIVE_PORT}"
fi

export LPORT=\$LPORT

if [[ "\${1,,}" == "off" || "\${1,,}" == "stop" ]]; then
    echo "Fermeture du tunnel \$PROTO..."
    ipfs p2p close -p "\$PROTO"
    exit 0
fi

# Vérification de présence du nœud
if ! ipfs --timeout=5s ping -n 2 "/p2p/\$NODE_ID" > /dev/null; then
    echo "ERREUR: La station \$NODE_ID est injoignable (Timeout)."
    exit 1
fi

echo "Établissement du tunnel \$SVC_NAME..."
echo "Accès local sur : http://127.0.0.1:\$LPORT"

# Bind sur localhost + adresses IP locales pour le réseau SoundSpot
ipfs p2p forward "\$PROTO" "/ip4/127.0.0.1/tcp/\$LPORT" "/p2p/\$NODE_ID"

for IP in \$(hostname -I); do
    ipfs p2p forward "\$PROTO" "/ip4/\$IP/tcp/\$LPORT" "/p2p/\$NODE_ID" 2>/dev/null || true
done
EOF
            chmod +x "$MY_NODE_DIR/x_$SVC_NAME.sh"
        fi
    done
}

# --- DÉCOUVERTE DU SWARM (Balises complètes) shuf limit 5 ---
discover_neighbors() {
    PEERS=$(ipfs swarm peers | grep -oP 'p2p/\K.*' | sort -u | shuf | head -n 5)
    for peer in $PEERS; do
        if [ "$peer" != "$IPFSNODEID" ]; then
            if [ ! -d "$SWARM_DIR/$peer" ] || [ "$(find "$SWARM_DIR/$peer" -maxdepth 0 -mmin +60)" ]; then
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

    # ── Capacités via heartbox_analysis.sh (format unifié swarm) ────────────────
    # Si heartbox_analysis.sh est disponible (Astroport.ONE light install),
    # on l'utilise pour générer le bloc capacities avec power_score et crypto_score.
    HB_CACHE="$MY_NODE_DIR/heartbox_analysis.json"
    CAPACITIES='{"power_score":0,"crypto_score":0,"provider_ready":false,"storage_ready":false}'

    if [[ -n "$HB_SCRIPT" ]]; then
        # Rafraîchir si absent ou > 900 s (TTL heartbox = 300 s, on tolère 3 cycles picoport)
        if [[ ! -s "$HB_CACHE" ]] || \
           [[ $(( $(date +%s) - $(stat -c%Y "$HB_CACHE" 2>/dev/null || echo 0) )) -gt 900 ]]; then
            bash "$HB_SCRIPT" update >/dev/null 2>&1
        fi
        if [[ -s "$HB_CACHE" ]]; then
            _CAPS=$(jq '.capacities // empty' "$HB_CACHE" 2>/dev/null)
            [[ -n "$_CAPS" ]] && CAPACITIES="$_CAPS"
        fi
    fi

    myIP=$(hostname -I | awk '{print $1}')
    G1PUB_CACHED=$(cat "$MY_NODE_DIR/G1PUB" 2>/dev/null || echo "")
    # Rafraîchir CHAN si swarm_sync.sh vient de créer la clé
    [ -z "$CHAN" ] && CHAN=$(ipfs key list -l 2>/dev/null | grep "MySwarm_${IPFSNODEID}" | awk '{print $1}' || echo "")

    cat > "$MY_NODE_DIR/12345.json" << EOF
{
    "version": "picoport-0.5-dragon",
    "created": $MOATS,
    "hostname":      "$(hostname)",
    "ipfsnodeid":    "$IPFSNODEID",
    "myIP":          "$myIP",
    "astroport":     "http://$myIP:12345",
    "relay":         "ws://127.0.0.1:9999",
    "u.spot":        "http://$myIP:54321",
    "g1station":     "/ipns/$IPFSNODEID",
    "g1swarm":       "/ipns/$CHAN",
    "g1pub":         "$G1PUB_CACHED",
    "type":          "soundspot",
    "captain":       "",
    "NODEHEX":       "$NODEHEX",
    "SSHPUB":        "$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || echo '')",
    "dragon_services": "$DRAGON_LIST",
    "streaming":     { "icecast": true, "snapcast": true },
    "capacities":    $CAPACITIES
}
EOF

    # Publication IPNS
    ss_info "Publication de la balise (Services: $DRAGON_LIST)"
    ipfs add -rwQ "$MY_NODE_DIR" | tail -n 1 | xargs ipfs name publish --lifetime=24h --ttl=1h >/dev/null 2>&1 &

    sleep 900
done