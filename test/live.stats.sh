#!/bin/bash
# ================================================================
#  stat.sh — SoundSpot Live Monitor (Loop Edition)
#  Quitter avec Ctrl+C
# ================================================================

# Couleurs
G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; W='\033[1;37m'; R='\033[0;31m'; N='\033[0m'; D='\033[2m'

# Config
SPOT_IP="127.0.0.1"
SNAP_API="1780"
ICE_PORT="8111"
[ -f /opt/soundspot/soundspot.conf ] && source /opt/soundspot/soundspot.conf
IFACE_AP="${IFACE_AP:-uap0}"
IFACE_WAN="${IFACE_WAN:-wlan0}"

# Nettoyage au Ctrl+C
trap "echo -e '\n${G}Fin du monitoring.${N}'; exit" SIGINT

get_bytes() { 
    # $1 = interface
    grep "$1" /proc/net/dev | awk '{print $2 " " $10}' || echo "0 0"
}

while true; do
    # 1. Prise de mesure réseau pour le débit
    read r1 t1 < <(get_bytes $IFACE_AP)
    read r2 t2 < <(get_bytes $IFACE_WAN)
    
    # On attend 1 seconde pour calculer le débit par seconde
    sleep 1
    
    read r3 t3 < <(get_bytes $IFACE_AP)
    read r4 t4 < <(get_bytes $IFACE_WAN)

    # Calcul kbps
    uap_rx=$(( (r3-r1)*8/1024 )); uap_tx=$(( (t3-t1)*8/1024 ))
    ma_rx=$(( (r4-r2)*8/1024 )); ma_tx=$(( (t4-t2)*8/1024 ))

    # 2. Affichage
    clear
    echo -e "${C}━━━ SoundSpot Monitor ${W}[$(date +%H:%M:%S)]${C} ━━━${N}"
    echo -e "${D}Appuyez sur Ctrl+C pour quitter${N}\n"

    # Icecast
    ICE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 1 http://$SPOT_IP:$ICE_PORT/live)
    if [ "$ICE_STATUS" == "200" ]; then
        echo -e "${W}Entrée DJ (Icecast) : ${G}● CONNECTÉ${N}"
    else
        echo -e "${W}Entrée DJ (Icecast) : ${R}○ EN ATTENTE${N}"
    fi

    # Snapcast via Python
    python3 <<EOF
import urllib.request, json
try:
    req = urllib.request.Request("http://$SPOT_IP:$SNAP_API/jsonrpc", 
        data=json.dumps({"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}).encode(),
        timeout=1)
    res = json.loads(urllib.request.urlopen(req).read())
    server = res['result']['server']
    
    # Stream
    stream = server['streams'][0]
    st_color = "${G}" if stream['status'] == "playing" else "${R}"
    print(f"${W}Sortie Audio      : {st_color}● {stream['status'].upper()}${N}")
    
    # Clients
    print(f"\n${W}Auditeurs connectés :${N}")
    count = 0
    for g in server['groups']:
        for c in g['clients']:
            if c['connected']:
                count += 1
                name = c['host']['name'][:12]
                ip = c['host']['ip']
                vol = c['config']['volume']['percent']
                print(f"  • {W}{name:12}${N} | {C}{ip:15}${N} | Vol: {vol}%")
    if count == 0: print("  ${D}Aucun client actif${N}")
except:
    print("${R}Erreur API Snapserver${N}")
EOF

    # Réseau
    echo -e "\n${W}Trafic Réseau :${N}"
    printf "  $IFACE_AP (AP Visiteurs) : RX: ${C}%4d kb/s${N}  TX: ${G}%4d kb/s${N}\n" "$uap_rx" "$uap_tx"
    printf "  $IFACE_WAN (MA / SATS)   : RX: ${C}%4d kb/s${N}  TX: ${G}%4d kb/s${N}\n" "$ma_rx" "$ma_tx"

    echo -e "\n${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    
    # Temps d'attente restant pour faire ~2s de cycle total 
    # (le sleep 1 du débit + temps API curl/python prend déjà du temps)
    sleep 1
done