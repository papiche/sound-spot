#!/bin/bash
# install/idle.sh — Clocher numérique SoundSpot
# Crée /opt/soundspot/wav/ avec les sons et textes sources des messages.
# Les .wav sont générés depuis les .txt. Remplacer un .wav par le vôtre pour personnaliser.
# Maître uniquement.

setup_idle() {
    hdr "Clocher numérique (annonces sans DJ)"
    local wav_dir="$INSTALL_DIR/wav"

    mkdir -p "$wav_dir"
    # L'utilisateur de runtime (pi) doit être propriétaire, groupe soundspot pour le web
    chown -R ${SOUNDSPOT_USER}:soundspot "$wav_dir"
    chmod -R 775 "$wav_dir"
    chmod g+s "$wav_dir" # Bit Setgid : les nouveaux fichiers héritent du groupe soundspot

    # ── Script principal ─────────────────────────────────────────
    install_template "idle_announcer.sh" "$INSTALL_DIR/idle_announcer.sh"
    chmod +x "$INSTALL_DIR/idle_announcer.sh"
    log "idle_announcer.sh déployé"

    # ── Sons 429.62 Hz (cf. Travaux sur l'eau de Marc Henry) ────────────
    # Bip d'annonce : 4s avec fade in/out doux
    ffmpeg -f lavfi \
        -i "sine=frequency=429.62:sample_rate=48000:duration=4" \
        -af "afade=t=in:st=0:d=0.3,afade=t=out:st=3:d=1" \
        -y "$wav_dir/tone_429hz.wav" -loglevel quiet 2>/dev/null \
        && log "tone_429hz.wav généré (429.62 Hz, 4s)" \
        || warn "ffmpeg : tone_429hz.wav non généré (ffmpeg absent ?)"

    # Coup de cloche : 2.5s avec fondu rapide (style église)
    ffmpeg -f lavfi \
        -i "sine=frequency=429.62:sample_rate=48000:duration=2.5" \
        -af "afade=t=out:st=0.5:d=2" \
        -y "$wav_dir/bell_429hz.wav" -loglevel quiet 2>/dev/null \
        && log "bell_429hz.wav généré (coup de cloche 2.5s)" \
        || warn "ffmpeg : bell_429hz.wav non généré"

    # ── Textes sources des messages (modifiables librement) ──────
    # Format : un fichier .txt par message, .wav généré automatiquement si absent.
    # Pour personnaliser : remplacer le .wav correspondant par votre enregistrement.

declare -A MSGS

    MSGS[01]="Bienvenue sur ZIC MAMA. Ici, la musique est libre comme l'air."
    MSGS[02]="Je peux fonctionner sur batterie, ajoutez un panneau. Branchez moi au soleil !"
    MSGS[03]="Pas de Cloud privé ici. Vos données se partagent entre amis."
    MSGS[04]="Soutenez le G-1 FabLab. Ensemble, semons des nœuds de liberté."
    MSGS[05]="Je suis un Satellite Astroport fait de code libre. À votre service."
    MSGS[06]="Connectez votre Multipass. Reprenez le contrôle de votre identité."
    MSGS[07]="La monnaie ZEN circule ici. Changez de monnaie, changez le monde."
    MSGS[08]="Mon cerveau est dans l'essaim U-Planet. Ma bouche est devant vous."
    MSGS[09]="Logiciel libre pour tous. C'est la base de notre souveraineté."
    MSGS[10]="Marre du contôle central ? Connectez-vous et découvrez l'alternative."
    MSGS[11]="Je suis un bien commun numérique. Prenez soin de moi."
    MSGS[12]="Votre smartphone est-il Libre?"
    MSGS[13]="Audit en cours !"
    MSGS[14]="Un futur pour tous, c'est du matériel réparable et du code ouvert."
    MSGS[15]="Rejoignez la constellation U-Planet. Installez un Astroport chez vous."
    MSGS[16]="Chaque don nous aide à fabriquer vos logiciels."
    MSGS[17]="Ici : zéro pistage, zéro pub. Juste du partage."
    MSGS[18]="La Toile de Confiance commence ici, entre nous."
    MSGS[19]="ALLO les DEV ! Construisons l'infra qui nous rendra libres."
    MSGS[20]="Ce son voyage en P-2-P. Pas de serveur central, juste l'essaim."

    for id in "${!MSGS[@]}"; do
        local txt_file="$wav_dir/message_${id}.txt"
        local wav_file="$wav_dir/message_${id}.wav"

        # Écrire le texte source (toujours, pour permettre l'édition)
        echo "${MSGS[$id]}" > "$txt_file"

        # Générer le .wav
        espeak-ng -v fr+f3 -s 115 -p 40 "${MSGS[$id]}" \
            -w "$wav_file" 2>/dev/null \
            && log "message_${id}.wav généré" \
            || warn "espeak-ng : message_${id}.wav non généré"
        
        chown www-data:soundspot "$wav_file" 2>/dev/null || true

    done

    log "Textes sources dans : ${wav_dir}/ (fichiers .txt modifiables)"
    log "Pour personnaliser un message : remplacer le .wav correspondant"

    # ── Service systemd ──────────────────────────────────────────
    install_template soundspot-idle.service \
        /etc/systemd/system/soundspot-idle.service \
        '${INSTALL_DIR} ${SOUNDSPOT_USER} ${SOUNDSPOT_UID}'
    systemctl enable soundspot-idle
    log "Service soundspot-idle activé"
}
