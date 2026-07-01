#!/bin/bash
################################################################################
# control_center.sh - SoundSpot Control Center TUI
# ----------------------------------------------------------------------------
# Interface interactive pour piloter, relancer, inspecter et tester
# l'ensemble des services de l'infrastructure SoundSpot / ZICMAMA.
################################################################################

trap "tput cnorm; clear; exit 0" SIGINT SIGTERM EXIT

# --- DROITS & CONTEXTE ---
REAL_USER=${SUDO_USER:-${USER:-pi}}
REAL_UID=$(id -u "$REAL_USER" 2>/dev/null || echo 1000)
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
CMD_USER="sudo -u $REAL_USER env XDG_RUNTIME_DIR=/run/user/$REAL_UID IPFS_PATH=${USER_HOME}/.ipfs"
ASTRO_PYTHON="${USER_HOME}/.astro/bin/python3"

# --- CONFIG ---
INSTALL_DIR="/opt/soundspot"
SNAP_FIFO="/dev/shm/snapfifo"
SNAP_FIFO_MIC="/dev/shm/snapfifo_mic"
REFRESH_RATE=2
cursor=0
running=true
last_msg="Prêt. Flèches pour naviguer, Entrée pour Start/Stop."
busy=false

# --- COULEURS ---
BG_HEAD='\033[45m'
FG_HEAD='\033[30m'
NC='\033[0m'
GREEN='\033[1;32m'
RED='\033[1;31m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'

# --- LISTE COMPLÈTE DES SERVICES ---
# Format: "nom_service|CATEGORIE|Description"
SERVICES=(
    "icecast2|AUDIO|Ingestion flux DJ (Port 8111)"
    "soundspot-decoder|AUDIO|Décodeur FFmpeg (Ogg → PCM → FIFO)"
    "snapserver|AUDIO|Serveur Snapcast multicast (Port 1704)"
    "soundspot-client|AUDIO|Client Snapcast local (→ Bluetooth)"
    "soundspot-autodj|AUDIO|AutoDJ fallback (playlist ~/Music)"
    "soundspot-mic|AUDIO|Capture micro ambiance (ReSpeaker)"
    "soundspot-bt-reactive|MATERIEL|Reconnexion Bluetooth réactive (D-Bus)"
    "soundspot-idle|MATERIEL|Clocher & bips (heure solaire)"
    "soundspot-battery|MATERIEL|Surveillance batterie INA219 (I2C)"
    "soundspot-presence|MATERIEL|Détection présence caméra (OpenCV)"
    "soundspot-rtmp-player|MATERIEL|Lecteur flux vidéo drone (RTMP)"
    "lighttpd|RESEAU|Portail web captif (Port 80)"
    "soundspot-ap|RESEAU|Hotspot WiFi public (uap0)"
    "soundspot-channel-sync|RESEAU|Synchronisation canal WiFi"
    "soundspot-mesh|RESEAU|Réseau maillé B.A.T.M.A.N. (bat0)"
    "picoport|P2P_IA|Nœud IPFS UPlanet + g1cli"
    "soundspot-fleet-relay|P2P_IA|Relay NOSTR local flotte (ws:9999)"
    "soundspot-fleet|P2P_IA|Écoute ordres flotte NOSTR"
    "soundspot-jukebox|P2P_IA|Jukebox Nostr (téléchargement MP3)"
    "soundspot-state|P2P_IA|Daemon état nœud (uptime/capteurs)"
    "mon-oeil|P2P_IA|Caméra IA → Swarm Ollama"
)

