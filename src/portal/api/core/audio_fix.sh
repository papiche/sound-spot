#!/bin/bash
# Forcer la reconnexion Bluetooth et le redémarrage du client audio
_SS_SERVICE="portal-audio-fix"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

sudo /opt/soundspot/bt_manage.sh connect
echo '{"status":"ok","message":"Reconnexion Bluetooth lancée"}'