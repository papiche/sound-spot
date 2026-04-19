#!/bin/bash
# dhcp_trigger.sh — Appelé par dnsmasq à chaque événement DHCP
# Arguments transmis par dnsmasq : $1=action  $2=MAC  $3=IP  $4=hostname

case "$1" in
    add|old)
        # Dès qu'un appareil reçoit une IP, on l'ajoute à la liste blanche
        # temporaire pour permettre les tests de connectivité (Google/Apple).
        /usr/sbin/ipset add soundspot_auth "$3" timeout 900 -exist 2>/dev/null || true
        ;;
    del)
        # On laisse le timeout expirer seul
        ;;
esac