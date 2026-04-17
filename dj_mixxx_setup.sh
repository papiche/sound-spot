#!/bin/bash
# ================================================================
#  dj_mixxx_setup.sh — Poste DJ Zicmama SoundSpot
#  G1FabLab / UPlanet ẐEN — zicmama.com
#
#  À lancer sur le PC Linux du DJ (pas sur le RPi).
#  Installe Snapclient + Mixxx et génère ~/zicmama_play.sh
#
#  Utilisation :
#    bash dj_mixxx_setup.sh
# ================================================================
set -euo pipefail

# ── Couleurs ─────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; M='\033[0;35m'
DIM='\033[2m'; N='\033[0m'
log()  { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err()  { echo -e "${R}✗${N}  $*" >&2; exit 1; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }
ask()  { echo -ne "${M}?${N}  $*"; }

[ "$(id -u)" -eq 0 ] && err "Ne lance PAS en root. sudo sera appelé si nécessaire."
command -v sudo >/dev/null || err "sudo requis"

clear
echo -e "
${C}  ░▀▀█░▀█▀░█▀▀░█▄█░█▀█░█▄█░█▀█
  ░▄▀░░░█░░█░░░█░█░█▀█░█░█░█▀█
  ░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀░▀░▀░▀░▀░▀${N}
${DIM}  Configuration poste DJ — G1FabLab / UPlanet ẐEN${N}
"

# ════════════════════════════════════════════════════════════════
#  1. Paramètres du SoundSpot
# ════════════════════════════════════════════════════════════════
hdr "Paramètres du SoundSpot"
echo -e "  Ces infos sont imprimées sur le portail captif du RPi."
echo ""

ask "SSID WiFi du SoundSpot [ZICMAMA] : "
read -r INPUT_NAME
SPOT_NAME="${INPUT_NAME:-ZICMAMA}"

ask "IP du RPi [192.168.10.1] : "
read -r INPUT_IP
SPOT_IP="${INPUT_IP:-192.168.10.1}"

ask "Mot de passe Icecast [0penS0urce!] : "
read -r INPUT_PASS
ICECAST_PASS="${INPUT_PASS:-0penS0urce!}"

SNAPCAST_PORT="1704"
ICECAST_PORT="8111"

log "SoundSpot : ${W}${SPOT_NAME}${N}  →  ${C}${SPOT_IP}${N}"

# ════════════════════════════════════════════════════════════════
#  2. Snapclient
# ════════════════════════════════════════════════════════════════
hdr "Snapclient"

if command -v snapclient &>/dev/null; then
    log "Snapclient déjà présent : $(snapclient --version 2>&1 | head -1)"
else
    ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
    VER=$(wget -qO- https://api.github.com/repos/badaix/snapcast/releases/latest \
          | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/' || echo "0.27.0")
    [ -z "$VER" ] && VER="0.27.0"
    DEB="snapclient_${VER}-1_${ARCH}.deb"
    URL="https://github.com/badaix/snapcast/releases/download/v${VER}/${DEB}"

    log "Téléchargement Snapclient ${VER} (${ARCH})..."
    if wget -q --show-progress -O "/tmp/${DEB}" "$URL" 2>/dev/null && \
       dpkg-deb --info "/tmp/${DEB}" &>/dev/null; then
        sudo dpkg -i "/tmp/${DEB}" || sudo apt-get install -f -y
        rm -f "/tmp/${DEB}"
    else
        rm -f "/tmp/${DEB}"
        warn "Package .deb indisponible — tentative via apt..."
        sudo apt-get update -qq
        sudo apt-get install -y snapclient 2>/dev/null || \
        sudo apt-get install -y snapcast   2>/dev/null || \
        warn "snapclient non installé — https://github.com/badaix/snapcast/releases"
    fi
    command -v snapclient &>/dev/null && log "Snapclient installé ✓"
fi

# ════════════════════════════════════════════════════════════════
#  3. Mixxx
# ════════════════════════════════════════════════════════════════
hdr "Mixxx"

if command -v mixxx &>/dev/null; then
    log "Mixxx déjà présent ✓"
else
    log "Installation Mixxx..."
    grep -r "mixxx" /etc/apt/sources.list.d/ &>/dev/null || \
        sudo add-apt-repository -y ppa:mixxx/mixxx 2>/dev/null || true
    sudo apt-get update -qq
    sudo apt-get install -y mixxx
    log "Mixxx installé ✓"
fi

# ════════════════════════════════════════════════════════════════
#  4. Lanceur ~/zicmama_play.sh
# ════════════════════════════════════════════════════════════════
hdr "Génération du lanceur ~/zicmama_play.sh"

LAUNCHER="$HOME/zicmama_play.sh"
cat > "$LAUNCHER" <<PLAYEOF
#!/bin/bash
# ══════════════════════════════════════════════════════
#  ZICMAMA SoundSpot — Lanceur PC DJ
#  G1FabLab / UPlanet ẐEN — zicmama.com
# ══════════════════════════════════════════════════════
SPOT_NAME="${SPOT_NAME}"
SPOT_IP="${SPOT_IP}"
SNAP_PORT="${SNAPCAST_PORT}"
ICECAST_PORT="${ICECAST_PORT}"
ICECAST_PASS="${ICECAST_PASS}"

G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'
W='\033[1;37m'; R='\033[0;31m'; N='\033[0m'
clear
echo -e "\n\${C}  ZICMAMA SoundSpot — session DJ\${N}\n"

# ── Connexion WiFi SoundSpot ────────────────────────────────
CURRENT=\$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '/^yes:/{print \$2}' \
           || iwgetid -r 2>/dev/null || echo "")

if [ "\$CURRENT" != "\$SPOT_NAME" ]; then
    echo -e "\${Y}⚠\${N}  Réseau actuel : \${CURRENT:-inconnu}"
    echo -e "   Connexion à \${W}\${SPOT_NAME}\${N}..."
    if command -v nmcli &>/dev/null; then
        nmcli dev wifi connect "\$SPOT_NAME" 2>/dev/null && sleep 2 || {
            echo -e "\${R}✗\${N}  Échec — connecte-toi manuellement à \${W}\${SPOT_NAME}\${N}"
            exit 1
        }
    else
        echo -e "   Connecte-toi manuellement à \${C}\${SPOT_NAME}\${N} puis relance."
        exit 1
    fi
fi
echo -e "\${G}▶\${N} WiFi : \${C}\${SPOT_NAME}\${N}"

# ── Joignabilité du RPi ─────────────────────────────────────
ping -c1 -W3 "\$SPOT_IP" &>/dev/null || {
    echo -e "\${R}✗\${N}  RPi \${SPOT_IP} non joignable — allumé ?"
    exit 1
}
echo -e "\${G}▶\${N} SoundSpot en ligne : \${C}\${SPOT_IP}\${N}"

# ── Snapclient local (retour casque) ────────────────────────
pkill snapclient 2>/dev/null || true; sleep 0.5
snapclient -h "\$SPOT_IP" -p "\$SNAP_PORT" &
SPID=\$!
trap "kill \$SPID 2>/dev/null; exit 0" INT TERM
echo -e "\${G}▶\${N} Snapclient local (casque, PID \$SPID)"

# ── Rappel configuration Mixxx ──────────────────────────────
echo -e "
  \${Y}╔════════════════════════════════════════════════╗\${N}
  \${Y}║   MIXXX — LIVE BROADCASTING                   ║\${N}
  \${Y}╠════════════════════════════════════════════════╣\${N}
  \${Y}║\${N}  Options → Live Broadcasting                  \${Y}║\${N}
  \${Y}║\${N}  Type     : \${W}Icecast2\${N}                          \${Y}║\${N}
  \${Y}║\${N}  Serveur  : \${C}\${SPOT_IP}\${N}                  \${Y}║\${N}
  \${Y}║\${N}  Port     : \${W}\${ICECAST_PORT}\${N}                           \${Y}║\${N}
  \${Y}║\${N}  Montage  : \${W}/live\${N}                           \${Y}║\${N}
  \${Y}║\${N}  Login    : \${W}source\${N}                          \${Y}║\${N}
  \${Y}║\${N}  Mdp      : \${W}\${ICECAST_PASS}\${N}                   \${Y}║\${N}
  \${Y}║\${N}  Format   : \${W}Ogg Vorbis 128 kbps\${N}               \${Y}║\${N}
  \${Y}╠════════════════════════════════════════════════╣\${N}
  \${Y}║\${N}  ⚠  LATENCE 1-3 s — caler sur la Cue casque  \${Y}║\${N}
  \${Y}╚════════════════════════════════════════════════╝\${N}

  \${C}http://\$SPOT_IP:1780\${N}  ← clients Snapcast connectés
"

mixxx
kill "\$SPID" 2>/dev/null || true
echo -e "\n\${G}▶\${N} Session terminée."
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
