# Guide Pratique : Utiliser une Steam Deck comme Console DJ/VJ avec l'Essaim

Ce guide explique comment déployer une architecture asymétrique complète, digne d'un setup cyberpunk :
- **La Steam Deck :** Terminal de contrôle nomade (Console DJ/VJ).
- **Le CyberCochon :** Routeur tactique de terrain (Audio/Réseau/Portail).
- **Sagittarius (PC Gamer à la maison) :** "Brain-Node" distant fournissant la puissance GPU et IA via les tunnels P2P.

La Steam Deck fonctionnant sous SteamOS (base Arch Linux immuable), nous n'utiliserons pas les scripts d'installation classiques du Pi, mais le mode Bureau et les Flatpaks.

---

## Étape 1 : Préparation de la Steam Deck (Mode Bureau)

Passez votre Steam Deck en **Mode Bureau** (Bouton Steam > Marche/Arrêt > Basculer vers le bureau).

### 1. Injecter votre MULTIPASS (Web3)
1. Ouvrez **Firefox** (ou Chrome) sur la Steam Deck.
2. Installez l'extension NOSTR **nos2x** (ou Alby).
3. Cliquez sur l'extension, choisissez "Import Key", et collez votre clé privée (`nsec`) générée sur votre station Astroport d'origine.
*Votre navigateur est maintenant une interface authentifiée sur l'essaim UPlanet.*

### 2. Installer les outils de production
Ouvrez le magasin d'applications (Discover) et installez les Flatpaks suivants :
- **Mixxx** (Pour le mix audio en direct).
- **OBS Studio** (Pour envoyer de la vidéo au vidéoprojecteur via le Cochon).

---

## Étape 2 : Le Deck comme Console DJ (Audio)

Sur le terrain, connectez la Steam Deck au réseau Wi-Fi **ZICMAMA** du CyberCochon.

1. Ouvrez **Mixxx**.
2. Allez dans **Options** > **Préférences** > **Live Broadcasting** (Diffusion en direct).
3. Configurez la connexion vers le CyberCochon :
   - **Type :** Icecast 2
   - **Serveur :** `192.168.10.1`
   - **Port :** `8111`
   - **Montage :** `/live`
   - **Login :** `source`
   - **Mot de passe :** `0penS0urce!` (ou celui défini dans `soundspot.conf`).
   - **Format :** Ogg Vorbis (Critique pour le décodeur ffmpeg du Cochon).
4. Cliquez sur l'icône **Antenne parabolique** en haut à droite de Mixxx pour lancer l'émission.

> **🎧 Astuce Latence :** Le réseau Snapcast ajoute ~2 secondes de délai (pour stabiliser le réseau Mesh). Pour caler vos morceaux (beatmatch), branchez votre casque directement sur la Steam Deck et utilisez la fonction **Cue (Pré-écoute)** de Mixxx, n'écoutez pas les enceintes du public.

---

## Étape 3 : Le Deck comme Régie V.J. (Vidéo)

Pour projeter des visuels génératifs ou un flux caméra de la Steam Deck sur le vidéoprojecteur (Nebula) branché au CyberCochon :

1. Ouvrez **OBS Studio** sur la Steam Deck.
2. Allez dans **Paramètres** > **Flux** (Stream).
   - **Service :** Personnalisé (Custom)
   - **Serveur :** `rtmp://192.168.10.1/live/`
   - **Clé de stream :** `steamdeck` (ou le nom de votre choix).
3. Cliquez sur **Commencer le streaming**.
4. Ouvrez Firefox sur la Steam Deck et allez sur le portail captif : `http://192.168.10.1/vj.html`.
5. Votre flux "steamdeck" apparaît dans la liste. L'extension `nos2x` s'activera pour prouver vos droits d'admin. Cliquez sur **Projeter 🎦**.

---

### Installez Astroport.ONE

https://ipfs.copylaradio.com/ipns/astroport.one


## Option : Invoquer la puissance de "Sagittarius" (L'IA de l'Essaim)

Vous avez accès au ressources GPU de la constellation (connecté à IPFS et Astroport). 
Votre CyberCochon est dans un champ (relié via 5G). La Steam Deck est connectée au CyberCochon.

Grâce au protocole **DRAGON** du Picoport :
1. Le CyberCochon repère `sagittarius` dans l'essaim IPFS P2P.
2. Il monte des tunnels chiffrés (`x_*.sh`) vers les ports du "PC gamer".
3. Depuis votre Steam Deck, vous avez accès à un GPU distant :
   - `http://192.168.10.1:11434` ➔ Discute avec **Ollama**.
   - `http://192.168.10.1:8188` ➔ Génère des images sur **ComfyUI** avec la carte graphique de Sagittarius.

NB: Ce canal sera limité et accessible aux capitaines certifiés.
