#!/bin/bash
# install/networking.sh — Réseau SoundSpot : AP virtuelle + firewall + portail captif

setup_networking() {
    hdr "Configuration Réseau"

    # 1. Empêcher NetworkManager de gérer uap0
    mkdir -p /etc/NetworkManager/conf.d
    cat > /etc/NetworkManager/conf.d/99-unmanaged-devices.conf <<'EOF'
[keyfile]
unmanaged-devices=interface-name:uap0
EOF
    systemctl reload NetworkManager 2>/dev/null || true

    # 2. Interface AP virtuelle (uap0)
    install_template uap0.service /etc/systemd/system/uap0.service '${SPOT_IP}'
    systemctl daemon-reload
    systemctl enable uap0

    # 3. IP statique pour uap0
    cat > /etc/systemd/system/uap0-ip.service <<EOF
[Unit]
Description=IP statique pour uap0
After=uap0.service
BindsTo=uap0.service

[Service]
Type=oneshot
ExecStart=/sbin/ip addr add ${SPOT_IP}/24 dev uap0 2>/dev/null || true
ExecStart=/sbin/ip link set uap0 up
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable uap0-ip.service

    # 4. hostapd & dnsmasq
    systemctl unmask hostapd
    install_template hostapd.conf /etc/hostapd/hostapd.conf \
        '${SPOT_NAME} ${WIFI_CHANNEL}'
    sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' \
        /etc/default/hostapd
    systemctl enable hostapd

    install_template dnsmasq.conf /etc/dnsmasq.conf \
        '${DHCP_START} ${DHCP_END} ${SPOT_IP}'
    systemctl enable dnsmasq

    # 5. ip_forward (persistant)
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/90-soundspot.conf
    sysctl -w net.ipv4.ip_forward=1

    # 6. ipset — service de persistance avec bon ordre de démarrage
    #    DOIT démarrer avant netfilter-persistent ET avant soundspot-firewall
    modprobe ip_set_hash_ip 2>/dev/null || true
    ipset create soundspot_auth hash:ip timeout 900 -exist

    cat > /etc/systemd/system/ipset-soundspot.service <<'SVCEOF'
[Unit]
Description=SoundSpot — Ipset soundspot_auth
DefaultDependencies=no
After=systemd-modules-load.service
Before=network-pre.target netfilter-persistent.service soundspot-firewall.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/sbin/modprobe ip_set_hash_ip
ExecStart=/bin/bash -c '\
    /usr/sbin/ipset create soundspot_auth hash:ip timeout 900 -exist; \
    /usr/sbin/ipset restore -! < /etc/soundspot_ipset.save 2>/dev/null || true'
ExecStop=/bin/bash -c '\
    /usr/sbin/ipset save soundspot_auth > /etc/soundspot_ipset.save 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl enable ipset-soundspot.service

    # 7. Firewall — service dédié (évite la fragilité de netfilter-persistent avec ipset)
    install_template soundspot-firewall.sh  "$INSTALL_DIR/soundspot-firewall.sh"
    install_template soundspot-firewall.service \
        /etc/systemd/system/soundspot-firewall.service
    chmod +x "$INSTALL_DIR/soundspot-firewall.sh"
    systemctl enable soundspot-firewall.service

    # Appliquer les règles immédiatement pour la session courante
    bash "$INSTALL_DIR/soundspot-firewall.sh"

    # 8. Script DHCP trigger
    install_template dhcp_trigger.sh "${INSTALL_DIR}/dhcp_trigger.sh"
    chmod +x "${INSTALL_DIR}/dhcp_trigger.sh"

    # S'assurer que netfilter-persistent ne sauvegarde pas de règles en doublon
    # (on utilise soundspot-firewall.service, pas netfilter-persistent pour nos règles)
    apt-get install -y -q netfilter-persistent iptables-persistent 2>/dev/null || true
    systemctl disable netfilter-persistent 2>/dev/null || true

    systemctl daemon-reload
    log "Réseau configuré — portail captif + pare-feu"
}
