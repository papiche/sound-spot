#!/bin/bash
setup_autodj() {
    hdr "AutoDJ (Lecture de ~/Music)"
    
    local USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
    mkdir -p "$USER_HOME/Music"
    chown -R ${SOUNDSPOT_USER}:${SOUNDSPOT_USER} "$USER_HOME/Music"
    
    install_template soundspot-autodj.service \
        /etc/systemd/system/soundspot-autodj.service \
        '${INSTALL_DIR} ${SOUNDSPOT_USER}'
    
    systemctl daemon-reload
    # On n'active pas par défaut au boot, c'est manuel via le portail
    log "Service soundspot-autodj installé (démarrage manuel)"
}
