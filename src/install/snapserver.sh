#!/bin/bash
# install/snapserver.sh — Snapcast serveur + décodeur ffmpeg (Icecast → PCM)
# Maître uniquement.

setup_snapserver() {
    hdr "Snapcast serveur"
    
    # 1. Droits d'accès : snapserver doit pouvoir lire les FIFOs du groupe audio
    id snapserver &>/dev/null && usermod -aG audio snapserver || true

    # 2. Création immédiate pour la session actuelle
    mkfifo /dev/shm/snapfifo     2>/dev/null || true
    mkfifo /dev/shm/snapfifo_mic 2>/dev/null || true
    
    # Correction CRITIQUE : on applique les droits tout de suite
    chgrp audio /dev/shm/snapfifo* 2>/dev/null || true
    chmod 660 /dev/shm/snapfifo*   2>/dev/null || true

    # 3. Persistance au reboot (Gestionnaire de fichiers temporaires systemd)
    cat > /etc/tmpfiles.d/soundspot-fifos.conf <<'TMPEOF'
p /dev/shm/snapfifo     0660 root audio -
p /dev/shm/snapfifo_mic 0660 root audio -
TMPEOF

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