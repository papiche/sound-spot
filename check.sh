#!/bin/bash
# check.sh — Diagnostic SoundSpot (maître)
# Usage :
#   sudo bash check.sh            # diagnostic rapide
#   sudo bash check.sh --debug    # diagnostic + logs détaillés + restart
#   sudo bash check.sh --restart  # restart propre puis diagnostic

# ── Args ────────────────────────────────────────────────────────
DEBUG=0; DO_RESTART=0
for _arg in "$@"; do
    case "$_arg" in
        --debug|-d)   DEBUG=1 ;;
        --restart|-r) DO_RESTART=1 ;;
    esac
done

[ "$(id -u)" -eq 0 ] || exec sudo bash "${BASH_SOURCE[0]}" "$@"

# ── Couleurs ────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; D='\033[2m'; N='\033[0m'

ERRORS=0; WARNINGS=0

ok()   { echo -e "  ${G}✓${N}  $*"; }
fail() { echo -e "  ${R}✗${N}  $*"; ERRORS=$((ERRORS+1)); }
warn() { echo -e "  ${Y}⚠${N}  $*"; WARNINGS=$((WARNINGS+1)); }
info() { echo -e "  ${D}·${N}  $*"; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }
dbg()  { [ "$DEBUG" -eq 1 ] && echo -e "${D}$*${N}"; }

# ── Config ──────────────────────────────────────────────────────
CONF=/opt/soundspot/soundspot.conf
[ -f "$CONF" ] && source "$CONF"
SPOT_IP="${SPOT_IP:-192.168.10.1}"
SPOT_NAME="${SPOT_NAME:-ZICMAMA}"
SNAPCAST_PORT="${SNAPCAST_PORT:-1704}"
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
BT_MACS="${BT_MACS:-${BT_MAC:-}}"
USER_ID=$(id -u "$SOUNDSPOT_USER" 2>/dev/null || echo 1000)
ASUSER="sudo -u $SOUNDSPOT_USER XDG_RUNTIME_DIR=/run/user/${USER_ID}"

# ── Restart ordonné ─────────────────────────────────────────────
restart_soundspot() {
    echo -e "\n${W}╔══════════════════════════════════════════════════╗${N}"
    echo -e "${W}║  Redémarrage SoundSpot dans l'ordre...           ║${N}"
    echo -e "${W}╚══════════════════════════════════════════════════╝${N}"

    # 1. PipeWire / WirePlumber (services utilisateur)
    hdr "Redémarrage PipeWire / WirePlumber"
    $ASUSER systemctl --user stop wireplumber pipewire-pulse pipewire 2>/dev/null || true
    sleep 2
    $ASUSER systemctl --user start pipewire 2>/dev/null && info "pipewire démarré"
    sleep 3
    $ASUSER systemctl --user start wireplumber 2>/dev/null && info "wireplumber démarré"
    info "Attente enregistrement A2DP (10s)..."
    sleep 10
    $ASUSER systemctl --user start pipewire-pulse 2>/dev/null && info "pipewire-pulse démarré"
    sleep 2

    # 2. Connexion Bluetooth
    hdr "Reconnexion Bluetooth"
    systemctl restart bt-autoconnect 2>/dev/null \
        && info "bt-autoconnect relancé" || info "bt-autoconnect inactif"
    info "Attente connexion BT (10s)..."
    sleep 10

    # 3. Snapclient
    hdr "Redémarrage soundspot-client"
    systemctl restart soundspot-client 2>/dev/null \
        && info "soundspot-client relancé" || info "soundspot-client inactif"
    sleep 5

    echo -e "${G}▶${N} Redémarrage terminé — lancement des vérifications\n"
}

[ "$DO_RESTART" -eq 1 ] || [ "$DEBUG" -eq 1 ] && restart_soundspot

