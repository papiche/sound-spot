#!/bin/bash

# Configuration
BASHRC="$HOME/.bashrc"
START_MARKER="# >>> PICOPORT ALIASES START >>>"
END_MARKER="# <<< PICOPORT ALIASES END <<<"

# Contenu du bloc PicoPort
read -r -d '' PICO_BLOCK << EOF
$START_MARKER
# Diagnostics Audio & Bluetooth
alias sound='wpctl status'
alias sound-fix='systemctl --user restart pipewire pipewire-pulse wireplumber'
alias vol='wpctl get-volume @DEFAULT_AUDIO_SINK@'
alias sound-test='pw-play /usr/share/sounds/alsa/Front_Center.wav'

# Surveillance Picoport & Logs
alias pico-log='tail -f ~/.zen/log/picoport_20h12.log'
alias pico-svc='journalctl -u picoport.service -f'
alias cam-log='journalctl -u soundspot-presence.service -f'
alias 12345='cat ~/.zen/tmp/\$(ipfs id -f="<id>")/12345.json | jq'

# Raccourcis de Configuration
alias conf-pico='sudo nano /opt/soundspot/soundspot.conf'
alias cd-pico='cd /opt/soundspot'

# Long listing
alias ll='ls -al'

# État du Nœud
pico-status() {
    echo -e "--- \e[32mPICOPORT STATUS\e[0m ---"
    echo -n "CPU Temp: " && vcgencmd measure_temp
    echo -n "Uptime:   " && uptime -p
    echo -n "IPFS Peers: " && ipfs swarm peers | wc -l
    if [ -f /var/lib/prometheus/node-exporter/picoport_battery.prom ]; then
        echo -e "\e[34mBatterie:\e[0m"
        grep "picoport_battery" /var/lib/prometheus/node-exporter/picoport_battery.prom
    fi
    echo -n "Bluetooth: "
    bluetoothctl info | grep "Connected: yes" || echo "Disconnected"
}

# Liste des stations voisines
swarm-nodes() {
    echo "Stations détectées dans l'essaim :"
    find ~/.zen/tmp/swarm/ -name "12345.json" -exec jq -r '.hostname' {} +
}
$END_MARKER
EOF

remove_block() {
    if grep -q "$START_MARKER" "$BASHRC"; then
        # Supprime tout ce qui se trouve entre les deux balises (incluses)
        sed -i "/$START_MARKER/,/$END_MARKER/d" "$BASHRC"
        return 0
    else
        return 1
    fi
}

install_block() {
    remove_block # On nettoie d'abord pour éviter les doublons
    echo -e "\n$PICO_BLOCK" >> "$BASHRC"
}

# Menu de commande
case "$1" in
    install)
        install_block
        echo "✅ Bloc PicoPort ajouté à $BASHRC"
        echo "👉 Tapez 'source ~/.bashrc' pour activer les changements."
        ;;
    remove)
        if remove_block; then
            echo "🗑️  Bloc PicoPort supprimé de $BASHRC"
            echo "👉 Tapez 'source ~/.bashrc' pour rafraîchir la session."
        else
            echo "ℹ️  Aucun bloc PicoPort trouvé dans $BASHRC."
        fi
        ;;
    *)
        echo "Usage: $0 {install|remove}"
        exit 1
        ;;
esac