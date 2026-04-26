#!/bin/bash
# install/colors.sh — Couleurs, fonctions de log et utilitaire install_template
# À sourcer en premier par tous les scripts d'installation SoundSpot.

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'

log()  { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err()  { echo -e "${R}✗${N}  $*"; exit 1; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }

# apt_retry — apt-get avec 3 tentatives (réseau instable : festivals, hotspots)
apt_retry() {
    local n=1
    until apt-get "$@"; do
        n=$((n + 1))
        [ "$n" -gt 3 ] && { warn "apt-get échoué après 3 tentatives"; return 1; }
        warn "apt-get échoué — tentative $n/3 dans 5s..."
        sleep 5
        apt-get update -qq
    done
}

# install_template SRC DEST [VARS]
install_template() {
    local src="$1" dest="$2"; shift 2
    # Recherche dans l'ordre : templates/ → config/services/ → backend/system/
    local template_path="${SCRIPT_DIR}/templates/${src}"
    [ ! -f "$template_path" ] && template_path="${SCRIPT_DIR}/config/services/${src}"
    [ ! -f "$template_path" ] && template_path="${SCRIPT_DIR}/config/network/${src}"
    [ ! -f "$template_path" ] && template_path="${SCRIPT_DIR}/backend/system/${src}"
    [ ! -f "$template_path" ] && template_path="${SCRIPT_DIR}/backend/audio/${src}"
    [ ! -f "$template_path" ] && template_path="${SCRIPT_DIR}/backend/video/${src}"
    [ ! -f "$template_path" ] && err "Template introuvable : ${src}"

    if [ $# -eq 0 ]; then
        cp "${template_path}" "${dest}"
    else
        envsubst "$*" < "${template_path}" > "${dest}"
    fi
}