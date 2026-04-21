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

    install_template soundspot-channel-sync.service \
        /etc/systemd/system/soundspot-channel-sync.service \
        '${INSTALL_DIR}'
    systemctl enable soundspot-channel-sync
    log "Service soundspot-channel-sync activé"
}