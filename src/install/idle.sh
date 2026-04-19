#!/bin/bash
# install/idle.sh — Clocher numérique SoundSpot
# Crée /opt/soundspot/wav/ avec les sons et textes sources des messages.
# Les .wav sont générés depuis les .txt. Remplacer un .wav par le vôtre pour personnaliser.
# Maître uniquement.

setup_idle() {
    hdr "Clocher numérique (annonces sans DJ)"
    local wav_dir="$INSTALL_DIR/wav"

    # ── Répertoire wav/ ─────────────────────────────────────────
    mkdir -p "$wav_dir"
    log "Répertoire $wav_dir créé"

    # ── Script principal ─────────────────────────────────────────
    cp "$SCRIPT_DIR/idle_announcer.sh" "$INSTALL_DIR/idle_announcer.sh"
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

    MSGS[01]="Vous écoutez un Bien Commun Numérique. Mon corps est un Raspberry Pi, ma voix sort en Bluetooth, et ma mémoire réside dans la constellation UPlanet."
    MSGS[02]="Ce nœud audio fonctionne à l'énergie solaire. Mon existence dépend des rayons du soleil et de l'usure de ma batterie. Prenez soin de moi."
    MSGS[03]="Je suis une bouche et des oreilles. Pour réfléchir, je fais appel aux cerveaux GPU du réseau coopératif UPlanet. Rejoignez la constellation."
    MSGS[04]="La création de cette station a un coût matériel, mais son utilisation est libre. Soutenez le G1 FabLab en monnaie libre pour essaimer d'autres nœuds."
    MSGS[05]="Utilisez votre MULTIPASS depuis votre smartphone pour me donner des ordres. Je copierai la musique dans votre disque souverain uDRIVE."
    MSGS[06]="La monnaie June circule librement entre ses membres, sans banque centrale. Devenez Parrain ZEN avec une ZEN Card pour soutenir l'infrastructure."

    MSGS[07]="Ce n'est pas « Ici Londres » pendant la Seconde Guerre Mondiale. C'est « ALLO ici les DEV » pour mettre fin à la troisième. Construisons un réseau libre."
    MSGS[08]="Dans le cinquième Élément, l'humanité subit un futur dystopique. Ici, avec votre MULTIPASS, vous devenez co-bâtisseur du monde libre. Entrez, et amenez vos amis."
    MSGS[09]="La chaîne de confiance numérique est enfin raccourcie : Utilisateur, Capitaine, Armateur. Ce modèle est généralisable à toutes nos relations. Reprenez le contrôle."
    MSGS[10]="Je suis une bouche et des oreilles. Pour réfléchir, je fais appel aux cerveaux GPU du réseau coopératif UPlanet. Rejoignez la constellation."
    MSGS[11]="Utilisez votre MULTIPASS depuis votre smartphone pour me donner des ordres. L'Intelligence Artificielle copiera la musique dans votre disque souverain uDRIVE."
    MSGS[12]="La monnaie libre June circule entre ses membres, sans banque centrale. Devenez Parrain avec une ZEN Card pour soutenir les infrastructures numériques physiques."

    for id in "${!MSGS[@]}"; do
        local txt_file="$wav_dir/message_${id}.txt"
        local wav_file="$wav_dir/message_${id}.wav"

        # Écrire le texte source (toujours, pour permettre l'édition)
        echo "${MSGS[$id]}" > "$txt_file"

        # Générer le .wav uniquement s'il n'existe pas déjà
        # (préserve un .wav personnalisé déposé manuellement)
        if [ ! -f "$wav_file" ]; then
            espeak-ng -v fr+f3 -s 115 -p 40 "${MSGS[$id]}" \
                -w "$wav_file" 2>/dev/null \
                && log "message_${id}.wav généré" \
                || warn "espeak-ng : message_${id}.wav non généré"
        else
            log "message_${id}.wav existant conservé (personnalisé ?)"
        fi
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