# --- AFFICHAGE PRINCIPAL ---
draw_ui() {
    clear
    tput civis

    # Bandeau titre
    local cols
    cols=$(tput cols)
    local title="  🐽 ZICMAMA CONTROL CENTER  "
    local keys=" [Q]uitter  [C]heck  [G]Log  [I]nfos  [S]hutdown flotte "
    printf "${BG_HEAD}${FG_HEAD}${BOLD}%-${cols}s${NC}\n" "${title}${keys}"

    # Métriques rapides
    local cpu_temp uptime_str ram_used
    cpu_temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.1f°C", $1/1000}' || echo "N/A")
    uptime_str=$(uptime -p 2>/dev/null | sed 's/up //' || echo "N/A")
    ram_used=$(free -m 2>/dev/null | awk '/Mem:/{printf "%dMB/%dMB", $3, $2}' || echo "N/A")
    echo -e "${DIM}  CPU: ${cpu_temp}  |  RAM: ${ram_used}  |  Uptime: ${uptime_str}${NC}\n"

    local current_cat=""
    for i in "${!SERVICES[@]}"; do
        IFS='|' read -r svc cat desc <<< "${SERVICES[$i]}"

        if [[ "$cat" != "$current_cat" ]]; then
            echo -e "${CYAN}─── $cat ───${NC}"
            current_cat="$cat"
        fi

        local line_start line_end
        if [ "$i" -eq "$cursor" ]; then
            line_start="${BOLD}${YELLOW} ▶"
            line_end="${NC}"
        else
            line_start="  "
            line_end=""
        fi

        local status
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            status="${GREEN}[EN LIGNE]${NC}"
        elif systemctl is-failed --quiet "$svc" 2>/dev/null; then
            status="${RED}[EN ECHEC]${NC}"
        else
            status="${DIM}[ ARRÊTÉ ]${NC}"
        fi

        local svc_name
        svc_name=$(printf "%-32s" "$svc")
        echo -e "${line_start} ${status} ${svc_name} ${DIM}${desc}${line_end}"
    done

    echo -e "\n${BG_HEAD}${FG_HEAD} [↑↓] Naviguer  [Entrée] On/Off  [R] Restart  [L] Log  [O] Ouvrir  [T] Tester  [F] Forcer refresh ${NC}"
    echo -e "${BOLD}›${NC} ${YELLOW}${last_msg}${NC}"
}

# --- INFOS SYSTÈME ---
action_sysinfo() {
    tput cnorm; clear
    echo -e "${CYAN}=== Informations Système SoundSpot ===${NC}\n"

    echo -e "${BOLD}Température & CPU${NC}"
    cpu_temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.2f°C", $1/1000}')
    echo "  CPU: ${cpu_temp}"
    if command -v vcgencmd &>/dev/null; then
        vcgencmd measure_temp 2>/dev/null
        vcgencmd measure_volts core 2>/dev/null
    fi

    echo -e "\n${BOLD}Mémoire${NC}"
    free -h

    echo -e "\n${BOLD}Disque / RAM tmpfs${NC}"
    df -h /dev/shm /opt/soundspot / 2>/dev/null | head -6

    echo -e "\n${BOLD}FIFO Snapcast${NC}"
    if [[ -p "$SNAP_FIFO" ]]; then
        echo "  ${GREEN}✓${NC} ${SNAP_FIFO} — actif"
    else
        echo "  ${RED}✗${NC} ${SNAP_FIFO} — absent (soundspot-decoder arrêté ?)"
    fi
    if [[ -p "$SNAP_FIFO_MIC" ]]; then
        echo "  ${GREEN}✓${NC} ${SNAP_FIFO_MIC} — actif"
    else
        echo "  ${DIM}·${NC} ${SNAP_FIFO_MIC} — absent (soundspot-mic inactif)"
    fi

    echo -e "\n${BOLD}Interfaces réseau${NC}"
    ip -br addr show 2>/dev/null | grep -v "^lo"

    echo -e "\n${BOLD}Clients WiFi connectés (AP)${NC}"
    iw dev uap0 station dump 2>/dev/null | grep "^Station" | awk '{print "  "$2}' \
        || echo "  uap0 inactif ou aucun client"

    echo -e "\n${BOLD}Bluetooth${NC}"
    bluetoothctl devices Connected 2>/dev/null || \
        hcitool con 2>/dev/null || echo "  Aucun périphérique connecté"

    if [[ -n "$USER_HOME" ]]; then
        echo -e "\n${BOLD}IPFS${NC}"
        $CMD_USER ipfs id -f "<id>\n  Pairs: " 2>/dev/null
        $CMD_USER ipfs swarm peers 2>/dev/null | wc -l | awk '{print $1 " peers connectés"}'
    fi

    echo -e "\n${YELLOW}Entrée pour retourner...${NC}"; read -r
}

