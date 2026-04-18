#!/bin/bash
# ================================================================
#  dj_mixxx_setup.sh — Poste DJ Zicmama SoundSpot (V2 Robuste)
# ================================================================
set -euo pipefail

# ── Couleurs ─────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; M='\033[0;35m'; N='\033[0m'
log()  { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err()  { echo -e "${R}✗${N}  $*" >&2; exit 1; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }
ask()  { echo -ne "${M}?${N}  $*"; }

[ "$(id -u)" -eq 0 ] && err "Ne lance PAS en root. sudo sera appelé si nécessaire."

clear
echo -e "${C}  Configuration poste DJ — SoundSpot${N}"

# 1. Paramètres
hdr "Paramètres du SoundSpot"
ask "SSID WiFi [ZICMAMA] : "; read -r INPUT_NAME
SPOT_NAME="${INPUT_NAME:-ZICMAMA}"
ask "IP du RPi [192.168.10.1] : "; read -r INPUT_IP
SPOT_IP="${INPUT_IP:-192.168.10.1}"
ask "Mot de passe Icecast [0penS0urce!] : "; read -r INPUT_PASS
ICECAST_PASS="${INPUT_PASS:-0penS0urce!}"

SNAPCAST_PORT="1704"
ICECAST_PORT="8111"

# 2. Installation snapclient mixxx curl
hdr "Vérification logiciels"
for pkg in snapclient mixxx curl; do
    if ! command -v $pkg &>/dev/null; then
        log "Installation de $pkg..."
        sudo apt-get update -qq && sudo apt-get install -y $pkg
    fi
done

# 3. Génération du lanceur
hdr "Génération de ~/zicmama_play.sh"
LAUNCHER="$HOME/zicmama_play.sh"
cat > "$LAUNCHER" <<PLAYEOF
#!/bin/bash
SPOT_NAME="${SPOT_NAME}"
SPOT_IP="${SPOT_IP}"
SNAP_PORT="${SNAPCAST_PORT}"
ICECAST_PORT="${ICECAST_PORT}"
ICECAST_PASS="${ICECAST_PASS}"

G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; W='\033[1;37m'; R='\033[0;31m'; N='\033[0m'

clear
echo -e "\n\${C}  ZICMAMA SoundSpot — Session DJ\${N}\n"

# ── 1. Connexion WiFi ───────────────────────────────────────
CURRENT=\$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2 || echo "")

if [ "\$CURRENT" != "\$SPOT_NAME" ]; then
    log "Connexion à \${W}\${SPOT_NAME}\${N}..."
    nmcli dev wifi connect "\$SPOT_NAME" || {
        echo -e "\${R}✗\${N} Échec WiFi. Vérifie que le SoundSpot est allumé."; exit 1
    }
    echo -e "   Attente stabilisation réseau (3s)..."
    sleep 3
fi
echo -e "\${G}▶\${N} WiFi : \${C}\${SPOT_NAME}\${N}"

# ── 2. Test de Joignabilité (Boucle de 15s) ─────────────────
echo -ne "\${G}▶\${N} Attente du RPi (\${SPOT_IP}) "
CONNECTED=false
for i in {1..15}; do
    if ping -c1 -W1 "\$SPOT_IP" &>/dev/null; then
        # On teste aussi si le port Snapcast répond
        if (echo > /dev/tcp/\$SPOT_IP/\$SNAP_PORT) >/dev/null 2>&1; then
            CONNECTED=true
            echo -e " \${G}[PRÊT]\${N}"
            break
        fi
    fi
    echo -ne "."
    sleep 1
done

if [ "\$CONNECTED" = false ]; then
    echo -e "\n\${R}✗\${N} Impossible de joindre l'audio sur \${SPOT_IP}."
    echo -e "   Note: Si tu as un câble Ethernet branché, débranche-le ou désactive-le."
    exit 1
fi

# ── 3. Lancement Audio ──────────────────────────────────────
pkill snapclient 2>/dev/null || true
snapclient -h "\$SPOT_IP" -p "\$SNAP_PORT" > /dev/null 2>&1 &
SPID=\$!
trap "kill \$SPID 2>/dev/null; exit 0" INT TERM

echo -e "\${G}▶\${N} Snapclient (retour casque) actif [PID \$SPID]"
echo -e "\${Y}   INFO : Configure Mixxx sur Icecast2 -> \${SPOT_IP}:\${ICECAST_PORT}\${N}"

mixxx
kill "\$SPID" 2>/dev/null
PLAYEOF

chmod +x "$LAUNCHER"
log "Lanceur créé : ${Y}${LAUNCHER}${N}"

# ════════════════════════════════════════════════════════════════
#  Résumé
# ════════════════════════════════════════════════════════════════
echo -e "
${W}════════════════════════════════════════════════════${N}
${G}  Poste DJ configuré !${N}
${W}════════════════════════════════════════════════════${N}

${C}── Jouer ────────────────────────────────────────────${N}
  1. Se connecter au WiFi : ${Y}${SPOT_NAME}${N}
  2. Lancer : ${Y}~/zicmama_play.sh${N}

${C}── Informations Icecast ─────────────────────────────${N}
  Serveur  : ${C}${SPOT_IP}:${ICECAST_PORT}${N}
  Montage  : /live    Login : source
  Mdp      : ${W}${ICECAST_PASS}${N}

${C}── Diagnostic Snapcast ──────────────────────────────${N}
  ${C}http://${SPOT_IP}:1780${N}

${W}════════════════════════════════════════════════════${N}
"