# ── Helpers ─────────────────────────────────────────────────────
svc_active()  { systemctl is-active  --quiet "$1" 2>/dev/null; }
svc_masked()  { systemctl is-enabled         "$1" 2>/dev/null | grep -q masked; }
port_open()   { ss -tlnp 2>/dev/null | awk '{print $4}' | grep -qE ":${1}$"; }

check_svc() {
    # check_svc NAME LABEL [masked]
    local svc="$1" label="$2" expect="${3:-active}"
    if [ "$expect" = "masked" ]; then
        if svc_masked "$svc"; then
            ok "$label masqué ${D}(intentionnel)${N}"
        elif svc_active "$svc"; then
            fail "$label tourne alors qu'il devrait être masqué"
        else
            warn "$label non masqué — lancer : systemctl mask $svc"
        fi
    else
        if svc_active "$svc"; then
            ok "$label"
        elif svc_masked "$svc"; then
            info "$label masqué"
        else
            local st; st=$(systemctl is-active "$svc" 2>/dev/null)
            fail "$label — état : $st"
        fi
    fi
}

# ════════════════════════════════════════════════════════════════
echo -e "\n${W}╔══════════════════════════════════════════════════╗${N}"
printf    "${W}║  SoundSpot Diagnostic  %-26s║${N}\n" "$(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${W}╚══════════════════════════════════════════════════╝${N}"
info "Spot : ${W}${SPOT_NAME}${N}  IP AP : ${W}${SPOT_IP}${N}  User : ${W}${SOUNDSPOT_USER}${N}"

# ── 1. Services systemd ─────────────────────────────────────────
hdr "Services systemd"
check_svc uap0                  "Interface uap0"
check_svc hostapd               "hostapd (WiFi AP)"
check_svc dnsmasq               "dnsmasq (DHCP/DNS)"
check_svc ipset-soundspot       "ipset-soundspot"
check_svc lighttpd              "lighttpd (portail captif)"
check_svc icecast2              "icecast2"
check_svc snapserver            "snapserver"
check_svc soundspot-decoder     "soundspot-decoder (ffmpeg)"
check_svc soundspot-client      "soundspot-client (snapclient)"
check_svc soundspot-presence    "soundspot-presence (caméra)"
check_svc soundspot-channel-sync "soundspot-channel-sync (canal WiFi)"
check_svc bt-autoconnect        "bt-autoconnect"
check_svc bluealsa              "bluealsa"   masked
check_svc bluealsa-aplay        "bluealsa-aplay" masked
check_svc opennds               "opennds"    masked

# ── 2. Réseau ───────────────────────────────────────────────────
hdr "Réseau"

# wlan0 - réseau amont
if ip addr show wlan0 2>/dev/null | grep -q "inet "; then
    WLAN_IP=$(ip -4 addr show wlan0 | awk '/inet/{print $2}' | head -1)
    SSID=$(iwgetid -r 2>/dev/null || echo "?")
    CHAN_WLAN=$(iw dev wlan0 info 2>/dev/null | awk '/channel/{print $2}')
    ok "wlan0 connecté  ${D}IP:${N} $WLAN_IP  ${D}SSID:${N} $SSID  ${D}canal:${N} ${CHAN_WLAN:-?}"
else
    fail "wlan0 sans adresse IP — pas de réseau amont"
fi

# uap0 - AP visiteurs
if ip -4 addr show uap0 2>/dev/null | grep -q "inet ${SPOT_IP}"; then
    AP_MAC=$(cat /sys/class/net/uap0/address 2>/dev/null || echo "?")
    CHAN_UAP=$(iw dev uap0 info 2>/dev/null | awk '/channel/{print $2}')
    CHAN_HOSTAPD=$(grep -E "^channel=" /etc/hostapd/hostapd.conf 2>/dev/null | cut -d= -f2)
    ok "uap0 up  ${D}IP:${N} ${SPOT_IP}  ${D}MAC:${N} ${AP_MAC}  ${D}canal radio:${N} ${CHAN_UAP:-?}  ${D}hostapd.conf:${N} ${CHAN_HOSTAPD:-?}"
    if [ -n "$CHAN_WLAN" ] && [ -n "$CHAN_UAP" ] && [ "$CHAN_WLAN" != "$CHAN_UAP" ]; then
        warn "Canal wlan0 (${CHAN_WLAN}) ≠ uap0 (${CHAN_UAP}) — possible instabilité AP"
    fi
