#!/bin/bash
setup_captive_portal() {
    hdr "Portail captif (Lighttpd)"

    # Autoriser www-data : ipset (portail captif) + scripts de configuration + admin BT
    USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
    cat > /etc/sudoers.d/soundspot-www <<SUDOEOF
www-data ALL=(ALL) NOPASSWD: /usr/sbin/ipset
www-data ALL=(ALL) NOPASSWD: /usr/sbin/batctl *
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/backend/system/set_clock_mode.sh
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/backend/system/set_voice_mode.sh
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/backend/system/set_bells_mode.sh
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/bt_manage.sh
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/backend/system/bt_connect_mac.sh
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/backend/system/set_bt_macs.sh
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/backend/system/print_ticket.sh
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/backend/system/bt-connect.sh
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart soundspot-idle
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart soundspot-decoder
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart snapserver
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart icecast2
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart soundspot-bt-reactive
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop soundspot-client
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart soundspot-client
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop snapserver
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop soundspot-decoder
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/backend/system/set_audio_output.sh *
www-data ALL=(ALL) NOPASSWD: /usr/sbin/poweroff
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl start soundspot-autodj
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop soundspot-autodj
www-data ALL=(${SOUNDSPOT_USER}) NOPASSWD: ${USER_HOME}/.zen/Astroport.ONE/IA/services/orpheus.me.sh
www-data ALL=(${SOUNDSPOT_USER}) NOPASSWD: ${USER_HOME}/.astro/bin/python3 ${USER_HOME}/.zen/Astroport.ONE/tools/nostr_send_note.py *
www-data ALL=(${SOUNDSPOT_USER}) NOPASSWD: /bin/bash ${INSTALL_DIR}/backend/audio/tts.sh *
www-data ALL=(${SOUNDSPOT_USER}) NOPASSWD: /usr/bin/python3 ${INSTALL_DIR}/backend/video/stream_commentator.py
SUDOEOF
    chmod 0440 /etc/sudoers.d/soundspot-www

    # Accès en écriture de www-data au log centralisé SoundSpot
    touch /var/log/sound-spot.log
    chown root:www-data /var/log/sound-spot.log
    chmod 664 /var/log/sound-spot.log

    # Configuration lighttpd — optimisée Pi Zero 2W
    # mod_accesslog retiré : évite un write SD par requête (trop cher sur petite machine)
    cat > /etc/lighttpd/lighttpd.conf <<EOF
server.modules = (
    "mod_access",
    "mod_alias",
    "mod_redirect",
    "mod_rewrite",
    "mod_cgi"
)
server.document-root        = "/var/www/html"
server.upload-dirs          = ( "/var/cache/lighttpd/uploads" )
server.errorlog             = "/var/log/lighttpd/error.log"
server.pid-file             = "/var/run/lighttpd.pid"
server.username             = "www-data"
server.groupname            = "www-data"
server.port                 = 80
server.follow-symlink       = "enable"
server.max-connections      = 16
server.max-keep-alive-requests = 4
server.max-keep-alive-idle  = 5
include_shell "/usr/share/lighttpd/create-mime.conf.pl"
cgi.assign                  = ( ".sh" => "/bin/bash" )

# Servir directement si l'hôte est une adresse IP ou le nom local du RPi.
# Sinon (domaine externe capturé par PREROUTING), rediriger vers le portail.
\$HTTP["host"] !~ "^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+|soundspot(\.local)?|raspberrypi(\.local)?)$" {
    url.redirect = ( ".*" => "http://${SPOT_IP}/" )
}

# Page d'accueil : index.html (SPA), fallback api.sh (CGI)
index-file.names = ( "index.html", "api.sh" )

# Exposer les fichiers wav (previews TTS depuis le portail)
alias.url = ( "/wav/" => "${INSTALL_DIR}/wav/" )

# Captiver les URL de test Android/Apple → api.sh répond en JSON
url.rewrite-once = (
    "^/(generate_204|hotspot-detect.html|ncsi.txt|success.txt).*$" => "/api.sh"
)
EOF

    # Lien symbolique : /var/www/html → $INSTALL_DIR/portal
    # Un simple `git pull` dans le dépôt source suffit à mettre le portail à jour.
    rm -rf /var/www/html
    ln -sfn "$INSTALL_DIR/portal" /var/www/html
    chmod +x /var/www/html/*.sh
    chmod +x /var/www/html/api/core/*.sh
    chmod +x /var/www/html/api/apps/*/run.sh 2>/dev/null || true
    log "Portail lié : /var/www/html → $INSTALL_DIR/portal"

    # Les scripts de config (set_*_mode.sh, bt_connect_mac.sh, set_bt_macs.sh)
    # sont déjà copiés dans $INSTALL_DIR/backend/system/ par install_soundspot.sh.
    # On s'assure qu'ils sont exécutables.
    chmod +x "$INSTALL_DIR/backend/system/"set_clock_mode.sh \
             "$INSTALL_DIR/backend/system/"set_voice_mode.sh \
             "$INSTALL_DIR/backend/system/"set_bells_mode.sh \
             "$INSTALL_DIR/backend/system/"bt_connect_mac.sh \
             "$INSTALL_DIR/backend/system/"set_bt_macs.sh \
             2>/dev/null || true
    log "Scripts config backend/system/ marqués exécutables"

    # Activer explicitement le module CGI dans Debian
    lighttpd-enable-mod cgi 2>/dev/null || true
    systemctl restart lighttpd
    systemctl enable lighttpd
    log "Portail captif Lighttpd configuré"

    # Donner accès à www-data pour le dossier Jukebox dans ~/.zen/tmp
    usermod -aG ${SOUNDSPOT_USER} www-data
    usermod -aG gpio www-data 2>/dev/null || true

    local USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
    chmod g+x "$USER_HOME" 2>/dev/null || true
    chmod g+rx "$USER_HOME/.zen" "$USER_HOME/.zen/tmp" 2>/dev/null || true

    # Droits d'écriture www-data sur les messages du clocher (textes + wav)
    chown -R www-data:www-data "$INSTALL_DIR/wav" 2>/dev/null || \
        chmod g+rw "$INSTALL_DIR/wav" 2>/dev/null || true
    log "Droits www-data sur wav/ configurés"

    # Scripts portal/api/apps exécutables
    chmod +x "$INSTALL_DIR/portal/api/apps/messages/run.sh" 2>/dev/null || true
}