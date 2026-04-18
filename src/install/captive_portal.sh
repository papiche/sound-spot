#!/bin/bash
setup_captive_portal() {
    hdr "Portail captif (Lighttpd)"

    # Autoriser www-data à utiliser ipset sans mot de passe
    echo "www-data ALL=(ALL) NOPASSWD: /usr/sbin/ipset" > /etc/sudoers.d/soundspot-www
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
cgi.assign                  = ( ".sh" => "/bin/bash" )

# Servir directement si l'hôte est une adresse IP ou le nom local du RPi.
# Sinon (domaine externe capturé par PREROUTING), rediriger vers le portail.
# Cela permet de tester le portail depuis qo-op (http://soundspot.local/ ou http://<IP wlan0>/)
\$HTTP["host"] !~ "^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+|soundspot(\.local)?|raspberrypi(\.local)?)$" {
    url.redirect = ( ".*" => "http://${SPOT_IP}/index.sh" )
}

# Assigner index.sh par défaut
index-file.names = ( "index.sh" )

# Capturer les URL de test Android/Apple
url.rewrite-once = (
    "^/(generate_204|hotspot-detect.html|ncsi.txt|success.txt).*$" => "/index.sh"
)
EOF

    # Installer les pages du portail
    install_template portal_index.sh /var/www/html/index.sh \
        '${SPOT_NAME} ${SPOT_IP} ${SNAPCAST_PORT} ${ICECAST_PORT} ${ICECAST_PASS}'
    install_template portal_auth.sh /var/www/html/auth.sh
    install_template portal_docs.sh /var/www/html/docs.sh

    chmod +x /var/www/html/index.sh
    chmod +x /var/www/html/auth.sh
    chmod +x /var/www/html/docs.sh
    
    systemctl restart lighttpd
    systemctl enable lighttpd
    log "Portail captif Lighttpd configuré"
}