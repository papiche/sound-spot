#!/bin/bash
# fix_wifi_dongle.sh — Remplace le driver noyau instable rtw_8822bu (RTL8822BU, 0bda:b812)
# par le driver DKMS morrownr/88x2bu-20210702, plus stable en mode AP.
#
# Outil de RÉPARATION pour un nœud déjà déployé (ex : régression après mise à
# jour noyau qui invalide le module DKMS). Pour une installation neuve, ce même
# driver est déjà géré automatiquement par src/install/wifi_driver.sh
# (_install_rtl88x2bu, mêmes chipsets 0bda:b812 et consorts).
#
# Usage : sudo bash fix_wifi_dongle.sh
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Lancez avec sudo : sudo bash $0"; exit 1; }

if dkms status 2>/dev/null | grep -q "88x2bu.*installed"; then
    echo "✓ Pilote 88x2bu déjà installé et actif dans DKMS — rien à faire."
    echo "  (si le dongle reste instable, vérifiez plutôt les options dans /etc/modprobe.d/88x2bu.conf)"
    exit 0
fi

echo "▶ 1/6 Dépendances..."
apt-get update -qq
apt-get install -y dkms build-essential bc git

echo "▶ 2/6 Kernel headers..."
KVER=$(uname -r)
if [ -d "/lib/modules/${KVER}/build" ]; then
    echo "  Kernel headers déjà présents pour ${KVER} ✓"
else
    # Paquet exact du noyau en cours en priorité — évite de tirer linux-headers-rpi-v8
    # (méta-paquet qui upgrade le noyau entier et peut échouer si /var/tmp est plein)
    apt-get install -y "linux-headers-${KVER}" || apt-get install -y raspberrypi-kernel-headers
fi

echo "▶ 3/6 Clonage + compilation morrownr/88x2bu (5-20 min sur Zero 2W, ne débranchez pas)..."
cd /tmp
rm -rf 88x2bu-20210702
git clone --depth 1 https://github.com/morrownr/88x2bu-20210702.git
cd 88x2bu-20210702
./install-driver.sh NoPrompt

echo "▶ 4/6 Vérification DKMS..."
dkms status | grep 88x2bu || { echo "✗ Échec DKMS — voir les logs ci-dessus."; exit 1; }

echo "▶ 5/6 Options driver (désactive power management agressif)..."
echo "options 88x2bu rtw_power_mgnt=0 rtw_enusbss=0" > /etc/modprobe.d/88x2bu.conf

echo "▶ 6/6 Nettoyage..."
cd /tmp && rm -rf 88x2bu-20210702

echo ""
echo "✓ Installation terminée. Redémarrage dans 10s — Ctrl+C pour annuler."
sleep 10
reboot