# --- SHUTDOWN FLOTTE ---
action_fleet_shutdown() {
    tput cnorm; clear
    echo -e "${RED}=== Extinction de la Flotte NOSTR ===${NC}\n"
    echo -e "${YELLOW}⚠  Cette action envoie un ordre 'shutdown' à TOUS les nœuds de la flotte${NC}"
    echo -e "   (Maître, Satellites, Nœud Énergie) via le relay NOSTR local.\n"
    echo -ne "Confirmer l'extinction ? [o/N] "
    read -r confirm
    if [[ "$confirm" =~ ^[oOyY]$ ]]; then
        if [[ -f "$INSTALL_DIR/backend/system/fleet_commander.sh" ]]; then
            echo -e "\nEnvoi de l'ordre shutdown..."
            sudo bash "$INSTALL_DIR/backend/system/fleet_commander.sh" shutdown
            echo -e "${GREEN}Ordre envoyé.${NC} Les nœuds s'éteignent dans les prochaines secondes."
        else
            echo -e "${RED}fleet_commander.sh introuvable — Picoport requis.${NC}"
        fi
    else
        echo "Annulé."
    fi
    echo -e "\n${YELLOW}Entrée pour retourner...${NC}"; read -r
}

# --- CONNEXION INTERACTIVE ---
action_connect() {
    local svc=$1
    tput cnorm; clear
    echo -e "${CYAN}=== Connexion : $svc ===${NC}\n"
    case "$svc" in
        "icecast2")
            echo "État Icecast2 (http://127.0.0.1:8111/) :"
            curl -s "http://127.0.0.1:8111/status-json.xsl" \
                | python3 -m json.tool 2>/dev/null \
                || curl -s "http://127.0.0.1:8111/status-json.xsl" \
                || echo "Icecast injoignable." ;;
        "snapserver")
            echo "Clients Snapcast connectés (live, Ctrl+C pour quitter) :"
            watch -n 2 "curl -s http://127.0.0.1:1780/jsonrpc \
                -d '{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"Server.GetStatus\"}' \
                | python3 -m json.tool 2>/dev/null | grep -A4 '\"connected\"'" ;;
        "soundspot-client")
            echo "Sinks audio PipeWire :"
            $CMD_USER wpctl status 2>/dev/null || pactl list sinks short 2>/dev/null ;;
        "soundspot-bt-reactive")
            echo "Lancement bluetoothctl (tapez 'exit' pour quitter)..."
            bluetoothctl ;;
        "soundspot-mesh")
            echo "Topologie BATMAN (live, Ctrl+C pour quitter) :"
            watch -n 1 "printf 'VOISINS:\n'; batctl n 2>/dev/null; printf '\nROUTAGE:\n'; batctl o 2>/dev/null" ;;
        "picoport")
            echo "Pairs IPFS Swarm (live, Ctrl+C pour quitter) :"
            watch -n 2 "$CMD_USER ipfs swarm peers 2>/dev/null | wc -l | xargs printf '%s peers connectés\n'" ;;
        "soundspot-fleet-relay")
            echo "Écoute trafic NOSTR relay local (ws://127.0.0.1:9999) — Ctrl+C pour stopper :"
            $CMD_USER python3 - <<'PYEOF' 2>/dev/null || echo "websockets non disponible — pip3 install websockets"
import asyncio, websockets
async def listen():
    async with websockets.connect("ws://127.0.0.1:9999") as ws:
        await ws.send('["REQ","cc_monitor",{"kinds":[9]}]')
        async for msg in ws:
            print(msg)
