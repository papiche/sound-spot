# Guide Pratique : Régie Vidéo (V.J.), Drone et Projecteur

Le SoundSpot intègre une véritable régie vidéo légère pour projeter des flux en direct (drones, smartphones) sur un vidéoprojecteur, sans utiliser internet.

## 1. Préparer le Vidéoprojecteur (Nebula)
1. Branchez votre vidéoprojecteur sur le port **Micro-HDMI** du Raspberry Pi 4 (le port le plus proche de l'alimentation USB-C).
2. Si vous avez branché l'alimentation du projecteur sur le relais du Pi (GPIO 18), vous pouvez l'allumer via l'API :
   `http://192.168.10.1/api.sh?action=projector&mode=on`

## 2. Envoyer un flux vidéo (Drone ou Smartphone)
N'importe quel appareil connecté au Wi-Fi `ZICMAMA` peut diffuser de la vidéo.
- **Pour un Drone DJI :** Dans l'application DJI Fly, allez dans Paramètres > Transmission > Live Broadcasting (RTMP).
- **Pour un Smartphone :** Utilisez l'application *Larix Broadcaster*.
- **URL de diffusion :** `rtmp://192.168.10.1/live/ce_que_vous_voulez` (ex: `.../live/drone` ou `.../live/public`).

## 3. Utiliser la Régie V.J. (Video Jockey)
L'administrateur du SoundSpot peut choisir quel flux afficher sur le projecteur :
1. Allez sur le portail captif, cliquez sur **Vision Macro**, puis sur **Ouvrir la Régie Vidéo**.
2. La liste des flux en cours d'émission s'affiche.
3. Cliquez sur **Projeter 🎦**. Le Raspberry Pi coupera le terminal texte et affichera la vidéo en plein écran via un rendu matériel direct (zéro lag).
4. Cliquez sur **Mettre au Noir** pour couper la projection.

## 4. VDO.Ninja — Diffusion WebRTC sans application

Si le nœud a accès à Internet (via qo-op ou eth0), les participants peuvent diffuser
depuis leur navigateur, sans installer Larix ni l'application DJI.

**Rejoindre comme diffuseur (smartphone, PC) :**
Dans la Régie V.J. → bouton **📷 Diffuser ma caméra** → le navigateur demande accès à la caméra.

**Afficher la scène composite sur le projecteur :**
Dans la Régie V.J. → bouton **📺 Scène projecteur** → ouvre la vue multi-sources dans un nouvel onglet (à afficher sur le HDMI via Chromium plein écran).

La room est dérivée automatiquement du `SPOT_NAME` configuré (ex : `SOUNDSPOTZICMAMA`).

| | RTMP (Larix / DJI Fly) | VDO.Ninja |
|--|--|--|
| Application nécessaire | Oui | Non — navigateur |
| Fonctionne hors-ligne | **Oui** | Non (signaling serveur) |
| Latence | ~1-2 s | ~100-200 ms |
| Sources simultanées | Non | Oui (scène composite) |
| Drone DJI | Natif | Via navigateur du contrôleur |
| Smartphone visiteur | Larix Broadcaster | Navigateur, aucune install |

> **Cas d'usage typique :** plusieurs festivaliers diffusent simultanément depuis leurs smartphones.
> La scène VDO.Ninja affiche toutes les sources en mosaïque sur le projecteur.
> Les drones ou sources professionnelles restent sur RTMP pour la qualité et l'autonomie hors-ligne.