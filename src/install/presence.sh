#!/bin/bash
# install/presence.sh — Détecteur de présence caméra (OpenCV) + monitoring
#                        batterie INA219 (optionnel)
# Maître uniquement.
# Prérequis : INSTALL_DIR, PRESENCE_COOLDOWN.

setup_presence() {
    hdr "Message d'accueil vocal"

    loginctl enable-linger "${SOUNDSPOT_USER}" 2>/dev/null || true

    # Génère le message d'accueil en synthèse vocale (espeak-ng, voix FR)
    local welcome_text="Salut ! Je suis un nœud musical libre. Je fonctionne à l'énergie solaire. Connectez-vous à mon réseau WiFi avec votre téléphone ou votre ordinateur. Si la musique s'arrête, c'est que ma batterie a besoin de soleil. Prenez soin de moi !"
    espeak-ng -v fr+f3 -s 120 -p 45 "$welcome_text" -w "$INSTALL_DIR/welcome.wav" 2>/dev/null \
        && log "Message d'accueil généré : ${INSTALL_DIR}/welcome.wav" \
        || warn "espeak-ng a échoué — créer manuellement ${INSTALL_DIR}/welcome.wav"

    # ── Détecteur de présence caméra (optionnel — Pi Camera Module 3 requis) ──
    # Désactivé par défaut : charge CPU significative sur Pi Zero 2W.
    # Nécessite Pi 4 minimum pour une utilisation confortable.
    if [ "${PRESENCE_ENABLED:-false}" = "true" ]; then
        if [ -f "$INSTALL_DIR/presence_detector.py" ]; then
            install_template soundspot-presence.service \
                /etc/systemd/system/soundspot-presence.service \
                '${INSTALL_DIR} ${SOUNDSPOT_USER}'
            systemctl enable soundspot-presence
            log "Service soundspot-presence activé (Pi Camera Module 3 requis)"
        else
            warn "presence_detector.py absent de ${INSTALL_DIR} — module ignoré"
        fi
    else
        warn "Détecteur de présence désactivé (PRESENCE_ENABLED=false)"
        log "→ Pour l'activer : PRESENCE_ENABLED=true dans soundspot.conf + systemctl enable soundspot-presence"
        log "→ Recommandé : Pi 4 minimum (charge CPU OpenCV sur Pi Zero 2W)"
    fi

# ── Monitoring batterie solaire (INA219 — optionnel) ──────
    hdr "Monitoring batterie (INA219 — unifié dans ~/.astro)"
    raspi-config nonint do_i2c 0 2>/dev/null || true
    log "Bus I2C activé (requis pour INA219)"

    if[ -f "$INSTALL_DIR/battery_monitor.py" ]; then
        local USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
        local ASTRO_VENV="$USER_HOME/.astro"

        # Utilisation du Venv Picoport commun (créé si absent)
        if[ ! -x "$ASTRO_VENV/bin/python3" ]; then
            log "Création du venv Python unifié ($ASTRO_VENV)..."
            apt-get install -y -q python3-venv python3-dev
            sudo -u "$SOUNDSPOT_USER" python3 -m venv "$ASTRO_VENV"
        fi

        log "Installation de pi-ina219 dans le venv..."
        sudo -u "$SOUNDSPOT_USER" "$ASTRO_VENV/bin/pip" install --quiet pi-ina219 2>/dev/null \
            && log "pi-ina219 installé ✓" \
            || warn "pi-ina219 indisponible"

        install_template soundspot-battery.service \
            /etc/systemd/system/soundspot-battery.service \
            '${INSTALL_DIR} ${SOUNDSPOT_USER}'
        systemctl enable soundspot-battery
        log "Service soundspot-battery activé"
    else
        warn "battery_monitor.py absent — monitoring batterie non installé"
    fi
    
    }
