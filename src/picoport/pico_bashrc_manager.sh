#!/bin/bash

# Configuration
BASHRC="$HOME/.bashrc"
START_MARKER="# >>> PICOPORT ALIASES START >>>"
END_MARKER="# <<< PICOPORT ALIASES END <<<"

# Contenu du bloc PicoPort
# Contenu du bloc PicoPort
read -r -d '' PICO_BLOCK << EOF
$START_MARKER

# ── Diagnostic & Surveillance ─────────────────────────────────────────────
# Correction de l'alias check pour pointer vers le workspace si absent de /opt
alias check='[ -f /opt/soundspot/check.sh ] && sudo bash /opt/soundspot/check.sh || sudo bash \$HOME/.zen/workspace/sound-spot/check.sh'
alias svc='systemctl status soundspot-* bt-autoconnect picoport 2>/dev/null | grep -E "●|Active:"'
alias pico-log='tail -f ~/.zen/log/picoport_20h12.log'
alias pico-svc='journalctl -u picoport.service -f'
alias 12345='cat ~/.zen/tmp/\$(ipfs id -f="<id>" 2>/dev/null)/12345.json 2>/dev/null | jq'

# ── Audio & Bluetooth ─────────────────────────────────────────────────────
alias sound='wpctl status'
alias sound-fix='systemctl --user restart pipewire pipewire-pulse wireplumber'
alias vol='wpctl get-volume @DEFAULT_AUDIO_SINK@'
alias sound-test='pw-play /usr/share/sounds/alsa/Front_Center.wav'
alias bt-fix='sudo systemctl restart bt-autoconnect && journalctl -u bt-autoconnect -f'

# ── Clocher numérique ─────────────────────────────────────────────────────
alias clock-bells='sudo sed -i "s/^CLOCK_MODE=.*/CLOCK_MODE=bells/" /opt/soundspot/soundspot.conf && echo "Mode : coups de cloche"'
alias clock-silent='sudo sed -i "s/^CLOCK_MODE=.*/CLOCK_MODE=silent/" /opt/soundspot/soundspot.conf && echo "Mode : heure vocale seule"'

# ── Développement & Update ────────────────────────────────────────────────
alias cd-pico='cd \$HOME/.zen/workspace/sound-spot'
alias pico-update='cd \$HOME/.zen/workspace/sound-spot && git pull && sudo bash deploy_on_pi.sh'

pico-welcome() {
    echo -e "\e[36m"
    echo "  ░▀▀█░▀█▀░█▀▀░█▄█░█▀█░█▄█░█▀█"
    echo "  ░▄▀░░░█░░█░░░█░█░█▀█░█░█░█▀█"
    echo "  ░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀░▀░▀░▀░▀░▀"
    echo -e "\e[0m"
    echo -e "\e[1mBienvenue sur ton SoundSpot Picoport !\e[0m"
    echo -e "Version : \e[32m$(git -C $HOME/.zen/workspace/sound-spot rev-parse --short HEAD 2>/dev/null || echo 'live')\e[0m"
    echo ""
    echo -e "\e[33m[Diagnostic]\e[0m"
    echo -e "  check         : Diagnostic complet réseau/audio"
    echo -e "  pico-status   : État rapide (Temp, IPFS, BT)"
    echo -e "  swarm-nodes   : Voir les voisins de l'essaim"
    echo ""
    echo -e "\e[33m[Audio]\e[0m"
    echo -e "  sound-test    : Vérifier si l'enceinte chante"
    echo -e "  bt-fix        : Relancer la connexion Bluetooth"
    echo ""
    echo -e "\e[33m[Maintenance]\e[0m"
    echo -e "  pico-update   : \e[5m⚠️\e[0m Mettre à jour le code et redéployer"
    echo -e "  conf          : Modifier la configuration (SSID, MAC, etc.)"
    echo ""
    echo -e "\e[35m[IA Swarm]\e[0m"
    echo -e "  ai ollama     : Se connecter au cerveau du Swarm"
    echo ""
}

