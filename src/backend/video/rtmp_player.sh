#!/bin/bash
# rtmp_player.sh — Affiche sur HDMI, par ordre de priorité :
#   1. Le flux sélectionné par la Régie VJ (current_vj)
#   2. Un flash blanc bref, déclenché par mon-oeil.py juste avant sa capture
#      (éclaire la scène — pas de VJ actif requis, comme la photo ci-dessous)
#   3. La dernière photo de mon-oeil.py (30s, une fois par nouvelle capture)
#   4. À défaut, le diaporama d'accueil (QR codes DJ/VJ/coopérative/piliers)
#      en rotation — voir eye_idle_screen.sh
# Nécessite un DRM libre : pas d'X/lightdm actif (systemctl set-default
# multi-user.target), sinon --vo=drm ne peut pas prendre la main.
#
# Un SEUL processus mpv reste vivant en permanence (--idle=yes), piloté par
# IPC (socket JSON). On ne tue/relance jamais mpv pour changer de contenu :
# tuer mpv relâche le DRM le temps de son redémarrage, ce qui laisse
# apparaître furtivement la console texte sous-jacente à chaque transition.
# Garder le même processus tout du long élimine ce clignotement.
export XDG_RUNTIME_DIR="/run/user/$(id -u ${SOUNDSPOT_USER:-pi} 2>/dev/null || echo 1000)"

MPV_SOCKET="/tmp/soundspot-mpv.sock"
CURRENT=""
LAST_PHOTO_TS=0
LAST_FLASH_TS=0
PHOTO_PATH="/dev/shm/eye_capture.jpg"
FLASH_TRIGGER="/dev/shm/eye_flash_trigger"
FLASH_IMG="/dev/shm/eye_flash.jpg"
IDLE_DIR="/dev/shm/eye_idle"
IDLE_GEN="$(dirname "$0")/eye_idle_screen.sh"
MPV_PID=""

[ -s "$FLASH_IMG" ] || convert -size 1280x720 xc:white "$FLASH_IMG" 2>/dev/null

_mpv_cmd() {
    # _mpv_cmd '<commande JSON mpv IPC>'
    echo "$1" | socat - "UNIX-CONNECT:$MPV_SOCKET" >/dev/null 2>&1
}

_mpv_alive() {
    [ -n "$MPV_PID" ] && kill -0 "$MPV_PID" 2>/dev/null
}

_start_mpv() {
    _mpv_alive && return
    rm -f "$MPV_SOCKET"
    mpv --idle=yes --force-window=yes --vo=drm --hwdec=auto --really-quiet \
        --input-ipc-server="$MPV_SOCKET" &
    MPV_PID=$!
    for _ in $(seq 1 50); do
        [ -S "$MPV_SOCKET" ] && return
        sleep 0.1
    done
}

_show_idle() {
    local slides=("$IDLE_DIR"/*.jpg)
    [ -e "${slides[0]}" ] || return
    _mpv_cmd "{\"command\":[\"loadfile\",\"${slides[0]}\",\"replace\"]}"
    local f
    for f in "${slides[@]:1}"; do
        _mpv_cmd "{\"command\":[\"loadfile\",\"$f\",\"append\"]}"
    done
    _mpv_cmd '{"command":["set_property","loop-playlist","inf"]}'
    _mpv_cmd '{"command":["set_property","image-display-duration","8"]}'
}

_show_image_for() {
    # _show_image_for <fichier> <secondes>
    _mpv_cmd "{\"command\":[\"set_property\",\"image-display-duration\",\"$2\"]}"
    _mpv_cmd "{\"command\":[\"loadfile\",\"$1\",\"replace\"]}"
}

_start_mpv

# Génère l'écran d'accueil en tâche de fond — réessaie tant qu'UPassport
# (port 54321, API QR code) n'est pas encore prêt après le boot.
( for _ in $(seq 1 30); do bash "$IDLE_GEN" 2>/dev/null && break; sleep 10; done; _show_idle ) &

while true; do
    _start_mpv   # relance discrète si mpv a planté — le socket est recréé

    WANTED=$(cat /dev/shm/current_vj 2>/dev/null || echo "")

    if [ -n "$WANTED" ]; then
        # Flux VJ demandé — priorité absolue
        if [ "$WANTED" != "$CURRENT" ]; then
            CURRENT="$WANTED"
            echo "Lancement du flux VJ : $CURRENT"
            _mpv_cmd "{\"command\":[\"loadfile\",\"rtmp://127.0.0.1/live/$CURRENT\",\"replace\"]}"
        fi
    else
        if [ -n "$CURRENT" ]; then
            CURRENT=""
            _show_idle
        fi

        # Flash déclenché par mon-oeil.py juste avant sa capture (éclairage)
        FLASH_TS=$(stat -c %Y "$FLASH_TRIGGER" 2>/dev/null || echo 0)
        if [ "$FLASH_TS" -gt 0 ] && [ "$FLASH_TS" != "$LAST_FLASH_TS" ]; then
            LAST_FLASH_TS="$FLASH_TS"
            echo "Flash lumineux (éclairage capture mon-oeil)"
            _show_image_for "$FLASH_IMG" 2
            sleep 2
            _show_idle
        fi

        # Nouvelle photo mon-oeil ? affichage prioritaire sur l'écran d'accueil
        PHOTO_TS=$(stat -c %Y "$PHOTO_PATH" 2>/dev/null || echo 0)
        if [ "$PHOTO_TS" -gt 0 ] && [ "$PHOTO_TS" != "$LAST_PHOTO_TS" ]; then
            LAST_PHOTO_TS="$PHOTO_TS"
            echo "Affichage photo mon-oeil ($PHOTO_PATH)"
            _show_image_for "$PHOTO_PATH" 30
            sleep 30
            _show_idle
        fi
    fi
    # Cadence resserrée (était 2s) : le flash et la photo mon-oeil.py sont
    # déclenchés par fichier (mtime), et la voix associée (annonce, puis
    # message d'ambiance à l'affichage de la photo) démarre côté mon-oeil.py
    # sans attendre l'écran — un poll trop lent désynchronisait nettement
    # le son (déjà audible) de l'image (encore sur l'ancien slide).
    sleep 0.3
done
