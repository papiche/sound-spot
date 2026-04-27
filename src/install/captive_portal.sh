#!/bin/bash
setup_captive_portal() {
    hdr "Portail captif (Lighttpd)"

    # Autoriser www-data : ipset (portail captif) + scripts de configuration + admin BT
    USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
    cat > /etc/sudoers.d/soundspot-www <<SUDOEOF
www-data ALL=(ALL) NOPASSWD: /usr/sbin/ipset
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/backend/system/set_clock_mode.sh
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/backend/system/set_voice_mode.sh
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/backend/system/set_bells_mode.sh
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/bt_manage.sh
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/backend/system/bt_connect_mac.sh
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/backend/system/set_bt_macs.sh
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart soundspot-idle
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart soundspot-decoder
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart snapserver
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart icecast2
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart soundspot-bt-reactive
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop soundspot-client
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop snapserver
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop soundspot-decoder
www-data ALL=(ALL) NOPASSWD: /usr/sbin/poweroff
www-data ALL=(${SOUNDSPOT_USER}) NOPASSWD: ${USER_HOME}/.zen/Astroport.ONE/IA/orpheus.me.sh
www-data ALL=(${SOUNDSPOT_USER}) NOPASSWD: ${USER_HOME}/.astro/bin/python3 ${USER_HOME}/.zen/Astroport.ONE/tools/nostr_send_note.py *
SUDOEOF
    chmod 0440 /etc/sudoers.d/soundspot-www

    # Configuration lighttpd
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
include_shell "/usr/share/lighttpd/create-mime.conf.pl"
cgi.assign                  = ( ".sh" => "/bin/bash" )

# Servir directement si l'hôte est une adresse IP ou le nom local du RPi.
# Sinon (domaine externe capturé par PREROUTING), rediriger vers le portail.
# Cela permet de tester le portail depuis qo-op (http://soundspot.local/ ou http://<IP wlan0>/)
\$HTTP["host"] !~ "^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+|soundspot(\.local)?|raspberrypi(\.local)?)$" {
    url.redirect = ( ".*" => "http://${SPOT_IP}/index.sh" )
}

# Assigner index.html en priorité (SPA statique), puis index.sh (fallback CGI)
index-file.names = ( "index.html", "index.sh" )

# Servir les fichiers .json comme JSON (manifest PWA)

# Capturer les URL de test Android/Apple
url.rewrite-once = (
    "^/(generate_204|hotspot-detect.html|ncsi.txt|success.txt).*$" => "/index.sh",
    "^/pinout/([^/.]+)$"                                            => "/pinout/\$1.html"
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