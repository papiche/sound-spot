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

    # ── Sons 429.62 Hz (générés par ffmpeg) ──────────────────────
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
    MSGS[01]="Vous êtes sur un espace sonore collectif libre. Ici la musique circule comme un bien commun. Rejoignez le G1 FabLab sur monnaie tiret libre point org"
    MSGS[02]="Ce nœud audio fonctionne à l'énergie solaire. Infrastructure décentralisée, sans serveur central, sans publicité. Soutenez le bien commun numérique."
    MSGS[03]="La Juin est une monnaie libre, co-créée en parts égales par tous ses membres. Comme ce son, elle appartient à chacun. Découvrez la monnaie libre sur monnaie tiret libre point org"
    MSGS[04]="Le G1 FabLab est un collectif de création et de partage. Outils libres, sons libres, monnaie libre. Ensemble construisons autrement."
    MSGS[05]="Vous pouvez diffuser votre musique sur ce nœud. Branchez Mixxx à ce point d'accès WiFi et devenez un diffuseur du bien commun sonore."
    MSGS[06]="La monnaie Juin circule librement entre ses membres, sans banque centrale. Un système économique coopératif pour un monde plus juste. Rejoignez nous."
    MSGS[07]="Ce point d'accès WiFi est ouvert à tous. Aucun compte, aucune publicité, aucune surveillance. Infrastructure de bien commun numérique."
    MSGS[08]="UPlanet ẐEN : un réseau coopératif de nœuds libres, sonores et solaires. Chaque nœud est une voix, chaque voix est un bien commun."

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
