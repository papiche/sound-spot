#!/bin/bash
# soundspot-firewall.sh — Applique les règles iptables SoundSpot au démarrage.
# Exécuté par soundspot-firewall.service APRÈS soundspot-ipset.service.
# Idempotent : flush les règles précédentes avant de réécrire.

SPOT_IP="${SPOT_IP:-192.168.10.1}"
IFACE_AP="${IFACE_AP:-uap0}"
IFACE_WAN="${IFACE_WAN:-wlan0}"

# ── Charger la configuration ──────────────────────────────────────
[ -f /opt/soundspot/soundspot.conf ] && source /opt/soundspot/soundspot.conf

# ── Vider les règles existantes de SoundSpot ─────────────────────
# (on réinitialise seulement nos chaînes pour ne pas casser le reste)
iptables -t nat  -F PREROUTING  2>/dev/null || true
iptables -t nat  -F POSTROUTING 2>/dev/null || true
iptables         -F FORWARD     2>/dev/null || true

# ── ip_forward ───────────────────────────────────────────────────
echo 1 > /proc/sys/net/ipv4/ip_forward

# ── NAT — partage de connexion uap0 → wlan0 ──────────────────────
iptables -t nat -A POSTROUTING -o "${IFACE_WAN}" -j MASQUERADE
iptables -t nat -A POSTROUTING -s 10.200.0.0/16 -o "${IFACE_WAN}" -j MASQUERADE
# Optimisation MTU : TCP MSS Clamping pour éviter le blocage des gros paquets dans le Mesh
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o "${IFACE_WAN}" -j TCPMSS --clamp-mss-to-pmtu
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu


# ── Interception HTTP (port 80) → portail lighttpd ───────────────
# Redirige tout le trafic HTTP de l'AP vers le portail local.
# Les smartphones testent http://connectivitycheck.gstatic.com/generate_204
# → DNS redirige vers ${SPOT_IP} → lighttpd sert le portail → popup captif
iptables -t nat -A PREROUTING -i "${IFACE_AP}" -p tcp --dport 80 \
    -j REDIRECT --to-port 80

# ── Règles FORWARD ────────────────────────────────────────────────
# 1. DNS universel (tout le monde peut résoudre)
# Autoriser tout le trafic interne du Mesh
iptables -A FORWARD -i bat0 -j ACCEPT
iptables -A FORWARD -o bat0 -j ACCEPT

iptables -A FORWARD -i "${IFACE_AP}" -p udp --dport 53 -j ACCEPT
# Autoriser le flux video RTMP (Drones)
iptables -A FORWARD -i "${IFACE_AP}" -p tcp --dport 1935 -j ACCEPT

iptables -A FORWARD -i "${IFACE_AP}" -p tcp --dport 53 -j ACCEPT

# 2. Trafic autorisé (IPs dans soundspot_auth)
iptables -A FORWARD -i "${IFACE_AP}" \
    -m set --match-set soundspot_auth src -j ACCEPT

# 3. Réponses établies (retour vers les clients)
iptables -A FORWARD -i "${IFACE_WAN}" -o "${IFACE_AP}" \
    -m state --state RELATED,ESTABLISHED -j ACCEPT

# 4. Bloquer tout le reste
iptables -A FORWARD -i "${IFACE_AP}" -j REJECT

echo "[soundspot-firewall] Règles appliquées (AP=${IFACE_AP} WAN=${IFACE_WAN})"
