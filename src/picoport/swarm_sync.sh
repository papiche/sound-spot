#!/bin/bash
# src/picoport/swarm_sync.sh — Service de visibilité Picoport (Port 12345)
# Version conforme Astroport.ONE (Clés déterministes + SSH Bootstrap)

source /opt/soundspot/soundspot.conf 2>/dev/null || true
source "$HOME/.astro/bin/activate" 2>/dev/null || true

ASTRO_TOOLS="$HOME/.zen/Astroport.ONE/tools"
set +e
[ -f "$ASTRO_TOOLS/my.sh" ] && source "$ASTRO_TOOLS/my.sh" 2>/dev/null || true
set -e

IPFSNODEID=$(ipfs id -f="<id>")
JSON_FILE="/tmp/12345.json"
HTTP_RES="/dev/shm/picoport_12345.http"

mkdir -p "$HOME/.zen/game"

# =========================================================================
# 1. DÉFINITION DE UPLANETNAME (Essaim de rattachement)
# =========================================================================
UPLANETNAME=$(cat ~/.ipfs/swarm.key 2>/dev/null | tail -n 1)
[ -z "$UPLANETNAME" ] && UPLANETNAME="0000000000000000000000000000000000000000000000000000000000000000"

# =========================================================================
# 2. INITIALISATION DÉTERMINISTE DES CLÉS MySwarm (Conforme _12345.sh)
# =========================================================================
CHAN=$(ipfs key list -l | grep -w "MySwarm_${IPFSNODEID}" | cut -d ' ' -f 1)

if [[ ! -s ~/.zen/game/myswarm_secret.june ]]; then
    echo "🔑 Initialisation déterministe de la clé MySwarm_${IPFSNODEID}..."
    
    # Hash matériel unique basé sur le CPU
    FULL_HASH=$(cat /proc/cpuinfo | grep -Ev MHz | sha512sum | cut -d ' ' -f 1)
    SECRET1=${FULL_HASH:0:32}
    SECRET2=${FULL_HASH:32:64}
    
    # Nettoyage ancienne clé si elle existe
    ipfs key rm "MySwarm_${IPFSNODEID}" 2>/dev/null || true
    
    # Fichiers secrets Astroport
    echo "SALT=$SECRET1 && PEPPER=$SECRET2" > ~/.zen/game/myswarm_secret.june
    chmod 600 ~/.zen/game/myswarm_secret.june
    
    # Génération IPNS
    "$ASTRO_TOOLS/keygen" -t ipfs -o ~/.zen/game/myswarm_secret.ipns "$SECRET1${UPLANETNAME}" "$SECRET2${UPLANETNAME}"
    chmod 600 ~/.zen/game/myswarm_secret.ipns
    
    # Génération Dunikey
    "$ASTRO_TOOLS/keygen" -t duniter -o ~/.zen/game/myswarm_secret.dunikey "$SECRET1${UPLANETNAME}" "$SECRET2${UPLANETNAME}"
    chmod 600 ~/.zen/game/myswarm_secret.dunikey
    
    # Importation de la clé dans IPFS
    ipfs key import "MySwarm_${IPFSNODEID}" -f pem-pkcs8-cleartext ~/.zen/game/myswarm_secret.ipns
    CHAN=$(ipfs key list -l | grep -w "MySwarm_${IPFSNODEID}" | cut -d ' ' -f 1)
    echo "✅ Clé MySwarm générée : $CHAN"
fi

# =========================================================================
# 3. DISTRIBUTION DES CLÉS SSH DE CONFIANCE (Bootstrap Capitaines)
# =========================================================================
SSHAUTHFILE="$HOME/.zen/Astroport.ONE/A_boostrap_ssh.txt"
if [[ -s "$SSHAUTHFILE" ]]; then
    echo "🛡️ Mise à jour des clés SSH autorisées (Capitaines UPlanet)..."
    mkdir -p ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    
    while IFS= read -r line; do
        # On ignore les commentaires et on cherche "ssh-ed25519"
        LINE=$(echo "$line" | grep "ssh-ed25519" | grep -Ev "#" || true)
        if [[ -n "$LINE" ]]; then
            # Ajout si non existant
            if ! grep -qF "$LINE" ~/.ssh/authorized_keys 2>/dev/null; then
                echo "$LINE" >> ~/.ssh/authorized_keys
                echo "   -> Nouvelle clé SSH ajoutée"
            fi
        fi
    done < "$SSHAUTHFILE"
    
    # Nettoyage des doublons sans altérer l'ordre
    awk '!seen[$0]++' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.clean
    mv ~/.ssh/authorized_keys.clean ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
fi

# =========================================================================
# 4. BOUCLE PRINCIPALE (Balise réseau 12345)
# =========================================================================
while true; do
    MOATS=$(date +%s)
    myIP=$(hostname -I | awk '{print $1}')
    
    # Génération du JSON de la balise Picoport
    cat > "$JSON_FILE" <<EOF
{
    "version": "picoport-12345-v2",
    "created": "$MOATS",
    "hostname": "$(hostname)",
    "ipfsnodeid": "$IPFSNODEID",
    "myIP": "$myIP",
    "astroport": "http://$myIP:12345",
    "relay": "ws://127.0.0.1:9999",
    "u.spot": "http://$myIP:54321",
    "g1station": "/ipns/$IPFSNODEID",
    "g1swarm": "/ipns/$CHAN",
    "type": "soundspot",
    "services": {
        "audio": "active",
        "p2p_relay": "tunneled"
    }
}
EOF

    # Préparation de la réponse HTTP brute pour socat
    cat > "$HTTP_RES" <<EOF
HTTP/1.1 200 OK
Content-Type: application/json
Access-Control-Allow-Origin: *
Connection: close

$(cat $JSON_FILE)
EOF

    # Lancement du serveur HTTP socat si pas déjà actif
    if ! pgrep -f "socat TCP4-LISTEN:12345" > /dev/null; then
        socat TCP4-LISTEN:12345,reuseaddr,fork SYSTEM:"cat $HTTP_RES" &
    fi

    # Publication de notre identité IPNS en tâche de fond
    (ipfs name publish --lifetime=24h --ttl=1h /ipfs/$(ipfs add -Q $JSON_FILE) >/dev/null 2>&1 &)

    # Maintenance du cache swarm : on télécharge les voisins détectés
    PEERS=$(ipfs swarm peers | grep -oP 'p2p/\K.*' | head -n 5)
    for p in $PEERS; do
        # On télécharge le répertoire complet (contient 12345.json + x_*.sh)
        # On utilise --timeout pour ne pas bloquer si un voisin est lent
        TMP_SWARM="/tmp/swarm_$p"
        if ipfs --timeout 20s get -o "$TMP_SWARM" "/ipns/$p/" >/dev/null 2>&1; then
            mkdir -p ~/.zen/tmp/swarm/
            rm -rf ~/.zen/tmp/swarm/$p
            mv "$TMP_SWARM" ~/.zen/tmp/swarm/$p
        fi
    done

    # Pause de 5 minutes avant le prochain cycle
    sleep 300
done