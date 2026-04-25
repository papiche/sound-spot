#!/bin/bash
# ============================================================
#  SoundSpot Satellite — G1FabLab / UPlanet ẐEN
#  Script d'installation pour RPi Zero 2W satellite
#
#  Réseau : uniquement l'AP WiFi du maître (SPOT_NAME, ouvert).
#  Le maître fait le NAT → le satellite a Internet via lui.
#  IP maître toujours fixe : 192.168.10.1
#
#  Pré-requis : le RPi maître doit être allumé et son AP actif.
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Modules d'installation ───────────────────────────────────
source "$SCRIPT_DIR/install/colors.sh"
source "$SCRIPT_DIR/install/bluetooth.sh"
source "$SCRIPT_DIR/install/pipewire.sh"
source "$SCRIPT_DIR/install/snapclient.sh"


# ── Variables configurables ─────────────────────────────────
TARGET_MASTER="${TARGET_MASTER:-soundspot-zicmama}"
MASTER_HOST="${MASTER_HOST:-${TARGET_MASTER}.local}"
SPOT_NAME="${SPOT_NAME:-ZICMAMA}"            # SSID AP du maître (pour roaming)
SNAPCAST_PORT="${SNAPCAST_PORT:-1704}"
BT_MAC="${BT_MAC:-}"
BT_MACS="${BT_MACS:-${BT_MAC:-}}"           # Liste MACs séparés par espaces (multi-enceintes)
INSTALL_DIR="/opt/soundspot"
PICOPORT_ENABLED="${PICOPORT_ENABLED:-true}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
SOUNDSPOT_LOG="${SOUNDSPOT_LOG:-/var/log/soundspot.log}"
export SOUNDSPOT_USER="${SOUNDSPOT_USER:-${SUDO_USER:-pi}}"
export SOUNDSPOT_UID=$(id -u "${SOUNDSPOT_USER}" 2>/dev/null || echo "1000")

# ── Vérifications ────────────────────────────────────────────
hdr "Vérifications"
[ "$(id -u)" -eq 0 ] || err "Lance ce script en root : sudo bash install_satellite.sh"
grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null || warn "Pas un RPi — on continue"
log "Mode satellite → snapserver ${MASTER_HOST}:${SNAPCAST_PORT}"

# ── Sélecteur de sortie audio ────────────────────────────────
hdr "Sélection de la sortie audio"
echo -e "
${W}Quelle est la sortie audio de ce satellite ?${N}

  1) ${C}HDMI${N}           — écran / vidéoprojecteur (dtoverlay=vc4-kms-v3d)
  2) ${C}Bluetooth${N}      — enceinte déportée (pipewire + bluez A2DP)
  3) ${C}Audio HAT${N}      — carte son HAT (pHAT DAC, HiFiBerry, ReSpeaker…)

"
AUDIO_OUTPUT=""
while [ -z "$AUDIO_OUTPUT" ]; do
    read -rp "Choix [1/2/3] : " _choice
    case "$_choice" in
        1) AUDIO_OUTPUT="hdmi"      ;;
        2) AUDIO_OUTPUT="bluetooth" ;;
        3) AUDIO_OUTPUT="hat"       ;;
        *) echo "Entrée invalide — tapez 1, 2 ou 3." ;;
    esac
done

CONFIG_TXT="/boot/firmware/config.txt"
[ -f "$CONFIG_TXT" ] || CONFIG_TXT="/boot/config.txt"   # Bookworm vs Buster

_configure_audio_hdmi() {
    log "Mode HDMI : activation vc4-kms-v3d"
    # S'assurer que HDMI audio est actif et que les sorties analogiques/HAT sont hors-jeu
    sed -i 's/^dtoverlay=vc4-kms-v3d.*$/dtoverlay=vc4-kms-v3d/' "$CONFIG_TXT" 2>/dev/null || \
        echo "dtoverlay=vc4-kms-v3d" >> "$CONFIG_TXT"
    # Désactiver la sortie audio 3.5 mm PWM (économie d'énergie)
    grep -q "^dtparam=audio=" "$CONFIG_TXT" \
        && sed -i 's/^dtparam=audio=.*/dtparam=audio=off/' "$CONFIG_TXT" \
        || echo "dtparam=audio=off" >> "$CONFIG_TXT"
    export BT_MACS=""   # Pas de BT
}

_configure_audio_bluetooth() {
    log "Mode Bluetooth : pipewire A2DP — dtparam=audio=off"
    grep -q "^dtparam=audio=" "$CONFIG_TXT" \
        && sed -i 's/^dtparam=audio=.*/dtparam=audio=off/' "$CONFIG_TXT" \
        || echo "dtparam=audio=off" >> "$CONFIG_TXT"
    # Retirer tout HAT audio éventuel
    sed -i '/^dtoverlay=hifiberry/d;/^dtoverlay=phat-dac/d;/^dtoverlay=fe-pi/d' "$CONFIG_TXT" 2>/dev/null || true
    log "BT MACs : ${BT_MACS:-à définir dans soundspot.conf}"
}

