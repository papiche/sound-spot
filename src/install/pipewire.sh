#!/bin/bash
# install/pipewire.sh — Session PipeWire persistante (user pi)
# Partagé entre maître et satellite.

setup_pipewire() {
    hdr "PipeWire session persistante (user pi)"
    loginctl enable-linger pi
    log "Linger activé — PipeWire disponible sans session active"
}
