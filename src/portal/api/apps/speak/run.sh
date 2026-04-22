#!/bin/bash
# /opt/soundspot/portal/api/apps/speak/run.sh — Laisse un organe distant utiliser la Bouche

read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true

TEXT=$(printf '%s' "$POST_DATA" | grep -oP '(?<=text=)[^&]+' | head -1 | python3 -c "import sys,urllib.parse; print(urllib.parse.unquote_plus(sys.stdin.read().strip()))" 2>/dev/null)
VOICE=$(printf '%s' "$POST_DATA" | grep -oP '(?<=voice=)[^&]+' | head -1)

if [ -n "$TEXT" ]; then
    # Lancement asynchrone pour répondre immédiatement au Cerveau
    (
        USER_ID=$(id -u "${SOUNDSPOT_USER:-pi}" 2>/dev/null || echo 1000)
        export XDG_RUNTIME_DIR="/run/user/${USER_ID}"
        
        WAV_OUT="/tmp/speak_$$.wav"
        USE_ESPEAK=true

        # Mode MULTIPASS / Orpheus IA Responder
        if [[ "$VOICE" == "pierre" || "$VOICE" == "amelie" ]]; then
            ORPHEUS_SCRIPT="$HOME/.zen/Astroport.ONE/tools/orpheus.me.sh"
            
            if [[ -x "$ORPHEUS_SCRIPT" ]]; then
                # On s'assure que le tunnel P2P vers Orpheus (5005) est actif
                "$ORPHEUS_SCRIPT" >/dev/null 2>&1
                
                # Requête au Swarm via le localhost du RPi Zero
                HTTP_CODE=$(curl -s -w "%{http_code}" -o "$WAV_OUT" \
                    http://127.0.0.1:5005/v1/audio/speech \
                    -H "Content-Type: application/json" \
                    --max-time 15 \
                    -d "{
                        \"model\": \"orpheus\",
                        \"input\": \"$TEXT\",
                        \"voice\": \"$VOICE\",
                        \"response_format\": \"wav\",
                        \"speed\": 1.0
                    }")
                
                # Si l'IA a répondu avec succès et que le fichier n'est pas vide
                if [[ "$HTTP_CODE" == "200" && -s "$WAV_OUT" ]]; then
                    USE_ESPEAK=false
                fi
            fi
        fi

        # Fallback de survie : Voix robotique
        if [[ "$USE_ESPEAK" == true ]]; then
            espeak-ng -v fr+f3 -s 125 -p 45 "$TEXT" -w "$WAV_OUT"
        fi

        # Verrouillage pour ne pas superposer les sons
        exec 9>"/run/user/${USER_ID}/soundspot_welcome.lock"
        flock -n 9 || exit 0
        
        paplay "$WAV_OUT" 2>/dev/null || pw-play "$WAV_OUT" 2>/dev/null || aplay "$WAV_OUT" 2>/dev/null
        rm -f "$WAV_OUT"
    ) &
    
    echo '{"status": "ok", "message": "Parole en cours..."}'
else
    echo '{"error": "no_text"}'
fi