asyncio.run(listen())
PYEOF
            ;;
        "soundspot-fleet")
            echo "Journal fleet_listener (live) :"
            sudo journalctl -u soundspot-fleet -f -n 30 ;;
        "soundspot-jukebox")
            echo "File d'attente Jukebox :"
            ls -lt "${USER_HOME}/.zen/tmp/jukebox/" 2>/dev/null \
                | head -20 \
                || echo "Aucun fichier en queue (ou dossier absent)." ;;
        "lighttpd")
            echo "Baux DHCP (visiteurs connectés) :"
            cat /var/lib/misc/dnsmasq.leases 2>/dev/null || echo "Aucun bail."
            echo -e "\nIPs autorisées (ipset soundspot_auth) :"
            ipset list soundspot_auth 2>/dev/null | tail -20 || echo "ipset inactif." ;;
        "soundspot-ap")
            echo "Interface uap0 :"
            iw dev uap0 info 2>/dev/null
            echo -e "\nStations connectées :"
            iw dev uap0 station dump 2>/dev/null || echo "Aucune station." ;;
        "mon-oeil")
            echo "Caméras disponibles :"
            libcamera-hello --list-cameras 2>/dev/null \
                || v4l2-ctl --list-devices 2>/dev/null \
                || ls -l /dev/video* 2>/dev/null \
                || echo "Aucune caméra détectée."
            echo -e "\nDernier log mon-oeil :"
            sudo journalctl -u mon-oeil -n 10 --no-pager 2>/dev/null ;;
        "soundspot-state")
            echo "Dernier état publié :"
            sudo journalctl -u soundspot-state -n 20 --no-pager 2>/dev/null ;;
        *)
            echo "Pas d'interface interactive spécifique pour $svc."
            echo "Utilisez [L] pour voir le journal systemd." ;;
    esac
    echo -e "\n${YELLOW}Entrée pour retourner...${NC}"; read -r
}

