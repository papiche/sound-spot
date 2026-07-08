#!/bin/bash
setup_video_rtmp() {
    hdr "Pont Vidéo RTMP et Régie VJ"

    cat > /etc/nginx/nginx.conf << 'NGINXEOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;
events { worker_connections 768; }

rtmp {
    server {
        listen 1935;
        chunk_size 4096;
        application live {
            live on;
            record off;
            # 192.168.10.0/24 = AP 2,4GHz | 192.168.11.0/24 = AP5G (si AP5G_ENABLED) | 10.200.0.0/16 = mesh
            allow publish 192.168.10.0/24;
            allow publish 192.168.11.0/24;
            allow publish 10.200.0.0/16;
            allow publish 127.0.0.1;
            deny publish all;
            allow play all;
            
            # Appels dynamiques à chaque nouveau flux
            exec_publish /opt/soundspot/backend/video/stream_event.sh start $name;
            exec_publish_done /opt/soundspot/backend/video/stream_event.sh stop $name;
        }
    }
}
NGINXEOF

    rm -f /etc/nginx/sites-enabled/default
    systemctl restart nginx
    systemctl enable nginx
    install_template soundspot-rtmp-player.service /etc/systemd/system/soundspot-rtmp-player.service '${INSTALL_DIR} ${SOUNDSPOT_USER}'
    systemctl enable soundspot-rtmp-player
    log "Lecteur vidéo HDMI (MPV) activé"
    log "Serveur RTMP vidéo (Régie VJ) activé sur le port 1935"
}
