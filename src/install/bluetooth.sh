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
        '${INSTALL_DIR} ${SOUNDSPOT_UID}'

    install_template bt-connect.sh      "$INSTALL_DIR/bt-connect.sh"
    chmod +x "$INSTALL_DIR/bt-connect.sh"

    install_template bt-combine-sinks.sh "$INSTALL_DIR/bt-combine-sinks.sh"
    chmod +x "$INSTALL_DIR/bt-combine-sinks.sh"

    # Script de gestion quotidienne BT + volume
    cp "$(dirname "${BASH_SOURCE[0]}")/../bt_manage.sh" "$INSTALL_DIR/bt_manage.sh" 2>/dev/null \
        || cp "$(dirname "${BASH_SOURCE[0]}")/../../bt_manage.sh" "$INSTALL_DIR/bt_manage.sh" 2>/dev/null \
        || true
    [ -f "$INSTALL_DIR/bt_manage.sh" ] && chmod +x "$INSTALL_DIR/bt_manage.sh" \
        && log "bt_manage.sh installé (connexion, volume)"

    # Service réactif (D-Bus BlueZ) — master ET satellite.
    # bt-autoconnect gère le boot ; bt_reactive gère les reconnexions runtime.
    install_template soundspot-bt-reactive.service \
        /etc/systemd/system/soundspot-bt-reactive.service \
        '${INSTALL_DIR} ${SOUNDSPOT_UID} ${SOUNDSPOT_USER}'
    cp "$SCRIPT_DIR/backend/system/bt_reactive.py" "$INSTALL_DIR/backend/system/bt_reactive.py" 2>/dev/null || true

    if [ -n "$BT_MACS" ]; then
        systemctl enable bt-autoconnect
        systemctl enable soundspot-bt-reactive
        log "Services bt-autoconnect + soundspot-bt-reactive activés"
    else
        log "BT_MACS non défini — services BT désactivés (configurer via portail admin)"
    fi
}
