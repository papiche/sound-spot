#!/bin/bash
# install/pipewire.sh — Session PipeWire persistante (user pi)
# Partagé entre maître et satellite.

setup_pipewire() {
    hdr "PipeWire session persistante (user pi)"
    loginctl enable-linger pi
    log "Linger activé — PipeWire disponible sans session active"

    # openNDS s'installe parfois comme dépendance et ajoute ses propres règles
    # iptables qui entrent en conflit avec notre portail captif (lighttpd + ipset).
    # On le masque pour qu'il ne puisse pas démarrer.
    systemctl stop    opennds 2>/dev/null || true
    systemctl disable opennds 2>/dev/null || true
    systemctl mask    opennds 2>/dev/null || true
    log "openNDS masqué — portail captif géré par lighttpd + iptables"
}
