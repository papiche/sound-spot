#!/bin/bash
# soundspot-uap0-mac.sh — Applique sur uap0 un MAC localement administré dérivé de wlan0.
# IEEE 802 : bit 1 du premier octet = "locally administered", bit 0 = "unicast" (cleared).
IFACE="uap0"
[ -e /sys/class/net/$IFACE ] || exit 0

MAC_WAN=$(cat /sys/class/net/wlan0/address 2>/dev/null) || exit 0
IFS=':' read -ra OCTETS <<< "$MAC_WAN"
FIRST=$(( (16#${OCTETS[0]} | 2) & 254 ))
OCTETS[0]=$(printf '%02x' "$FIRST")
NEW_MAC=$(IFS=':'; echo "${OCTETS[*]}")

# Procédure sécurisée : DOWN -> SET -> UP
/sbin/ip link set dev $IFACE down
/sbin/ip link set dev $IFACE address "$NEW_MAC"
/sbin/ip link set dev $IFACE up
