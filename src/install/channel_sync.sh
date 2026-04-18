#!/bin/bash
setup_channel_sync() {
    hdr "Synchronisation canal WiFi"

    # ── Ordre de démarrage systemd ──
    mkdir -p /etc/systemd/system/hostapd.service.d
    install_template after-soundspot-ap-hostapd.conf \
        /etc/systemd/system/hostapd.service.d/after-soundspot-ap.conf

    mkdir -p /etc/systemd/system/dnsmasq.service.d
    install_template after-soundspot-ap-dnsmasq.conf \
        /etc/systemd/system/dnsmasq.service.d/after-soundspot-ap.conf

    systemctl daemon-reload

    if [ "$IFACE_AP" != "uap0" ]; then
        log "Mode Dual-WiFi : Indépendance des canaux activée."
        log "Hostapd utilisera le canal dédié ${WIFI_CHANNEL} au lieu de suivre wlan0."
        return 0
    fi

    log "Mode Monocarte : Synchronisation hostapd ↔ réseau amont activée."
    install_template sync_channel.sh "$INSTALL_DIR/sync_channel.sh"
    chmod +x "$INSTALL_DIR/sync_channel.sh"

    install_template soundspot-channel-sync.service \
        /etc/systemd/system/soundspot-channel-sync.service \
        '${INSTALL_DIR}'
    systemctl enable soundspot-channel-sync
    log "Service soundspot-channel-sync activé"
}