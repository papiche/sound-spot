#!/bin/bash
# install/pipewire.sh — Session PipeWire persistante (user pi)
# Partagé entre maître et satellite.

setup_pipewire() {
    hdr "PipeWire session persistante (user ${SOUNDSPOT_USER})"
    
    # 1. Forcer le linger pour l'utilisateur pi
    loginctl enable-linger "${SOUNDSPOT_USER}"
    
    # 2. Installer les paquets nécessaires pour le mode système si besoin
    # Mais surtout activer les unités user au niveau global
    systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service
    
    # 3. Créer le dossier config pour le null-sink
    mkdir -p /etc/pipewire/pipewire.conf.d
    install_template pipewire-soundspot-null.conf \
        /etc/pipewire/pipewire.conf.d/50-soundspot-null.conf
    
    # 4. FIX : S'assurer que PipeWire démarre AVANT que le client ne le cherche
    # On force le démarrage immédiat pour l'UID 1000
    sudo -u ${SOUNDSPOT_USER} XDG_RUNTIME_DIR=/run/user/${SOUNDSPOT_UID} systemctl --user start pipewire.socket wireplumber
    
    log "PipeWire configuré globalement."
}
