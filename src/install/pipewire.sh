#!/bin/bash
# install/pipewire.sh — Session PipeWire persistante (user pi)
# Partagé entre maître et satellite.

setup_pipewire() {
    hdr "PipeWire session persistante (user pi)"
    loginctl enable-linger pi
    log "Linger activé — PipeWire disponible sans session active"

    # Sink virtuel de secours : snapclient démarre même sans enceinte BT.
    # WirePlumber bascule automatiquement vers le sink BT dès connexion.
    mkdir -p /etc/pipewire/pipewire.conf.d
    install_template pipewire-soundspot-null.conf \
        /etc/pipewire/pipewire.conf.d/50-soundspot-null.conf
    log "Null sink PipeWire configuré (fallback si BT hors ligne)"

    # openNDS s'installe parfois comme dépendance et ajoute ses propres règles
    # iptables qui entrent en conflit avec notre portail captif (lighttpd + ipset).
    # On le masque pour qu'il ne puisse pas démarrer.
    systemctl stop    opennds 2>/dev/null || true
    systemctl disable opennds 2>/dev/null || true
    systemctl mask    opennds 2>/dev/null || true
    log "openNDS masqué — portail captif géré par lighttpd + iptables"
}