_configure_audio_hat() {
    echo -e "
${W}Quel HAT audio ?${N}

  1) pHAT DAC (Pimoroni)         → dtoverlay=hifiberry-dac
  2) HiFiBerry DAC+              → dtoverlay=hifiberry-dacplus
  3) HiFiBerry AMP+              → dtoverlay=hifiberry-amp
  4) ReSpeaker 2-mic Pi HAT      → (driver séparé — voir install/respeaker.sh)
  5) Autre (saisie manuelle)

"
    HAT_OVERLAY=""
    while [ -z "$HAT_OVERLAY" ]; do
        read -rp "Choix [1-5] : " _h
        case "$_h" in
            1) HAT_OVERLAY="hifiberry-dac"     ;;
            2) HAT_OVERLAY="hifiberry-dacplus"  ;;
            3) HAT_OVERLAY="hifiberry-amp"      ;;
            4) HAT_OVERLAY="respeaker"          ;;
            5) read -rp "Overlay dtoverlay= : " HAT_OVERLAY ;;
            *) echo "Choix invalide." ;;
        esac
    done

    if [ "$HAT_OVERLAY" = "respeaker" ]; then
        log "ReSpeaker : driver séparé — exécutez install/respeaker.sh manuellement"
    else
        log "HAT audio : dtoverlay=${HAT_OVERLAY}"
        # Retirer les anciens overlays audio HAT
        sed -i '/^dtoverlay=hifiberry/d;/^dtoverlay=phat-dac/d;/^dtoverlay=fe-pi/d' "$CONFIG_TXT" 2>/dev/null || true
        echo "dtoverlay=${HAT_OVERLAY}" >> "$CONFIG_TXT"
    fi
    # Désactiver la sortie PWM (conflit avec HAT I2S)
    grep -q "^dtparam=audio=" "$CONFIG_TXT" \
        && sed -i 's/^dtparam=audio=.*/dtparam=audio=off/' "$CONFIG_TXT" \
        || echo "dtparam=audio=off" >> "$CONFIG_TXT"
    export BT_MACS=""   # Pas de BT
}

case "$AUDIO_OUTPUT" in
    hdmi)      _configure_audio_hdmi      ;;
    bluetooth) _configure_audio_bluetooth ;;
    hat)       _configure_audio_hat       ;;
esac

log "config.txt : sortie audio configurée → ${AUDIO_OUTPUT}"

# ── Paquets ──────────────────────────────────────────────────
hdr "Installation des paquets"
apt_retry update -qq
PKGS="bluez libspa-0.2-bluetooth pipewire pipewire-alsa pipewire-pulse wireplumber snapclient iw wireless-tools zram-tools python3-websockets"
[ "$AUDIO_OUTPUT" = "bluetooth" ] && PKGS="$PKGS bluez-alsa-utils"
apt_retry install -y --no-install-recommends $PKGS

mkdir -p "$INSTALL_DIR/backend/system"

# ── log2ram : /var/log en RAM (protection SD solaire) ────────
hdr "log2ram — /var/log en RAM"
if ! command -v log2ram &>/dev/null; then
    KEYRING="/usr/share/keyrings/azlux-archive-keyring.gpg"
    wget -qO "$KEYRING" https://azlux.fr/repo.gpg 2>/dev/null \
        && echo "deb [signed-by=${KEYRING}] http://packages.azlux.fr/debian/ bookworm main" \
            > /etc/apt/sources.list.d/azlux.list \
        && apt-get update -qq 2>/dev/null \
        && apt-get install -y -q log2ram 2>/dev/null \
        && sed -i 's/^SIZE=.*/SIZE=128M/;s/^MAIL=true/MAIL=false/' /etc/log2ram.conf 2>/dev/null \
        && log "log2ram installé ✓" \
        || warn "log2ram non installé — logs sur SD"
else
    log "log2ram déjà présent ✓"
fi

# ── Groupe système soundspot ─────────────────────────────────
groupadd --system soundspot 2>/dev/null || true
for _u in "${SOUNDSPOT_USER}" www-data; do
    id "$_u" &>/dev/null && usermod -aG soundspot "$_u" || true
done

# ── Configuration ─────────────────────────────────────────────
[ "$AUDIO_OUTPUT" = "bluetooth" ] && setup_bluetooth
setup_pipewire
setup_snapclient satellite

# Reconnexion BT réactive (remplace le polling 60s de bt-autoconnect)
if [ "$AUDIO_OUTPUT" = "bluetooth" ]; then
    install_template soundspot-bt-reactive.service \
        /etc/systemd/system/soundspot-bt-reactive.service \
        '${INSTALL_DIR} ${SOUNDSPOT_USER} ${SOUNDSPOT_UID}'
    systemctl disable bt-autoconnect 2>/dev/null || true
    systemctl enable soundspot-bt-reactive
    log "BT réactif activé — bt-autoconnect désactivé"
fi

