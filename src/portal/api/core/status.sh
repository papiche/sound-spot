#!/bin/bash
# api/core/status.sh — État du système SoundSpot
# Appelé par api.sh (hérite des exports : SPOT_NAME, SPOT_IP, ICECAST_PORT, …)

_SS_SERVICE="portal-status"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

VOICE_ENABLED="${VOICE_ENABLED:-true}"
BELLS_ENABLED="${BELLS_ENABLED:-true}"
DJ_ACTIVE="false"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 1 \
    "http://127.0.0.1:${ICECAST_PORT}/live" 2>/dev/null || echo "000")
[ "$HTTP_CODE" = "200" ] && DJ_ACTIVE="true"

PICOPORT_ACTIVE="false"
systemctl is-active --quiet picoport.service 2>/dev/null && PICOPORT_ACTIVE="true"

CPU_LOAD=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo "0")
MEM_FREE=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null || echo "0")

# Batterie INA219 — données en /dev/shm (RAM, zéro écriture SD)
BATT_PCT=$(cat /dev/shm/battery_percent  2>/dev/null || echo "0")
BATT_VOLT=$(cat /dev/shm/battery_voltage 2>/dev/null || echo "0")
BATT_CUR=$(cat /dev/shm/battery_current  2>/dev/null || echo "0")
BATT_POW=$(cat /dev/shm/battery_power    2>/dev/null || echo "0")

# États des services systemd
_svc() { systemctl is-active "$1" 2>/dev/null || echo "inactive"; }
SVC_SNAPSERVER=$(_svc snapserver)
SVC_DECODER=$(_svc soundspot-decoder)
SVC_CLIENT=$(_svc soundspot-client)
SVC_IDLE=$(_svc soundspot-idle)
SVC_ICECAST=$(_svc icecast2)
SVC_LIGHTTPD=$(_svc lighttpd)
SVC_PICOPORT=$(_svc picoport)
SVC_BT_REACTIVE=$(_svc soundspot-bt-reactive)

jq -n \
  --arg spot_name "$SPOT_NAME" \
  --arg spot_ip "$SPOT_IP" \
  --argjson snapcast_port "$SNAPCAST_PORT" \
  --argjson icecast_port "$ICECAST_PORT" \
  --argjson dj_active "$DJ_ACTIVE" \
  --arg clock_mode "$CLOCK_MODE" \
  --argjson voice_enabled "$VOICE_ENABLED" \
  --argjson bells_enabled "$BELLS_ENABLED" \
  --argjson picoport_active "$PICOPORT_ACTIVE" \
  --arg cpu_load "$CPU_LOAD" \
  --argjson mem_free_kb "$MEM_FREE" \
  --argjson batt_pct "${BATT_PCT:-0}" \
  --argjson batt_volt "${BATT_VOLT:-0}" \
  --argjson batt_cur "${BATT_CUR:-0}" \
  --argjson batt_pow "${BATT_POW:-0}" \
  --arg svc_snapserver "$SVC_SNAPSERVER" \
  --arg svc_decoder "$SVC_DECODER" \
  --arg svc_client "$SVC_CLIENT" \
  --arg svc_idle "$SVC_IDLE" \
  --arg svc_icecast "$SVC_ICECAST" \
  --arg svc_lighttpd "$SVC_LIGHTTPD" \
  --arg svc_picoport "$SVC_PICOPORT" \
  --arg svc_bt_reactive "$SVC_BT_REACTIVE" \
  '{
    spot_name: $spot_name,
    spot_ip: $spot_ip,
    snapcast_port: $snapcast_port,
    icecast_port: $icecast_port,
    dj_active: $dj_active,
    clock_mode: $clock_mode,
    voice_enabled: $voice_enabled,
    bells_enabled: $bells_enabled,
    picoport_active: $picoport_active,
    cpu_load: $cpu_load,
    mem_free_kb: $mem_free_kb,
    batt_pct: $batt_pct,
    batt_volt: $batt_volt,
    batt_cur: $batt_cur,
    batt_pow: $batt_pow,
    services: {
      snapserver: $svc_snapserver,
      "soundspot-decoder": $svc_decoder,
      "soundspot-client": $svc_client,
      "soundspot-idle": $svc_idle,
      icecast2: $svc_icecast,
      lighttpd: $svc_lighttpd,
      picoport: $svc_picoport,
      "soundspot-bt-reactive": $svc_bt_reactive
    }
  }'
