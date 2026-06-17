#!/bin/bash
# =======================================================================
# Picoport.sh — Version DRAGON & SWARM -- :12345
# =======================================================================

export IPFS_PATH="${IPFS_PATH:-$HOME/.ipfs}"
TMP_DIR="$HOME/.zen/tmp"
IPFSNODEID=$(ipfs id -f="<id>")
MY_NODE_DIR="$TMP_DIR/$IPFSNODEID"
SWARM_DIR="$TMP_DIR/swarm"

# ── Logs (chargés EN PREMIER — requis par les vérifications IPFS suivantes) ──
_SS_SERVICE="picoport"
source /opt/soundspot/backend/system/log.sh 2>/dev/null || {
    ss_info()  { echo "[INFO]  [picoport] $*"; }
    ss_debug() { echo "[DEBUG] [picoport] $*"; }
    ss_warn()  { echo "[WARN]  [picoport] $*"; }
    ss_error() { echo "[ERROR] [picoport] $*" >&2; }
}

# Services à exposer (Nom:PortLocal) — upassport exposé seulement si actif localement
MY_SERVICES="icecast:8111 snapcast:1704 upassport:54321 ssh:22"

# ── heartbox_analysis.sh (Astroport.ONE light install) ──────────────────────
HB_SCRIPT="$HOME/.zen/Astroport.ONE/tools/heartbox_analysis.sh"

# ── Chemins UPlanet media pipeline (upload2ipfs.sh + publish_nostr_video.sh) ─
# Permet aux apps du portail (yt_copy, etc.) d'utiliser le système UPlanet complet.
UPLOAD_SCRIPT=""
PUBLISH_SCRIPT=""
ASTRO_TOOLS="$HOME/.zen/Astroport.ONE/tools"
for _p in \
    "$HOME/.zen/UPassport/upload2ipfs.sh" \
    "/opt/soundspot/picoport/upload2ipfs.sh"; do
    [ -f "$_p" ] && { UPLOAD_SCRIPT="$_p"; break; }
done
[ -f "$ASTRO_TOOLS/publish_nostr_video.sh" ] && \
    PUBLISH_SCRIPT="$ASTRO_TOOLS/publish_nostr_video.sh"

# Écrire les chemins en RAM pour les apps CGI (www-data)
mkdir -p /dev/shm/soundspot_env
[ -n "$UPLOAD_SCRIPT"  ] && echo "$UPLOAD_SCRIPT"  > /dev/shm/soundspot_env/upload2ipfs_path
[ -n "$PUBLISH_SCRIPT" ] && echo "$PUBLISH_SCRIPT" > /dev/shm/soundspot_env/publish_nostr_path

mkdir -p "$MY_NODE_DIR" "$SWARM_DIR"

announce_fail() {
    espeak-ng -v fr+f3 -s 140 "Erreur picoport : $1" | aplay -q 2>/dev/null &
}

# Vérifier IPFS
if ! ipfs id >/dev/null 2>&1; then
    ss_error "IPFS ne répond pas"
    announce_fail "Le système de fichier interplanétaire est arrêté ou est mal configuré."
fi

# Vérifier Swarm
PEERS=$(ipfs swarm peers | wc -l)
if [ "$PEERS" -eq 0 ]; then
    ss_warn "Nœud isolé"
    if [ ! -f /tmp/swarm_fail_start ]; then touch /tmp/swarm_fail_start; fi
else
    rm -f /tmp/swarm_fail_start
fi

# ── NOSTR Identity (Y-Level) ────────────────────────────────────────────────
NODEHEX=""
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
[[ -n "$NODEHEX" ]] && echo "$NODEHEX" > "$MY_NODE_DIR/HEX"

# Mot de passe admin portail = 10 derniers caractères de UPLANETNAME (swarm.key)
_UPLANETNAME=$(tail -n 1 ~/.ipfs/swarm.key 2>/dev/null || echo "")
if [ -n "$_UPLANETNAME" ]; then
    echo "${_UPLANETNAME: -10}" > /dev/shm/soundspot_admin_pass
    chmod 644 /dev/shm/soundspot_admin_pass
fi

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

# ── BRO DM Daemon — traite les DMs NOSTR pour les MULTIPASS locaux ──────────
# bro_dm_daemon.sh exécute localement les commandes (#BRO, #rec, #mem, udrive…)
# pour tout MULTIPASS dont ce picoport est le Home (fichier HEX présent, pas .roaming).
# La queue est alimentée par _pico_dm_listener() via nostr_node_intercom.py depuis le relay constellation.
BRO_DM_DAEMON="$HOME/.zen/Astroport.ONE/IA/bro/bro_dm_daemon.sh"
BRO_DM_QUEUE="$HOME/.zen/tmp/bro_dm_queue"
mkdir -p "$BRO_DM_QUEUE"

_pico_dm_listener() {
    # Abonnement relay : dépose les kind 4 + kind 14 adressés à ce node dans la queue
    [[ -z "$NODEHEX" ]] && { ss_warn "DM listener: NODEHEX absent — abonnement relay impossible"; return; }
    local _relay="${PICO_RELAY:-wss://relay.copylaradio.com}"
    local _since
    _since=$(date +%s)
    ss_info "DM listener démarré (relay: $_relay npub=${NODEHEX:0:12}… — via nostr_node_intercom.py)"
    while true; do
        local _filter
        _filter=$(printf '{"kinds":[4,14],"#p":["%s"],"since":%d}' "$NODEHEX" "$(( _since - 60 ))")
        "$HOME/.astro/bin/python3" "$ASTRO_TOOLS/nostr_node_intercom.py" \
            query --filter "$_filter" --relays "$_relay" 2>/dev/null \
        | jq -c '.[]' 2>/dev/null \
        | while IFS= read -r _event; do
            [[ -z "$_event" ]] && continue
            local _ts
            _ts=$(date +%s%N 2>/dev/null || date +%s)
            printf '%s\n' "$_event" > "$BRO_DM_QUEUE/dm_${_ts}.json"
        done
        _since=$(date +%s)
        sleep 30
    done
}

