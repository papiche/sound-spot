#!/bin/bash
# install/snapserver.sh — Snapcast serveur + décodeur ffmpeg (Icecast → PCM)
# Maître uniquement.
# Prérequis : INSTALL_DIR, SNAPCAST_PORT.

setup_snapserver() {
    hdr "Snapcast serveur"

    mkfifo /tmp/snapfifo 2>/dev/null || true

    install_template snapserver.conf /etc/snapserver.conf

    systemctl enable snapserver
    log "Snapserver configuré (pipe PCM, port ${SNAPCAST_PORT})"

    hdr "Décodeur Icecast → Snapcast (ffmpeg)"

    install_template decoder.sh "$INSTALL_DIR/decoder.sh"
    chmod +x "$INSTALL_DIR/decoder.sh"

    install_template soundspot-decoder.service \
        /etc/systemd/system/soundspot-decoder.service \
        '${INSTALL_DIR}'

    systemctl enable soundspot-decoder
    log "Décodeur Icecast → Snapcast activé (ffmpeg)"
}
