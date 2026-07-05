# Guide Pratique : Régie Vidéo (V.J.), Drone et Projecteur

Le SoundSpot intègre une véritable régie vidéo légère pour projeter des flux en direct (drones, smartphones) sur un vidéoprojecteur, sans utiliser internet.

## 1. Préparer le Vidéoprojecteur (Nebula)
1. Branchez votre vidéoprojecteur sur le port **Micro-HDMI** du Raspberry Pi 4 (le port le plus proche de l'alimentation USB-C).
2. Si vous avez branché l'alimentation du projecteur sur le relais du Pi (GPIO 18), vous pouvez l'allumer via l'API :
   `http://192.168.10.1/api.sh?action=projector&mode=on`

## 2. Envoyer un flux vidéo (Drone ou Smartphone)
N'importe quel appareil connecté au Wi-Fi `ZICMAMA` peut diffuser de la vidéo en RTMP
(seul protocole compatible avec l'affichage projecteur — pas de WebRTC/VDO.Ninja ici,
les deux ne sont pas interopérables).
- **Pour un Drone DJI :** Dans l'application DJI Fly, allez dans Paramètres > Transmission > Live Broadcasting (RTMP).
- **Pour un Smartphone :** Utilisez l'application *Larix Broadcaster*.
- **URL de diffusion :** `rtmp://192.168.10.1/live/ce_que_vous_voulez` (ex: `.../live/drone` ou `.../live/public`).
- La Régie V.J. affiche cette URL sous forme de **QR code** (généré via l'API UPassport,
  `GET http://192.168.10.1:54321/qr?data=<url>`) — pratique pour la configurer rapidement
  dans Larix sans la retaper. Un second QR code y renvoie vers https://qo-op.com.

## 3. Utiliser la Régie V.J. (Video Jockey)
L'administrateur du SoundSpot peut choisir quel flux afficher sur le projecteur :
1. Allez sur le portail captif, cliquez sur **Vision Macro**, puis sur **Ouvrir la Régie Vidéo**.
2. La liste des flux en cours d'émission s'affiche.
3. Cliquez sur **Projeter 🎦**. Le Raspberry Pi coupera le terminal texte et affichera la vidéo en plein écran via un rendu matériel direct (zéro lag).
4. Cliquez sur **Mettre au Noir** pour couper la projection.
5. Quand aucun flux n'est projeté, l'écran affiche automatiquement la dernière photo
   capturée par `mon-oeil.py` (voir `explanation-architecture.md`).