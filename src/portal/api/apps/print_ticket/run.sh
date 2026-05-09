#!/bin/bash
# API : Déclenche le script d'impression du système
# Appel depuis le navigateur : /api.sh?action=print_ticket

# On appelle un script externe via sudo pour avoir les droits sur l'USB
sudo /opt/soundspot/backend/system/print_ticket.sh > /dev/null 2>&1 &

echo '{"status": "ok", "message": "Impression déclenchée en tâche de fond"}'