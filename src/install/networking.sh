#!/bin/bash
# install/networking.sh — Mode : Ouvert par défaut / Bloqué après 15 min

setup_networking() {
    hdr "Configuration Réseau (Mode Ouvert + Limiteur)"

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

    # 5. Pare-feu (Inversion de logique)
    hdr "Pare-feu : Autorisation par défaut"
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/90-soundspot.conf
    sysctl -p /etc/sysctl.d/90-soundspot.conf
    
    apt-get install -y ipset iptables-persistent

    modprobe ip_set_hash_ip 2>/dev/null || true

    # Création de la liste NOIRE (Blocked) - Timeout 3600s (1 heure)
    ipset create soundspot_blocked hash:ip timeout 3600 -exist
    
    # NAT classique
    iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
    
    # --- REDIRECTION DES BLOQUÉS ---
    # Si l'IP est bloquée, on redirige son trafic HTTP (port 80) vers le portail
    iptables -t nat -A PREROUTING -i uap0 -p tcp --dport 80 -m set --match-set soundspot_blocked src -j REDIRECT --to-port 80

    # --- RÈGLES DE FORWARD (INTERNET) ---
    # 1. Autoriser DNS pour tout le monde (sinon même le portail ne s'affiche pas)
    iptables -A FORWARD -i uap0 -p udp --dport 53 -j ACCEPT
    iptables -A FORWARD -i uap0 -p tcp --dport 53 -j ACCEPT

    # 2. Bloquer le trafic de ceux qui sont dans la liste noire
    iptables -A FORWARD -i uap0 -m set --match-set soundspot_blocked src -j REJECT

    # 3. Autoriser tout le reste par défaut (Open Internet)
    iptables -A FORWARD -i uap0 -o wlan0 -j ACCEPT
    iptables -A FORWARD -i wlan0 -o uap0 -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Persistance ipset
    cat > /etc/systemd/system/ipset-soundspot.service <<EOF
[Unit]
Description=Ipset SoundSpot (Blocked list)
Before=netfilter-persistent.service
[Service]
Type=oneshot
ExecStartPre=/sbin/modprobe ip_set_hash_ip
ExecStart=/usr/sbin/ipset create soundspot_blocked hash:ip timeout 3600 -exist
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable ipset-soundspot.service
    
    netfilter-persistent save
    log "Réseau configuré (Accès libre 15min / Bloqué 1h)"

# Installation du service limiteur
    cp ${SCRIPT_DIR}/limiter.py ${INSTALL_DIR}/limiter.py
    chmod +x ${INSTALL_DIR}/limiter.py

    cat > /etc/systemd/system/soundspot-limiter.service <<EOF
[Unit]
Description=SoundSpot — Limiteur de temps Internet
After=dnsmasq.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/limiter.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable --now soundspot-limiter.service

}