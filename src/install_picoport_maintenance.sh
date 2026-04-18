#!/bin/bash
# install_picoport_maintenance.sh
set -e

INSTALL_DIR="/opt/soundspot/picoport"
mkdir -p ~/.zen/workspace

# 1. Récupération du code Astroport (pour les outils de calcul solaire et crypto)
if [[ ! -d ~/.zen/Astroport.ONE ]]; then
    echo "📥 Clonage de Astroport.ONE pour les outils système..."
    git clone --depth 1 https://github.com/papiche/Astroport.ONE ~/.zen/Astroport.ONE
fi

# 2. Lien symbolique pour simplifier l'accès aux outils
mkdir -p ~/.local/bin
ln -sf ~/.zen/Astroport.ONE/tools/keygen ~/.local/bin/keygen
ln -sf ~/.zen/Astroport.ONE/tools/solar_time.sh ~/.local/bin/solar_time
ln -sf ~/.zen/Astroport.ONE/tools/cpcode ~/.local/bin/cpcode
ln -sf ~/.zen/Astroport.ONE/tools/cpscript ~/.local/bin/cpscript

# 3. Initialisation de l'identité automatique (support+hostnameGPS@qo-op.com)
# On récupère le code pays et les coordonnées floues
source ~/.zen/Astroport.ONE/tools/my.sh
GPS_RAW=$(my_LatLon 2>/dev/null || echo "fr 0.00 0.00")
# Formatage du suffixe GPS (ex: fr_43.60_1.44)
GPS_SUFFIX=$(echo $GPS_RAW | awk '{print tolower($1)"_"$2"_"$3}' | sed 's/ /_/g')
PICO_ID="support+$(hostname)_${GPS_SUFFIX}@qo-op.com" ## TODO : randomize hostname with diceware word_XX 

echo "🆔 Identité Picoport générée : $PICO_ID"
mkdir -p ~/.zen/game/players/.current/
echo "$PICO_ID" > ~/.zen/game/players/.current/.player

# 4. Création du script de maintenance spécifique au Picoport
cat > "$INSTALL_DIR/picoport_20h12.sh" << 'EOF'
#!/bin/bash
# Maintenance quotidienne Picoport
source ~/.zen/Astroport.ONE/tools/my.sh
PICO_PLAYER=$(cat ~/.zen/game/players/.current/.player)
LOG_FILE="$HOME/.zen/log/picoport_20h12.log"
mkdir -p "$(dirname "$LOG_FILE")"

exec >> "$LOG_FILE" 2>&1
echo "--- PICOPORT MAINTENANCE 20H12 SOLAR [$(date)] ---"

# 1. Mise à jour du code Picoport & Astroport
echo "🔄 Mise à jour du code..."
cd ~/.zen/Astroport.ONE && git pull
cd /opt/soundspot && git pull || true

# 2. Recalibration de l'heure solaire pour demain
echo "☀️ Recalibration solaire..."
~/.zen/picoport/picoport_cron_control.sh RECALIBRATE

# 3. Signal de vie sur Nostr (Santé du nœud)
# On récupère les infos batterie si disponibles
BATT="N/A"
[[ -f /tmp/battery_level ]] && BATT=$(cat /tmp/battery_level)
UPTIME=$(uptime -p)

MESSAGE="🤖 Signal de vie Picoport
📍 Station: $(hostname)
🔋 Batterie: $BATT
uptime: $UPTIME
🌐 /ipns/$IPFSNODEID"

# Envoi via la clé déterministe du Picoport
source ~/.zen/game/nostr/$PICO_PLAYER/.secret.nostr
python3 ~/.zen/Astroport.ONE/tools/nostr_send_note.py \
    --keyfile ~/.zen/game/nostr/$PICO_PLAYER/.secret.nostr \
    --content "$MESSAGE" \
    --kind 1 --relays "ws://127.0.0.1:9999,wss://relay.copylaradio.com"

echo "✅ Maintenance terminée."
EOF

chmod +x "$INSTALL_DIR/picoport_20h12.sh"