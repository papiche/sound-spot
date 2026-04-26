#!/bin/bash
# ================================================================
#  bt_manage.sh — Gestion Bluetooth + Volume SoundSpot
#  G1FabLab / UPlanet ẐEN — zicmama.com
#
#  Gestion quotidienne : connexion, déconnexion, volume, état.
#  Pour l'appairage initial, utiliser bt_update.sh.
#
#  Usage :
#    sudo bash bt_manage.sh                    # menu interactif
#    bash bt_manage.sh pi@soundspot.local      # SSH → RPi
#    sudo bash bt_manage.sh status             # état rapide
#    sudo bash bt_manage.sh connect            # connexion BT
#    sudo bash bt_manage.sh disconnect         # déconnexion BT
#    sudo bash bt_manage.sh volume 80          # volume 80%
#    sudo bash bt_manage.sh fix-a2dp           # réparer "Protocol not available"
# ================================================================

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; M='\033[0;35m'
DIM='\033[2m'; N='\033[0m'
log()  { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err()  { echo -e "${R}✗${N}  $*" >&2; exit 1; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }
ok()   { echo -e "  ${G}✓${N}  $*"; }
fail() { echo -e "  ${R}✗${N}  $*"; }
info() { echo -e "  ${DIM}·${N}  $*"; }

CONF="/opt/soundspot/soundspot.conf"
INSTALL_DIR="/opt/soundspot"

# ── Mode SSH distant ────────────────────────────────────────────
REMOTE_HOST="${1:-}"
if [[ "$REMOTE_HOST" =~ @ ]] && [ "$REMOTE_HOST" != "--rpi" ]; then
    REMOTE_SCRIPT="/tmp/soundspot_bt_manage_$$.sh"
    echo -e "${C}SoundSpot bt_manage → ${REMOTE_HOST}${N}"
    scp -q "${BASH_SOURCE[0]}" "${REMOTE_HOST}:${REMOTE_SCRIPT}" \
        || err "Échec du transfert. SSH configuré ?"
    ssh -t "$REMOTE_HOST" "sudo bash ${REMOTE_SCRIPT} --rpi ${2:-}; rm -f ${REMOTE_SCRIPT}"
    exit $?
fi

# ── Mode local — doit tourner en root ───────────────────────────
[ "$(id -u)" -eq 0 ] || exec sudo bash "${BASH_SOURCE[0]}" "$@"

# ── Charger la config ───────────────────────────────────────────
[ -f "$CONF" ] && source "$CONF" || warn "soundspot.conf introuvable"
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_ID=$(id -u "$SOUNDSPOT_USER" 2>/dev/null || echo 1000)
ASUSER="sudo -u $SOUNDSPOT_USER XDG_RUNTIME_DIR=/run/user/${USER_ID}"
MACS="${BT_MACS:-${BT_MAC:-}}"

# ── Helpers PipeWire ────────────────────────────────────────────
pw_get_bt_sink_id() {
    $ASUSER wpctl status 2>/dev/null \
        | grep -iE "bluez|blue" \
        | awk '{print $2}' | tr -d '.' | head -1
}

pw_get_bt_volume() {
    local sink_id; sink_id=$(pw_get_bt_sink_id)
    [ -n "$sink_id" ] || { echo "?"; return; }
    $ASUSER wpctl get-volume "$sink_id" 2>/dev/null \
        | awk '{printf "%.0f", $2 * 100}'
}

snapcast_set_volume() {
    local pct="$1"
    local SNAP_IP="127.0.0.1"
    local SNAP_PORT="${SNAPCAST_PORT:-1704}"
    local WEB_PORT=1780
    # Récupérer l'ID du client local
    local client_id
    client_id=$(curl -s --max-time 2 \
        "http://${SNAP_IP}:${WEB_PORT}/jsonrpc" \
        -d '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' 2>/dev/null \
        | python3 -c "
import sys, json
d = json.load(sys.stdin)
groups = d.get('result',{}).get('server',{}).get('groups',[])
for g in groups:
    for c in g.get('clients',[]):
        print(c['id'])
" 2>/dev/null | head -1)
    [ -z "$client_id" ] && return 1
    curl -s --max-time 2 "http://${SNAP_IP}:${WEB_PORT}/jsonrpc" \
        -d "{\"id\":2,\"jsonrpc\":\"2.0\",\"method\":\"Client.SetVolume\",\"params\":{\"id\":\"${client_id}\",\"volume\":{\"muted\":false,\"percent\":${pct}}}}" \
        >/dev/null 2>&1
}

# ── Fonctions principales ────────────────────────────────────────
cmd_status() {
    echo -e "\n${W}╔══════════════════════════════════════════════════╗${N}"
    printf    "${W}║  SoundSpot BT/Volume  %-26s║${N}\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${W}╚══════════════════════════════════════════════════╝${N}"

    hdr "Bluetooth"
    if [ -z "$MACS" ]; then
        warn "Aucune enceinte configurée (BT_MACS vide) — utiliser bt_update.sh"
        return
    fi
    for mac in $MACS; do
        local name; name=$(bluetoothctl info "$mac" 2>/dev/null | awk '/Name:/{print substr($0, index($0,$2))}')
        name="${name:-$mac}"
        if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
            ok "${W}${name}${N}  ${C}${mac}${N}  connectée"
        elif bluetoothctl info "$mac" 2>/dev/null | grep -q "Paired: yes"; then
            warn "${W}${name}${N}  ${C}${mac}${N}  appairée, non connectée"
        else
            fail "${mac}  non appairée — lancer bt_update.sh"
        fi
    done

    hdr "PipeWire / Audio"
    local bt_sink_id; bt_sink_id=$(pw_get_bt_sink_id)
    if [ -n "$bt_sink_id" ]; then
        local vol; vol=$(pw_get_bt_volume)
        ok "Sink Bluetooth ID ${bt_sink_id}  volume ${W}${vol}%${N}"
    else
        warn "Aucun sink Bluetooth visible dans PipeWire"
        info "Causes : enceinte éteinte, A2DP non enregistré, libspa-0.2-bluetooth manquant"
        info "→ Essayer : sudo bash bt_manage.sh fix-a2dp"
    fi

    # Snapclient
    if pgrep -x snapclient &>/dev/null; then
        ok "snapclient en cours"
    else
        warn "snapclient absent (pas de sink BT ?)"
    fi

    # Snapcast server clients
    local snap_clients
    snap_clients=$(curl -s --max-time 2 "http://127.0.0.1:1780/jsonrpc" \
        -d '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' 2>/dev/null \
        | python3 -c "
import sys, json
d = json.load(sys.stdin)
groups = d.get('result',{}).get('server',{}).get('groups',[])
for g in groups:
    for c in g.get('clients',[]):
        h = c.get('host',{})
        v = c.get('config',{}).get('volume',{})
        s = 'connecté' if c.get('connected') else 'déconnecté'
        print(f\"  {h.get('name','?')} ({h.get('ip','?')}) — {s} — volume {v.get('percent','?')}%\")
" 2>/dev/null)
    if [ -n "$snap_clients" ]; then
        info "Clients Snapcast :"; echo "$snap_clients"
    fi
}

cmd_connect() {
    [ -z "$MACS" ] && err "BT_MACS non défini — lancer bt_update.sh d'abord"
    log "Connexion BT..."
    systemctl restart bt-autoconnect 2>/dev/null || true
    bash "${INSTALL_DIR}/bt-connect.sh" && log "Connexion réussie" || warn "Connexion partielle"
    sleep 3
    systemctl restart soundspot-client 2>/dev/null || true
    log "soundspot-client relancé"
}

cmd_disconnect() {
    [ -z "$MACS" ] && err "BT_MACS non défini"
    for mac in $MACS; do
        log "Déconnexion $mac..."
        bluetoothctl disconnect "$mac" 2>/dev/null || true
    done
    systemctl stop soundspot-client 2>/dev/null || true
    log "Enceintes déconnectées"
}

cmd_volume() {
    local pct="$1"
    [[ "$pct" =~ ^[0-9]+$ ]] || err "Volume invalide : '$pct' (attendu : 0-100)"
    [ "$pct" -gt 100 ] && pct=100

    local vol_pw; vol_pw=$(echo "scale=2; $pct / 100" | bc 2>/dev/null || echo "0.8")

    local bt_sink_id; bt_sink_id=$(pw_get_bt_sink_id)
    if [ -n "$bt_sink_id" ]; then
        $ASUSER wpctl set-volume "$bt_sink_id" "${vol_pw}" \
            && ok "Volume PipeWire (sink BT ${bt_sink_id}) → ${pct}%" \
            || warn "Erreur wpctl"
    else
        # Fallback : sink par défaut
        $ASUSER wpctl set-volume @DEFAULT_AUDIO_SINK@ "${vol_pw}" 2>/dev/null \
            && ok "Volume sink par défaut → ${pct}%" \
            || warn "Aucun sink disponible"
    fi

    # Volume Snapcast
    snapcast_set_volume "$pct" \
        && ok "Volume Snapcast local → ${pct}%" \
        || info "Snapcast non joignable (normal si snapclient arrêté)"
}

cmd_fix_a2dp() {
    hdr "Réparation A2DP (Protocol not available)"
    log "Installation libspa-0.2-bluetooth..."
    apt-get install -y libspa-0.2-bluetooth \
        && ok "libspa-0.2-bluetooth installé" \
        || warn "Erreur apt-get (déjà installé ?)"

    log "Redémarrage WirePlumber..."
    $ASUSER systemctl --user restart wireplumber 2>/dev/null \
        && ok "WirePlumber redémarré" \
        || warn "Erreur redémarrage WirePlumber"

    sleep 5
    log "Tentative de connexion BT..."
    cmd_connect

    log "État après correction :"
    local bt_sink_id; bt_sink_id=$(pw_get_bt_sink_id)
    if [ -n "$bt_sink_id" ]; then
        ok "Sink Bluetooth présent dans PipeWire (ID ${bt_sink_id})"
    else
        warn "Sink BT toujours absent — enceinte allumée ?"
        info "Vérifier : sudo -u pi XDG_RUNTIME_DIR=/run/user/${USER_ID} journalctl --user -u wireplumber -n 30 --no-pager"
    fi
}

cmd_menu() {
    cmd_status

    echo ""
    echo -e "  ${C}[1]${N}  Connecter l'enceinte BT"
    echo -e "  ${C}[2]${N}  Déconnecter l'enceinte BT"
    echo -e "  ${C}[3]${N}  Régler le volume"
    echo -e "  ${C}[4]${N}  Réparer A2DP (Protocol not available)"
    echo -e "  ${C}[5]${N}  Appairage / changer d'enceinte (bt_update.sh)"
    echo -e "  ${C}[q]${N}  Quitter"
    echo ""
    echo -ne "${M}?${N}  Choix : "
    read -r CHOICE

    case "$CHOICE" in
        1) cmd_connect ;;
        2) cmd_disconnect ;;
        3)
            echo -ne "${M}?${N}  Volume (0-100) : "
            read -r VOL
            cmd_volume "$VOL"
            ;;
        4) cmd_fix_a2dp ;;
        5) bash "${BASH_SOURCE[0]%/*}/bt_update.sh" --rpi ;;
        q|Q) echo "Bye."; exit 0 ;;
        *) warn "Choix invalide" ;;
    esac
}

# ── Dispatch ─────────────────────────────────────────────────────
ACTION="${1:-menu}"
[ "$ACTION" = "--rpi" ] && ACTION="${2:-menu}"

case "$ACTION" in
    status)     cmd_status ;;
    connect)    cmd_connect ;;
    disconnect) cmd_disconnect ;;
    volume)     cmd_volume "${2:-80}" ;;
    fix-a2dp)   cmd_fix_a2dp ;;
    menu)       cmd_menu ;;
    *)          err "Action inconnue : $ACTION (status|connect|disconnect|volume N|fix-a2dp)" ;;
esac
