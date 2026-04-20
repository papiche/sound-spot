# 🛠 Guide du Développeur SoundSpot

Bienvenue dans le code de **SoundSpot** ! 
Si tu souhaites ajouter tes propres applications (jeux, outils, interactions avec la musique), ce guide est pour toi. 

SoundSpot n'est pas un serveur web classique. C'est un **Nœud UPlanet**, ce qui signifie qu'il fait le pont entre le monde traditionnel (Web2) et le monde distribué (Web3).

---

## 🎭 Les deux visages de SoundSpot

Quand un utilisateur interagit avec ton application sur le portail captif, deux scénarios sont possibles :

### 1. Le mode "Web3" (L'utilisateur a un MULTIPASS)
L'utilisateur possède une extension NOSTR (comme *nos2x*) ou l'application *Ẑelkova*. Il possède sa propre clé privée (`nsec`).
👉 **L'action :** Son navigateur signe cryptographiquement un événement NOSTR et l'envoie au réseau. L'essaim UPlanet (les autres ordinateurs du réseau) capte le message, fait le calcul (via des intelligences artificielles ou des GPU distants) et renvoie le résultat. Le Raspberry Pi ne fait **rien d'autre qu'écouter**.

### 2. Le mode "Web2" (L'utilisateur est un visiteur anonyme)
L'utilisateur n'a rien installé. Il est juste sur le WiFi "ZICMAMA".
👉 **L'action :** Son navigateur fait un simple appel API HTTP classique (`fetch`) vers le Raspberry Pi. Le Raspberry Pi utilise alors **sa propre identité NOSTR** (ses clés Picoport) pour agir comme un "Relai" ou un proxy. C'est le Pi qui va faire le travail ou signer la demande à la place de l'utilisateur.

---

## 🎵 Étude de cas : Le Jukebox

Le module Jukebox permet à un visiteur de coller un lien YouTube. Le système va télécharger la vidéo, extraire le MP3, le stocker sur IPFS (le réseau de fichiers décentralisé) et le jouer sur les enceintes du SoundSpot.

Regardons comment c'est codé dans l'interface (`src/portal/index.html` > fonction `doYtCopy()`) :

### Le Chemin Web3 (L'utilisateur a un MULTIPASS)
```javascript
if (window.nostr) {
    // 1. On crée un événement NOSTR demandant la musique
    const event = {
        kind: 1,
        tags: [["t", "jukebox"]],
        content: `#BRO #youtube #mp3 ${url}`
    };
    
    // 2. Le navigateur de l'utilisateur signe l'événement
    const signedEvent = await window.nostr.signEvent(event);
    
    // 3. On l'envoie à la constellation (wss://relay.copylaradio.com)
    ws.send(JSON.stringify(["EVENT", signedEvent]));
}
```
**Ce qu'il se passe ensuite :** Une IA distante voit ce message, télécharge le MP3, le met sur IPFS, et répond sur NOSTR. Sur le Raspberry Pi, un petit script (`jukebox_listener.py`) écoute NOSTR en permanence. Quand il voit le lien IPFS arriver, il crée un fichier `.job` dans `~/.zen/tmp/$IPFSNODEID/soundspot_queue/` et le lecteur musical (`jukebox_player.sh`) le joue !

### Le Chemin Web2 (L'utilisateur n'a rien)
```javascript
if (!window.nostr) {
    // 1. Appel HTTP classique vers l'API locale en Bash
    const r = await fetch('/api.sh?action=yt_copy', {
      method: 'POST',
      body: 'url=' + encodeURIComponent(url)
    });
}
```
**Ce qu'il se passe ensuite :** La requête arrive sur le script local `src/portal/api/apps/yt_copy/run.sh`. 
Puisque personne ne peut le faire à notre place, c'est le processeur du Raspberry Pi qui travaille :
1. Il utilise `yt-dlp` pour télécharger le MP3 localement.
2. Il utilise l'API de Kubo (IPFS) locale pour l'épingler.
3. Il écrit lui-même le fichier `.job` dans `~/.zen/tmp/$IPFSNODEID/soundspot_queue/` pour que la musique se lance.

---

## 🛠 Comment créer ton propre module

SoundSpot possède **deux API** distinctes pour coder le backend (le mode Web2) :

### 1. L'API Locale en Bash (`api.sh`)
C'est l'API la plus légère, parfaite pour interagir avec le système du Raspberry Pi (audio, GPIO, fichiers temporaires).
* **Où coder :** Crée un dossier `src/portal/api/apps/mon_app/` et un fichier `run.sh`.
* **Comment l'appeler :** `fetch('/api.sh?action=mon_app')`
* **Exemple d'utilisation :** Le volume, les cloches (`clock`), le Jukebox local.
* **Avantage :** Ultra léger, tourne en pur Bash, redémarrage instantané (hot-reload).

```bash
# Exemple de src/portal/api/apps/ping/run.sh
echo '{"status": "ok", "message": "Pong depuis le Pi !"}'
```

### 2. L'API UPassport en Python (Port 54321)
C'est le backend "Lourd" (FastAPI), conçu pour les interactions complexes avec la blockchain Ğ1, les bases de données, le crowdfunding, et les profils utilisateurs.
* **Où coder :** Dans les routeurs du fichier `54321.py` (ou `routers/*.py`).
* **Comment l'appeler :** `fetch('http://192.168.10.1:54321/api/mon_action')`
* **Exemple d'utilisation :** Le financement participatif (`/api/crowdfunding`), la génération d'avatars (`/robohash`), les envois de Ẑen.
* **Avantage :** Puissance de Python, validation Pydantic, gestion native des WebSockets et de la cryptographie avancée.

---

## 📝 Résumé de la philosophie de dev

1. **Pense d'abord au Swarm (Web3) :** Si la tâche est lourde (télécharger une vidéo, générer une image IA), demande-le via NOSTR (`window.nostr.signEvent`). Un nœud plus puissant de la constellation fera le travail.
2. **Prévois toujours un Fallback (Web2) :** Tous les visiteurs n'ont pas de MULTIPASS. Fais en sorte que le Raspberry Pi puisse utiliser ses propres clés (`~/.zen/game/nostr.keys`) pour publier sur NOSTR à la place du visiteur, ou utilise un script Bash local pour faire un traitement dégradé.
3. **Live Reload :** Si tu modifies l'interface (`src/portal/index.html`) ou un script Bash (`api.sh`), rafraîchis juste ton navigateur ! Pas besoin de relancer le serveur. (Pour le backend lourd Python, tape `ss-reload` dans le terminal de ton Pi).

Bon code ! 🚀
