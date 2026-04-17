#!/bin/bash
# install/icecast.sh — Configuration Icecast2 (récepteur du flux Mixxx)
# Maître uniquement.
# Prérequis : WIFI_PASS.

setup_icecast() {
    hdr "Icecast2"

    # PiOS installe icecast2 avec ENABLE=false par sécurité — on le réveille
    sed -i 's/ENABLE=false/ENABLE=true/' /etc/default/icecast2 2>/dev/null || true

    # Remplacer le mot de passe par défaut 'hackme'
    sed -i "s|<source-password>hackme</source-password>|<source-password>${WIFI_PASS}</source-password>|" /etc/icecast2/icecast.xml
    sed -i "s|<relay-password>hackme</relay-password>|<relay-password>${WIFI_PASS}</relay-password>|"     /etc/icecast2/icecast.xml
    sed -i "s|<admin-password>hackme</admin-password>|<admin-password>${WIFI_PASS}</admin-password>|"     /etc/icecast2/icecast.xml

    systemctl enable --now icecast2
    log "Icecast2 activé (port 8111, mdp : ${WIFI_PASS})"
}
