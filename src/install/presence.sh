#!/bin/bash
# install/presence.sh — Détecteur de présence caméra (OpenCV) + monitoring
#                        batterie INA219 (optionnel)
# Maître uniquement.
# Prérequis : INSTALL_DIR, PRESENCE_COOLDOWN.

setup_presence() {
    hdr "Détecteur de présence (Pi Camera Module 3)"

    loginctl enable-linger "${SOUNDSPOT_USER}" 2>/dev/null || true

    # Script de lecture du message d'accueil (copie verbatim — paths hardcodés)
    install_template play_welcome.sh "$INSTALL_DIR/play_welcome.sh"
    chmod +x "$INSTALL_DIR/play_welcome.sh"
    log "play_welcome.sh créé"

    # Génère le message d'accueil en synthèse vocale (espeak-ng, voix FR)
    local welcome_text="Salut ! Je suis un nœud musical libre. Je fonctionne à l'énergie solaire. Connectez-vous à mon réseau WiFi avec votre téléphone ou votre ordinateur. Si la musique s'arrête, c'est que ma batterie a besoin de soleil. Prenez soin de moi !"
    espeak-ng -v fr+f3 -s 120 -p 45 "$welcome_text" -w "$INSTALL_DIR/welcome.wav" 2>/dev/null \
        && log "Message d'accueil généré : ${INSTALL_DIR}/welcome.wav" \
        || warn "espeak-ng a échoué — créer manuellement ${INSTALL_DIR}/welcome.wav"

    if [ -f "$INSTALL_DIR/presence_detector.py" ]; then
        install_template soundspot-presence.service \
            /etc/systemd/system/soundspot-presence.service \
            '${INSTALL_DIR} ${SOUNDSPOT_USER}'
        systemctl enable soundspot-presence
        log "Service soundspot-presence activé"
    else
        warn "presence_detector.py absent de ${INSTALL_DIR} — module ignoré"
        warn "(Copier presence_detector.py puis : systemctl enable soundspot-presence)"
    fi

    # ── Monitoring batterie solaire (INA219 — optionnel) ──────
    hdr "Monitoring batterie (INA219 — optionnel)"
    raspi-config nonint do_i2c 0 2>/dev/null || true
    log "Bus I2C activé (requis pour INA219)"

    if [ -f "$INSTALL_DIR/battery_monitor.py" ]; then
        # Venv Python isolé pour pi-ina219 (non disponible via apt)
        if [ ! -x "$INSTALL_DIR/venv/bin/python3" ]; then
            log "Création du venv Python pour battery_monitor..."
            apt-get install -y -q python3-venv
            python3 -m venv "$INSTALL_DIR/venv"
            "$INSTALL_DIR/venv/bin/pip" install --quiet pi-ina219 2>/dev/null \
                && log "pi-ina219 installé dans le venv ✓" \
                || warn "pi-ina219 indisponible — monitoring désactivé si INA219 absent"
        else
            log "Venv existant réutilisé ✓"
        fi

        install_template soundspot-battery.service \
            /etc/systemd/system/soundspot-battery.service \
            '${INSTALL_DIR} ${SOUNDSPOT_USER}'
        systemctl enable soundspot-battery
        log "Service soundspot-battery activé (quitte proprement si INA219 absent)"
    else
        warn "battery_monitor.py absent — monitoring batterie non installé"
        warn "(Copier battery_monitor.py puis relancer setup_presence)"
    fi
}