else
    fail "uap0 absent ou IP ${SPOT_IP} non assignée"
fi

# Clients WiFi associés à uap0
STATIONS=$(iw dev uap0 station dump 2>/dev/null | grep -c "^Station")
if [ "$STATIONS" -gt 0 ]; then
    ok "${STATIONS} client(s) WiFi associé(s) à uap0"
    iw dev uap0 station dump 2>/dev/null | awk '/^Station/{print "    MAC: "$2}'
else
    info "Aucun client WiFi connecté à uap0 actuellement"
fi

# ip_forward
if [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" = "1" ]; then
    ok "ip_forward = 1"
else
    fail "ip_forward = 0 — routage désactivé (internet impossible pour les visiteurs)"
fi

# Internet amont
if ping -c1 -W2 -I wlan0 8.8.8.8 &>/dev/null; then
    ok "Internet amont joignable via wlan0"
else
    fail "Pas d'Internet via wlan0 (8.8.8.8 injoignable)"
fi

# ── 3. Pare-feu ─────────────────────────────────────────────────
hdr "Pare-feu  iptables / ipset"

# NAT
if iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q MASQUERADE; then
    ok "NAT MASQUERADE actif"
else
    fail "MASQUERADE absent — pas d'Internet pour les visiteurs"
fi

# Redirection port 80
if iptables -t nat -L PREROUTING -n 2>/dev/null | grep -qE "REDIRECT.*dpt:80"; then
    ok "PREROUTING port 80 → portail (lighttpd)"
else
    fail "PREROUTING port 80 absent — portail captif inactif"
fi

# FORWARD soundspot_auth
if iptables -L FORWARD -n 2>/dev/null | grep -q soundspot_auth; then
    ok "FORWARD soundspot_auth présent"
else
    fail "FORWARD soundspot_auth absent — internet bloqué pour tous les visiteurs"
fi

# REJECT final
if iptables -L FORWARD -n 2>/dev/null | grep -q "REJECT"; then
    ok "REJECT final présent (visiteurs non-auth bloqués)"
else
    warn "Pas de REJECT final — tout le trafic passe sans validation"
fi

# ipset
if ipset list soundspot_auth &>/dev/null; then
    COUNT=$(ipset list soundspot_auth 2>/dev/null | awk '/^[0-9]/{c++} END{print c+0}')
    ok "ipset soundspot_auth — ${COUNT} IP(s) actuellement autorisée(s)"
    if [ "$COUNT" -gt 0 ]; then
        ipset list soundspot_auth | grep -E "^[0-9]" | \
            while read -r entry; do info "  $entry"; done
    fi
else
    fail "ipset soundspot_auth introuvable"
fi

# dhcp_trigger.sh
if [ -x "/opt/soundspot/dhcp_trigger.sh" ]; then
    ok "dhcp_trigger.sh présent et exécutable"
else
    fail "dhcp_trigger.sh absent — les nouveaux clients ne seront pas autorisés"
fi

# ── 4. Pipeline audio ───────────────────────────────────────────
hdr "Pipeline audio"

# FIFO snapcast
if [ -p /tmp/snapfifo ]; then
    ok "FIFO /tmp/snapfifo présente"
else
    fail "FIFO /tmp/snapfifo absente — snapserver sans source PCM"
fi

# Ports
ICECAST_PORT_REAL=$(grep -oP '(?<=<port>)\d+(?=</port>)' /etc/icecast2/icecast.xml 2>/dev/null | head -1)
if port_open 8111; then
    ok "icecast2 port 8111 ouvert"
elif [ -n "$ICECAST_PORT_REAL" ] && [ "$ICECAST_PORT_REAL" != "8111" ]; then
    fail "icecast2 écoute sur port ${ICECAST_PORT_REAL} (pas 8111) — corriger : sudo sed -i 's|<port>${ICECAST_PORT_REAL}</port>|<port>8111</port>|' /etc/icecast2/icecast.xml && sudo systemctl restart icecast2"
else
    fail "icecast2 port 8111 fermé"
fi
port_open "$SNAPCAST_PORT" && ok "snapserver port $SNAPCAST_PORT ouvert" || fail "snapserver port $SNAPCAST_PORT fermé"
port_open 1780             && ok "snapserver WebUI port 1780 ouvert" || warn "WebUI port 1780 fermé"

# snapclient process
if pgrep -x snapclient &>/dev/null; then
    ok "snapclient en cours d'exécution"
else
    fail "snapclient absent des processus"
fi

# ffmpeg decoder
if pgrep -f "ffmpeg" &>/dev/null; then
    ok "ffmpeg (decoder) actif"
else
    warn "ffmpeg inactif ${D}(normal si aucun DJ connecté)${N}"
fi

# Flux Icecast
HTTP_ICECAST=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 3 "http://127.0.0.1:8111/live" 2>/dev/null; true)
case "$HTTP_ICECAST" in
    200) ok "Flux Icecast /live actif (DJ connecté)" ;;
    404) warn "Flux Icecast /live absent ${D}(DJ non connecté — normal)${N}" ;;
    *)   warn "Icecast /live : HTTP ${HTTP_ICECAST}" ;;
