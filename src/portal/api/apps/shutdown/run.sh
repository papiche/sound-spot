#!/bin/bash
# api/apps/shutdown/run.sh — Extinction ordonnée du Master RPi4
# Fallback de dernier recours pour le nœud Énergie (INA219 + relais) quand le
# mécanisme sécurisé (fleet_commander.sh, ordre NOSTR kind 9 signé Amiral) est
# indisponible — voir battery_monitor.py:_notify_master_direct().
#
# Accepte uniquement les requêtes POST depuis le réseau local AP (192.168.10.x),
# à L'EXCLUSION de la plage DHCP attribuée aux visiteurs (DHCP_START..DHCP_END) :
# cette plage n'héberge jamais d'infrastructure de confiance, seulement des
# téléphones/PC anonymes connectés au SSID ouvert.

_SS_SERVICE="portal-shutdown"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

REMOTE_ADDR="${REMOTE_ADDR:-}"
DHCP_START="${DHCP_START:-192.168.10.10}"
DHCP_END="${DHCP_END:-192.168.10.50}"

_is_visitor_ip() {
    local last="${1##*.}" lo="${DHCP_START##*.}" hi="${DHCP_END##*.}"
    [[ "$last" =~ ^[0-9]+$ ]] && [ "$last" -ge "$lo" ] 2>/dev/null && [ "$last" -le "$hi" ] 2>/dev/null
}

case "$REMOTE_ADDR" in
    192.168.10.*|127.0.0.1|::1)
        if [[ "$REMOTE_ADDR" == 192.168.10.* ]] && _is_visitor_ip "$REMOTE_ADDR"; then
            ss_warn "shutdown: refusé — IP visiteur ($REMOTE_ADDR dans la plage DHCP $DHCP_START-$DHCP_END)"
            echo '{"error":"unauthorized"}'
            exit 0
        fi
        echo '{"status":"shutting_down"}'
        # Flush les tampons audio proprement avant d'éteindre
        systemctl stop soundspot-client snapserver soundspot-decoder 2>/dev/null || true
        sleep 2
        sudo /usr/sbin/poweroff
        ;;
    *)
        echo '{"error":"unauthorized"}'
        ;;
esac
