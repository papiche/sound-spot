#!/bin/bash
# install/bluetooth.sh — Configuration Bluetooth auto-connect
# Partagé entre maître (install_soundspot.sh) et satellite (install_satellite.sh).
# Prérequis : INSTALL_DIR, BT_MACS définis ; colors.sh sourcé.

setup_bluetooth() {
    hdr "Bluetooth"
    sed -i 's/^#*AutoEnable=.*/AutoEnable=true/' /etc/bluetooth/main.conf

    mkdir -p "$INSTALL_DIR"

    install_template bt-autoconnect.service \
        /etc/systemd/system/bt-autoconnect.service \
        '${INSTALL_DIR}'

    install_template bt-connect.sh      "$INSTALL_DIR/bt-connect.sh"
    chmod +x "$INSTALL_DIR/bt-connect.sh"

    install_template bt-combine-sinks.sh "$INSTALL_DIR/bt-combine-sinks.sh"
    chmod +x "$INSTALL_DIR/bt-combine-sinks.sh"

    [ -n "$BT_MACS" ] && systemctl enable bt-autoconnect
    log "Service bt-autoconnect configuré"
}
