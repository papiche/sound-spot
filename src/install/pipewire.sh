#!/bin/bash
# install/pipewire.sh — Configuration de PipeWire en mode persistant

setup_pipewire() {
    hdr "PipeWire session persistante (user ${SOUNDSPOT_USER})"
    
    # 1. Activer le Linger (fondation de la persistance au boot)
    loginctl enable-linger "${SOUNDSPOT_USER}"

    # 2. Préparer le répertoire Runtime (indispensable pour que PipeWire communique)
    # PAM le crée normalement à la connexion, mais on force sa création pour le script
    local RUNTIME_DIR="/run/user/${SOUNDSPOT_UID}"
    if [ ! -d "$RUNTIME_DIR" ]; then
        mkdir -p "$RUNTIME_DIR"
        chown "${SOUNDSPOT_USER}:${SOUNDSPOT_USER}" "$RUNTIME_DIR"
        chmod 700 "$RUNTIME_DIR"
    fi

    # 3. Installer la configuration du Null-Sink (Sortie de secours)
    # Cela garantit que le système audio ne "disparaît" pas si le Bluetooth coupe
    mkdir -p /etc/pipewire/pipewire.conf.d
    install_template pipewire-soundspot-null.conf \
        /etc/pipewire/pipewire.conf.d/50-soundspot-null.conf

    # 4. Activation des services au niveau utilisateur
    # On définit XDG_RUNTIME_DIR pour que systemctl puisse trouver le bus systemd de l'utilisateur
    local AS_USER="sudo -u ${SOUNDSPOT_USER} XDG_RUNTIME_DIR=${RUNTIME_DIR}"

    log "Activation des services systemd utilisateur..."
    
    # On utilise un "mask" préventif sur Pulseaudio système pour éviter les conflits
    systemctl --global mask pulseaudio.service pulseaudio.socket 2>/dev/null || true

    # Activation (enable)
    $AS_USER systemctl --user enable pipewire.service pipewire-pulse.service wireplumber.service
    
    # Démarrage immédiat (start) pour que la suite de l'installation puisse tester le son
    $AS_USER systemctl --user start pipewire.service pipewire-pulse.service wireplumber.service

    log "PipeWire est configuré et démarré pour l'utilisateur ${SOUNDSPOT_USER}."
}