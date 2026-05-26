#!/bin/bash

# Configuration
BASHRC="$HOME/.bashrc"

# Contenu du bloc PicoPort
read -r -d '' PICO_BLOCK << 'EOF'
# >>> PICOPORT ALIASES START >>>

# ── Diagnostic & Surveillance ─────────────────────────────────────────────
# Correction de l'alias check pour pointer vers le workspace si absent de /opt
alias check='bash /opt/soundspot/check.sh'
alias ss-center='sudo bash /opt/soundspot/backend/system/control_center.sh'

alias svc='systemctl status soundspot-* bt-autoconnect picoport 2>/dev/null | grep -E "●|Active:"'
alias pico-log='tail -f ~/.zen/log/picoport_20h12.log'
alias pico-svc='journalctl -u picoport.service -f'
alias 12345='cat ~/.zen/tmp/\$(ipfs id -f="<id>" 2>/dev/null)/12345.json 2>/dev/null | jq'
alias pico-low='~/.zen/Astroport.ONE/tools/cron_VRFY.sh LOW'
alias pico-on='~/.zen/Astroport.ONE/tools/cron_VRFY.sh ON'

# ── Audio & Bluetooth ─────────────────────────────────────────────────────
alias sound='wpctl status'
alias sound-fix='systemctl --user restart pipewire pipewire-pulse wireplumber'
vol() {
    if [ -z "$1" ]; then
        wpctl get-volume @DEFAULT_AUDIO_SINK@
    else
        # wpctl utilise des valeurs de 0.0 à 1.0 (ou >1.0 pour booster)
        # On convertit si l'utilisateur entre un entier (ex: 80 -> 0.8)
        local VAL=$1
        [[ "$VAL" -gt 1 ]] && VAL=$(echo "scale=2; $VAL / 100" | bc)
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "$VAL"
        echo "Volume réglé à $VAL"
    fi
}
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
    echo -e "Version : \e[32m\$(git -C \$HOME/.zen/workspace/sound-spot rev-parse --short HEAD 2>/dev/null || echo 'live')\e[0m"
    echo ""
    echo -e "\e[33m─── Commandes & Alias disponibles ────────────────────────────────────\e[0m"
    echo -e "  \e[36m[Diag/Logs]\e[0m  check, svc, pico-status, pico-log, pico-svc, 12345"
    echo -e "  \e[36m[Énergie]  \e[0m  pico-on, pico-low, pico-power"
    echo -e "  \e[36m[Audio/BT] \e[0m  sound, vol, sound-test, sound-fix, bt-fix"
    echo -e "  \e[36m[Clocher]  \e[0m  clock-bells, clock-silent"
    echo -e "  \e[36m[IA/Swarm] \e[0m  swarm-nodes, ai, asys-swarm, asys-qdrant, asys-nc, asys-ollama, asys-orpheus, asys-help"
    echo -e "  \e[36m[Admin/Dev]\e[0m  ss-center, conf, cd-pico, pico-update, ss-status, ss-reload"
    echo -e "\e[33m──────────────────────────────────────────────────────────────────────\e[0m"
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
    if [ -f /dev/shm/battery_percent ]; then
        echo -n "Batterie:   " && cat /dev/shm/battery_percent && echo " %"
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
alias asys-qdrant='astrosystemctl enable qdrant'
alias asys-nc='astrosystemctl enable nextcloud-app'
alias asys-ollama='astrosystemctl enable ollama'
alias asys-orpheus='astrosystemctl enable orpheus'

# Connexion rapide à un service IA du swarm (ex: ai ollama)
ai() {
    local svc="\${1:-ollama}"
    echo "Connexion au service swarm : \$svc"
    astrosystemctl connect "\$svc"
}

# Aide astrosystemctl
asys-help() {
    cat << 'HELP'

  astrosystemctl — Cloud P2P de Puissance UPlanet
  ──────────────────────────────────────────────────────────────────────

  Ce Picoport est un nœud Light (RPi Zero 2W) — il délègue le calcul
  IA aux Brain-Nodes (GPU) de la constellation via tunnels IPFS P2P.

  Alias rapides :
    asys-swarm      → Lister les Brain-Nodes du swarm
    asys-list       → Services locaux disponibles
    asys-status     → État des tunnels actifs
    asys-qdrant     → Activer le tunnel Qdrant  (port 6333)
    asys-nc         → Activer le tunnel NextCloud
    ai ollama       → Se connecter à Ollama distant (port 11434)
    ai comfyui      → Se connecter à ComfyUI distant (port 8188)

  Commandes directes astrosystemctl :
    astrosystemctl list-remote        → Brain-Nodes et leurs services
    astrosystemctl connect <service>  → Connexion ponctuelle
    astrosystemctl enable  <service>  → Tunnel persistant (watchdog)
    astrosystemctl disable <service>  → Désactiver le tunnel
    astrosystemctl status             → Tunnels actifs

  Ports utilisés (127.0.0.1 local = service distant via tunnel) :
    qdrant     :6333    nextcloud  :8002
    ollama     :11434   comfyui    :8188

  La clé API Qdrant (sha256 de UPLANETNAME) est identique sur tout
  le swarm — aucune configuration supplémentaire requise.

HELP
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

## activate ~/.astro python venv
[[ -f $HOME/.astro/bin/activate ]] && source $HOME/.astro/bin/activate

# <<< PICOPORT ALIASES END <<<
EOF

remove_block() {
    if grep -q "# >>> PICOPORT ALIASES START >>>" "$BASHRC"; then
        # Supprime tout ce qui se trouve entre les deux balises (incluses)
        sed -i "/# >>> PICOPORT ALIASES START >>>/,/# <<< PICOPORT ALIASES END <<</d" "$BASHRC"
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