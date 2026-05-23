#!/bin/bash
# mesh_batman.sh — Configure le réseau maillé B.A.T.M.A.N.-adv pour la flotte SoundSpot
# S'exécute généralement sur le dongle USB externe (ex: Vemfay)

IFACE_MESH="${1:-wlan1}"
# Auto-detection si l'interface spécifiée n'existe pas
if ! ip link show $IFACE_MESH >/dev/null 2>&1; then
    IFACE_MESH=$(ip -o link show | awk -F": " '{print $2}' | grep -E "^(wlan|wlx)" | grep -v "^wlan0$" | head -n 1)
fi
[ -z "$IFACE_MESH" ] && echo "[Mesh] ERREUR: Aucun dongle Wi-Fi externe trouvé !" && exit 1

MESH_ESSID="CYBERCOCHON_MESH"
MESH_BSSID="02:BA:7A:11:22:33" # BSSID fixe : crucial pour que tous les nœuds fusionnent
MESH_CHANNEL="36" # Bande 5GHz : indispensable pour le Mesh (plus de bande passante, moins d'interférences avec l'AP 2.4GHz)

# Charger le module kernel B.A.T.M.A.N.
modprobe batman-adv

# Arrêter l'interface pour la configurer
ip link set $IFACE_MESH down

# Configurer en mode Ad-Hoc (IBSS)
iw dev $IFACE_MESH set type ibss
ip link set $IFACE_MESH mtu 1532 2>/dev/null || true # Tente d'augmenter le MTU pour encapsuler BATMAN
ip link set $IFACE_MESH up

# Rejoindre la cellule Mesh
iw dev $IFACE_MESH ibss join $MESH_ESSID $MESH_CHANNEL $MESH_BSSID

# Attacher l'interface à B.A.T.M.A.N.
batctl if add $IFACE_MESH
ip link set up dev bat0

# Assigner une IP locale unique basée sur l'adresse MAC (pour éviter le DHCP dans le mesh)
if [ -f /etc/hostapd/hostapd.conf ]; then
    # -- NŒUD MAÎTRE --
    ip addr add 10.200.0.1/16 dev bat0
    echo "[Mesh] B.A.T.M.A.N. Master activé (IP: 10.200.0.1)"
else
    # -- NŒUD SATELLITE / ÉNERGIE --
    MAC_SUFFIX=$(cat /sys/class/net/$IFACE_MESH/address | awk -F: '{print $5"."$6}')
    IP_DEC1=$(printf "%d" 0x${MAC_SUFFIX%.*})
    IP_DEC2=$(printf "%d" 0x${MAC_SUFFIX#*.})
    ip addr add 10.200.$IP_DEC1.$IP_DEC2/16 dev bat0
    
    # Définir le Master comme passerelle par défaut (Gateway)
    ip route replace default via 10.200.0.1 dev bat0 metric 50 || true
    echo "[Mesh] B.A.T.M.A.N. Satellite activé (IP: 10.200.$IP_DEC1.$IP_DEC2, GW: 10.200.0.1)"
fi
