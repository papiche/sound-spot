#!/bin/bash
# install/presence.sh — Message d'accueil vocal + détecteur de présence caméra
# Maître uniquement.
# Prérequis : INSTALL_DIR, SOUNDSPOT_USER, PRESENCE_COOLDOWN.
#
# Le monitoring batterie (INA219) est dans battery.sh — séparé car indépendant.

setup_presence() {
    hdr "Message d'accueil vocal"

    loginctl enable-linger "${SOUNDSPOT_USER}" 2>/dev/null || true

    # Pas de génération espeak : play_welcome.sh reste silencieux tant que
    # welcome.wav est absent. La voix (Orpheus, via tts.sh) prend le relais
    # dès que la constellation UPlanet est joignable — cf. presence_detector.py.
    log "welcome.wav non généré (espeak désactivé) — Orpheus prendra le relais via tts.sh"
    log "Pour un accueil statique hors-ligne : déposer manuellement ${INSTALL_DIR}/welcome.wav"

    # ── Détecteur de présence caméra (optionnel) ──────────────────────
    # Modes : motion (défaut, CPU<5%), face, audio, any
    # Désactivé par défaut — activer dans soundspot.conf : PRESENCE_ENABLED=true
    if [ "${PRESENCE_ENABLED:-false}" = "true" ]; then
        local detector="${INSTALL_DIR}/backend/system/presence_detector.py"
        if [ -f "$detector" ]; then
            install_template soundspot-presence.service \
                /etc/systemd/system/soundspot-presence.service \
                '${INSTALL_DIR} ${SOUNDSPOT_USER} ${SOUNDSPOT_UID}'
            systemctl enable soundspot-presence
            log "Service soundspot-presence activé (mode=${PRESENCE_MODE:-motion})"
        else
            warn "presence_detector.py absent de ${INSTALL_DIR}/backend/system/ — module ignoré"
        fi
    else
        warn "Détecteur de présence désactivé (PRESENCE_ENABLED=false)"
        log "→ Pour l'activer : PRESENCE_ENABLED=true + PRESENCE_MODE=motion dans soundspot.conf"
    fi
}
