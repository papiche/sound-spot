#!/bin/bash
# =========================================================================
#  dj_mixx.sh — Poste DJ Zicmama SoundSpot (Version UPlanet Swarm)
#  Connecte le WiFi (Local) ou les Tunnels P2P (Swarm), et lance Mixxx.
#
#  Usage : 
#    bash dj_mixx.sh           (lance la session DJ)
#    bash dj_mixx.sh --setup   (force la reconfiguration)
# =========================================================================
set -euo pipefail

# ── Couleurs ─────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; M='\033[0;35m'; N='\033[0m'; D='\033[2m'
log()  { echo -e "${G}▶${N} $*"; }
info() { echo -e "${C}ℹ${N}  $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err()  { echo -e "${R}✗${N}  $*" >&2; exit 1; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }
ask()  { echo -ne "${M}?${N}  $*"; }

[ "$(id -u)" -eq 0 ] && err "Ne lancez PAS ce script en root. (sudo sera appelé si nécessaire)"

CONF_FILE="$HOME/.config/soundspot_dj.conf"
P2P_TUNNELS_TO_CLOSE=""

# ── Gestion des arguments ─────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo -e "${C}Usage : bash dj_mixx.sh [OPTION]${N}"
            echo "Options :"
            echo "  --reset   : Effacer la configuration et recommencer à zéro"
            echo "  --help    : Afficher ce message d'aide"
            exit 0
            ;;
        --reset)
            echo -e "${Y}⚠ Suppression de la configuration ($CONF_FILE)${N}"
            rm -f "$CONF_FILE"
            ;;
    esac
done
# ────────────────────────────────────────────────────────────────

# ════════════════════════════════════════════════════════════════
#  Helper : Récupération du port d'un tunnel P2P
# ════════════════════════════════════════════════════════════════
get_p2p_port() {
    local svc_slug=$1
    local node_id=$2
    # Cherche la redirection TCP dans la liste des tunnels IPFS actifs
    local port=$(ipfs p2p ls 2>/dev/null | grep "/x/${svc_slug}-${node_id}" | grep -oP 'tcp/\K\d+' | head -n 1)
    echo "$port"
}

