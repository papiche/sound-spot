#!/bin/bash

# Configuration
BASHRC="$HOME/.bashrc"
START_MARKER="# >>> PICOPORT ALIASES START >>>"
END_MARKER="# <<< PICOPORT ALIASES END <<<"

# Contenu du bloc PicoPort
read -r -d '' PICO_BLOCK << EOF
$START_MARKER

# ── Diagnostic & Surveillance ─────────────────────────────────────────────
alias check='sudo bash /opt/soundspot/check.sh'
alias svc='systemctl status soundspot-* bt-autoconnect picoport 2>/dev/null | grep -E "●|Active:"'
alias pico-log='tail -f ~/.zen/log/picoport_20h12.log'
alias pico-svc='journalctl -u picoport.service -f'
alias cam-log='journalctl -u soundspot-presence.service -f'
alias bt-log='journalctl -u bt-autoconnect -f'
alias 12345='cat ~/.zen/tmp/\$(ipfs id -f="<id>" 2>/dev/null)/12345.json 2>/dev/null | jq'

# ── Audio & Bluetooth ─────────────────────────────────────────────────────
alias sound='wpctl status'
alias sound-fix='systemctl --user restart pipewire pipewire-pulse wireplumber'
alias vol='wpctl get-volume @DEFAULT_AUDIO_SINK@'
alias sound-test='pw-play /usr/share/sounds/alsa/Front_Center.wav'
alias bt-fix='sudo systemctl restart bt-autoconnect && journalctl -u bt-autoconnect -f'

# ── Clocher numérique (idle_announcer) ────────────────────────────────────
alias clock-bells='sudo sed -i "s/^CLOCK_MODE=.*/CLOCK_MODE=bells/" /opt/soundspot/soundspot.conf && echo "Mode : coups de cloche"'
alias clock-silent='sudo sed -i "s/^CLOCK_MODE=.*/CLOCK_MODE=silent/" /opt/soundspot/soundspot.conf && echo "Mode : heure vocale seule"'

# ── Configuration ─────────────────────────────────────────────────────────
alias conf='sudo nano /opt/soundspot/soundspot.conf'
alias conf-pico='sudo nano /opt/soundspot/soundspot.conf'
alias cd-pico='cd /opt/soundspot'

# ── Utilitaires ───────────────────────────────────────────────────────────
alias ll='ls -al'

# ── État complet du nœud ─────────────────────────────────────────────────
pico-status() {
    echo -e "--- \e[32mPICOPORT / SOUNDSPOT STATUS\e[0m ---"
    echo -n "CPU Temp:   " && vcgencmd measure_temp 2>/dev/null || cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "temp=%.1f'\''C\n", \$1/1000}'
    echo -n "Uptime:     " && uptime -p
    echo -n "IPFS Peers: " && ipfs swarm peers 2>/dev/null | wc -l || echo "IPFS arrêté"
    echo -n "Bluetooth:  "
    bluetoothctl info 2>/dev/null | grep -q "Connected: yes" && echo "connecté" || echo "déconnecté"
    echo -n "Snapclient: " && systemctl is-active soundspot-client 2>/dev/null
    echo -n "Snapserver: " && systemctl is-active snapserver 2>/dev/null
    if [ -f /tmp/battery_level ]; then
        echo -n "Batterie:   " && cat /tmp/battery_level
    fi
}

# ── Liste des stations voisines ───────────────────────────────────────────
swarm-nodes() {
    echo "Stations détectées dans l'essaim :"
    find ~/.zen/tmp/swarm/ -name "12345.json" 2>/dev/null -exec jq -r '.hostname' {} + || echo "(aucune station swarm détectée)"
}

# ── astrosystemctl — Cloud P2P de Puissance UPlanet ───────────────────────
# Raccourcis pour déléguer calcul/IA au swarm ou gérer les tunnels P2P
alias asys='astrosystemctl'
alias asys-list='astrosystemctl list'
alias asys-swarm='astrosystemctl list-remote'
alias asys-status='astrosystemctl status'
alias asys-local='astrosystemctl local'

# Connexion rapide à un service IA du swarm (ex: ai ollama)
ai() {
    local svc="\${1:-ollama}"
    echo "🔍 Connexion au service swarm : \$svc"
    astrosystemctl connect "\$svc"
}

# Score de puissance du Picoport (toujours 🌿 Light sur Zero 2W → délègue au swarm)
pico-power() {
    local cache="\$HOME/.zen/tmp/\$(ipfs id -f='<id>' 2>/dev/null)/heartbox_analysis.json"
    if [ -s "\$cache" ]; then
        echo -n "Power-Score: " && jq -r '.capacities.power_score // 0' "\$cache"
        echo -n "Rôle: "       && jq -r 'if .capacities.provider_ready == true then "⚡ Fournisseur" else "🌿 Consommateur (délègue au swarm)" end' "\$cache"
    else
        echo "🌿 Picoport Light — délègue le calcul IA au swarm UPlanet"
        echo "   (heartbox_analysis.json absent — IPFS en cours de démarrage ?)"
    fi
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