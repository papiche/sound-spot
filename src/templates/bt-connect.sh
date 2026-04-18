#!/bin/bash
source /opt/soundspot/soundspot.conf
# Support multi-enceintes : BT_MACS contient une liste de MACs séparés par espaces
MACS="${BT_MACS:-${BT_MAC:-}}"
[ -z "$MACS" ] && { echo "BT_MACS non défini, skip"; exit 0; }

# ── Attendre que WirePlumber soit prêt à gérer le profil A2DP ──────────────
# WirePlumber est un service utilisateur : il démarre après les services système.
# Sans cette attente, bluetoothd répond "Protocol not available" car son handler
# A2DP n'est pas encore enregistré.
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_ID=$(id -u "$SOUNDSPOT_USER" 2>/dev/null || echo 1000)
PW_SOCK="/run/user/${USER_ID}/pipewire-0"

echo "Attente du socket PipeWire (max 45s)..."
WAITED=0
while [ $WAITED -lt 45 ] && [ ! -S "$PW_SOCK" ]; do
    sleep 1
    WAITED=$((WAITED + 1))
done

if [ -S "$PW_SOCK" ]; then
    echo "PipeWire prêt après ${WAITED}s — attente enregistrement A2DP (3s)..."
    sleep 3   # laisser le plugin bluetooth de WirePlumber s'enregistrer auprès de bluetoothd
else
    echo "Avertissement : socket PipeWire non trouvé après 45s — tentative quand même"
fi

# ── Activer l'agent Bluetooth ─────────────────────────────────────────────
bluetoothctl agent on 2>/dev/null || true
bluetoothctl default-agent 2>/dev/null || true

CONNECTED=0
for mac in $MACS; do
    echo "Connexion BT : $mac"

    # Si déjà connecté, compter et passer au suivant
    if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
        echo "Enceinte $mac déjà connectée — skip"
        CONNECTED=$((CONNECTED + 1))
        continue
    fi

    # Vérifier si l'appareil est connu (appairé) avant de tenter connect
    if ! bluetoothctl info "$mac" 2>&1 | grep -q "Device $mac"; then
        echo "Appareil $mac non appairé — tentative de scan (8s)..."
        bluetoothctl scan on &
        SCAN_PID=$!
        sleep 8
        kill "$SCAN_PID" 2>/dev/null || true
        wait "$SCAN_PID" 2>/dev/null || true
    fi

    for i in $(seq 1 5); do
        if bluetoothctl connect "$mac" 2>&1 | grep -q "Connection successful"; then
            echo "Enceinte BT connectée : $mac"
            CONNECTED=$((CONNECTED + 1))
            break
        fi
        sleep 5
    done
done

[ "$CONNECTED" -gt 0 ] || { echo "Échec connexion BT pour toutes les enceintes"; exit 1; }

# Si plusieurs enceintes, créer un sink combiné PipeWire/PulseAudio
MAC_COUNT=$(echo "$MACS" | wc -w)
if [ "$MAC_COUNT" -gt 1 ]; then
    sleep 3
    /opt/soundspot/bt-combine-sinks.sh 2>/dev/null || true
fi
exit 0
