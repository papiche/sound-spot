#!/bin/bash
# mesh_batman.sh — Configure le réseau maillé B.A.T.M.A.N.-adv pour la flotte SoundSpot
# S'exécute généralement sur le dongle USB externe (ex: Vemfay)

# Interface WAN effective (même détection que soundspot-firewall.sh) : sert à
# refuser de saisir le dongle qui porte déjà la connexion Internet — un seul
# radio ne peut pas être simultanément client WAN (managed) et nœud Mesh (IBSS).
if ip link show eth0 2>/dev/null | grep -q "state UP"; then
    _WAN_NOW="eth0"
else
    _WAN_NOW=$(ip route get 8.8.8.8 2>/dev/null \
        | awk '/dev/{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
fi

IFACE_MESH="${1:-wlan1}"
# Auto-detection si l'interface spécifiée n'existe pas ou sert déjà de WAN
if ! ip link show "$IFACE_MESH" >/dev/null 2>&1 || [ "$IFACE_MESH" = "$_WAN_NOW" ]; then
    IFACE_MESH=$(ip -o link show | awk -F": " '{print $2}' | grep -E "^(wlan|wlx)" \
        | grep -v "^wlan0$" | grep -vF "$_WAN_NOW" | head -n 1)
fi
[ -z "$IFACE_MESH" ] && echo "[Mesh] ERREUR: Aucun dongle Wi-Fi externe trouvé !" && exit 1
if [ "$IFACE_MESH" = "$_WAN_NOW" ]; then
    echo "[Mesh] ERREUR: ${IFACE_MESH} est déjà l'interface WAN (Internet) — mesh désactivé pour ne pas couper la connexion. Branchez un second dongle Wi-Fi dédié au mesh."
    exit 1
fi

MESH_ESSID="CYBERCOCHON_MESH"
MESH_BSSID="02:BA:7A:11:22:33" # BSSID fixe : crucial pour que tous les nœuds fusionnent
MESH_CHANNEL="36" # Bande 5GHz : indispensable pour le Mesh (plus de bande passante, moins d'interférences avec l'AP 2.4GHz)
# `iw ibss join` attend une fréquence en MHz, pas un numéro de canal — sans cette
# conversion la commande échoue silencieusement (« kernel reports: Unknown channel »,
# Invalid argument -22) et batctl reste attaché à une interface jamais réellement en IBSS.
MESH_FREQ=$((5000 + MESH_CHANNEL * 5))

# Charger le module kernel B.A.T.M.A.N.
modprobe batman-adv

# Empêcher NetworkManager de reprendre la main sur l'interface pendant/après
# la configuration IBSS — sinon il la reconnecte à son profil managed enregistré
# dès qu'on la repasse "up", et le mesh se retrouve silencieusement rompu.
command -v nmcli >/dev/null 2>&1 && nmcli device set "$IFACE_MESH" managed no 2>/dev/null

# Arrêter l'interface pour la configurer
ip link set $IFACE_MESH down

# Configurer en mode Ad-Hoc (IBSS)
iw dev $IFACE_MESH set type ibss
ip link set $IFACE_MESH mtu 1532 2>/dev/null || true # Tente d'augmenter le MTU pour encapsuler BATMAN
ip link set $IFACE_MESH up

# Rejoindre la cellule Mesh
if ! iw dev $IFACE_MESH ibss join $MESH_ESSID $MESH_FREQ $MESH_BSSID; then
    echo "[Mesh] ERREUR: échec de la jonction IBSS sur ${IFACE_MESH} (canal ${MESH_CHANNEL} / ${MESH_FREQ}MHz) — mesh non fonctionnel."
    exit 1
fi

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
