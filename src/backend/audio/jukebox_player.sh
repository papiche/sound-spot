#!/bin/bash
# /opt/soundspot/backend/audio/jukebox_player.sh
# Moteur de Playlist unifiée avec promotion automatique OpenCollective et verrouillage anti-superposition

[ -f /opt/soundspot/soundspot.conf ] && source /opt/soundspot/soundspot.conf
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
USER_ID=$(id -u "$SOUNDSPOT_USER" 2>/dev/null || echo 1000)
export XDG_RUNTIME_DIR="/run/user/${USER_ID}"

QUEUE_DIR="/dev/shm/soundspot_queue"
MPV_SOCKET="/tmp/soundspot-mpv.sock"
LOCAL_GATEWAY="http://127.0.0.1:8080"
AUDIO_LOCK="/dev/shm/soundspot_audio.lock"

# Dossier IPC partagé avec les droits d'écriture de www-data
mkdir -p "$QUEUE_DIR"
chgrp soundspot "$QUEUE_DIR" 2>/dev/null || true
chmod 775 "$QUEUE_DIR"

PI_MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo "")
IS_LOW_POWER=false
if echo "$PI_MODEL" | grep -qi "Zero"; then
    IS_LOW_POWER=true
fi

TRACK_COUNTER=0

_mpv_ipc_cmd() {
    if [ -S "$MPV_SOCKET" ]; then
        echo "$1" | socat - "UNIX-CONNECT:$MPV_SOCKET" >/dev/null 2>&1
    fi
}

play_collective_jingle() {
    echo "📢 [PROMO] Jingle de soutien OpenCollective"
    local jingle_txt="Cette station et son logiciel libre vivent grâce à vos dons. Aidez-nous à maintenir la constellation, faites un don sur notre OpenCollective !"
    local tmp_jingle="/dev/shm/promo_jingle_temp.wav"
    
    if curl -s -o /dev/null -w "%{http_code}" --max-time 2 "http://localhost:5005/docs" 2>/dev/null | grep -q "200"; then
        bash /opt/soundspot/backend/audio/tts.sh "$jingle_txt" "${ORPHEUS_VOICE:-pierre}" "$tmp_jingle" >/dev/null 2>&1
    else
        espeak-ng -v fr+f3 -s 120 "$jingle_txt" -w "$tmp_jingle" 2>/dev/null
    fi

    if [ -s "$tmp_jingle" ]; then
        touch "/dev/shm/soundspot_speaker_active" 2>/dev/null
        pw-play "$tmp_jingle" 2>/dev/null || aplay -q "$tmp_jingle" 2>/dev/null
        rm -f "$tmp_jingle"
    fi
}

echo "🎵 Player de Playlist unifié démarré (Mode Basse Énergie: $IS_LOW_POWER) -> $QUEUE_DIR"

