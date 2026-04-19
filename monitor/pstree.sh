#!/usr/bin/env bash

INTERVAL=1
USER_FILTER="$USER"
CPU_ALERT=80
LOG_FILE="$HOME/proc_watch.log"

has_fzf=$(command -v fzf)
has_htop=$(command -v htop)
has_perf=$(command -v perf)

function log_msg() {
    echo "[$(date '+%F %T')] $1" >> "$LOG_FILE"
}

function select_process() {
    if [[ -n "$has_fzf" ]]; then
        ps -u "$USER_FILTER" -o pid,ppid,cmd,%cpu,%mem --sort=-%cpu --no-headers \
        | fzf --header="PID PPID CMD CPU% MEM%" \
        | awk '{print $1}'
    else
        read -rp "PID: " pid
        echo "$pid"
    fi
}

function monitor_process() {
    local pid="$1"

    watch -n "$INTERVAL" "
        CPU=\$(ps -p $pid -o %cpu= | awk '{print int(\$1)}')

        echo '=== PROCESS ==='
        ps -fp $pid

        echo
        echo '=== TREE ==='
        pstree -ap -s $pid

        echo
        echo '=== THREADS ==='
        ps -T -p $pid

        echo
        echo '=== NETWORK (ss) ==='
        ss -p | grep $pid | head -10

        echo
        echo '=== FILES ==='
        lsof -p $pid 2>/dev/null | head -10

        if [ \"\$CPU\" -gt $CPU_ALERT ]; then
            echo '!!! CPU ALERT !!!'
            echo \"PID $pid CPU=\$CPU%\" 
        fi
    " | while read -r line; do
        echo "$line"
        log_msg "$line"
    done
}

function trace_syscalls() {
    local pid="$1"
    echo "Attach strace sur PID $pid (Ctrl+C pour quitter)"
    strace -p "$pid" -tt -T -f 2>&1 | tee -a "$LOG_FILE"
}

function profile_cpu() {
    local pid="$1"

    if [[ -z "$has_perf" ]]; then
        echo "perf non installé"
        return
    fi

    echo "Profil CPU sur PID $pid (10s)..."
    sudo perf top -p "$pid"
}

function system_overview() {
    watch -n "$INTERVAL" "
        echo '=== TOP CPU ==='
        ps -eo pid,cmd,%cpu,%mem --sort=-%cpu | head -10

        echo
        echo '=== NETWORK GLOBAL ==='
        ss -tupn | head -10

        echo
        echo '=== LOAD ==='
        uptime
    "
}

function menu() {
    clear
    echo "==== PROC WATCH PLUS ===="
    echo "1) Vue système"
    echo "2) Sélectionner & monitor process"
    echo "3) strace (syscalls)"
    echo "4) perf (CPU profiling)"
    if [[ -n "$has_htop" ]]; then
        echo "5) htop"
    fi
    echo "q) Quitter"
    echo

    read -rp "Choix: " choice

    case "$choice" in
        1) system_overview ;;
        2)
            pid=$(select_process)
            [[ -n "$pid" ]] && monitor_process "$pid"
            ;;
        3)
            pid=$(select_process)
            [[ -n "$pid" ]] && trace_syscalls "$pid"
            ;;
        4)
            pid=$(select_process)
            [[ -n "$pid" ]] && profile_cpu "$pid"
            ;;
        5)
            [[ -n "$has_htop" ]] && htop
            ;;
        q) exit 0 ;;
    esac
}

while true; do
    menu
done