#!/bin/bash
# bt-combine-sinks.sh — regroupe tous les sinks BT en un sink combiné
# Appelé par bt-connect.sh après connexion des enceintes Bluetooth.
# Fonctionne avec PipeWire (via compatibilité PulseAudio) et PulseAudio natif.

export XDG_RUNTIME_DIR="/run/user/$(id -u pi 2>/dev/null || echo 1000)"

BT_SINKS=$(pactl list sinks short 2>/dev/null \
    | grep -i "bluez\|bluetooth" | awk '{print $2}')

[ -z "$BT_SINKS" ] && { echo "Aucun sink BT trouvé"; exit 0; }

SINK_COUNT=$(echo "$BT_SINKS" | wc -l)
if [ "$SINK_COUNT" -lt 2 ]; then
    DEFAULT=$(echo "$BT_SINKS" | head -1)
    pactl set-default-sink "$DEFAULT" 2>/dev/null || true
    echo "Sink BT défaut : $DEFAULT"
    exit 0
fi

# Décharger un ancien sink combiné s'il existe
pactl unload-module module-combine-sink 2>/dev/null || true

# Créer le sink combiné avec tous les BT
SLAVES=$(echo "$BT_SINKS" | tr '\n' ',' | sed 's/,$//')
pactl load-module module-combine-sink \
    sink_name=bt_combined \
    sink_properties=device.description=SoundSpot_BT_Combined \
    slaves="$SLAVES" 2>/dev/null \
    && pactl set-default-sink bt_combined \
    && echo "Sink combiné créé : $SLAVES" \
    || { echo "Échec combine-sink, sink défaut = $(echo "$BT_SINKS" | head -1)";
         pactl set-default-sink "$(echo "$BT_SINKS" | head -1)" 2>/dev/null || true; }
