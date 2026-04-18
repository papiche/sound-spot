#!/bin/bash
# install/bluetooth.sh — Configuration Bluetooth auto-connect
# Partagé entre maître (install_soundspot.sh) et satellite (install_satellite.sh).
# Prérequis : INSTALL_DIR, BT_MACS définis ; colors.sh sourcé.

setup_bluetooth() {
    hdr "Bluetooth"
    sed -i 's/^#*AutoEnable=.*/AutoEnable=true/' /etc/bluetooth/main.conf

    # BlueALSA et PipeWire ne coexistent pas : BlueALSA vole le profil A2DP
    # avant que WirePlumber puisse le réclamer → pas de son.
    # On masque BlueALSA définitivement ; PipeWire/WirePlumber gère seul le BT.
    for svc in bluealsa bluealsa-aplay; do
        systemctl stop    "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
        systemctl mask    "$svc" 2>/dev/null || true
    done
    log "BlueALSA masqué — PipeWire/WirePlumber gère le Bluetooth"

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
