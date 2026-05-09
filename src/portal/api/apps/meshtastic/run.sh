#!/bin/bash
# Reçoit du texte depuis le portail captif et le balance sur Meshtastic
TEXT=$(echo "$POST_DATA" | grep -oP '(?<=text=)[^&]+' | urldecode)
/home/${SOUNDSPOT_USER:-pi}/.astro/bin/meshtastic --sendtext "🐷 Cochon: $TEXT" > /dev/null
echo '{"status":"ok", "message":"Message diffusé sur LoRa"}'