# ── Fichier de configuration central ─────────────────────────
hdr "Fichier de configuration central"
install_template soundspot.conf.satellite.env "$INSTALL_DIR/soundspot.conf" \
    '${MASTER_HOST} ${TARGET_MASTER} ${SPOT_NAME} ${SNAPCAST_PORT} ${BT_MAC} ${BT_MACS} ${INSTALL_DIR} ${SOUNDSPOT_USER} ${PICOPORT_ENABLED} ${LOG_LEVEL} ${SOUNDSPOT_LOG}'
chgrp soundspot "$INSTALL_DIR/soundspot.conf" 2>/dev/null || true
chmod 640 "$INSTALL_DIR/soundspot.conf"

# ── Roaming dual-réseau (AP maître + réseau amont) ────────────
hdr "Roaming WiFi dual-réseau"
if command -v nmcli &>/dev/null && [ -n "${WIFI_SSID:-}" ]; then
    # Réseau amont (qo-op) — basse priorité
    nmcli con delete "soundspot-upstream" 2>/dev/null || true
    nmcli con add type wifi ifname wlan0 con-name "soundspot-upstream" \
        ssid "$WIFI_SSID" -- wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$WIFI_PASS" 2>/dev/null \
        && nmcli con mod "soundspot-upstream" connection.autoconnect yes \
                         connection.autoconnect-priority 10 \
        && log "Réseau amont ${WIFI_SSID} (priorité 10) ✓" \
        || warn "nmcli : impossible d'ajouter ${WIFI_SSID}"

    # AP maître — haute priorité
    nmcli con delete "soundspot-ap" 2>/dev/null || true
    nmcli con add type wifi ifname wlan0 con-name "soundspot-ap" \
        ssid "$SPOT_NAME" -- wifi-sec.key-mgmt none 2>/dev/null \
        && nmcli con mod "soundspot-ap" connection.autoconnect yes \
                         connection.autoconnect-priority 20 \
        && log "AP maître ${SPOT_NAME} (priorité 20) ✓" \
        || warn "nmcli : impossible d'ajouter ${SPOT_NAME}"
else
    warn "nmcli absent ou WIFI_SSID vide — roaming dual-réseau non configuré"
fi

# ── Astroport.ONE léger (keygen + outils flotte NOSTR) ───────
if [ "${PICOPORT_ENABLED:-true}" = "true" ]; then
    hdr "Astroport.ONE léger (keygen flotte)"
    ASTRO_LIGHT="${SCRIPT_DIR}/picoport/install_astroport_light.sh"
    if [ -f "$ASTRO_LIGHT" ]; then
        mkdir -p "$INSTALL_DIR/picoport"
        cp "$ASTRO_LIGHT" "$INSTALL_DIR/picoport/"
        chown "${SOUNDSPOT_USER}:${SOUNDSPOT_USER}" "$INSTALL_DIR/picoport/install_astroport_light.sh"
        sudo -u "${SOUNDSPOT_USER}" bash "$INSTALL_DIR/picoport/install_astroport_light.sh" 2>/dev/null \
            && log "Astroport.ONE cloné — keygen disponible" \
            || warn "Clone Astroport.ONE partiel (Internet requis)"
    else
        warn "install_astroport_light.sh introuvable"
    fi
fi

# ── Scripts + service flotte NOSTR ───────────────────────────
for _f in fleet_listener.sh amiral_keygen.sh fleet_relay.py; do
    _src="${SCRIPT_DIR}/backend/system/${_f}"
    [ -f "$_src" ] && cp "$_src" "$INSTALL_DIR/backend/system/" || true
done
chmod +x "$INSTALL_DIR/backend/system/"*.sh 2>/dev/null || true

if [ "${PICOPORT_ENABLED:-true}" = "true" ]; then
    # Génération clé Amiral (même dérivation que le maître → même npub)
    bash "${INSTALL_DIR}/backend/system/amiral_keygen.sh" \
        && log "Clé Amiral dérivée ✓" \
        || warn "amiral_keygen.sh échoué (pynostr ou swarm.key absent)"

    install_template soundspot-fleet.service \
        /etc/systemd/system/soundspot-fleet.service \
        '${INSTALL_DIR}'
    systemctl enable soundspot-fleet
    log "Fleet listener activé (écoute relay maître port 9999)"
fi

# ── Résumé ────────────────────────────────────────────────────
hdr "Installation satellite terminée ✓"
echo -e "
${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}
${G}  SoundSpot Satellite installé !${N}
${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}

  Maître Snapcast : ${C}${MASTER_HOST}:${SNAPCAST_PORT}${N}
  Sortie audio    : ${W}${AUDIO_OUTPUT}${N}
  Enceinte(s) BT  : ${W}${BT_MACS:-n/a}${N}

${Y}Si une enceinte BT n'est pas couplée :${N}
  bluetoothctl → power on / scan on / pair / trust / connect
  nano ${INSTALL_DIR}/soundspot.conf   # BT_MACS=\"AA:BB:CC:DD:EE:FF\"
  sudo systemctl enable bt-autoconnect

${Y}Un redémarrage est nécessaire pour activer la config.txt.${N}
${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}
"
