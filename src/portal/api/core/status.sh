#!/bin/bash
# api/core/status.sh — État du système SoundSpot
# Appelé par api.sh (hérite des exports : SPOT_NAME, SPOT_IP, ICECAST_PORT, …)

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

cat <<JSON
{
  "spot_name": "${SPOT_NAME}",
  "spot_ip": "${SPOT_IP}",
  "snapcast_port": ${SNAPCAST_PORT},
  "icecast_port": ${ICECAST_PORT},
  "dj_active": ${DJ_ACTIVE},
  "clock_mode": "${CLOCK_MODE}",
  "voice_enabled": ${VOICE_ENABLED},
  "bells_enabled": ${BELLS_ENABLED},
  "picoport_active": ${PICOPORT_ACTIVE},
  "cpu_load": "${CPU_LOAD}",
  "mem_free_kb": ${MEM_FREE},
  "batt_pct": ${BATT_PCT},
  "batt_volt": ${BATT_VOLT},
  "batt_cur": ${BATT_CUR},
  "batt_pow": ${BATT_POW},
  "services": {
    "snapserver":        "${SVC_SNAPSERVER}",
    "soundspot-decoder": "${SVC_DECODER}",
    "soundspot-client":  "${SVC_CLIENT}",
    "soundspot-idle":    "${SVC_IDLE}",
    "icecast2":          "${SVC_ICECAST}",
    "lighttpd":          "${SVC_LIGHTTPD}",
    "picoport":          "${SVC_PICOPORT}",
    "soundspot-bt-reactive": "${SVC_BT_REACTIVE}"
  }
}
JSON
