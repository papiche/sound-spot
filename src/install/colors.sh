#!/bin/bash
# install/colors.sh — Couleurs, fonctions de log et utilitaire install_template
# À sourcer en premier par tous les scripts d'installation SoundSpot.

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'

log()  { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err()  { echo -e "${R}✗${N}  $*"; exit 1; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }

# install_template SRC DEST [VARS]
# Copie templates/SRC vers DEST.
# Si VARS est fourni (ex: '${INSTALL_DIR} ${SNAPCAST_PORT}'), envsubst substitue
# uniquement ces variables — les ${VAR} runtime dans les scripts installés restent intacts.
install_template() {
    local src="$1" dest="$2"; shift 2
    if [ $# -eq 0 ]; then
        cp "${SCRIPT_DIR}/templates/${src}" "${dest}"
    else
        envsubst "$*" < "${SCRIPT_DIR}/templates/${src}" > "${dest}"
    fi
}