while true; do
    # On s'assure qu'aucune instance libre n'est lancée de manière orpheline
    if ! pgrep -x "pw-play" >/dev/null && ! pgrep -x "aplay" >/dev/null; then
        
        NEXT_JOB=$(find "$QUEUE_DIR" -maxdepth 1 -name "*.job" -type f | sort | head -n 1)
        
        if [ -n "$NEXT_JOB" ]; then
            MEDIA_TARGET=$(cat "$NEXT_JOB")
            rm -f "$NEXT_JOB"

            # ── PRISE DE POSSESSION DU CANAL AUDIO UNIQUE (Bloquant) ──
            # Attend la fin d'un message d'accueil ou d'une annonce horaire pour jouer la piste
            (
                flock 9
                
                ((TRACK_COUNTER++))
                if [ $((TRACK_COUNTER % 3)) -eq 0 ]; then
                    play_collective_jingle
                fi

                echo "▶ Playlist : Lecture de $MEDIA_TARGET"
                
                TMP_PLAY_FILE="/dev/shm/current_playlist_item"
                rm -f "$TMP_PLAY_FILE"*

                # ── CAS 1 : Lien YouTube (Nécessite yt-dlp) ──
                if [[ "$MEDIA_TARGET" =~ youtube\.com|youtu\.be ]]; then
                    if [ "$IS_LOW_POWER" = "true" ]; then
                        echo "📥 Mode Basse Énergie : Récupération audio YouTube..."
                        if yt-dlp -f "bestaudio[ext=m4a]/bestaudio" --no-playlist -o "$TMP_PLAY_FILE.%(ext)s" "$MEDIA_TARGET" 2>/dev/null; then
                            LOCAL_FILE=$(ls "${TMP_PLAY_FILE}"* | head -n 1)
                            touch "/dev/shm/soundspot_speaker_active" 2>/dev/null
                            pw-play "$LOCAL_FILE" 2>/dev/null
                        else
                            echo "⚠ Échec du téléchargement audio YouTube"
                        fi
                    else
                        echo "📥 Mode Master : Récupération vidéo complète..."
                        if yt-dlp -f "bestvideo[height<=720]+bestaudio/best" --no-playlist -o "$TMP_PLAY_FILE.%(ext)s" "$MEDIA_TARGET" 2>/dev/null; then
                            LOCAL_FILE=$(ls "${TMP_PLAY_FILE}"* | head -n 1)
                            echo "🎬 Projection en direct sur HDMI : $LOCAL_FILE"
                            _mpv_ipc_cmd "{\"command\":[\"loadfile\",\"$LOCAL_FILE\",\"replace\"]}"
                            
                            while pgrep -x "mpv" >/dev/null && [ -S "$MPV_SOCKET" ]; do
                                IS_IDLE=$(echo '{"command":["get_property","idle-active"]}' | socat - "UNIX-CONNECT:$MPV_SOCKET" 2>/dev/null | jq -r '.data // "false"')
                                [ "$IS_IDLE" = "true" ] && break
                                sleep 1
                            done
                        else
                            echo "⚠ Échec du téléchargement vidéo YouTube"
                        fi
                    fi

                # ── CAS 2 : Fichier local, IPFS direct ou HTTP standard ──
                else
                    if [[ "$MEDIA_TARGET" =~ \.(mp4|mkv|avi|mov|webm)$ ]] && [ "$IS_LOW_POWER" = "false" ]; then
                        echo "🎬 Projection de la vidéo locale : $MEDIA_TARGET"
                        _mpv_ipc_cmd "{\"command\":[\"loadfile\",\"$MEDIA_TARGET\",\"replace\"]}"
                        
                        while pgrep -x "mpv" >/dev/null && [ -S "$MPV_SOCKET" ]; do
                            IS_IDLE=$(echo '{"command":["get_property","idle-active"]}' | socat - "UNIX-CONNECT:$MPV_SOCKET" 2>/dev/null | jq -r '.data // "false"')
                            [ "$IS_IDLE" = "true" ] && break
                            sleep 1
                        done
                    else
                        echo "🔊 Lecture audio locale : $MEDIA_TARGET"
                        if [[ "$MEDIA_TARGET" =~ ^https?:// ]]; then
                            if wget -q --timeout=10 --tries=2 -O "$TMP_PLAY_FILE.media" "$MEDIA_TARGET" && [ -s "$TMP_PLAY_FILE.media" ]; then
                                touch "/dev/shm/soundspot_speaker_active" 2>/dev/null
                                pw-play "$TMP_PLAY_FILE.media" 2>/dev/null
                            fi
                        else
                            touch "/dev/shm/soundspot_speaker_active" 2>/dev/null
                            pw-play "$MEDIA_TARGET" 2>/dev/null
                        fi
                    fi
                fi

                rm -f "$TMP_PLAY_FILE"*
            ) 9>"$AUDIO_LOCK"
        fi
    fi
    sleep 2
done