esac

# welcome.wav
[ -f "/opt/soundspot/welcome.wav" ] \
    && ok "welcome.wav présent" \
    || warn "welcome.wav absent — message d'accueil silencieux"

# ── 5. Bluetooth ────────────────────────────────────────────────
hdr "Bluetooth"

# BlueALSA — doit être masqué
check_svc bluealsa     "bluealsa"      masked
check_svc bluealsa-aplay "bluealsa-aplay" masked

# Enceintes configurées
if [ -n "$BT_MACS" ]; then
    for mac in $BT_MACS; do
        if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
            ok "Enceinte BT connectée : ${W}${mac}${N}"
        elif bluetoothctl info "$mac" 2>/dev/null | grep -q "Paired: yes"; then
            warn "Enceinte BT appairée mais non connectée : $mac"
        else
            fail "Enceinte BT inconnue / non appairée : $mac"
        fi
    done
else
    warn "BT_MACS non défini dans soundspot.conf"
fi

# Sockets PipeWire (indispensables pour le handler A2DP et snapclient)
if [ -S "/run/user/${USER_ID}/pipewire-0" ]; then
    ok "Socket PipeWire présent"
else
    fail "Socket PipeWire absent — WirePlumber non démarré (handler A2DP non enregistré → Protocol not available)"
fi
if [ -S "/run/user/${USER_ID}/pulse/native" ]; then
    ok "Socket PipeWire-Pulse présent"
else
    warn "Socket PipeWire-Pulse absent — snapclient --player pulse ne peut pas démarrer"
fi

# Sink PipeWire BT
if $ASUSER wpctl status 2>/dev/null | grep -qi "blue"; then
    BT_SINK=$($ASUSER wpctl status 2>/dev/null | grep -i blue | head -1 | sed 's/^[[:space:]]*//')
    ok "Sink Bluetooth dans PipeWire : ${D}${BT_SINK}${N}"
else
    warn "Sink Bluetooth non visible ${D}(enceinte hors ligne ou handler A2DP non encore enregistré)${N}"
    info "Diagnostic → sudo journalctl -u bt-autoconnect -n 30 --no-pager"
