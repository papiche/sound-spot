#!/bin/bash
hdr "Monitoring de la Batterie (INA219)"

# Création d'un environnement virtuel propre pour éviter --break-system-packages
apt-get install -y python3-venv
python3 -m venv ${INSTALL_DIR}/venv
${INSTALL_DIR}/venv/bin/pip install pi-ina219 2>/dev/null || true

cat > /etc/systemd/system/soundspot-battery.service <<EOF
[Unit]
Description=SoundSpot — Monitoring Batterie Solaire
After=soundspot-presence.service

[Service]
Type=simple
Environment="XDG_RUNTIME_DIR=/run/user/1000"
# Utilisation du Python de l'environnement virtuel
ExecStart=${INSTALL_DIR}/venv/bin/python ${INSTALL_DIR}/battery_monitor.py
Restart=always
RestartSec=60
User=${SOUNDSPOT_USER}
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF

# N'activer le service que si le script a été déployé
if [ -f "$INSTALL_DIR/battery_monitor.py" ]; then
    systemctl enable soundspot-battery
    log "Service soundspot-battery activé"
else
    warn "battery_monitor.py absent — monitoring désactivé"
fi