# --- TESTS UNITAIRES ---
action_test() {
    local svc=$1
    tput cnorm; clear
    echo -e "${CYAN}=== Test : $svc ===${NC}\n"
    case "$svc" in
        "icecast2")
            echo "Test HTTP Icecast2 :"
            curl -I "http://127.0.0.1:8111/" 2>&1 | head -5
            echo -e "\nMounts actifs :"
            curl -s "http://127.0.0.1:8111/status-json.xsl" \
                | python3 -c "import sys,json; d=json.load(sys.stdin); mounts=d.get('icestats',{}).get('source',[]); [print('  '+m.get('listenurl','?')) for m in (mounts if isinstance(mounts,list) else [mounts])]" \
                2>/dev/null || echo "  (aucun mount ou Icecast arrêté)" ;;
        "soundspot-decoder")
            echo "Vérification FIFO ${SNAP_FIFO} :"
            if [[ -p "$SNAP_FIFO" ]]; then
                echo -e "  ${GREEN}✓${NC} FIFO présent"
                bytes=$(timeout 2 cat "$SNAP_FIFO" 2>/dev/null | wc -c)
                echo "  ${bytes} octets de PCM reçus en 2 secondes"
                [[ "$bytes" -gt 0 ]] && echo -e "  ${GREEN}✓${NC} Flux actif" || echo -e "  ${YELLOW}⚠${NC} Flux nul (Mixxx en pause ?)"
            else
                echo -e "  ${RED}✗${NC} FIFO absent — soundspot-decoder inactif ou Icecast sans flux"
            fi ;;
        "snapserver")
            echo "Test TCP port 1704 :"
            (echo > /dev/tcp/127.0.0.1/1704) >/dev/null 2>&1 \
                && echo -e "  ${GREEN}✓${NC} Port 1704 ouvert" \
                || echo -e "  ${RED}✗${NC} Port 1704 fermé"
            echo -e "\nTest API JSON-RPC :"
            curl -s "http://127.0.0.1:1780/jsonrpc" \
                -d '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' \
                | python3 -c "import sys,json; d=json.load(sys.stdin); g=d.get('result',{}).get('server',{}).get('groups',[]); print(f'  {sum(len(g2.get(\"clients\",[])) for g2 in g)} client(s) connecté(s)')" \
                2>/dev/null || echo "  API Snapserver injoignable" ;;
        "soundspot-client")
            echo "Injection son test PipeWire :"
            $CMD_USER pw-play /usr/share/sounds/alsa/Front_Center.wav 2>/dev/null \
                && echo -e "  ${GREEN}✓${NC} Son lu" \
                || $CMD_USER pw-play /usr/share/sounds/alsa/Noise.wav 2>/dev/null \
                || echo -e "  ${RED}✗${NC} Échec pw-play (PipeWire inactif ou aucun sink)" ;;
        "soundspot-autodj")
            echo "Démarrage forcé AutoDJ + vérification Icecast :"
            sudo systemctl start soundspot-autodj
            sleep 2
            curl -s "http://127.0.0.1:8111/status-json.xsl" | grep -q '"source"' \
                && echo -e "  ${GREEN}✓${NC} AutoDJ en diffusion sur Icecast" \
                || echo -e "  ${YELLOW}⚠${NC} Aucun flux Icecast (~/Music vide ?)" ;;
        "soundspot-mic")
            echo "Vérification FIFO micro ${SNAP_FIFO_MIC} :"
            if [[ -p "$SNAP_FIFO_MIC" ]]; then
                bytes=$(timeout 2 cat "$SNAP_FIFO_MIC" 2>/dev/null | wc -c)
                echo "  ${bytes} octets de PCM reçus en 2s"
                [[ "$bytes" -gt 0 ]] && echo -e "  ${GREEN}✓${NC} Micro actif" || echo -e "  ${YELLOW}⚠${NC} Micro silencieux"
            else
                echo -e "  ${DIM}·${NC} FIFO micro absent (service inactif)"
            fi ;;
        "soundspot-idle")
            echo "Test TTS clocher :"
            if [[ -f "$INSTALL_DIR/backend/audio/tts.sh" ]]; then
                $CMD_USER bash "$INSTALL_DIR/backend/audio/tts.sh" \
                    "Test du clocher depuis la console." pierre /tmp/cc_test_tts.wav
                $CMD_USER pw-play /tmp/cc_test_tts.wav 2>/dev/null \
                    && echo -e "  ${GREEN}✓${NC} TTS lu" \
                    || echo -e "  ${RED}✗${NC} pw-play échoué"
            else
                $CMD_USER espeak-ng -v fr "Test du clocher depuis la console." 2>/dev/null \
                    && echo -e "  ${GREEN}✓${NC} espeak-ng OK" \
                    || echo -e "  ${RED}✗${NC} espeak-ng absent"
            fi ;;
        "soundspot-battery")
            echo "Interrogation capteur INA219 (I2C) :"
            if [[ -x "$ASTRO_PYTHON" ]]; then
                $CMD_USER "$ASTRO_PYTHON" -c "
