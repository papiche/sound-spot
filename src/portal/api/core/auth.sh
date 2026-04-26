#!/bin/bash
# api/core/auth.sh — Autorisation accès Internet 15 min
# Ajoute l'IP cliente dans ipset soundspot_auth (timeout 900s).
# Hérite des exports de api.sh.

CLIENT_IP="$REMOTE_ADDR"

# Validation stricte du format IPv4 (prévient l'injection dans ipset)
if [[ "$CLIENT_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    # Appel ipset en arrière-plan : réponse immédiate même sous charge (100+ festivaliers)
    (sudo /usr/sbin/ipset add soundspot_auth "$CLIENT_IP" timeout 900 -exist 2>/dev/null) &
    printf '{"status":"authorized","timeout":900,"ip":"%s"}\n' "$CLIENT_IP"
else
    printf '{"error":"no_ip"}\n'
fi
