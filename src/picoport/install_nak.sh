#!/bin/bash
# =======================================================================
# src/picoport/install_nak.sh
# Installation de l'outil CLI 'nak' (fiatjaf/nak) pour SoundSpot
# =======================================================================
set -e

[ "$(id -u)" -eq 0 ] || { echo "❌ Ce script doit être lancé en root"; exit 1; }

# Détection de l'architecture
PICO_ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

echo "=== Installation de nak (Nostr CLI) — ${PICO_ARCH} ==="

if command -v nak &>/dev/null; then
    echo "✅ nak est déjà installé."
    exit 0
fi

echo "▶ Résolution de la dernière release de nak sur GitHub..."
API_URL="https://api.github.com/repos/fiatjaf/nak/releases/latest"

# On utilise python pour parser le JSON car jq n'est pas toujours garanti ici
BIN_URL=$(curl -sf --max-time 15 "$API_URL" 2>/dev/null \
    | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    arch = 'linux-${PICO_ARCH}'
    for asset in data.get('assets',[]):
        name = asset.get('name', '').lower()
        if arch in name and not name.endswith('.sha256') and not name.endswith('.zip') and not name.endswith('.tar.gz'):
            print(asset['browser_download_url'])
            break
except Exception:
    pass
" 2>/dev/null)

if[ -n "$BIN_URL" ]; then
    echo "▶ Téléchargement depuis : $BIN_URL"
    wget -q --show-progress "$BIN_URL" -O /tmp/nak_dl
    install -m 755 /tmp/nak_dl /usr/local/bin/nak
    rm -f /tmp/nak_dl
    echo "✅ nak installé avec succès dans /usr/local/bin/nak"
else
    echo "⚠ Impossible de trouver le binaire nak pour l'architecture linux-${PICO_ARCH}."
    exit 1
fi