from ina219 import INA219
i = INA219(0.1)
i.configure()
print(f'  Tension : {i.voltage():.2f} V')
print(f'  Courant : {i.current():.2f} mA')
print(f'  Puissance: {i.power():.2f} mW')
" 2>/dev/null || echo "  Capteur absent ou non câblé."
            else
                echo "  venv ~/.astro/ absent (Picoport non installé)."
            fi ;;
        "soundspot-presence")
            echo "Caméras disponibles :"
            libcamera-hello --list-cameras 2>/dev/null \
                || v4l2-ctl --list-devices 2>/dev/null \
                || ls -l /dev/video* 2>/dev/null \
                || echo "  Aucune caméra détectée."
            echo -e "\nDernière détection :"
            sudo journalctl -u soundspot-presence -n 5 --no-pager 2>/dev/null ;;
        "soundspot-rtmp-player")
            echo "Vérification process ffmpeg RTMP :"
            pgrep -a ffmpeg 2>/dev/null | grep -i rtmp \
                && echo -e "  ${GREEN}✓${NC} ffmpeg RTMP actif" \
                || echo "  Aucun process ffmpeg RTMP." ;;
        "lighttpd")
            echo "Test HTTP portail captif :"
            curl -sI "http://127.0.0.1/" 2>&1 | head -3
            echo -e "\nVisiteurs autorisés (ipset) :"
            ipset list soundspot_auth 2>/dev/null | grep -c "^[0-9]" \
                | xargs printf '  %s IP(s) dans la liste blanche\n' 2>/dev/null || true ;;
        "soundspot-ap")
            echo "État AP uap0 :"
            iw dev uap0 info 2>/dev/null \
                && iw dev uap0 station dump 2>/dev/null \
                || echo "  uap0 inactif." ;;
        "soundspot-channel-sync")
            echo "Canal WiFi actuel :"
            iw dev wlan0 info 2>/dev/null | grep channel
            sudo journalctl -u soundspot-channel-sync -n 5 --no-pager 2>/dev/null ;;
        "soundspot-mesh")
            echo "Topologie BATMAN actuelle :"
            batctl n 2>/dev/null || echo "  batman-adv inactif." ;;
        "picoport")
            echo "Identité IPFS :"
            $CMD_USER ipfs id -f "<id>\n" 2>/dev/null || echo "  IPFS injoignable."
            echo -e "\nPairs connectés :"
            $CMD_USER ipfs swarm peers 2>/dev/null | wc -l | xargs printf '  %s pairs\n' ;;
        "soundspot-fleet-relay")
            echo "Test WebSocket relay NOSTR local (ws://127.0.0.1:9999) :"
            if command -v python3 &>/dev/null; then
                timeout 3 python3 -c "
import socket, sys
s = socket.socket()
s.settimeout(2)
try:
    s.connect(('127.0.0.1', 9999))
    print('  Port 9999 ouvert')
    s.close()
except Exception as e:
    print(f'  Port 9999 fermé : {e}')
" 2>/dev/null
            else
                (echo > /dev/tcp/127.0.0.1/9999) >/dev/null 2>&1 \
                    && echo -e "  ${GREEN}✓${NC} Port 9999 ouvert" \
                    || echo -e "  ${RED}✗${NC} Port 9999 fermé"
            fi ;;
        "soundspot-fleet")
            echo "Injection ordre 'announce' sur la flotte :"
            if [[ -f "$INSTALL_DIR/backend/system/fleet_commander.sh" ]]; then
                sudo bash "$INSTALL_DIR/backend/system/fleet_commander.sh" announce \
                    "Test réseau depuis le Control Center"
                echo -e "  ${GREEN}✓${NC} Ordre envoyé"
            else
                echo "  fleet_commander.sh absent (Picoport requis)."
            fi ;;
        "soundspot-jukebox")
            echo "File d'attente Jukebox :"
            local queue_dir="${USER_HOME}/.zen/tmp/jukebox"
            if [[ -d "$queue_dir" ]]; then
                local count
                count=$(ls "$queue_dir" 2>/dev/null | wc -l)
                echo "  ${count} fichier(s) en queue"
                ls -lt "$queue_dir" 2>/dev/null | head -10
            else
                echo "  Dossier queue absent (${queue_dir})"
            fi ;;
        "soundspot-state")
            echo "Journal state_daemon (20 dernières lignes) :"
            sudo journalctl -u soundspot-state -n 20 --no-pager 2>/dev/null ;;
        "mon-oeil")
            echo "Ping Ollama swarm (http://127.0.0.1:11434/) :"
            curl -s --max-time 2 "http://127.0.0.1:11434/" \
                && echo -e "\n  ${GREEN}✓${NC} Ollama local actif" \
                || echo "  Ollama local inactif (mode swarm distant)."
            echo -e "\nDernier log mon-oeil :"
            sudo journalctl -u mon-oeil -n 5 --no-pager 2>/dev/null ;;
        *)
            echo "Aucun test scripté pour $svc."
            echo "Utilisez [C] pour un diagnostic complet via check.sh." ;;
    esac
    echo -e "\n${YELLOW}Entrée pour retourner...${NC}"; read -r
}

