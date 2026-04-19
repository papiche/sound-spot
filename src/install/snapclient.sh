#!/bin/bash
# install/snapclient.sh — Service soundspot-client (snapclient)
# Partagé entre maître (localhost) et satellite (MASTER_HOST).
# Prérequis : INSTALL_DIR, SNAPCAST_PORT ; MASTER_HOST requis en mode satellite.

setup_snapclient() {
    local mode="${1:-master}"
    hdr "Snapclient (mode ${mode})"

    # ── Scripts d'attente déployés dans INSTALL_DIR ──────────────
    for _script in wait-pw-socket.sh wait-bt-sink.sh; do
        cp "$SCRIPT_DIR/config/$_script" "$INSTALL_DIR/$_script"
        chmod +x "$INSTALL_DIR/$_script"
        log "$_script déployé"
    done

    # ── NTP sync — évite les sauts d'horloge qui décrochent Snapclient ──
    systemctl enable systemd-time-wait-sync 2>/dev/null || true
    log "systemd-time-wait-sync activé (NTP avant démarrage Snapclient)"

    if [ "$mode" = "satellite" ]; then
        install_template soundspot-client-satellite.service \
            /etc/systemd/system/soundspot-client.service \
            '${INSTALL_DIR} ${SNAPCAST_PORT} ${MASTER_HOST} ${SOUNDSPOT_USER} ${SOUNDSPOT_UID}'
        log "Snapclient activé → ${MASTER_HOST}:${SNAPCAST_PORT}"
    else
        install_template soundspot-client-master.service \
            /etc/systemd/system/soundspot-client.service \
            '${INSTALL_DIR} ${SNAPCAST_PORT} ${SOUNDSPOT_USER} ${SOUNDSPOT_UID}'
        log "Snapclient local activé (synchronisé avec les satellites)"
    fi

    systemctl enable soundspot-client
}
