#!/bin/bash
# install_astroport_light.sh — Dépendances Astroport.ONE pour Picoport
# À exécuter comme SOUNDSPOT_USER (pas root) — voir setup_picoport() dans install_soundspot.sh
set -e

PICOPORT_DIR="/opt/soundspot/picoport"

# ── 1. Astroport.ONE (outils système : keygen, solar_time, my.sh) ─
if [ ! -d "$HOME/.zen/Astroport.ONE" ]; then
    echo "▶ Clonage de Astroport.ONE..."
    mkdir -p "$HOME/.zen"
    git clone --depth 1 https://github.com/papiche/Astroport.ONE "$HOME/.zen/Astroport.ONE"
    chmod +x "$HOME/.zen/Astroport.ONE/tools/"*.sh \
             "$HOME/.zen/Astroport.ONE/"*.sh 2>/dev/null || true
else
    echo "▶ Astroport.ONE déjà présent — mise à jour..."
    cd "$HOME/.zen/Astroport.ONE" && git pull --ff-only 2>/dev/null || true
fi

# ── 2. Liens symboliques vers les outils fréquemment utilisés ────
mkdir -p "$HOME/.local/bin"
ln -sf "$HOME/.zen/Astroport.ONE/tools/keygen"              "$HOME/.local/bin/keygen"
ln -sf "$HOME/.zen/Astroport.ONE/tools/solar_time.sh"       "$HOME/.local/bin/solar_time"
ln -sf "$HOME/.zen/Astroport.ONE/tools/astrosystemctl.sh"   "$HOME/.local/bin/astrosystemctl"
ln -sf "$HOME/.zen/Astroport.ONE/tools/cpcode"              "$HOME/.local/bin/cpcode"   2>/dev/null || true
ln -sf "$HOME/.zen/Astroport.ONE/tools/cpscript"            "$HOME/.local/bin/cpscript" 2>/dev/null || true
# S'assurer que ~/.local/bin est dans le PATH pour la session courante
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null \
    || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
echo "▶ Liens symboliques outils créés dans ~/.local/bin"

# ── 3. Venv Python ~/.astro/ (compatible Astroport.ONE) ───────────
# Même chemin que l'install Astroport.ONE standard (install.sh ligne 202)
if [ ! -s "$HOME/.astro/bin/activate" ]; then
    echo "▶ Création du venv Python ~/.astro/..."
    python3 -m venv "$HOME/.astro" \
        && echo "✅ venv créé" \
        || { echo "⚠ python3-venv absent ?"; exit 1; }
fi
# shellcheck disable=SC1090
sudo apt-get install -y python3-dev libffi-dev

