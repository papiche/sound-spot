#!/bin/bash
# sync_channel.sh — Met à jour le canal hostapd pour qu'il corresponde
# au canal réel du réseau amont (lu depuis wlan0 connecté).

source /opt/soundspot/soundspot.conf 2>/dev/null || true

log() { echo "[sync_channel] $*"; }

# Attendre que wlan0 soit associé au réseau amont (max 60 s)
for i in $(seq 1 30); do
    iwgetid wlan0 --raw 2>/dev/null | grep -q . && break
    sleep 2
done

# Lire le canal courant de wlan0 (= canal effectif du réseau amont)
CHANNEL=$(iw dev wlan0 info 2>/dev/null | awk '/channel/{print $2; exit}')

if [ -z "$CHANNEL" ]; then
    log "Canal non détecté — hostapd.conf inchangé"
    exit 0
fi

CURRENT=$(grep "^channel=" /etc/hostapd/hostapd.conf 2>/dev/null | cut -d= -f2)

if [ "$CHANNEL" = "$CURRENT" ]; then
    log "Canal ${CHANNEL} déjà correct — aucun changement"
    exit 0
fi

log "Canal ${WIFI_SSID:-réseau amont} : ${CURRENT:-?} → ${CHANNEL} — mise à jour hostapd.conf"
sed -i "s/^channel=.*/channel=${CHANNEL}/" /etc/hostapd/hostapd.conf
