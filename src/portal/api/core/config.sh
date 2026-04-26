#!/bin/bash
# api/core/config.sh — Variables de configuration pour le front-end statique
#
# Appelé au démarrage de l'app JS :  fetch('/api.sh?action=config')
# Permet à index.html d'être un fichier 100% statique (sans bash injecté).
# Hérite des exports de api.sh.

# Vérifier si yt-dlp est disponible (conditionne l'affichage du module YouTube)
YT_DLP_AVAILABLE="false"
command -v yt-dlp &>/dev/null && YT_DLP_AVAILABLE="true"

# Vérifier si jq est disponible (requis pour yt_copy)
JQ_AVAILABLE="false"
command -v jq &>/dev/null && JQ_AVAILABLE="true"

# Version du portail (git describe si possible)
PORTAL_VERSION=$(git -C "${INSTALL_DIR}" describe --tags --always 2>/dev/null || echo "dev")

_HOSTNAME=$(hostname 2>/dev/null || echo "soundspot")
_WAN_IP=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1 || echo "")
_BT_MACS="${BT_MACS:-${BT_MAC:-}}"

jq -n \
    --arg spot_name       "$SPOT_NAME" \
    --arg spot_ip         "$SPOT_IP" \
    --argjson snapcast_port "${SNAPCAST_PORT}" \
    --argjson snapcast_http 1780 \
    --argjson icecast_port  "${ICECAST_PORT}" \
    --arg clock_mode      "$CLOCK_MODE" \
    --argjson voice_enabled "$([ "${VOICE_ENABLED:-true}" = "false" ] && echo false || echo true)" \
    --argjson bells_enabled "$([ "${BELLS_ENABLED:-true}" = "false" ] && echo false || echo true)" \
    --argjson picoport    "$([ "${PICOPORT_ENABLED:-true}" = "true" ] && echo true || echo false)" \
    --argjson yt_available "$YT_DLP_AVAILABLE" \
    --argjson jq_available "$JQ_AVAILABLE" \
    --arg version         "$PORTAL_VERSION" \
    --arg hostname        "$_HOSTNAME" \
    --arg wan_ip          "$_WAN_IP" \
    --arg bt_macs         "$_BT_MACS" \
    '{
      spot_name:        $spot_name,
      spot_ip:          $spot_ip,
      snapcast_port:    $snapcast_port,
      icecast_port:     $icecast_port,
      clock_mode:       $clock_mode,
      voice_enabled:    $voice_enabled,
      bells_enabled:    $bells_enabled,
      picoport_enabled: $picoport,
      yt_available:     $yt_available,
      jq_available:     $jq_available,
      version:          $version,
      hostname:         $hostname,
      wan_ip:           $wan_ip,
      bt_macs:          $bt_macs,
      links: {
        snapdroid_fdroid: "https://f-droid.org/en/packages/de.badaix.snapcast/",
        snapdroid_play:   "https://play.google.com/store/apps/details?id=de.badaix.snapcast",
        snapcast_ios:     "https://apps.apple.com/app/snapcast-client/id1552559654",
        zelkova_release:  "https://github.com/papiche/zelkova/releases/latest",
        g1fablab:         "https://opencollective.com/monnaie-libre",
        uplanet:          "https://qo-op.com",
        source:           "https://github.com/papiche/sound-spot"
      }
    }'
