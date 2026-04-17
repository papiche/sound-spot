#!/bin/bash
# install/captive_portal.sh — Portail captif opennds + thème HTML SoundSpot
# Maître uniquement.
# Prérequis : SPOT_IP, SNAPCAST_PORT.

setup_captive_portal() {
    hdr "Portail captif (opennds ThemeSpec)"

    # Le port HTTP de Snapcast est SNAPCAST_PORT + 1 (à ouvrir dans le walled garden)
    SNAPCAST_HTTP_PORT=$((SNAPCAST_PORT + 1))
    export SNAPCAST_HTTP_PORT

    install_template opennds.conf /etc/opennds/opennds.conf \
        '${SPOT_IP} ${SNAPCAST_PORT} ${SNAPCAST_HTTP_PORT}'

    # Le thème est un script shell exécuté par OpenNDS — copie verbatim
    install_template theme_soundspot.sh /etc/opennds/theme_soundspot.sh
    chmod +x /etc/opennds/theme_soundspot.sh

    systemctl enable opennds
    log "Portail captif configuré (opennds ThemeSpec)"
}
