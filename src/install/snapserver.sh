#!/bin/bash
# install/snapserver.sh — Snapcast serveur + décodeur ffmpeg (Icecast → PCM)
# Maître uniquement.

setup_snapserver() {
    hdr "Snapcast serveur"
    
    # Détection de l'utilisateur snapserver (souvent _snapserver sur Bookworm)
    SNAP_USER="snapserver"
    id _snapserver &>/dev/null && SNAP_USER="_snapserver"

    # 1. Droits d'accès
    usermod -aG audio "$SNAP_USER" || true

    # 2. Création immédiate
    mkfifo /dev/shm/snapfifo     2>/dev/null || true
    mkfifo /dev/shm/snapfifo_mic 2>/dev/null || true
    chown "$SNAP_USER:audio" /dev/shm/snapfifo*
    chmod 660 /dev/shm/snapfifo*

    # 3. Persistance au reboot
    cat > /etc/tmpfiles.d/soundspot-fifos.conf <<EOF
p /dev/shm/snapfifo     0660 $SNAP_USER audio -
p /dev/shm/snapfifo_mic 0660 $SNAP_USER audio -
EOF

    install_template snapserver.conf /etc/snapserver.conf

    # On s'assure que le service est bien redémarré avec les nouveaux droits de groupe
    systemctl daemon-reload
    systemctl enable snapserver
    systemctl restart snapserver
    log "Snapserver configuré (pipe PCM, port ${SNAPCAST_PORT})"

    hdr "Décodeur Icecast → Snapcast (ffmpeg)"

    install_template decoder.sh "$INSTALL_DIR/decoder.sh"
    chmod +x "$INSTALL_DIR/decoder.sh"

    install_template soundspot-decoder.service \
        /etc/systemd/system/soundspot-decoder.service \
        '${INSTALL_DIR}'

    systemctl enable soundspot-decoder
    systemctl restart soundspot-decoder
    log "Décodeur Icecast → Snapcast activé (ffmpeg)"
}