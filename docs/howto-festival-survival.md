# Guide Pratique : Manuel de Survie en Festival

Gérer un SoundSpot pendant 3 jours dans un champ demande un peu d'organisation. Voici comment utiliser les fonctions d'animation et de diffusion.

## 1. Split Audio : Radio FM + Vidéoprojecteur
Si vous branchez un émetteur Radio FM sur la prise Jack du Raspberry Pi, le son risque de ne plus sortir sur le vidéoprojecteur (HDMI). Pour envoyer le son **aux deux en même temps** :
1. Connectez-vous en SSH : `ssh pi@soundspot.local`
2. Lancez la commande magique : `bash /opt/soundspot/backend/system/split_audio.sh`
*Le système va fusionner le Jack et le HDMI. Les festivaliers devant l'écran et les voitures à 2 km sur la bande FM entendront la même chose, sans décalage.*

## 2. L'AutoDJ (Quand le DJ humain fait une pause)
L'AutoDJ prend des MP3 au hasard et les diffuse sur la radio locale.
- **Ajouter de la musique :** Copiez vos fichiers `.mp3`, `.ogg` ou `.flac` dans le dossier `/home/pi/Music/` du nœud Maître.
- **Lancer l'AutoDJ :** Depuis la page `index_2.html` (Interface CyberCochon) du portail captif, cliquez sur "Lancer l'AutoDJ". Le système prendra le relais sur Icecast.

## 3. Le Jukebox Collaboratif (IPFS)
Les visiteurs peuvent ajouter des musiques en collant un lien YouTube dans le portail captif.
- Le Raspberry Pi télécharge la musique en arrière-plan, la stocke sur le réseau P2P (IPFS) et l'ajoute à la file d'attente (visible dans `/dev/shm/soundspot_queue/`).
- Le système lit la file d'attente automatiquement tant que le DJ ou l'AutoDJ ne diffuse pas.

## 4. Gérer l'Énergie (Ce qu'il se passe la nuit)
Si la batterie solaire passe sous les 20% :
1. La musique va se couper.
2. Le système va crier "Attention, mon énergie est critique" sur les enceintes.
3. Tous les nœuds du festival (Satellites) vont s'éteindre proprement.
4. **Le relais physique coupera le courant.** Le système se rallumera automatiquement au lever du soleil quand le panneau solaire rechargera la batterie.

## 5. Modules Expérimentaux (LoRa & Impression)
- **Meshtastic (LoRa) :** Si un module LoRa est branché en USB, les messages du portail peuvent être diffusés par ondes radio textuelles (module `api/apps/meshtastic`). A TESTER !
- **Tickets (Brother QL-700) :** Si une imprimante thermique est branchée, l'API `api.sh?action=print_ticket` imprimera un QR Code d'accès (module `print_ticket.sh`). A TESTER !