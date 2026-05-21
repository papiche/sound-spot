#!/bin/bash
# install/wifi_driver.sh — Installation du pilote Realtek 88x2bu pour la clé USB Vemfay
# Requis pour le réseau maillé B.A.T.M.A.N. sur la bande 5GHz

setup_wifi_driver() {
    hdr "Installation du Pilote Wi-Fi Vemfay (RTL88x2bu)"

    # Vérifier si le pilote est déjà installé pour gagner du temps
    if dkms status 2>/dev/null | grep -q "88x2bu"; then
        log "Pilote 88x2bu déjà installé dans DKMS. Ignoré."
        return 0
    fi

    log "1/3 Installation des en-têtes du noyau et outils de compilation..."
    apt_retry install -y dkms raspberrypi-kernel-headers build-essential bc git

    log "2/3 Téléchargement du code source morrownr/88x2bu-20210702..."
    cd /tmp
    rm -rf 88x2bu-20210702
    git clone --depth 1 https://github.com/morrownr/88x2bu-20210702.git
    cd 88x2bu-20210702

    log "3/3 Compilation DKMS en cours..."
    warn "ATTENTION: Cette étape prend environ 5 min sur RPi 4, et jusqu'à 20 min sur Pi Zero 2W !"
    warn "Ne débranchez pas le Raspberry Pi."
    
    # Le script de morrownr accepte l'argument "NoPrompt" pour faire une installation silencieuse (sans interaction)
    ./install-driver.sh NoPrompt

    if dkms status 2>/dev/null | grep -q "88x2bu.*installed"; then
    # Desactiver la gestion d'energie agressive du pilote Realtek pour stabiliser le Mesh
    echo "options 88x2bu rtw_power_mgnt=0 rtw_enusbss=0" > /etc/modprobe.d/88x2bu.conf

        log "Pilote Wi-Fi compilé et installé avec succès ✓"
    else
        err "Échec de l'installation du pilote Wi-Fi. Vérifiez les logs DKMS."
    fi

    # Nettoyage
    cd /tmp
    rm -rf 88x2bu-20210702
}