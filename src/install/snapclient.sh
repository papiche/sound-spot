#!/bin/bash
# install/snapclient.sh — Service soundspot-client (snapclient)
# Partagé entre maître (localhost) et satellite (MASTER_HOST).
# Prérequis : INSTALL_DIR, SNAPCAST_PORT ; MASTER_HOST requis en mode satellite.

setup_snapclient() {
    local mode="${1:-master}"
    hdr "Snapclient (mode ${mode})"

    if [ "$mode" = "satellite" ]; then
        install_template soundspot-client-satellite.service \
            /etc/systemd/system/soundspot-client.service \
            '${INSTALL_DIR} ${SNAPCAST_PORT} ${MASTER_HOST} ${SOUNDSPOT_USER}'
        log "Snapclient activé → ${MASTER_HOST}:${SNAPCAST_PORT}"
    else
        install_template soundspot-client-master.service \
            /etc/systemd/system/soundspot-client.service \
            '${INSTALL_DIR} ${SNAPCAST_PORT} ${SOUNDSPOT_USER}'
        log "Snapclient local activé (synchronisé avec les satellites)"
    fi

    systemctl enable soundspot-client
}