source "$HOME/.astro/bin/activate"
echo "▶ Vérification des packages Python (keygen + Nostr + G1 + uDRIVE)..."
pip install --upgrade pip 2>/dev/null || true
# Format "paquet_pip:module_python" — vérifie l'import avant d'installer
# Liste complète exigée par keygen (imports top-level → tous obligatoires)
_PYPACKAGES=(
    "base58:base58"          "cryptography:cryptography"  "duniterpy:duniterpy"
    "python-gnupg:gnupg"     "jwcrypto:jwcrypto"          "PyNaCl:nacl"
    "pynostr:pynostr"        "bech32:bech32"               "ecdsa:ecdsa"
    "pynentry:pynentry"      "websocket-client:websocket"  "requests:requests"
    "monero:monero"          "bitcoin:bitcoin"
    "scrypt:scrypt"
)
_TOTAL=${#_PYPACKAGES[@]}; _IDX=0
for _entry in "${_PYPACKAGES[@]}"; do
    _pip="${_entry%%:*}"; _mod="${_entry##*:}"
    _IDX=$((_IDX + 1))
    if timeout 5 python3 -c "import $_mod" 2>/dev/null; then
        echo "  ($_IDX/$_TOTAL) $_pip — déjà présent"
    else
        echo -n "  ($_IDX/$_TOTAL) $_pip — installation... "
        if pip install --prefer-binary -q "$_pip" 2>&1 | tail -1; then
            echo "✓"
        else
            echo "⚠  échec (connexion ?)"
        fi
    fi
done
echo "✅ Packages Python keygen/Picoport vérifiés"

# ── 4. Identité Picoport (support+hostname_GPS@qo-op.com) ────────
source "$HOME/.zen/Astroport.ONE/tools/my.sh" 2>/dev/null || true
GPS_RAW=$(my_LatLon 2>/dev/null || echo "FR 0.00 0.00")
GPS_SUFFIX=$(echo "$GPS_RAW" | awk '{print tolower($1)"_"$2"_"$3}' | sed 's/ /_/g')
PICO_ID="support+$(hostname)_${GPS_SUFFIX}@qo-op.com"
echo "▶ Identité Picoport : $PICO_ID"
mkdir -p "$HOME/.zen/game/players/.current/"
echo "$PICO_ID" > "$HOME/.zen/game/players/.current/.player"
CC=$(echo "$GPS_RAW" | awk '{print $1}')
LAT=$(echo "$GPS_RAW" | awk '{print $2}')
LON=$(echo "$GPS_RAW" | awk '{print $3}')

echo "LAT=$LAT; LON=$LON" > ~/.zen/GPS

# --- Bonus 
echo "installation yt-dlp"
bash $HOME/.zen/Astroport.ONE/install/youtube-dl.sh  
sudo chown "$(whoami):$(whoami)" /usr/local/bin/yt-dlp 2>/dev/null || true

# ── 5. Script de maintenance quotidienne (20h12 solaire) ─────────
# Chemin du dépôt sound-spot : déterminé dynamiquement depuis le HOME utilisateur
SOUNDSPOT_REPO="$HOME/.zen/workspace/sound-spot"
[ -d "$SOUNDSPOT_REPO" ] || SOUNDSPOT_REPO="/opt/soundspot"

mkdir -p "$PICOPORT_DIR"
cat > "$PICOPORT_DIR/picoport_20h12.sh" << MAINEOF
#!/bin/bash
# Maintenance quotidienne Picoport (20h12 solaire)
source "$HOME/.astro/bin/activate" 2>/dev/null || true
source "$HOME/.zen/Astroport.ONE/tools/my.sh" 2>/dev/null || true
PICO_PLAYER=\$(cat "$HOME/.zen/game/players/.current/.player" 2>/dev/null || echo "unknown")
LOG_FILE="$HOME/.zen/log/picoport_20h12.log"
mkdir -p "\$(dirname "\$LOG_FILE")"
exec >> "\$LOG_FILE" 2>&1
echo "--- PICOPORT MAINTENANCE 20H12 SOLAR [\$(date)] ---"

# 1. Mise à jour du code
echo "▶ Mise à jour Astroport.ONE..."
cd "$HOME/.zen/Astroport.ONE" && git pull --ff-only 2>/dev/null || true

echo "▶ Mise à jour sound-spot..."
cd "$SOUNDSPOT_REPO" && git pull --ff-only 2>/dev/null || true

# 2. Recalibration heure solaire
echo "▶ Recalibration solaire..."
"$HOME/.zen/Astroport.ONE/tools/cron_VRFY.sh" RECALIBRATE

# 3. Signal de vie Nostr (kind 1)
BATT="N/A"
[ -f /tmp/battery_level ] && BATT=\$(cat /tmp/battery_level)
UPTIME=\$(uptime -p)
IPFSNODEID=\$(ipfs id -f="<id>" 2>/dev/null || echo "unknown")
MESSAGE="🎶 Picoport SoundSpot
nœud : \$(hostname)
player : \$PICO_PLAYER
🔋 \$BATT // uptime: \$UPTIME
🌐 http://127.0.0.1:8080/ipns/\$IPFSNODEID"

KEYFILE="$HOME/.zen/game/nostr/\$PICO_PLAYER/.secret.nostr"
if [ -f "\$KEYFILE" ]; then
    python3 "$HOME/.zen/Astroport.ONE/tools/nostr_send_note.py" \
        --keyfile "\$KEYFILE" \
        --content "\$MESSAGE" \
        --kind 1 \
        --relays "wss://relay.copylaradio.com" 2>/dev/null \
        && echo "✅ Signal Nostr envoyé" \
        || echo "⚠  Signal Nostr échoué"
fi
echo "✅ Maintenance terminée."
MAINEOF

sudo chmod +x "$PICOPORT_DIR/picoport_20h12.sh"
echo "▶ picoport_20h12.sh créé"

