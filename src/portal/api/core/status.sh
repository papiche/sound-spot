#!/bin/bash
# api/status.sh — État du système SoundSpot
# Appelé par api.sh (hérite des exports : SPOT_NAME, SPOT_IP, ICECAST_PORT, …)

DJ_ACTIVE="false"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 1 \
    "http://127.0.0.1:${ICECAST_PORT}/live" 2>/dev/null || echo "000")
[ "$HTTP_CODE" = "200" ] && DJ_ACTIVE="true"

PICOPORT_ACTIVE="false"
systemctl is-active --quiet picoport.service 2>/dev/null && PICOPORT_ACTIVE="true"

# Charge CPU (1 min)
CPU_LOAD=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo "0")

# Mémoire libre (ko)
MEM_FREE=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null || echo "0")

cat <<JSON
{
  "spot_name": "${SPOT_NAME}",
  "spot_ip": "${SPOT_IP}",
  "snapcast_port": ${SNAPCAST_PORT},
  "icecast_port": ${ICECAST_PORT},
  "dj_active": ${DJ_ACTIVE},
  "clock_mode": "${CLOCK_MODE}",
  "picoport_active": ${PICOPORT_ACTIVE},
  "cpu_load": "${CPU_LOAD}",
  "mem_free_kb": ${MEM_FREE}
}
JSON
