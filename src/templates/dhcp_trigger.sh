#!/bin/bash
# dhcp_trigger.sh — Appelé par dnsmasq à chaque événement DHCP
# Arguments transmis par dnsmasq : $1=action  $2=MAC  $3=IP  $4=hostname (optionnel)
#
# Stratégie : dès qu'un smartphone obtient son IP, on l'ajoute immédiatement
# à soundspot_auth (15 min) pour que ses tests de connectivité HTTPS réussissent.
# Ainsi le téléphone affiche "Connecté" (pas de rejet du hotspot) ET déclenche
# la fenêtre portail via l'interception du port 80 en parallèle.

case "$1" in
    add|old)
        /usr/sbin/ipset add soundspot_auth "$3" timeout 900 -exist 2>/dev/null || true
        ;;
    del)
        # On laisse le timeout ipset expirer naturellement (pas de suppression forcée)
        ;;
esac
