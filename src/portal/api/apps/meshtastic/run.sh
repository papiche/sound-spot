#!/bin/bash
# Reçoit du texte depuis le portail captif et le balance sur Meshtastic
read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
TEXT=$(echo "$POST_DATA" | grep -oP '(?<=text=)[^&]+' | urldecode)
if [ -z "$TEXT" ]; then
    echo '{"error":"empty_text","hint":"Aucun message à diffuser"}'
    exit 0
fi
/home/${SOUNDSPOT_USER:-pi}/.astro/bin/meshtastic --sendtext "🐷 Cochon: $TEXT" > /dev/null
echo '{"status":"ok", "message":"Message diffusé sur LoRa"}'