fi

# ── 6. Portail captif ───────────────────────────────────────────
hdr "Portail captif"

port_open 80 && ok "lighttpd écoute sur port 80" || fail "lighttpd ne répond pas sur port 80"

# Réponse HTML
HTTP_PORTAL=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 3 "http://${SPOT_IP}/" 2>/dev/null; true)
[ "${HTTP_PORTAL:-000}" != "000" ] \
    && ok "Portail répond : HTTP ${HTTP_PORTAL} sur http://${SPOT_IP}/" \
    || fail "Portail injoignable sur http://${SPOT_IP}/"

# auth.sh
AUTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 3 -X POST "http://${SPOT_IP}/auth.sh" 2>/dev/null; true)
[ "${AUTH_CODE:-000}" != "000" ] \
    && ok "auth.sh répond : HTTP ${AUTH_CODE}" \
    || fail "auth.sh injoignable"

# Probes Android/Apple
for probe in generate_204 hotspot-detect.html ncsi.txt; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 3 "http://${SPOT_IP}/${probe}" 2>/dev/null; true)
    [ "${CODE:-000}" != "000" ] \
        && ok "Probe /${probe} → HTTP ${CODE}" \
        || warn "Probe /${probe} ne répond pas"
done

# ── 7. Détecteur de présence ────────────────────────────────────
hdr "Détecteur de présence"

if pgrep -f "presence_detector.py" &>/dev/null; then
    ok "presence_detector.py actif"
else
    warn "presence_detector.py inactif ${D}(normal si pas de caméra)${N}"
fi

if command -v vcgencmd &>/dev/null; then
    if vcgencmd get_camera 2>/dev/null | grep -q "detected=1"; then
        ok "Caméra Pi détectée (vcgencmd)"
    else
        warn "Caméra Pi non détectée"
    fi
else
    # Bookworm : libcamera remplace vcgencmd
    if ls /dev/video* &>/dev/null 2>&1; then
        ok "Périphérique(s) vidéo : $(ls /dev/video* | tr '\n' ' ')"
    else
        info "Aucun périphérique vidéo détecté"
    fi
fi

# ── 8. Clients Snapcast connectés ───────────────────────────────
hdr "Clients Snapcast"

