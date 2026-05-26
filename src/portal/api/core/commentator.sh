#!/bin/bash
# api/core/commentator.sh — Contrôle du Commentateur IA de flux vidéo
#
# Démarre/arrête stream_commentator.py et configure ses paramètres à chaud.
#
# GET  /api.sh?action=commentator&cmd=status
# POST /api.sh?action=commentator   body: cmd=start|stop|interval|style
#                                         value=<N>   (pour interval, en secondes)
#                                         value=<S>   (pour style: concert|accueil|poetic|free)

_SS_SERVICE="portal-commentator"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

ENABLED_FLAG="/dev/shm/commentator_enabled"
INTERVAL_F="/dev/shm/commentator_interval"
STYLE_F="/dev/shm/commentator_style"
LAST_F="/dev/shm/commentator_last"
PID_FILE="/dev/shm/commentator.pid"
CURRENT_VJ="/dev/shm/current_vj"
COMMENTATOR_PY="${INSTALL_DIR:-/opt/soundspot}/backend/video/stream_commentator.py"
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"

# ── Lecture paramètre ─────────────────────────────────────────────────
read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
CMD=$(echo "$QUERY_STRING$POST_DATA" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)
VALUE=$(echo "$POST_DATA" | grep -oP '(?<=value=)[^&]+' | head -1 | tr -cd '[:alnum:]-._')
[ -z "$CMD" ] && CMD="status"

# ── Helpers ───────────────────────────────────────────────────────────
_is_enabled()  { [ -f "$ENABLED_FLAG" ]; }
_pid_alive()   {
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null) && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}
_interval()    { cat "$INTERVAL_F" 2>/dev/null || echo "60"; }
_style()       { cat "$STYLE_F"    2>/dev/null || echo "concert"; }
_last()        { cat "$LAST_F"     2>/dev/null || echo ""; }
_stream()      { cat "$CURRENT_VJ" 2>/dev/null | tr -d '\n' || echo ""; }

_start_daemon() {
    _pid_alive && return 0
    [ -f "$COMMENTATOR_PY" ] || { ss_warn "commentator.py introuvable"; return 1; }
    nohup sudo -u "$SOUNDSPOT_USER" \
        python3 "$COMMENTATOR_PY" \
        >> /var/log/sound-spot.log 2>&1 &
    sleep 1
    _pid_alive
}

_stop_daemon() {
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null) || return 0
    kill "$pid" 2>/dev/null || true
    rm -f "$PID_FILE"
}

# ── Dispatch commande ─────────────────────────────────────────────────
case "$CMD" in

  start)
    touch "$ENABLED_FLAG"
    _start_daemon
    ss_info "Commentateur IA démarré (style=$(_style) interval=$(_interval)s)"
    printf '{"status":"ok","commentator":"started","style":"%s","interval":%s}\n' \
        "$(_style)" "$(_interval)"
    ;;

  stop)
    rm -f "$ENABLED_FLAG"
    _stop_daemon
    ss_info "Commentateur IA arrêté"
    printf '{"status":"ok","commentator":"stopped"}\n'
    ;;

  interval)
    if [ -n "$VALUE" ] && [ "$VALUE" -eq "$VALUE" ] 2>/dev/null; then
        CLAMPED=$(( VALUE < 15 ? 15 : VALUE > 600 ? 600 : VALUE ))
        printf '%d' "$CLAMPED" > "$INTERVAL_F"
        ss_info "Intervalle commentateur : ${CLAMPED}s"
        printf '{"status":"ok","interval":%d}\n' "$CLAMPED"
    else
        printf '{"error":"invalid_value","hint":"interval must be integer 15-600"}\n'
    fi
    ;;

  style)
    case "$VALUE" in
      concert|accueil|poetic|free)
        printf '%s' "$VALUE" > "$STYLE_F"
        ss_info "Style commentateur : $VALUE"
        printf '{"status":"ok","style":"%s"}\n' "$VALUE"
        ;;
      *)
        printf '{"error":"unknown_style","hint":"concert|accueil|poetic|free"}\n'
        ;;
    esac
    ;;

  trigger)
    # Déclenche un commentaire immédiat (indépendant du timer)
    _stream_name=$(_stream)
    if [ -z "$_stream_name" ]; then
        printf '{"error":"no_stream","hint":"aucun flux actif"}\n'
    elif ! _is_enabled; then
        printf '{"error":"disabled","hint":"démarrer le commentateur d abord"}\n'
    else
        # Signal: supprime le timestamp next_run en touchant le flag
        touch "$ENABLED_FLAG"
        ss_info "Commentaire immédiat demandé sur $_stream_name"
        printf '{"status":"ok","trigger":"sent","stream":"%s"}\n' "$_stream_name"
    fi
    ;;

  status|*)
    DAEMON=$( _pid_alive && echo "running" || echo "stopped" )
    ENABLED=$( _is_enabled && echo "true" || echo "false" )
    STREAM=$(_stream)
    LAST=$(_last | sed 's/"/\\"/g' | head -c 200)
    printf '{"status":"ok","commentator":"%s","enabled":%s,"style":"%s","interval":%s,"stream":"%s","last_comment":"%s"}\n' \
        "$DAEMON" "$ENABLED" "$(_style)" "$(_interval)" "$STREAM" "$LAST"
    ;;

esac
