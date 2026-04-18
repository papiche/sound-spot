#!/bin/bash
# install/jukebox.sh — Installation du démon Jukebox
setup_jukebox() {
    hdr "Jukebox Nostr/IPFS"

    install_template jukebox_player.sh "$INSTALL_DIR/jukebox_player.sh"
    chmod +x "$INSTALL_DIR/jukebox_player.sh"

    install_template soundspot-jukebox.service \
        /etc/systemd/system/soundspot-jukebox.service \
        '${INSTALL_DIR} ${SOUNDSPOT_USER}'

    systemctl enable soundspot-jukebox
    log "Service soundspot-jukebox activé"
}