#!/bin/bash
# install/battery.sh — Monitoring batterie solaire (INA219 I2C)
# Maître uniquement. Indépendant du détecteur de présence caméra.
# Prérequis : INSTALL_DIR, SOUNDSPOT_USER.

setup_battery() {
    hdr "Monitoring batterie (INA219)"

    # Activer le bus I2C (nécessaire pour le capteur INA219)
    raspi-config nonint do_i2c 0 2>/dev/null || true
    log "Bus I2C activé (requis pour INA219)"

    local monitor="${INSTALL_DIR}/backend/system/battery_monitor.py"
    if [ ! -f "$monitor" ]; then
        warn "battery_monitor.py absent de ${INSTALL_DIR}/backend/system/ — monitoring batterie ignoré"
        return 0
    fi

    local USER_HOME
    USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
    local ASTRO_VENV="${USER_HOME}/.astro"

    # Réutilise le venv Picoport commun si déjà créé ; en crée un sinon
    if [ ! -x "${ASTRO_VENV}/bin/python3" ]; then
        log "Création du venv Python unifié (${ASTRO_VENV})..."
        apt-get install -y -q python3-venv python3-dev
        sudo -u "${SOUNDSPOT_USER}" python3 -m venv "${ASTRO_VENV}"
    fi

    log "Installation de pi-ina219 + RPi.GPIO dans le venv..."
    sudo -u "${SOUNDSPOT_USER}" "${ASTRO_VENV}/bin/pip" install --quiet \
        pi-ina219 RPi.GPIO 2>/dev/null \
        && log "Dépendances batterie installées ✓" \
        || warn "Installation partielle — vérifier le venv manuellement"

    install_template soundspot-battery.service \
        /etc/systemd/system/soundspot-battery.service \
        '${INSTALL_DIR} ${SOUNDSPOT_USER} ${SOUNDSPOT_UID}'
    systemctl enable soundspot-battery
    log "Service soundspot-battery activé"
}