# Lancer le message de bienvenue
pico-welcome

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

# ── Développement portail (src/dev/) ─────────────────────────────────────
SS_DEV_DIR="\$HOME/.zen/workspace/sound-spot"

# Activer le mode dev sur une branche (crée si nouvelle)
ss-dev() {
    local branch="\${1:-dev-\$(hostname)}"
    if [ -f "\${SS_DEV_DIR}/src/dev/dev_setup.sh" ]; then
        bash "\${SS_DEV_DIR}/src/dev/dev_setup.sh" "\$branch"
    else
        echo "dev_setup.sh introuvable — cloner d'abord le dépôt dans \${SS_DEV_DIR}"
    fi
}

# Changer de branche en live
ss-switch() {
    bash "\${SS_DEV_DIR}/src/dev/dev_switch.sh" "\${1:-}"
}

# Restaurer le portail en mode production (copie depuis main)
ss-prod() {
    bash "\${SS_DEV_DIR}/src/dev/dev_restore.sh"
}

# Recharger le code backend en runtime
ss-reload() {
    if [ -f "\${SS_DEV_DIR}/src/dev/dev_reload.sh" ]; then
        sudo bash "\${SS_DEV_DIR}/src/dev/dev_reload.sh"
    else
        echo "Script dev_reload.sh introuvable."
    fi
}

# Statut git de la branche active du portail
ss-status() {
    if [ -d "\${SS_DEV_DIR}/.git" ]; then
        cd "\${SS_DEV_DIR}"
        echo -e "\e[36mBranche active  :\e[0m \$(git branch --show-current)"
        echo -e "\e[36mPortal symlink  :\e[0m \$(readlink -f /opt/soundspot/portal 2>/dev/null)"
        echo -e "\e[36mFichiers modif. :\e[0m"
        git status --short src/portal/ 2>/dev/null || true
    else
        echo "Mode production (pas de workspace dev)"
    fi
}

# Tester un module API directement dans le terminal
ss-api() {
    local action="\${1:-status}"
    shift 2>/dev/null || true
    QUERY_STRING="action=\${action}" \
    SPOT_NAME="\$(grep SPOT_NAME /opt/soundspot/soundspot.conf | cut -d= -f2 | tr -d '\"')" \
    SPOT_IP="\$(grep SPOT_IP /opt/soundspot/soundspot.conf | cut -d= -f2 | tr -d '\"')" \
    ICECAST_PORT="\$(grep ICECAST_PORT /opt/soundspot/soundspot.conf | cut -d= -f2 | tr -d '\"')" \
    SNAPCAST_PORT="\$(grep SNAPCAST_PORT /opt/soundspot/soundspot.conf | cut -d= -f2 | tr -d '\"')" \
    CLOCK_MODE="\$(grep CLOCK_MODE /opt/soundspot/soundspot.conf | cut -d= -f2 | tr -d '\"')" \
    INSTALL_DIR="/opt/soundspot" \
    bash /opt/soundspot/portal/api.sh 2>/dev/null | jq . 2>/dev/null || \
    bash /opt/soundspot/portal/api.sh 2>/dev/null
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
    remove_block
    echo -e "\n$PICO_BLOCK" >> "$BASHRC"
    
    # AJOUT : Aussi injecter dans .bash_aliases qui est souvent sourcé par défaut
    local ALIAS_FILE="$HOME/.bash_aliases"
    [ -f "$ALIAS_FILE" ] || touch "$ALIAS_FILE"
    if ! grep -q "check" "$ALIAS_FILE"; then
        echo "alias ll='ls -al'" >> "$ALIAS_FILE"
        echo "alias check='sudo bash /opt/soundspot/check.sh'" >> "$ALIAS_FILE"
    fi
    
    # Forcer la prise en compte immédiate pour l'utilisateur courant
    export PATH="$HOME/.local/bin:$PATH"
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