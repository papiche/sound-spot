#!/bin/bash
setup_captive_portal() {
    hdr "Portail captif (Lighttpd)"

    # Autoriser www-data : ipset (portail captif) + set_clock_mode (toggle horloge) + bt_manage.sh
    USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
    cat > /etc/sudoers.d/soundspot-www <<SUDOEOF
www-data ALL=(ALL) NOPASSWD: /usr/sbin/ipset
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/set_clock_mode.sh
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/set_voice_mode.sh
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/set_bells_mode.sh
www-data ALL=(ALL) NOPASSWD: /opt/soundspot/bt_manage.sh
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop soundspot-client
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop snapserver
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop soundspot-decoder
www-data ALL=(ALL) NOPASSWD: /usr/sbin/poweroff
www-data ALL=(${SOUNDSPOT_USER}) NOPASSWD: ${USER_HOME}/.zen/Astroport.ONE/IA/orpheus.me.sh
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
    "^/(generate_204|hotspot-detect.html|ncsi.txt|success.txt).*$" => "/index.sh"
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

    # Scripts root pour modification de soundspot.conf depuis le portail
    install_template set_clock_mode.sh "$INSTALL_DIR/set_clock_mode.sh"
    chmod +x "$INSTALL_DIR/set_clock_mode.sh"
    install_template set_voice_mode.sh "$INSTALL_DIR/set_voice_mode.sh"
    chmod +x "$INSTALL_DIR/set_voice_mode.sh"
    install_template set_bells_mode.sh "$INSTALL_DIR/set_bells_mode.sh"
    chmod +x "$INSTALL_DIR/set_bells_mode.sh"
    log "set_clock_mode.sh + set_voice_mode.sh + set_bells_mode.sh déployés"

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
}