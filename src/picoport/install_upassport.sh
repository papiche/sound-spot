#!/bin/bash
set -e

[ "$(id -u)" -eq 0 ] || { echo "Ce script doit être lancé en root"; exit 1; }

INSTALL_DIR="/opt/soundspot"
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)

echo "🚀 Installation UPassport Light pour Picoport..."

# 1 à 3 : Toutes les actions fichiers/python doivent se faire via sudo -u
sudo -u "$SOUNDSPOT_USER" bash -c "
    mkdir -p '$USER_HOME/.zen'
    cd '$USER_HOME/.zen'
    if [ ! -d 'UPassport' ]; then
        git clone --depth 1 https://github.com/papiche/UPassport.git
    else
        cd UPassport && git pull && cd ..
    fi

    source '$USER_HOME/.astro/bin/activate'
    pip install -U -r UPassport/requirements.txt

    cat > '$USER_HOME/.zen/UPassport/.env' <<EOL
myDUNITER=\"https://g1.cgeek.fr\"
myCESIUM=\"https://g1.data.e-is.pro\"
EOL
"

# 4. Service Systemd UPassport
cat > /etc/systemd/system/upassport.service <<EOF
[Unit]
Description=UPassport API - Picoport Edition
After=network.target

[Service]
Type=simple
User=$SOUNDSPOT_USER
WorkingDirectory=$USER_HOME/.zen/UPassport
ExecStart=$USER_HOME/.astro/bin/python3 -m uvicorn main:app --host 0.0.0.0 --port 54321
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now upassport
echo "✅ UPassport installé et démarré sur le port 54321"