#!/bin/bash
# install/wifi_driver.sh — Détection et installation du pilote Wi-Fi 5GHz pour le mesh
# Critères minimum : mode IBSS (ad-hoc) + 5 GHz + driver Linux stable
#
# Chipsets supportés :
#   RTL88x2bu  — DKMS morrownr (5-20 min de compilation)
#   RTL8812AU  — DKMS morrownr (5-20 min de compilation)
#   MT7612U    — driver in-kernel mt76      (aucune compilation)
#   MT7921AU   — driver in-kernel mt7921u   (aucune compilation)

# ── USB IDs des chipsets supportés ───────────────────────────────────────────
# Format : "idVendor:idProduct" comme affiché par lsusb
_UIDS_RTL88X2BU="0bda:b812 0bda:b82c 0bda:a811 2357:012d 0846:9055"
_UIDS_RTL8812AU="0bda:8812 0bda:881a 0bda:8821 2357:0101 0e66:0023 0b05:17d1"
_UIDS_MT7612U="148f:7612 0e8d:7612 7392:b711 0b05:17d2 2357:010c"
_UIDS_MT7921AU="0e8d:7961 13b1:0045 2eca:c300 0bda:c820"

_detect_usb_chipset() {
    local usb_ids
    usb_ids=$(lsusb 2>/dev/null | awk '{print tolower($6)}')

    for uid in $_UIDS_RTL88X2BU; do
        echo "$usb_ids" | grep -qF "$uid" && echo "rtl88x2bu" && return
    done
    for uid in $_UIDS_RTL8812AU; do
        echo "$usb_ids" | grep -qF "$uid" && echo "rtl8812au" && return
    done
    for uid in $_UIDS_MT7612U; do
        echo "$usb_ids" | grep -qF "$uid" && echo "mt7612u" && return
    done
    for uid in $_UIDS_MT7921AU; do
        echo "$usb_ids" | grep -qF "$uid" && echo "mt7921au" && return
    done
    echo ""
}

_install_rtl88x2bu() {
    if dkms status 2>/dev/null | grep -q "88x2bu"; then
        log "Pilote RTL88x2bu déjà dans DKMS — ignoré."
        return 0
    fi
    warn "Compilation RTL88x2bu : ~5 min sur RPi 4, jusqu'à 20 min sur RPi Zero 2W."
    warn "Ne débranchez pas le Raspberry Pi pendant la compilation."
    apt_retry install -y dkms raspberrypi-kernel-headers build-essential bc git
    cd /tmp || err "cd /tmp impossible"
    rm -rf 88x2bu-20210702
    git clone --depth 1 https://github.com/morrownr/88x2bu-20210702.git \
        || err "Échec git clone RTL88x2bu (réseau ?)"
    cd 88x2bu-20210702 || err "Dossier 88x2bu-20210702 introuvable après clone"
    ./install-driver.sh NoPrompt
    if dkms status 2>/dev/null | grep -q "88x2bu.*installed"; then
        echo "options 88x2bu rtw_power_mgnt=0 rtw_enusbss=0" > /etc/modprobe.d/88x2bu.conf
        log "RTL88x2bu compilé et installé ✓"
    else
        err "Échec DKMS RTL88x2bu — vérifiez les logs DKMS."
    fi
    cd /tmp && rm -rf 88x2bu-20210702
}

_install_rtl8812au() {
    if dkms status 2>/dev/null | grep -q "8812au"; then
        log "Pilote RTL8812AU déjà dans DKMS — ignoré."
        return 0
    fi
    warn "Compilation RTL8812AU : ~5 min sur RPi 4, jusqu'à 20 min sur RPi Zero 2W."
    warn "Ne débranchez pas le Raspberry Pi pendant la compilation."
    apt_retry install -y dkms raspberrypi-kernel-headers build-essential bc git
    cd /tmp || err "cd /tmp impossible"
    rm -rf 8812au
    git clone --depth 1 https://github.com/morrownr/8812au-20210629.git 8812au \
        || err "Échec git clone RTL8812AU (réseau ?)"
    cd 8812au || err "Dossier 8812au introuvable après clone"
    ./install-driver.sh NoPrompt
    if dkms status 2>/dev/null | grep -q "8812au.*installed"; then
        echo "options 8812au rtw_power_mgnt=0 rtw_enusbss=0" > /etc/modprobe.d/8812au.conf
        log "RTL8812AU compilé et installé ✓"
    else
        err "Échec DKMS RTL8812AU — vérifiez les logs DKMS."
    fi
    cd /tmp && rm -rf 8812au
}

_install_mt76() {
    local chipset="$1"
    log "Chipset ${chipset} — driver in-kernel (mt76), aucune compilation requise."
    apt_retry install -y firmware-misc-nonfree 2>/dev/null || true
    modprobe mt76_usb 2>/dev/null || true
    modprobe mt7612u 2>/dev/null || true
    modprobe mt7921u 2>/dev/null || true
    # Désactiver la gestion d'énergie agressive (même principe que Realtek)
    cat > /etc/modprobe.d/mt76-mesh.conf <<'EOF'
options mt76_usb disable_usb_sg=1
EOF
    log "Driver mt76 activé ✓"
}

setup_wifi_driver() {
    hdr "Détection du dongle Wi-Fi 5GHz (mesh B.A.T.M.A.N.)"

    local chipset
    chipset=$(_detect_usb_chipset)

    if [ -z "$chipset" ]; then
        warn "Aucun dongle Wi-Fi 5GHz reconnu parmi les chipsets supportés."
        warn "Chipsets supportés : RTL88x2bu · RTL8812AU · MT7612U · MT7921AU"
        warn "Mesh CYBERCOCHON_MESH désactivé — le nœud fonctionnera sans mesh."
        return 0
    fi

    log "Chipset détecté : ${chipset}"

    case "$chipset" in
        rtl88x2bu) _install_rtl88x2bu ;;
        rtl8812au)  _install_rtl8812au ;;
        mt7612u|mt7921au) _install_mt76 "$chipset" ;;
    esac
}
