#!/bin/bash
setup_respeaker() {
    hdr "Installation Driver ReSpeaker 2-Mics"

    # Dépendances pour la compilation des modules noyau
    apt_retry install -y raspberrypi-kernel-headers git bc

    # Clone du driver (version communautaire souvent plus à jour pour Bookworm/6.x)
    cd /tmp
    git clone --depth 1 https://github.com/respeaker/seeed-voicecard
    cd seeed-voicecard
    
    # Installation
    sudo ./install.sh
    
    # Forcer l'activation dans config.txt si l'installeur Seeed échoue
    if ! grep -q "seeed-2mic-voicecard" /boot/firmware/config.txt; then
        echo "dtoverlay=seeed-2mic-voicecard" | sudo tee -a /boot/firmware/config.txt
    fi
    
    log "Driver ReSpeaker installé. Reboot requis pour activer le module noyau."
}