#!/bin/bash
# install/networking.sh — Portail captif : Internet immédiat (DHCP) + portail au 1er HTTP

setup_networking() {
    hdr "Configuration Réseau (Portail captif avec accès immédiat)"

    # 1. Empêcher NetworkManager de gérer uap0
    mkdir -p /etc/NetworkManager/conf.d
    cat > /etc/NetworkManager/conf.d/99-unmanaged-devices.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:uap0
EOF
    systemctl reload NetworkManager 2>/dev/null || true

    # 2. Interface AP virtuelle (uap0)
    install_template uap0.service /etc/systemd/system/uap0.service
    systemctl daemon-reload
    systemctl enable --now uap0
    
    # 3. IP statique pour uap0
    cat > /etc/systemd/system/uap0-ip.service <<EOF
[Unit]
Description=IP statique pour uap0
After=uap0.service
[Service]
Type=oneshot
ExecStart=/sbin/ip addr add ${SPOT_IP}/24 dev uap0
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable --now uap0-ip.service

    # 4. hostapd & dnsmasq
    systemctl unmask hostapd
    install_template hostapd.conf /etc/hostapd/hostapd.conf '${SPOT_NAME} ${WIFI_CHANNEL}'
    sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
    systemctl enable hostapd

    install_template dnsmasq.conf /etc/dnsmasq.conf '${DHCP_START} ${DHCP_END} ${SPOT_IP}'
    systemctl enable dnsmasq

    # 5. Pare-feu — internet immédiat via DHCP + portail au premier HTTP
    hdr "Pare-feu : accès immédiat DHCP + portail HTTP"
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/90-soundspot.conf
    sysctl -p /etc/sysctl.d/90-soundspot.conf

    apt-get install -y ipset iptables-persistent

    modprobe ip_set_hash_ip 2>/dev/null || true

    # Liste blanche des IPs connectées — timeout 900s (15 min)
    # Alimentée automatiquement par dhcp_trigger.sh à chaque attribution DHCP.
    ipset create soundspot_auth hash:ip timeout 900 -exist

    # NAT classique
    iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE

    # --- INTERCEPTION HTTP (port 80) — inconditionnelle ---
    # TOUT le port 80 est redirigé vers le portail local.
    # Le smartphone fait un test HTTP (generate_204, hotspot-detect…) juste après
    # le DHCP → il tombe sur notre portail → fenêtre surgissante automatique.
    # Les apps (WhatsApp, Instagram) fonctionnent déjà car elles utilisent HTTPS.
    iptables -t nat -A PREROUTING -i uap0 -p tcp --dport 80 -j REDIRECT --to-port 80

    # --- RÈGLES DE FORWARD ---
    # 1. DNS pour tout le monde
    iptables -A FORWARD -i uap0 -p udp --dport 53 -j ACCEPT
    iptables -A FORWARD -i uap0 -p tcp --dport 53 -j ACCEPT

    # 2. HTTPS en priorité pour les IPs autorisées (accès instantané après DHCP)
    iptables -A FORWARD -i uap0 -p tcp --dport 443 \
        -m set --match-set soundspot_auth src -j ACCEPT

    # 3. Tout le reste pour les IPs autorisées (Snapcast, etc.)
    iptables -A FORWARD -i uap0 -m set --match-set soundspot_auth src -j ACCEPT

    # 4. Bloquer tout ce qui reste
    iptables -A FORWARD -i uap0 -j REJECT

    iptables -A FORWARD -i wlan0 -o uap0 -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Script DHCP — ajoute l'IP à soundspot_auth dès l'attribution de bail
    install_template dhcp_trigger.sh "${INSTALL_DIR}/dhcp_trigger.sh"
    chmod +x "${INSTALL_DIR}/dhcp_trigger.sh"
    log "dhcp_trigger.sh installé"

    # Persistance ipset — restaure la liste au démarrage, sauvegarde à l'arrêt
    cat > /etc/systemd/system/ipset-soundspot.service <<EOF
[Unit]
Description=Ipset SoundSpot (Auth list)
Before=netfilter-persistent.service
[Service]
Type=oneshot
ExecStartPre=/sbin/modprobe ip_set_hash_ip
ExecStart=/bin/bash -c '/usr/sbin/ipset restore -! < /etc/soundspot_ipset.save 2>/dev/null || /usr/sbin/ipset create soundspot_auth hash:ip timeout 900 -exist'
ExecStop=/bin/bash -c '/usr/sbin/ipset save soundspot_auth > /etc/soundspot_ipset.save 2>/dev/null || true'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable ipset-soundspot.service

    netfilter-persistent save
    log "Réseau configuré (internet immédiat DHCP + portail au 1er HTTP)"

}