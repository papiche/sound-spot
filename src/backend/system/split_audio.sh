#!/bin/bash
# split_audio.sh — Fusionne le Jack 3.5mm et le HDMI pour l'émetteur FM et le projecteur
export XDG_RUNTIME_DIR="/run/user/$(id -u ${SOUNDSPOT_USER:-pi} 2>/dev/null || echo 1000)"

# Trouver les sinks ALSA correspondant à l'analogique et au HDMI
SINK_JACK=$(pactl list sinks short | grep "alsa_output.*analog-stereo" | awk '{print $2}' | head -n 1)
SINK_HDMI=$(pactl list sinks short | grep "alsa_output.*hdmi-stereo" | awk '{print $2}' | head -n 1)

if [ -n "$SINK_JACK" ] && [ -n "$SINK_HDMI" ]; then
    pactl unload-module module-combine-sink 2>/dev/null || true
    pactl load-module module-combine-sink sink_name=split_hdmi_jack slaves=$SINK_JACK,$SINK_HDMI sink_properties=device.description=Projector_FM_Split
    pactl set-default-sink split_hdmi_jack
    echo "Split Audio activé : HDMI + Jack FM"
else
    echo "Impossible de créer le split : Jack ou HDMI introuvable/débranché."
fi
