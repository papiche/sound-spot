#!/bin/bash
# tests/test_voices.sh — Tester et remplacer les voix du clocher SoundSpot
#
# Utilisation (sur le RPi, via SSH ou en direct) :
#   sudo bash tests/test_voices.sh
#   sudo bash tests/test_voices.sh --dir /opt/soundspot/wav
#
# Permet pour chaque message_NN :
#   [p] jouer le wav actuel
#   [e] régénérer avec espeak-ng
#   [o] régénérer avec Orpheus (pierre ou amelie)
#   [t] saisir un nouveau texte + régénérer
#   [s] passer au suivant (skip)
#   [q] quitter

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/soundspot}"
WAV_DIR="${1:-${INSTALL_DIR}/wav}"
TTS_SH="${INSTALL_DIR}/backend/audio/tts.sh"
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
ORPHEUS_PORT="${ORPHEUS_PORT:-5005}"

# ── Couleurs ─────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'

log()  { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }

# ── Jouer un wav (via session audio de SOUNDSPOT_USER) ───────
play_wav() {
    local f="$1"
    if [ ! -f "$f" ]; then warn "Fichier absent : $f"; return; fi
    local uid; uid=$(id -u "$SOUNDSPOT_USER" 2>/dev/null || echo "1000")
    sudo -u "$SOUNDSPOT_USER" \
        XDG_RUNTIME_DIR="/run/user/${uid}" \
        PULSE_SERVER="unix:/run/user/${uid}/pulse/native" \
        bash -c "paplay '$f' 2>/dev/null || pw-play '$f' 2>/dev/null || aplay '$f' 2>/dev/null" \
    || warn "Aucun lecteur audio disponible (paplay/pw-play/aplay)"
}

# ── Vérifier Orpheus ─────────────────────────────────────────
orpheus_alive() {
    curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
        "http://localhost:${ORPHEUS_PORT}/docs" 2>/dev/null | grep -q "200"
}

# ── Générer avec espeak ──────────────────────────────────────
gen_espeak() {
    local txt="$1" out="$2"
    espeak-ng -v fr+f3 -s 115 -p 40 "$txt" -w "$out" 2>/dev/null \
        && chown www-data:www-data "$out" 2>/dev/null || true
    [ -f "$out" ] && log "espeak-ng → $out" || warn "espeak-ng échoué"
}

# ── Générer avec Orpheus (appel API direct, pas de fallback espeak) ──
gen_orpheus() {
    local txt="$1" out="$2" voice="${3:-pierre}"
    if ! orpheus_alive; then
        warn "Orpheus non disponible (port ${ORPHEUS_PORT})"
        return 1
    fi
    local tmp="/dev/shm/tts_test_$$.wav"
    local json_txt
    json_txt=$(python3 -c "import sys,json; print(json.dumps(sys.argv[1]))" "$txt" 2>/dev/null \
               || echo "\"${txt//\"/\\\"}\"")
    if curl -sf --max-time 20 \
        -o "$tmp" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"orpheus\",\"input\":${json_txt},\"voice\":\"${voice}\",\"response_format\":\"wav\",\"speed\":1.0}" \
        "http://localhost:${ORPHEUS_PORT}/v1/audio/speech" 2>/dev/null \
        && [ -s "$tmp" ]; then
        mv "$tmp" "$out"
        chown www-data:www-data "$out" 2>/dev/null || true
        log "Orpheus ($voice) → $out"
        return 0
    fi
    rm -f "$tmp"
    warn "Génération Orpheus échouée (réponse vide ou erreur curl)"
    return 1
}

# ── Boucle principale ─────────────────────────────────────────
hdr "SoundSpot — Test & Remplacement des voix"
echo -e "Répertoire : ${W}${WAV_DIR}${N}"
echo ""

if [ "$(id -u)" -ne 0 ]; then
    warn "Ce script doit être lancé en root (sudo) pour écrire dans ${WAV_DIR}"
    exit 1
fi

[ -d "$WAV_DIR" ] || { warn "Répertoire introuvable : $WAV_DIR"; exit 1; }

orpheus_alive && log "Orpheus actif sur :${ORPHEUS_PORT}" || warn "Orpheus absent — seul espeak disponible"
echo ""

for txt_file in "$WAV_DIR"/message_*.txt; do
    [ -f "$txt_file" ] || continue
    num=$(basename "$txt_file" .txt | sed 's/message_//')
    wav_file="$WAV_DIR/message_${num}.wav"

    hdr "Message ${num}"
    echo -e "Texte : ${W}$(cat "$txt_file")${N}"
    if [ -f "$wav_file" ]; then
        echo -e "WAV   : ${G}présent${N} ($(du -sh "$wav_file" 2>/dev/null | cut -f1))"
    else
        echo -e "WAV   : ${R}absent${N}"
    fi
    echo ""
    echo -e "  [${W}p${N}] Écouter   [${W}e${N}] espeak   [${W}o${N}] Orpheus pierre   [${W}a${N}] Orpheus amélie"
    echo -e "  [${W}t${N}] Nouveau texte   [${W}s${N}] Passer   [${W}q${N}] Quitter"
    echo ""

    while true; do
        printf "  Choix > "
        read -r choice
        case "$choice" in
            p|P)
                if [ -f "$wav_file" ]; then
                    log "Lecture de message_${num}.wav…"
                    play_wav "$wav_file"
                else
                    warn "Pas de wav — génère d'abord avec [e] ou [o]"
                fi
                ;;
            e|E)
                gen_espeak "$(cat "$txt_file")" "$wav_file"
                log "Lecture…"; play_wav "$wav_file"
                break
                ;;
            o|O)
                gen_orpheus "$(cat "$txt_file")" "$wav_file" "pierre" && \
                    { log "Lecture…"; play_wav "$wav_file"; }
                break
                ;;
            a|A)
                gen_orpheus "$(cat "$txt_file")" "$wav_file" "amelie" && \
                    { log "Lecture…"; play_wav "$wav_file"; }
                break
                ;;
            t|T)
                printf "  Nouveau texte > "
                read -r new_text
                if [ -n "$new_text" ]; then
                    printf '%s' "$new_text" > "$txt_file"
                    log "Texte mis à jour"
                    rm -f "$wav_file"
                    echo -e "  Générer avec [${W}e${N}] espeak, [${W}o${N}] Orpheus pierre, ou [${W}a${N}] Orpheus amélie ?"
                else
                    warn "Texte vide — ignoré"
                fi
                ;;
            s|S|"")
                log "Passage au message suivant"
                break
                ;;
            q|Q)
                echo ""
                log "Terminé."
                exit 0
                ;;
            *)
                warn "Choix invalide"
                ;;
        esac
    done
done

echo ""
log "Tous les messages ont été traités."
