#!/bin/bash
# install/channel_sync.sh — Synchronisation canal WiFi hostapd ↔ réseau amont
#                            + override systemd pour l'ordre de démarrage
# Maître uniquement.
# Prérequis : INSTALL_DIR.

setup_channel_sync() {
    hdr "Synchronisation canal WiFi (hostapd ↔ réseau amont)"

    install_template sync_channel.sh "$INSTALL_DIR/sync_channel.sh"
    chmod +x "$INSTALL_DIR/sync_channel.sh"

    install_template soundspot-channel-sync.service \
        /etc/systemd/system/soundspot-channel-sync.service \
        '${INSTALL_DIR}'
    systemctl enable soundspot-channel-sync
    log "Service soundspot-channel-sync activé"

    # ── Ordre de démarrage : uap0 + channel-sync avant hostapd/dnsmasq ──
    hdr "Ordre de démarrage systemd"

    mkdir -p /etc/systemd/system/hostapd.service.d
    install_template after-uap0-hostapd.conf \
        /etc/systemd/system/hostapd.service.d/after-uap0.conf

    mkdir -p /etc/systemd/system/dnsmasq.service.d
    install_template after-uap0-dnsmasq.conf \
        /etc/systemd/system/dnsmasq.service.d/after-uap0.conf

    systemctl daemon-reload
}
