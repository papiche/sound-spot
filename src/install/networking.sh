#!/bin/bash
# install/networking.sh — Mode : Validation par clic (Portail → 15 min d'accès)

setup_networking() {
    hdr "Configuration Réseau (Validation par clic)"

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

    # 5. Pare-feu — logique de validation par clic
    hdr "Pare-feu : Validation par clic requise"
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/90-soundspot.conf
    sysctl -p /etc/sysctl.d/90-soundspot.conf

    apt-get install -y ipset iptables-persistent

    modprobe ip_set_hash_ip 2>/dev/null || true

    # Liste BLANCHE des IPs ayant validé le portail — timeout 900s (15 min)
    # Géré nativement par le noyau : aucun daemon Python nécessaire.
    ipset create soundspot_auth hash:ip timeout 900 -exist

    # NAT classique
    iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE

    # --- INTERCEPTION HTTP (port 80) ---
    # Si l'IP n'est PAS dans soundspot_auth, on redirige vers le portail local
    iptables -t nat -A PREROUTING -i uap0 -p tcp --dport 80 \
        -m set ! --match-set soundspot_auth src -j REDIRECT --to-port 80

    # --- RÈGLES DE FORWARD (INTERNET) ---
    # 1. DNS pour tout le monde (sinon le portail ne peut pas s'afficher)
    iptables -A FORWARD -i uap0 -p udp --dport 53 -j ACCEPT
    iptables -A FORWARD -i uap0 -p tcp --dport 53 -j ACCEPT

    # 2. HTTPS pour tout le monde — le téléphone affiche "Connecté" et évite
    #    le faux message "Pas d'internet" qui ferait peur à l'utilisateur.
    iptables -A FORWARD -i uap0 -p tcp --dport 443 -j ACCEPT

    # 3. Accès complet pour les IPs qui ont validé le portail
    iptables -A FORWARD -i uap0 -m set --match-set soundspot_auth src -j ACCEPT

    # 4. Bloquer tout le reste (non-DNS, non-HTTPS, non-validé)
    iptables -A FORWARD -i uap0 -j REJECT

    iptables -A FORWARD -i wlan0 -o uap0 -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Persistance ipset — les validations survivent au redémarrage
    # (ipset restore recharge l'ancienne liste ; si elle est vide c'est normal
    #  car les timeouts de 15 min auront expiré entre-temps)
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
    log "Réseau configuré (Portail captif — validation par clic → 15 min)"

}