# ════════════════════════════════════════════════════════════════
#  Phase 1 : Configuration & Radar Swarm (si inexistante ou --setup)
# ════════════════════════════════════════════════════════════════
do_setup() {
    clear
    echo -e "${C}  Configuration Poste DJ — SoundSpot / UPlanet${N}"
    mkdir -p "$(dirname "$CONF_FILE")"

    DEST_MODE="local"
    SWARM_NODE=""
    SWARM_NAME=""
    STREAM_MODE="1"

    # Radar Swarm
    declare -a S_NODES
    declare -a S_NAMES
    idx=0
    
    if command -v ipfs &>/dev/null && [ -d "$HOME/.zen/tmp/swarm" ]; then
        for script in "$HOME"/.zen/tmp/swarm/*/x_icecast.sh; do
            [ -f "$script" ] || continue
            node=$(basename "$(dirname "$script")")
            name="$node"
            json_file="$HOME/.zen/tmp/swarm/$node/12345.json"
            if [ -f "$json_file" ]; then
                parsed_name=$(jq -r '.hostname // empty' "$json_file" | head -n 1)
                [ -n "$parsed_name" ] && name="$parsed_name"
            fi

            S_NODES[$idx]="$node"
            S_NAMES[$idx]="$name"
            ((idx += 1))
        done
    fi

    if [ $idx -eq 0 ]; then
        echo -e "  ${D}(Aucun nœud distant détecté dans le Swarm)${N}"
    fi

    hdr "Destination de la diffusion"
    echo -e "  ${C}[0]${N} Réseau Local  (En direct via WiFi)"
    
    # Correction : On commence à 0 pour l'index et on vérifie si idx > 0
    if [ $idx -gt 0 ]; then
        for i in $(seq 0 $((idx-1))); do
            # On affiche i+1 pour que l'utilisateur tape 1 pour le premier nœud
            echo -e "  ${C}[$((i+1))]${N} Constellation : ${W}${S_NAMES[$i]}${N} (P2P distant)"
        done
    else
        echo -e "  ${D}(Aucun nœud distant détecté dans le Swarm)${N}"
    fi
    echo ""
    ask "Choix de la destination [0] : "; read -r DEST_CHOICE
    DEST_CHOICE="${DEST_CHOICE:-0}"

    if [ "$DEST_CHOICE" -gt 0 ] && [ "$DEST_CHOICE" -le "$idx" ]; then
        REAL_IDX=$((DEST_CHOICE-1))
        DEST_MODE="swarm"
        SWARM_NODE="${S_NODES[$REAL_IDX]}"
        SWARM_NAME="${S_NAMES[$REAL_IDX]}"
        log "Mode Constellation (P2P) sélectionné → ${SWARM_NAME}"
        
        STREAM_MODE="1"
        SPOT_NAME="N/A"
        SPOT_IP="127.0.0.1" 
    else
        DEST_MODE="local"
        log "Mode Local (WiFi) sélectionné"
        
        ask "SSID WiFi [ZICMAMA] : "; read -r INPUT_NAME
        SPOT_NAME="${INPUT_NAME:-ZICMAMA}"
        
        ask "IP du RPi [192.168.10.1] : "; read -r INPUT_IP
        SPOT_IP="${INPUT_IP:-192.168.10.1}"
        
        hdr "Mode de diffusion audio"
        echo -e "  ${C}[1]${N} Icecast (Classique : config Mixxx requise, latence 2-3s)"
        echo -e "  ${C}[2]${N} Direct  (Capture le son du PC, Zéro latence, requiert SSH)"
        ask "Choix [1] : "; read -r S_MODE
        STREAM_MODE="${S_MODE:-1}"
    fi

    ask "Mot de passe Icecast [0penS0urce!] : "; read -r INPUT_PASS
    ICECAST_PASS="${INPUT_PASS:-0penS0urce!}"

    # Sauvegarde
    cat > "$CONF_FILE" <<EOF
DEST_MODE="$DEST_MODE"
SWARM_NODE="$SWARM_NODE"
SWARM_NAME="$SWARM_NAME"
SPOT_NAME="$SPOT_NAME"
SPOT_IP="$SPOT_IP"
ICECAST_PASS="$ICECAST_PASS"
STREAM_MODE="$STREAM_MODE"
SNAPCAST_PORT_DEFAULT="1704"
ICECAST_PORT_DEFAULT="8111"
EOF
    log "Configuration sauvegardée dans $CONF_FILE"

    if [ "$STREAM_MODE" == "2" ]; then
        echo ""
        hdr "Configuration SSH (Mode Direct)"
        info "Le mode Direct nécessite une connexion SSH sans mot de passe."
        
        if [ ! -f "$HOME/.ssh/id_rsa" ] && [ ! -f "$HOME/.ssh/id_ed25519" ]; then
            log "Génération d'une clé SSH locale..."
            ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
        fi
        
        log "Copie de la clé vers le Raspberry Pi (pi@$SPOT_IP)..."
        info "Si le système vous demande 'Are you sure you want to continue connecting', tapez 'yes' en toutes lettres."
        info "Veuillez entrer le mot de passe du Pi si on vous le demande."
        ssh-copy-id "pi@$SPOT_IP" || warn "La copie a échoué. Le flux direct nécessitera un mot de passe."
    fi
}

if [ ! -f "$CONF_FILE" ] || [ "${1:-}" == "--setup" ]; then
    do_setup
fi

# Charger la configuration
source "$CONF_FILE"
SNAPCAST_PORT="${SNAPCAST_PORT_DEFAULT:-1704}"
ICECAST_PORT="${ICECAST_PORT_DEFAULT:-8111}"

# ════════════════════════════════════════════════════════════════
#  Phase 2 : Vérification des dépendances
# ════════════════════════════════════════════════════════════════
PKGS="snapclient mixxx curl"
[ "$STREAM_MODE" == "2" ] && PKGS="$PKGS pulseaudio-utils openssh-client"

MISSING=""
for pkg in $PKGS; do
    if ! command -v "$pkg" &>/dev/null; then
        if [ "$pkg" == "pulseaudio-utils" ] && command -v parec &>/dev/null; then continue; fi
        MISSING="$MISSING $pkg"
    fi
done

if [ -n "$MISSING" ]; then
    hdr "Installation des dépendances manquantes"
    log "Requiert sudo pour : apt-get install -y$MISSING"
    sudo apt-get update -qq && sudo apt-get install -y $MISSING
fi

# ════════════════════════════════════════════════════════════════
#  Phase 3 : Préparation du Réseau (WiFi ou Tunnels P2P)
# ════════════════════════════════════════════════════════════════
clear
echo -e "\n${C}  ZICMAMA SoundSpot — Session DJ${N}\n"

if [ "$DEST_MODE" == "swarm" ]; then
    echo -e "${G}▶${N} Destination : Constellation ${W}${SWARM_NAME}${N} (P2P)"
    
    # Montage du tunnel Icecast
    if [ -f "$HOME/.zen/tmp/swarm/$SWARM_NODE/x_icecast.sh" ]; then
        info "Ouverture du tunnel Icecast..."
        bash "$HOME/.zen/tmp/swarm/$SWARM_NODE/x_icecast.sh" > /dev/null 2>&1 &
        sleep 2
        ICECAST_PORT=$(get_p2p_port "icecast" "$SWARM_NODE")
        # ... (reste du montage P2P inchangé)
    fi
else
    # ── Correction : On entoure toute la logique WiFi par ce bloc else ──
    CURRENT=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes' | cut -d: -f2 || echo "")
    if [ "$CURRENT" != "$SPOT_NAME" ]; then
        echo -e "${G}▶${N} Connexion à ${W}${SPOT_NAME}${N}..."
        nmcli dev wifi connect "$SPOT_NAME" || err "Échec WiFi. Vérifiez que le SoundSpot est allumé."
        sleep 3
    fi
    echo -e "${G}▶${N} WiFi : ${C}${SPOT_NAME}${N}"

    echo -ne "${G}▶${N} Attente du RPi ($SPOT_IP) "
    CONNECTED=false
    for i in {1..15}; do
        if ping -c1 -W1 "$SPOT_IP" &>/dev/null; then CONNECTED=true; echo -e " ${G}[PRÊT]${N}"; break; fi
        echo -ne "."; sleep 1
    done
    if [ "$CONNECTED" = false ]; then err "Impossible de joindre $SPOT_IP"; fi
fi

# ════════════════════════════════════════════════════════════════
#  Phase 4 : Démarrage Audio & Trap de fermeture
# ════════════════════════════════════════════════════════════════
pkill snapclient 2>/dev/null || true
SNAP_PID=""

# Lancement de Snapclient seulement si on a réussi à résoudre le port
if [ -n "$SNAPCAST_PORT" ]; then
    snapclient -h "$SPOT_IP" -p "$SNAPCAST_PORT" > /dev/null 2>&1 &
    SNAP_PID=$!
    echo -e "${G}▶${N} Snapclient (retour casque) actif [PID $SNAP_PID]"
fi

PAREC_PID=""
if [ "$STREAM_MODE" == "2" ]; then
    # ── NOUVEAU : Vérification SSH au premier plan avant la capture ──
    echo -e "${G}▶${N} Mode DIRECT : Vérification de l'accès SSH..."
    info "Une confirmation d'empreinte (fingerprint) peut apparaître ci-dessous :"
    
    # On lance un test SSH synchrone. L'utilisateur peut répondre 'yes' tranquillement.
    if ! ssh -o ConnectTimeout=5 "pi@$SPOT_IP" "echo '[SSH OK]'"; then
        err "Échec de la connexion SSH. Avez-vous accepté la clé ? (Relancez avec --reset pour reconfigurer)"
    fi
    # ─────────────────────────────────────────────────────────────────

    echo -e "${G}▶${N} Capture du son vers le RPi..."
    parec -d @DEFAULT_SINK@.monitor --format=s16le --rate=48000 --channels=2 | ssh "pi@$SPOT_IP" "cat > /dev/shm/snapfifo" &
    PAREC_PID=$!
    echo -e "${Y}   INFO : Le son du PC est diffusé instantanément sur SoundSpot !${N}"
else
    echo -e "${Y}   INFO : Configurez le Broadcaster Mixxx vers Icecast2 -> ${SPOT_IP}:${ICECAST_PORT}${N}"
    echo -e "          Montage: /live | Login: source | Mdp: $ICECAST_PASS"
fi

# Cleanup Function (S'exécute à la fermeture de Mixxx ou en cas d'interruption)
cleanup() {
    echo -e "\n${C}Fermeture de la session DJ...${N}"
    
    # Correction de la syntaxe de kill
    [ -n "$SNAP_PID" ] && kill "$SNAP_PID" 2>/dev/null || true
    [ -n "$PAREC_PID" ] && kill "$PAREC_PID" 2>/dev/null || true
    
    if [ -n "$P2P_TUNNELS_TO_CLOSE" ]; then
        info "Fermeture des tunnels IPFS P2P..."
        for proto in $P2P_TUNNELS_TO_CLOSE; do
            # On utilise l'ID du protocole pour fermer proprement
            ipfs p2p close -p "$proto" 2>/dev/null || true
        done
    fi
}
trap cleanup INT TERM EXIT

# ════════════════════════════════════════════════════════════════
#  Phase 5 : Lancement de Mixxx
# ════════════════════════════════════════════════════════════════
echo -e "${G}▶${N} Lancement de Mixxx..."
mixxx

# La fonction `cleanup` sera appelée automatiquement après la fermeture de Mixxx grâce au trap EXIT.