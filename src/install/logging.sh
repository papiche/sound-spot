#!/bin/bash
# install/logging.sh — Système de logs centralisés SoundSpot
# À sourcer par install_soundspot.sh (après colors.sh).
# Exporte la fonction : setup_logging()

setup_logging() {
    hdr "Logs centralisés (/var/log/sound-spot.log)"

    # 1. Créer le fichier log accessible à tous les services (world-writable :
    #    les scripts tournent en $SOUNDSPOT_USER, pas en root)
    if [ ! -f /var/log/sound-spot.log ]; then
        install -m 666 /dev/null /var/log/sound-spot.log
        log "Fichier /var/log/sound-spot.log créé"
    else
        chmod 666 /var/log/sound-spot.log
    fi

    # 2. Bibliothèque bash log.sh → INSTALL_DIR (sourcée par tous les scripts)
    install_template log.sh "$INSTALL_DIR/log.sh"
    chmod 644 "$INSTALL_DIR/log.sh"
    log "log.sh installé → $INSTALL_DIR/log.sh"

    # 3. rsyslog — collecte journald (SyslogIdentifier soundspot-*) → fichier
    if dpkg-query -W rsyslog >/dev/null 2>&1; then
        install_template soundspot-rsyslog.conf /etc/rsyslog.d/40-soundspot.conf
        systemctl restart rsyslog 2>/dev/null \
            && log "rsyslog rechargé — journald soundspot-* → /var/log/sound-spot.log" \
            || warn "rsyslog non disponible — logs journald uniquement"
    else
        warn "rsyslog absent — journald uniquement (les logs bash restent dans le fichier)"
    fi

    # 4. logrotate — rotation quotidienne, 7 jours, compression
    install_template soundspot-logrotate /etc/logrotate.d/sound-spot
    log "logrotate configuré (daily, 7j, compress)"

    log "Logs centralisés OK — niveau : ${LOG_LEVEL:-INFO}"
    log "  tail -f /var/log/sound-spot.log"
    log "  journalctl -fu soundspot-\\* -fu picoport -fu ipfs"
}
