#!/bin/bash
# install/networking.sh — Version Bookworm Pure

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
    
    # 3. Assigner l'IP fixe à uap0 manuellement (NM ne le fait plus)
    # On utilise une petite astuce systemd pour remettre l'IP au boot
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
    # Forcer hostapd à utiliser uap0
    sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
    systemctl enable hostapd

    # 5. dnsmasq (DHCP)
    hdr "DHCP + DNS (dnsmasq)"
    install_template dnsmasq.conf /etc/dnsmasq.conf \
        '${DHCP_START} ${DHCP_END} ${SPOT_IP}'
    systemctl enable dnsmasq

    # 6. NAT (Partage de connexion)
    hdr "Partage de connexion (NAT)"
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/90-soundspot.conf
    sysctl -p /etc/sysctl.d/90-soundspot.conf
    
    # Configuration IPTABLES persistante
    iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
    iptables -A FORWARD -i uap0 -o wlan0 -j ACCEPT
    iptables -A FORWARD -i wlan0 -o uap0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    # Sauvegarde
    apt-get install -y iptables-persistent
    netfilter-persistent save
    
    log "Réseau configuré : wlan0 (client) + uap0 (hotspot)"
}