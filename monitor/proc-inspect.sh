#!/usr/bin/env bash

set -e

LOG_FILE="$HOME/proc-inspect.log"

function help() {
cat <<EOF
proc-inspect — observabilité des processus (systemd, bash, python)

USAGE:
  proc-inspect [mode] [options]

MODES:
  --find <name>           Trouver PID par nom
  --unit <systemd-unit>   Trouver PID d’un service systemd
  --trace <PID>           Monitor complet (process, réseau, fichiers)
  --exec <PID>            Voir commandes lancées (execve)
  --syscalls <PID>        Tracer syscalls (strace)
  --launch "<cmd>"        Lancer et tracer un programme
  --overview              Vue système globale

OPTIONS:
  --interval N            Refresh (défaut: 1s)
  --log FILE              Fichier de log

DOC:
  --howto                 Guide d’utilisation

EXEMPLES:
  proc-inspect --unit nginx --trace
  proc-inspect --find python --exec
  proc-inspect --launch "python app.py"

EOF
}

function howto() {
cat <<EOF
=== HOWTO ===

🔎 Analyser un service systemd :
  proc-inspect --unit nginx --trace

👉 récupère automatiquement le PID principal

📜 Voir ce qu’un script lance réellement :
  proc-inspect --exec <PID>

👉 basé sur execve (fiable)

🧠 Debug complet d’un script bash/python :
  proc-inspect --trace <PID>

👉 tu vois :
  - commande complète
  - enfants
  - réseau
  - fichiers ouverts

🚀 Meilleur mode pour comprendre un programme :
  proc-inspect --launch "commande"

👉 trace tout dès le début (recommandé)

⚠️ Tips :
- utilise sudo pour systemd et perf
- execve = vérité terrain
- strace ralentit → normal

EOF
}

INTERVAL=1

# args parsing
MODE=""
TARGET=""
CMD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help) help; exit 0 ;;
        --howto) howto; exit 0 ;;
        --find) MODE="find"; TARGET="$2"; shift ;;
        --unit) MODE="unit"; TARGET="$2"; shift ;;
        --trace) MODE="trace"; TARGET="$2"; shift ;;
        --exec) MODE="exec"; TARGET="$2"; shift ;;
        --syscalls) MODE="syscalls"; TARGET="$2"; shift ;;
        --launch) MODE="launch"; CMD="$2"; shift ;;
        --overview) MODE="overview" ;;
        --interval) INTERVAL="$2"; shift ;;
        --log) LOG_FILE="$2"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

function log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

function get_pid_from_unit() {
    systemctl show -p MainPID --value "$1"
}

function full_cmd() {
    tr '\0' ' ' < /proc/$1/cmdline
}

function trace() {
    local pid="$1"

    watch -n "$INTERVAL" "
        echo '=== PID $pid ==='
        echo CMD: \$(tr '\0' ' ' < /proc/$pid/cmdline)

        echo
        echo '=== TREE ==='
        pstree -ap $pid

        echo
        echo '=== CPU/MEM ==='
        ps -p $pid -o %cpu,%mem,etime

        echo
        echo '=== NETWORK ==='
        ss -p | grep $pid

        echo
        echo '=== FILES ==='
        lsof -p $pid 2>/dev/null | head
    "
}

function exec_trace() {
    local pid="$1"
    log "Tracing execve for PID $pid"

    strace -f -e execve -s 200 -p "$pid" 2>&1 \
    | while read -r line; do
        echo "$line"
        log "$line"
    done
}

function syscall_trace() {
    local pid="$1"
    log "Tracing syscalls for PID $pid"

    strace -f -tt -T -s 200 -p "$pid" 2>&1 | tee -a "$LOG_FILE"
}

function launch_trace() {
    log "Launching: $CMD"

    strace -f -e execve -s 200 bash -c "$CMD" 2>&1 \
    | while read -r line; do
        echo "$line"
        log "$line"
    done
}

function overview() {
    watch -n "$INTERVAL" "
        echo '=== TOP ==='
        ps -eo pid,cmd,%cpu,%mem --sort=-%cpu | head

        echo
        echo '=== SYSTEMD ==='
        systemctl list-units --type=service --state=running | head

        echo
        echo '=== NETWORK ==='
        ss -tupn | head
    "
}

# dispatch
case "$MODE" in
    find)
        pgrep -af "$TARGET"
        ;;
    unit)
        pid=$(get_pid_from_unit "$TARGET")
        echo "PID: $pid"
        ;;
    trace)
        trace "$TARGET"
        ;;
    exec)
        exec_trace "$TARGET"
        ;;
    syscalls)
        syscall_trace "$TARGET"
        ;;
    launch)
        launch_trace
        ;;
    overview)
        overview
        ;;
    *)
        help
        ;;
esac