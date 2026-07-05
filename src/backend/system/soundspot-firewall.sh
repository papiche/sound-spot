#!/bin/bash
# soundspot-firewall.sh — Applique les règles iptables SoundSpot au démarrage.
# Exécuté par soundspot-firewall.service APRÈS soundspot-ipset.service.
# Idempotent : flush les règles précédentes avant de réécrire.
#
# WAN détecté dynamiquement (eth0 > wlan0) — fonctionne avec :
#   • Box 4G via Ethernet (eth0)
#   • Smartphone en hotspot WiFi (wlan0)
#   • Basculement à chaud entre les deux

SPOT_IP="${SPOT_IP:-192.168.10.1}"
IFACE_AP="${IFACE_AP:-uap0}"
IFACE_WAN="${IFACE_WAN:-wlan0}"

# ── Charger la configuration ──────────────────────────────────────
[ -f /opt/soundspot/soundspot.conf ] && source /opt/soundspot/soundspot.conf

# ── AP 5GHz bi-bande (dongle, AP5G_ENABLED=true) ──────────────────
# Sous-réseau distinct routé par le Pi (pas de bridge) — reçoit exactement les
# mêmes règles que l'AP principal, voir la boucle AP_IFACES plus bas.
AP_IFACES=("$IFACE_AP")
[ "${AP5G_ENABLED:-false}" = "true" ] && [ -n "${IFACE_AP5G:-}" ] && AP_IFACES+=("$IFACE_AP5G")

# ── Détection WAN dynamique ───────────────────────────────────────
# Priorité : eth0 si UP (box 4G / routeur) → sinon route par défaut actuelle
if ip link show eth0 2>/dev/null | grep -q "state UP"; then
    IFACE_WAN="eth0"
else
    # Route par défaut effective (gère le basculement smartphone ↔ routeur)
    _DYN_WAN=$(ip route get 8.8.8.8 2>/dev/null \
        | awk '/dev/{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
    [ -n "$_DYN_WAN" ] && IFACE_WAN="$_DYN_WAN"
fi

echo "[soundspot-firewall] AP=${AP_IFACES[*]}  WAN=${IFACE_WAN}  IP=${SPOT_IP}"

# ── Vider les règles existantes de SoundSpot ─────────────────────
iptables -t nat    -F PREROUTING  2>/dev/null || true
iptables -t nat    -F POSTROUTING 2>/dev/null || true
iptables -t mangle -F POSTROUTING 2>/dev/null || true
iptables -t mangle -F FORWARD     2>/dev/null || true
iptables           -F FORWARD     2>/dev/null || true
iptables           -F INPUT       2>/dev/null || true

# ── ip_forward ───────────────────────────────────────────────────
echo 1 > /proc/sys/net/ipv4/ip_forward

# ── NAT — partage de connexion → WAN ─────────────────────────────
iptables -t nat -A POSTROUTING -o "${IFACE_WAN}" -j MASQUERADE
# Mesh B.A.T.M.A.N. : les nœuds distants sortent aussi via le WAN du maître
iptables -t nat -A POSTROUTING -s 10.200.0.0/16 -o "${IFACE_WAN}" -j MASQUERADE
# TCP MSS Clamping : évite le blocage des gros paquets (PPPoE, VPN, mesh)
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN \
    -o "${IFACE_WAN}" -j TCPMSS --clamp-mss-to-pmtu
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN \
    -j TCPMSS --clamp-mss-to-pmtu

# ── Services locaux accessibles depuis le mesh bat0 ──────────────
# Les satellites distants (via B.A.T.M.A.N.) atteignent Snapserver et le portail
iptables -A INPUT -i bat0 -p tcp --dport 1704 -j ACCEPT  # Snapcast audio
iptables -A INPUT -i bat0 -p tcp --dport 80   -j ACCEPT  # Portail captif
iptables -A INPUT -i bat0 -p tcp --dport 8111 -j ACCEPT  # Icecast2
iptables -A INPUT -i bat0 -p udp --dport 5353 -j ACCEPT  # mDNS (découverte soundspot.local)
iptables -A INPUT -i bat0 -p tcp --dport 9999 -j ACCEPT  # Relay NOSTR flotte local

# ── Interception HTTP (port 80) → portail + Règles FORWARD ───────
# 1. Mesh B.A.T.M.A.N. — tout le trafic inter-nœuds est libre
iptables -A FORWARD -i bat0 -j ACCEPT
iptables -A FORWARD -o bat0 -j ACCEPT

# Les règles suivantes sont identiques pour chaque radio AP visiteurs
# (uap0 2,4GHz + dongle 5GHz si AP5G_ENABLED=true — voir AP_IFACES plus haut).
for _ap in "${AP_IFACES[@]}"; do
    iptables -t nat -A PREROUTING -i "${_ap}" -p tcp --dport 80 \
        -j REDIRECT --to-port 80

    # 2. DNS et RTMP universels (AP visiteurs)
    iptables -A FORWARD -i "${_ap}" -p udp --dport 53 -j ACCEPT
    iptables -A FORWARD -i "${_ap}" -p tcp --dport 53 -j ACCEPT
    iptables -A FORWARD -i "${_ap}" -p tcp --dport 1935 -j ACCEPT  # RTMP drones

    # 3. IPs autorisées (ipset soundspot_auth — ouverture portail 4h)
    iptables -A FORWARD -i "${_ap}" \
        -m set --match-set soundspot_auth src -j ACCEPT

    # 4. Réponses établies (retour vers les clients AP)
    iptables -A FORWARD -i "${IFACE_WAN}" -o "${_ap}" \
        -m state --state RELATED,ESTABLISHED -j ACCEPT

    # 5. Bloquer tout le reste en provenance de cet AP
    iptables -A FORWARD -i "${_ap}" -j REJECT
done

echo "[soundspot-firewall] Règles appliquées ✓"
