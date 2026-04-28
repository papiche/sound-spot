#!/bin/bash
########################################################################
# SYSPREP SOUNDSPOT / ASTROPORT.ONE — Version "Golden Image"
########################################################################
set -e

# Couleurs
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; N='\033[0m'

echo -e "${R}⚠️  DANGER : Ce script va EFFACER l'identité unique de ce nœud.${N}"
read -p "Confirmer la création de l'image de distribution ? (OUI/non) : " CONFIRM
[ "$CONFIRM" != "OUI" ] && exit 1

# 1. Arrêt des services SoundSpot et Astroport
echo -e "${G}▶ 1. Arrêt des services...${N}"
SERVICES="soundspot-ap hostapd dnsmasq icecast2 snapserver soundspot-decoder soundspot-client soundspot-idle picoport ipfs upassport"
sudo systemctl stop $SERVICES 2>/dev/null || true

# 2. Nettoyage Identité SoundSpot (Config locale)
echo -e "${G}▶ 2. Reset de la configuration locale...${N}"
if [ -f /opt/soundspot/soundspot.conf ]; then
    # On garde le fichier mais on vide les variables d'identité
    sudo sed -i 's/^BT_MAC=.*/BT_MAC=""/' /opt/soundspot/soundspot.conf
    sudo sed -i 's/^BT_MACS=.*/BT_MACS=""/' /opt/soundspot/soundspot.conf
    sudo sed -i 's/^SPOT_NAME=.*/SPOT_NAME="ZICMAMA"/' /opt/soundspot/soundspot.conf
fi
sudo rm -f /var/log/sound-spot.log
sudo rm -rf /tmp/snapfifo

# 3. Nettoyage Astroport / Picoport
echo -e "${G}▶ 3. Purge des clés cryptographiques...${N}"
rm -rf ~/.zen/game/*
rm -rf ~/.zen/tmp/*
rm -f ~/.zen/GPS ~/.zen/♥Box ~/.zen/IPCity ~/.zen/.env

# 4. Reset IPFS (Crucial pour le PeerID)
echo -e "${G}▶ 4. Reset IPFS...${N}"
rm -rf ~/.ipfs
# On n'initie pas ici, on laisse le premier boot du client le faire pour garantir l'aléa

# 5. Nettoyage Système et Réseau
echo -e "${G}▶ 5. Nettoyage identité Linux...${N}"
sudo rm -f /etc/ssh/ssh_host_*
sudo rm -rf ~/.ssh/*
sudo truncate -s 0 /etc/machine-id
[ -f /var/lib/dbus/machine-id ] && sudo rm -f /var/lib/dbus/machine-id

# Nettoyage des baux DHCP et WiFi
sudo rm -f /var/lib/misc/dnsmasq.leases
sudo rm -f /etc/wpa_supplicant/wpa_supplicant-wlan0.conf

# 6. Ménage Logs et Cache
echo -e "${G}▶ 6. Purge des logs et de l'historique...${N}"
sudo apt-get clean
sudo journalctl --vacuum-time=1s
sudo rm -rf /var/log/*.gz /var/log/*.[0-9]
cat /dev/null > ~/.bash_history
history -c

echo -e "\n${Y}✅ PRÊT POUR LE CLONAGE.${N}"
echo -e "1. Éteignez : ${W}sudo /usr/sbin/poweroff${N}"
echo -e "2. Retirez la carte SD et insérez-la dans votre PC."
echo -e "3. Compressez avec PiShrink : ${G}sudo ./pishrink.sh -z -a soundspot_v2.img${N}\n"