#!/bin/bash
# Forcer la reconnexion Bluetooth et le redémarrage du client audio
sudo /opt/soundspot/bt_manage.sh connect
echo '{"status":"ok","message":"Reconnexion Bluetooth lancée"}'