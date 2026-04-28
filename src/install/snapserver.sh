#!/bin/bash
# install/snapserver.sh — Snapcast serveur + décodeur ffmpeg (Icecast → PCM)
# Maître uniquement.

setup_snapserver() {
    hdr "Snapcast serveur"
    
    # Détection de l'utilisateur snapserver
    SNAP_USER="snapserver"
    id _snapserver &>/dev/null && SNAP_USER="_snapserver"

    # 1. Droits d'accès
    usermod -aG audio "$SNAP_USER" || true

    # 2. Création immédiate avec droits permissifs (0666)
    # On supprime d'abord au cas où c'est un reliquat mal configuré
    rm -f /dev/shm/snapfifo /dev/shm/snapfifo_mic
    mkfifo /dev/shm/snapfifo     2>/dev/null || true
    mkfifo /dev/shm/snapfifo_mic 2>/dev/null || true
    
    # CRITIQUE : 666 pour permettre à TOUT LE MONDE d'écrire/lire (ffmpeg + snapserver)
    chmod 0666 /dev/shm/snapfifo*
    chown root:audio /dev/shm/snapfifo*

    # 3. Persistance au reboot via systemd-tmpfiles
    cat > /etc/tmpfiles.d/soundspot-fifos.conf <<EOF
p /dev/shm/snapfifo     0666 root audio -
p /dev/shm/snapfifo_mic 0666 root audio -
EOF

    install_template snapserver.conf /etc/snapserver.conf

    # Appliquer la config tmpfiles immédiatement
    systemd-tmpfiles --create /etc/tmpfiles.d/soundspot-fifos.conf

    systemctl daemon-reload
    systemctl enable snapserver
    systemctl restart snapserver
    log "Snapserver configuré (pipe PCM, port ${SNAPCAST_PORT})"

    # Installation de Snapweb
    if [ ! -d "/usr/share/snapserver/snapweb" ]; then
        log "Téléchargement et installation de Snapweb..."
        mkdir -p /usr/share/snapserver/snapweb
        wget -qO /tmp/snapweb.zip https://github.com/snapcast/snapweb/releases/download/v0.9.3/snapweb.zip || true
        if [ -s /tmp/snapweb.zip ]; then
            unzip -qo /tmp/snapweb.zip -d /usr/share/snapserver/snapweb/ 2>/dev/null || python3 -m zipfile -e /tmp/snapweb.zip /usr/share/snapserver/snapweb/ || true
            rm -f /tmp/snapweb.zip
            log "Snapweb installé dans /usr/share/snapserver/snapweb"
        else
            warn "Échec du téléchargement de Snapweb"
        fi
    fi

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