# --- BOUCLE PRINCIPALE ---
while $running; do
    if [[ "$busy" == "false" ]]; then
        draw_ui
    fi

    read -rsn1 -t "$REFRESH_RATE" key

    case "$key" in
        $'\x1b')  # Séquences flèches
            read -rsn2 -t 0.1 seq
            case "$seq" in
                "[A") ((cursor--)) ;;
                "[B") ((cursor++)) ;;
            esac
            ;;
        $'\x0a'|$'\x0d')  # Entrée — Toggle Start/Stop
            IFS='|' read -r svc _ _ <<< "${SERVICES[$cursor]}"
            if systemctl is-active --quiet "$svc" 2>/dev/null; then
                last_msg="Arrêt de $svc..."
                draw_ui
                sudo systemctl stop "$svc"
                last_msg="$svc arrêté."
            else
                last_msg="Démarrage de $svc..."
                draw_ui
                sudo systemctl start "$svc"
                last_msg="$svc démarré."
            fi
            ;;
        "r"|"R")  # Redémarrer
            IFS='|' read -r svc _ _ <<< "${SERVICES[$cursor]}"
            last_msg="Redémarrage de $svc..."
            draw_ui
            sudo systemctl restart "$svc"
            last_msg="$svc redémarré."
            ;;
        "l"|"L")  # Log live du service
            busy=true
            IFS='|' read -r svc _ _ <<< "${SERVICES[$cursor]}"
            tput cnorm; clear
            echo -e "${CYAN}=== Journal : $svc  (q ou Ctrl+C pour quitter) ===${NC}\n"
            sudo journalctl -u "$svc" -f -n 50
            busy=false
            last_msg="Retour depuis les logs de $svc."
            ;;
        "o"|"O")  # Ouvrir / Connecter
            busy=true
            IFS='|' read -r svc _ _ <<< "${SERVICES[$cursor]}"
            action_connect "$svc"
            busy=false
            last_msg="Retour depuis la connexion à $svc."
            ;;
        "t"|"T")  # Test unitaire
            busy=true
            IFS='|' read -r svc _ _ <<< "${SERVICES[$cursor]}"
            action_test "$svc"
            busy=false
            last_msg="Test $svc terminé."
            ;;
        "c"|"C")  # check.sh global
            busy=true
            tput cnorm; clear
            if [[ -f "$INSTALL_DIR/check.sh" ]]; then
                sudo bash "$INSTALL_DIR/check.sh"
            else
                echo -e "${RED}check.sh introuvable dans $INSTALL_DIR${NC}"
            fi
            echo -e "\n${YELLOW}Entrée pour retourner...${NC}"; read -r
            busy=false
            last_msg="Diagnostic check.sh terminé."
            ;;
        "g"|"G")  # Log global
            busy=true
            tput cnorm; clear
            echo -e "${CYAN}=== Log global /var/log/sound-spot.log  (Ctrl+C pour quitter) ===${NC}\n"
            tail -f /var/log/sound-spot.log
            busy=false
            last_msg="Retour depuis le log global."
            ;;
        "i"|"I")  # Infos système
            busy=true
            action_sysinfo
            busy=false
            last_msg="Infos système affichées."
            ;;
        "s"|"S")  # Shutdown flotte
            busy=true
            action_fleet_shutdown
            busy=false
            last_msg="Action fleet shutdown terminée."
            ;;
        "f"|"F")  # Forcer le rafraîchissement
            last_msg="Rafraîchissement forcé."
            ;;
        "q"|"Q")  # Quitter
            running=false
            ;;
    esac

    # Bouclage du curseur
    [[ $cursor -lt 0 ]] && cursor=$(( ${#SERVICES[@]} - 1 ))
    [[ $cursor -ge ${#SERVICES[@]} ]] && cursor=0
done
