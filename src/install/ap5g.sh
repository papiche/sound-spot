#!/bin/bash
# install/ap5g.sh — AP 5GHz bi-bande sur dongle USB Wi-Fi (même SSID que l'AP visiteurs)
#
# Alternative à mesh_batman.sh pour un dongle non dédié au mesh : au lieu de
# servir de relais vers des satellites distants, la radio 5GHz renforce l'AP
# ${SPOT_NAME} pour les visiteurs déjà à portée (meilleur débit, moins
# d'interférences 2,4GHz). Mutuellement exclusif avec le mesh — un seul
# dongle ne peut pas être à la fois en IBSS (mesh) et en AP (ce module).
#
# Sous-réseau distinct de l'AP 2,4GHz (routé par le Pi, pas de bridge entre
# les deux radios — même principe que le mesh B.A.T.M.A.N. sur 10.200.0.0/16).
# Réutilise la détection de chipset/driver de wifi_driver.sh (sourcé avant ce
# module dans install_soundspot.sh).

setup_ap5g() {
    hdr "AP 5GHz bi-bande (dongle USB Wi-Fi)"

    local chipset
    chipset=$(_detect_usb_chipset)
    if [ -z "$chipset" ]; then
        warn "Aucun dongle Wi-Fi 5GHz reconnu — AP 5GHz désactivé (AP visiteurs 2,4GHz uniquement)."
        export AP5G_ENABLED="false"
        return 0
    fi
    log "Chipset détecté : ${chipset}"

    case "$chipset" in
        rtl88x2bu) _install_rtl88x2bu ;;
        rtl8812au) _install_rtl8812au ;;
        mt7612u|mt7921au) _install_mt76 "$chipset" ;;
    esac

    # Interface dédiée au dongle : ni wlan0 (puce interne) ni l'interface WAN actuelle.
    IFACE_AP5G=$(ip -o link show | awk -F': ' '{print $2}' | grep -E "^(wlan|wlx)" \
        | grep -v "^wlan0$" | grep -vF "${IFACE_WAN}" | head -n 1)
    if [ -z "$IFACE_AP5G" ]; then
        warn "Dongle détecté mais aucune interface wlan* disponible — AP 5GHz désactivé."
        export AP5G_ENABLED="false"
        return 0
    fi
    export IFACE_AP5G
    log "Interface AP 5GHz : ${IFACE_AP5G}"

    # Service : monte l'interface + assigne l'IP avant hostapd/dnsmasq.
    # Copie brute (pas d'envsubst) : ${IFACE_AP5G}/${AP5G_IP} doivent rester littéraux
    # dans le fichier unit, résolus à CHAQUE démarrage via EnvironmentFile=soundspot.conf
    # — même mécanisme que soundspot-ap.service (voir CLAUDE.md, note IFACE_AP/IFACE_WAN).
    install_template soundspot-ap5g.service /etc/systemd/system/soundspot-ap5g.service
    systemctl daemon-reload
    systemctl enable soundspot-ap5g

    # hostapd : une seule instance peut gérer plusieurs interfaces (plusieurs
    # fichiers de config passés en argument) — pas besoin d'un second service.
    install_template hostapd-ap5g.conf /etc/hostapd/hostapd-ap5g.conf \
        '${IFACE_AP5G} ${SPOT_NAME}'
    sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf /etc/hostapd/hostapd-ap5g.conf"|' \
        /etc/default/hostapd

    # dnsmasq : fragment /etc/dnsmasq.d/ (conf-dir activé dans le dnsmasq.conf de base)
    install_template dnsmasq-ap5g.conf /etc/dnsmasq.d/soundspot-ap5g.conf \
        '${IFACE_AP5G} ${AP5G_DHCP_START} ${AP5G_DHCP_END}'

    log "AP 5GHz activé sur ${IFACE_AP5G} — SSID ${SPOT_NAME} bi-bande, sous-réseau ${AP5G_IP%.*}.0/24"
}