if port_open "$SNAPCAST_PORT"; then
    # Interroge l'API JSON de snapserver
    SNAP_JSON=$(curl -s --max-time 3 \
        "http://127.0.0.1:1780/jsonrpc" \
        -d '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' 2>/dev/null)
    if [ -n "$SNAP_JSON" ]; then
        CLIENTS=$(echo "$SNAP_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    clients = d['result']['server']['groups'][0]['clients']
    for c in clients:
        name = c['host']['name']
        ip   = c['host']['ip']
        conn = 'connecté' if c['connected'] else 'déconnecté'
        vol  = c['config']['volume']['percent']
        print(f'  {name} ({ip}) — {conn} — volume {vol}%')
except:
    print('  (impossible de parser la réponse JSON)')
" 2>/dev/null)
        if [ -n "$CLIENTS" ]; then
            ok "Clients Snapcast :"
            echo "$CLIENTS"
        else
            info "Aucun client Snapcast enregistré"
        fi
    else
        warn "API Snapserver non joignable sur port 1780"
    fi
fi

# ── 9. Erreurs récentes ─────────────────────────────────────────
hdr "Journaux (erreurs < 60s)"
RECENT=$(journalctl --since "60 seconds ago" -p err..emerg \
    --no-pager -q 2>/dev/null | grep -v "^$" | head -15)
if [ -n "$RECENT" ]; then
    warn "Erreurs récentes dans journald :"
    echo "$RECENT" | sed "s/^/    ${R}/; s/$/${N}/"
else
    ok "Aucune erreur récente dans journald"
fi

# ── Résumé ──────────────────────────────────────────────────────
echo -e "\n${W}╔══════════════════════════════════════════════════╗${N}"
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo -e "${W}║${N}  ${G}✓  Tout OK — SoundSpot opérationnel${N}            ${W}║${N}"
elif [ "$ERRORS" -eq 0 ]; then
    printf "${W}║${N}  ${Y}⚠  %d avertissement(s) — fonctionnel avec réserves${N}" "$WARNINGS"
    echo -e "  ${W}║${N}"
else
    printf "${W}║${N}  ${R}✗  %d erreur(s)  %d avertissement(s) — action requise${N}" "$ERRORS" "$WARNINGS"
    echo -e " ${W}║${N}"
fi
echo -e "${W}╚══════════════════════════════════════════════════╝${N}"

# Code de sortie utile pour les scripts appelants
EXIT_CODE=0; [ "$ERRORS" -eq 0 ] || EXIT_CODE=1

# ── Mode debug : logs détaillés ──────────────────────────────────
if [ "$DEBUG" -eq 1 ]; then
    echo -e "\n${W}╔══════════════════════════════════════════════════╗${N}"
    echo -e "${W}║  LOGS DÉTAILLÉS (--debug)                        ║${N}"
    echo -e "${W}╚══════════════════════════════════════════════════╝${N}"

    hdr "WirePlumber — wpctl status"
    $ASUSER wpctl status 2>/dev/null || echo "(erreur wpctl — WirePlumber non joignable)"

    hdr "WirePlumber — journal (50 lignes)"
    $ASUSER journalctl --user -u wireplumber -n 50 --no-pager 2>/dev/null \
        || journalctl -u wireplumber -n 50 --no-pager 2>/dev/null \
        || echo "(journal WirePlumber inaccessible)"

    hdr "PipeWire — sinks"
    $ASUSER pactl list sinks 2>/dev/null \
        | grep -E "^(Sink #|	Name:|	State:|	Volume:|	Description:)" \
        || echo "(pactl inaccessible ou aucun sink)"

    hdr "Bluetooth — adaptateur"
    bluetoothctl show 2>/dev/null || echo "(bluetoothctl indisponible)"

    if [ -n "$BT_MACS" ]; then
        for _mac in $BT_MACS; do
            hdr "Bluetooth — info $_mac"
            bluetoothctl info "$_mac" 2>/dev/null || echo "(appareil inconnu)"
        done
    fi

    hdr "bt-autoconnect — journal (40 lignes)"
    journalctl -u bt-autoconnect -n 40 --no-pager 2>/dev/null || true

    hdr "soundspot-client — journal (40 lignes)"
    journalctl -u soundspot-client -n 40 --no-pager 2>/dev/null || true

    hdr "soundspot-decoder — journal (20 lignes)"
    journalctl -u soundspot-decoder -n 20 --no-pager 2>/dev/null || true

    hdr "dnsmasq — journal (20 lignes)"
    journalctl -u dnsmasq -n 20 --no-pager 2>/dev/null || true

    hdr "hostapd — journal (20 lignes)"
    journalctl -u hostapd -n 20 --no-pager 2>/dev/null || true

    hdr "Paquets PipeWire/WirePlumber/Bluetooth"
    dpkg -l 2>/dev/null | grep -E "pipewire|wireplumber|libspa|bluez|pulseaudio" \
        | awk '{printf "  %-30s %s\n", $2, $3}' || true

    hdr "Fichiers conf PipeWire"
    ls -la /etc/pipewire/ /etc/pipewire/pipewire.conf.d/ 2>/dev/null || true

    hdr "Fichiers conf WirePlumber"
    ls -la /etc/wireplumber/ /etc/wireplumber/wireplumber.conf.d/ 2>/dev/null \
        || echo "(pas de conf WirePlumber utilisateur)"

    echo -e "\n${C}━━━  Fin des logs --debug  ━━━${N}\n"
fi

exit "$EXIT_CODE"
