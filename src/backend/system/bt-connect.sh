#!/bin/bash
# bt-connect.sh — Connexion Bluetooth automatique au boot
# Supporte le Linger et attend que PipeWire soit prêt.

source /opt/soundspot/soundspot.conf

# Support multi-enceintes
MACS="${BT_MACS:-${BT_MAC:-}}"
[ -z "$MACS" ] && { echo "BT_MACS non défini, skip"; exit 0; }

SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_ID=$(id -u "$SOUNDSPOT_USER" 2>/dev/null || echo 1000)
export XDG_RUNTIME_DIR="/run/user/${USER_ID}"

# 1. --- CRITIQUE : Attendre que le dossier utilisateur soit créé par Systemd (Linger) ---
echo "Attente de l'environnement utilisateur ($XDG_RUNTIME_DIR)..."
for i in {1..30}; do
    if [ -d "$XDG_RUNTIME_DIR" ]; then
        break
    fi
    sleep 1
done

# 2. --- Attendre que le socket PipeWire soit créé ---
echo "Attente du socket PipeWire..."
for i in {1..20}; do
    if [ -S "$XDG_RUNTIME_DIR/pipewire-0" ]; then
        break
    fi
    sleep 1
done

# Laisser 2 secondes de plus à WirePlumber pour stabiliser le plugin Bluetooth
sleep 2

# 3. --- Préparer l'agent Bluetooth ---
bluetoothctl agent on 2>/dev/null || true
bluetoothctl default-agent 2>/dev/null || true

# 4. --- Boucle de connexion robuste ---
CONNECTED_COUNT=0
for mac in $MACS; do
    echo "Vérification enceinte : $mac"

    # Si déjà connecté, on passe à la suivante
    if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
        echo "Enceinte $mac déjà connectée."
        CONNECTED_COUNT=$((CONNECTED_COUNT + 1))
        continue
    fi

    # Si l'appareil est totalement inconnu, on tente un scan rapide
    if ! bluetoothctl info "$mac" 2>&1 | grep -q "Device $mac"; then
        echo "Appareil $mac inconnu — scan de 8s..."
        bluetoothctl scan on &
        SCAN_PID=$!
        sleep 8
        kill "$SCAN_PID" 2>/dev/null || true
        wait "$SCAN_PID" 2>/dev/null || true
    fi

    # Tentatives de connexion (5 essais)
    for i in $(seq 1 5); do
        echo "Tentative de connexion $i/5 vers $mac..."
        if bluetoothctl connect "$mac" 2>&1 | grep -q "Connection successful"; then
            echo "Succès : $mac connecté."
            CONNECTED_COUNT=$((CONNECTED_COUNT + 1))
            break
        fi
        sleep 5
    done
done

# 5. --- Finalisation ---
if [ "$CONNECTED_COUNT" -gt 0 ]; then
    # Si plusieurs enceintes, on les regroupe
    if [ $(echo "$MACS" | wc -w) -gt 1 ]; then
        sleep 2
        /opt/soundspot/backend/system/bt-combine-sinks.sh 2>/dev/null || true
    fi

    # TRÈS IMPORTANT : Relancer le client pour qu'il "voit" la sortie Bluetooth
    echo "Relance de soundspot-client pour basculer sur le Bluetooth..."
    systemctl restart soundspot-client
else
    echo "Échec : aucune enceinte connectée."
    exit 1
fi

exit 0