_pico_bro_watchdog() {
    [[ ! -x "$BRO_DM_DAEMON" ]] && { ss_warn "bro_dm_daemon.sh absent — BRO non disponible"; return; }
    while true; do
        local _pid_file="$HOME/.zen/tmp/bro_dm_daemon.pid"
        if [[ -f "$_pid_file" ]] && kill -0 "$(cat "$_pid_file" 2>/dev/null)" 2>/dev/null; then
            sleep 60
        else
            ss_info "Démarrage bro_dm_daemon.sh (HOME MULTIPASS: $(ls "$HOME/.zen/game/nostr/" 2>/dev/null | grep -v '^$' | wc -l) compte(s))"
            bash "$BRO_DM_DAEMON" >> "$HOME/.zen/tmp/bro_dm_daemon.log" 2>&1 &
            sleep 10
        fi
    done
}

# Lancer listener DM + watchdog BRO en arrière-plan si NOSTR identity disponible
if [[ -s "$HOME/.zen/game/secret.nostr" ]]; then
    _pico_dm_listener &
    _pico_bro_watchdog &
    ss_info "BRO activé — DM listener + daemon watchdog démarrés"
else
    ss_warn "secret.nostr absent — BRO désactivé (relancer après picoport_init_keys.sh)"
fi

# Boucle principale
while true; do
    MOATS=$(date +%s)
    
    generate_dragon_scripts  # Crée les x_*.sh locaux
    discover_neighbors       # Télécharge les x_*.sh voisins

    # Mise à jour du 12345.json (ajoute les services détectés)
    DRAGON_LIST=$(ls "$MY_NODE_DIR"/x_*.sh 2>/dev/null | xargs -I{} basename {} .sh | sed 's/^x_//' | paste -sd',' -)

    # ── Capacités via heartbox_analysis.sh ──────────────────────────────────────
    HB_CACHE="$MY_NODE_DIR/heartbox_analysis.json"
    CAPACITIES='{"power_score":0,"crypto_score":0,"provider_ready":false,"storage_ready":false}'

    if [[ -f "$HB_SCRIPT" ]]; then
        if [[ ! -s "$HB_CACHE" ]] || \
           [[ $(( $(date +%s) - $(stat -c%Y "$HB_CACHE" 2>/dev/null || echo 0) )) -gt 900 ]]; then
            bash "$HB_SCRIPT" update >/dev/null 2>&1
        fi
        if [[ -s "$HB_CACHE" ]]; then
            _CAPS=$(jq '.capacities // empty' "$HB_CACHE" 2>/dev/null)
            [[ -n "$_CAPS" ]] && CAPACITIES="$_CAPS"
        fi
    fi

    # ── Détection UPassport local (pour les apps CGI et le swarm) ───────────────
    UPASSPORT_AVAILABLE="false"
    if curl -sf --max-time 2 "http://127.0.0.1:54321/health" >/dev/null 2>&1; then
        UPASSPORT_AVAILABLE="true"
    fi

    myIP=$(hostname -I | awk '{print $1}')
    G1PUB_CACHED=$(cat "$MY_NODE_DIR/G1PUB" 2>/dev/null || echo "")
    [ -z "$CHAN" ] && CHAN=$(ipfs key list -l 2>/dev/null | grep "MySwarm_${IPFSNODEID}" | awk '{print $1}' || echo "")

    cat > "$MY_NODE_DIR/12345.json" << EOF
{
    "version": "picoport-0.6-dragon",
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
    "uplanet": {
        "upassport_available": $UPASSPORT_AVAILABLE,
        "upload2ipfs":  "${UPLOAD_SCRIPT:-}",
        "publish_nostr": "${PUBLISH_SCRIPT:-}"
    },
    "capacities":    $CAPACITIES
}
EOF

    # Publication IPNS
    ss_info "Publication de la balise (Services: $DRAGON_LIST)"
    
    # ── AJOUT : Sécurisation vitale de la balise pour l'Astroport ──
    echo "${MOATS}" > "$MY_NODE_DIR/_MySwarm.moats"
    echo "$(date -u)" > "$MY_NODE_DIR/_MySwarm.staom"
    echo "$(hostname)" > "$MY_NODE_DIR/name"
    echo "🌿 Light" > "$MY_NODE_DIR/power"
    
    # ── AJOUT : Preuve cryptographique Y-Level (SSH PubKey) ──
    if [[ -f ~/.ssh/id_ed25519.pub ]]; then
        # Fichier brut pour compatibilité générale
        cat ~/.ssh/id_ed25519.pub > "$MY_NODE_DIR/SSHPUB"
        # Fichier y_ssh.pub qui prouve au swarm que nous sommes "Y-Level"
        cat ~/.ssh/id_ed25519.pub > "$MY_NODE_DIR/y_ssh.pub"
    fi
    # ───────────────────────────────────────────────────────────────
    
    ipfs add -rwQ "$MY_NODE_DIR" | tail -n 1 | xargs ipfs name publish --lifetime=24h --ttl=1h >/dev/null 2>&1 &

    # S'aligner sur le rythme de la constellation (5 minutes)
    sleep 300
done