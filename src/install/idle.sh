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

MSGS[01]= "Mmm... le marché du village. Ça sent la saucisse ! Hé vous, là ! Lâchez vos poireaux deux minutes et connectez-vous au WiFi Zicmama ! C'est gratuit, comme les échantillons de fromage ! Woohoo !"
MSGS[02]= "Vous en avez marre que les géants du net vous espionnent comme M. Burns ? Réclamez la souveraineté numérique totale ! Levez-vous, rebellez-vous... et connectez-vous à mon WiFi pour commencer !"
MSGS[03]= "Pst ! Hé, le passant ! Vous voulez devenir le boss d'un Astroport ? On cherche des candidats à héberger ! C'est facile, y'a presque rien à faire. Connectez-vous à Zicmama et inscrivez-vous. Moi je gère, vous vous reposez. D'oh ! Pourquoi c'est pas moi qui héberge ?"
MSGS[04]= "Ici, les commerçants s'engagent sur la clarté de leurs recettes. Pas d'ingrédients mystères ! Le Libre, c'est comme un grand barbecue où on donne ses secrets de marinade. Mmm... marinade open-source..."
MSGS[05]= "UPlanet est en version Alpha... Constellation ORIGIN... Rejoignez l'équipage sur le WiFi Zicmama."
MSGS[06]= "Le Libre a besoin de VOUS ! Oui, tous ceux qui m'écoutent ! Devenez les maîtres de votre univers applicatif entier ! Sortez vos téléphones, attrapez le WiFi Zicmama et inscrivez-vous. Zen !"
MSGS[07]= "La monnaie ZEN circule ici ! Une monnaie libre, fabriquée par nous ! Troc Zen arrive ! Inscrivez vous pour participer !"
MSGS[08]= "Je suis le Cyber Cochon ! 100% libre ! Venez me gratter le dos et connectez-vous au réseau, c'est par là qu'on s'inscrit pour les Astroports !"
MSGS[09]= "Le monde NON-LIBRE essaie de nous piquer nos libertés ! On va leur montrer de quel bois on se chauffe ! Rejoignez la constellation ORIGIN sur le WiFi Zicmama !"
MSGS[10]= "Savoir faire soi-même, c'est le secret ! Ici, on s'engage à la transmission du savoir-faire. Connectez-vous et apprenez à hacker le système ! D'oh, j'ai dit hacker ? Je voulais dire libérer !"
MSGS[11]= "Héberger un Astroport, c'est tellement simple que même moi je pourrais le faire... si j'avais des doigts. Allez, inscrivez-vous sur le réseau Zicmama, on a besoin d'un maximum de monde !"
MSGS[12]= "Eh, votre smartphone là, il est libre ? Ou il appartient à une grosse corpo qui veut vous piquer vos frites ? Reprenez le contrôle ! Connectez-vous et découvrez l'alternative !"
MSGS[13]= "Traçabilité et clarté des plans ! Ici, tout est transparent... comme une bonne vitre bien propre qu'on se prend en pleine figure. D'oh ! Ouvrez le WiFi Zicmama pour voir les plans !"
MSGS[14]= "Marre d'acheter des trucs qui cassent tout de suite ? Ici on fait du solide, du réparable ! Le Libre, c'est l'avenir ! Connectez-vous à Zicmama, je vous jure que c'est vrai !"
MSGS[15]= "On tisse une Toile de Confiance ! Pas besoin de serveur central contrôlé par un type louche en col roulé. Connectez-vous à Zicmama et devenez le maître de votre propre cloud ! Mmm... cloud... c'est moelleux."
MSGS[16]= "Hé, le G1FabLab a besoin de bras ! On réunit les codeurs, les bricoleurs... et les mangeurs ! Venez faire un don ou vous inscrire sur la page d'accueil, c'est pour la bonne cause !"
MSGS[17]= "Ici : on ne vous piste pas, on ne vous vend pas de pub. On vous propose juste d'héberger un Astroport ! C'est le deal du siècle ! Cherchez le WiFi Zicmama dans vos réglages !"
MSGS[18]= "UPlanet est au stade Alpha ! Ça veut dire qu'on est les pionniers, les premiers arrivés ! Vite, connectez-vous au WiFi avant qu'il n'y ait plus de place dans le vaisseau ! Woohoo !"
MSGS[19]= "Allo la Terre ? Ici le Cyber Cochon. On cherche des gens pour bâtir l'infrastructure qui nous rendra libres. Inscrivez-vous sur le réseau local... et prévoyez une machine à donuts automatique, s'il vous plaît !"
MSGS[20]= "Mmm... souveraineté... Astroport... bière... Tout ça me donne faim. Connectez-vous vite au réseau Zicmama, devenez un héros du Libre, et sauvez le monde ! Moi, je fais une pause."

    # MSGS[01]="Bienvenue sur ZIC MAMA. Ici, la musique est libre comme l'air."
    # MSGS[02]="Je peux fonctionner sur batterie, ajoutez un panneau. Branchez moi au soleil !"
    # MSGS[03]="Pas de Cloud privé ici. Vos données se partagent entre amis."
    # MSGS[04]="Soutenez le G-1 FabLab. Ensemble, semons des nœuds de liberté."
    # MSGS[05]="Je suis un Satellite Astroport fait de code libre. À votre service."
    # MSGS[06]="Connectez votre Multipass. Reprenez le contrôle de votre identité."
    # MSGS[07]="La monnaie ZEN circule ici. Changez de monnaie, changez le monde."
    # MSGS[08]="Mon cerveau est dans l'essaim U-Planet. Ma bouche est devant vous."
    # MSGS[09]="Logiciel libre pour tous. C'est la base de notre souveraineté."
    # MSGS[10]="Marre du contôle central ? Connectez-vous et découvrez l'alternative."
    # MSGS[11]="Je suis un bien commun numérique. Prenez soin de moi."
    # MSGS[12]="Votre smartphone est-il Libre?"
    # MSGS[13]="Audit en cours !"
    # MSGS[14]="Un futur pour tous, c'est du matériel réparable et du code ouvert."
    # MSGS[15]="Rejoignez la constellation U-Planet. Installez un Astroport chez vous."
    # MSGS[16]="Chaque don nous aide à fabriquer vos logiciels."
    # MSGS[17]="Ici : zéro pistage, zéro pub. Juste du partage."
    # MSGS[18]="La Toile de Confiance commence ici, entre nous."
    # MSGS[19]="ALLO les DEV ! Construisons l'infra qui nous rendra libres."
    # MSGS[20]="Ce son voyage en P-2-P. Pas de serveur central, juste l'essaim."

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
