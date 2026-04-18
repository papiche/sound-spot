#!/bin/bash
# picoport_cron_control.sh

# 20:12 Solaire par défaut si pas de GPS
SOLAR_TIME="12 20"

if [[ -s ~/.zen/GPS ]]; then
    source ~/.zen/GPS
    # Utilise l'outil Astroport pour convertir l'heure solaire en heure légale
    SOLAR_TIME=$(~/.zen/Astroport.ONE/tools/solar_time.sh "$LAT" "$LON" 2>/dev/null | tail -n 1)
fi

# Mise à jour de la crontab
(crontab -l 2>/dev/null | grep -v "picoport_20h12.sh" ; \
 echo "$SOLAR_TIME * * * /bin/bash /opt/soundspot/picoport/picoport_20h12.sh") | crontab -

echo "⏰ Cron Picoport aligné sur 20h12 Solaire ($SOLAR_TIME légal)"