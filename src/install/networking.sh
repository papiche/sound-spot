#!/bin/bash
# install/networking.sh — Version compatible Bookworm & Trixie (Kernel 6.12+)
# Correction : Spécification explicite des protocoles pour iptables-nft

setup_networking() {
    hdr "Configuration Réseau (NetworkManager Mode)"

    # 1. Empêcher NetworkManager de gérer uap0 (hostapd va s'en charger)
    mkdir -p /etc/NetworkManager/conf.d
    cat > /etc/NetworkManager/conf.d/99-unmanaged-devices.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:uap0
EOF
    systemctl reload NetworkManager 2>/dev/null || true

    # 2. Installer et démarrer l'interface virtuelle uap0
    hdr "Interface AP virtuelle (uap0)"
    install_template uap0.service /etc/systemd/system/uap0.service
    systemctl daemon-reload
    systemctl enable --now uap0
    
    # 3. Assigner l'IP fixe à uap0 manuellement
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

    # 4. hostapd (Point d'accès)
    hdr "Point d'accès WiFi (hostapd)"
    systemctl unmask hostapd
    install_template hostapd.conf /etc/hostapd/hostapd.conf \
        '${SPOT_NAME} ${WIFI_CHANNEL}'
    sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
    systemctl enable hostapd

    # 5. dnsmasq (DHCP)
    hdr "DHCP + DNS (dnsmasq)"
    install_template dnsmasq.conf /etc/dnsmasq.conf \
        '${DHCP_START} ${DHCP_END} ${SPOT_IP}'
    systemctl enable dnsmasq

    # 6. Pare-feu et Portail Captif (Ipset + Iptables)
    hdr "Partage de connexion et Portail Captif"
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/90-soundspot.conf
    sysctl -p /etc/sysctl.d/90-soundspot.conf
    
    apt-get install -y ipset iptables-persistent

    # Chargement des modules noyau
    modprobe ip_set 2>/dev/null || true
    modprobe ip_set_hash_ip 2>/dev/null || true

    # Création du set basé sur l'IP (plus compatible sur kernels récents)
    ipset create soundspot_auth hash:ip timeout 900 -exist
    
    # Règles de base NAT
    iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
    
    # Redirection du portail captif (Port 80)
    iptables -t nat -N CAPTIVE_PORTAL 2>/dev/null || true
    iptables -t nat -F CAPTIVE_PORTAL 2>/dev/null || true
    
    # On saute dans CAPTIVE_PORTAL pour tout le trafic HTTP TCP/80
    iptables -t nat -A PREROUTING -i uap0 -p tcp --dport 80 -j CAPTIVE_PORTAL
    
    # Dans CAPTIVE_PORTAL :
    # 1. Si IP dans l'ipset -> on laisse passer (RETURN)
    iptables -t nat -A CAPTIVE_PORTAL -m set --match-set soundspot_auth src -j RETURN
    # 2. Sinon -> REDIRECT vers le port 80 local
    # NOTE : -p tcp est OBLIGATOIRE ici pour iptables-nft
    iptables -t nat -A CAPTIVE_PORTAL -p tcp -j REDIRECT --to-port 80

    # Règles de Forwarding (Accès Internet)
    iptables -A FORWARD -i uap0 -p udp --dport 53 -j ACCEPT
    iptables -A FORWARD -i uap0 -o wlan0 -m set --match-set soundspot_auth src -j ACCEPT
    iptables -A FORWARD -i wlan0 -o uap0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i uap0 -o wlan0 -j REJECT
    
    # Persistance de l'ipset
    cat > /etc/systemd/system/ipset-soundspot.service <<EOF
[Unit]
Description=Création de l'ipset SoundSpot au boot
Before=netfilter-persistent.service

[Service]
Type=oneshot
ExecStartPre=/sbin/modprobe ip_set_hash_ip
ExecStart=/usr/sbin/ipset create soundspot_auth hash:ip timeout 900 -exist
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable ipset-soundspot.service
    
    # Sauvegarde
    netfilter-persistent save
    log "Réseau et Portail Captif configurés"
}