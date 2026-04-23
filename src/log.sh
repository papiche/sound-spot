#!/bin/bash
# /opt/soundspot/log.sh — Bibliothèque de logs centralisés (Version SD-Safe)
#
# Utilisation (sourcer ce fichier depuis tout script SoundSpot) :
#   _SS_SERVICE="monservice"
#   source /opt/soundspot/log.sh
#   ss_info "démarrage"
#   ss_warn "ressource manquante : $VAR"
#   ss_error "échec critique : $MSG"
#   ss_debug "valeur intermédiaire : $VAL"
#
# Format de sortie :
#   2026-04-19 14:23:45 [INFO ] [monservice  ] message
#
# Variables d'environnement :
#   LOG_LEVEL      Filtre : DEBUG, INFO, WARN, ERROR  (défaut : INFO)
#   SOUNDSPOT_LOG  Chemin du fichier de log (défaut : /var/log/sound-spot.log)

# On recharge la config pour avoir le LOG_LEVEL à jour (ex: ERROR)
[ -f /opt/soundspot/soundspot.conf ] && source /opt/soundspot/soundspot.conf
SOUNDSPOT_LOG="${SOUNDSPOT_LOG:-/var/log/sound-spot.log}"

_ss_level_num() {
    case "${1:-INFO}" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        *)     echo 1 ;;
    esac
}

ss_log() {
    local level="$1" service="$2"; shift 2
    local msg="$*"
    
    local configured; configured=$(_ss_level_num "${LOG_LEVEL:-INFO}")
    local current;    current=$(_ss_level_num "$level")
    
    # --- PROTECTION SD ---
    # Si le message n'est pas au niveau requis, on quitte IMMEDIATEMENT
    # sans même ouvrir le fichier de log en écriture.
    [ "$current" -lt "$configured" ] && return 0
    
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    local entry; entry=$(printf '%s [%-5s] [%-12s] %s' "$ts" "$level" "$service" "$msg")
    
    # Écriture disque uniquement si le niveau est suffisant
    printf '%s\n' "$entry" >> "$SOUNDSPOT_LOG" 2>/dev/null || true
    
    # Les erreurs sont toujours envoyées vers stderr pour journald
    [ "$level" = "ERROR" ] && printf '%s\n' "$entry" >&2
    return 0
}

ss_info()  { ss_log INFO  "${_SS_SERVICE:-soundspot}" "$@"; }
ss_warn()  { ss_log WARN  "${_SS_SERVICE:-soundspot}" "$@"; }
ss_error() { ss_log ERROR "${_SS_SERVICE:-soundspot}" "$@"; }
ss_debug() { ss_log DEBUG "${_SS_SERVICE:-soundspot}" "$@"; }