# Guide Pratique : Manuel de Survie en Festival

Gérer un SoundSpot pendant 3 jours dans un champ demande un peu d'organisation.
Voici comment utiliser les fonctions d'animation et de diffusion.

## 1. Priorité des sources audio

Quand plusieurs sources sont actives, la hiérarchie est la suivante :

| Priorité | Source | Condition d'activation |
|----------|--------|----------------------|
| **1** | DJ en Live | Stream Icecast actif (`/live` occupé) |
| **2** | AutoDJ | Activé depuis le portail, aucun DJ actif |
| **3** | Jukebox P2P | File non vide, aucun DJ ni AutoDJ actif |

## 2. Les visiteurs comme enceintes

Tout visiteur connecté au WiFi **ZICMAMA** peut transformer son smartphone en enceinte
synchronisée avec le reste de la flotte — sans application à installer.

### Via le navigateur (aucune installation)

1. Se connecter au WiFi **ZICMAMA** (sans mot de passe)
2. Le portail s'ouvre automatiquement — cliquer sur **📻 Radio**
3. L'audio démarre dans le navigateur via **Snapcast.js**

Le son est synchronisé avec les enceintes Bluetooth des satellites et du maître,
avec la même latence (~2 s) que tout le reste de la flotte.

### Via l'application (meilleure synchronisation)

| Application | Plateforme | Paramètres |
|-------------|-----------|-----------|
| **Snapdroid** | Android | Hôte : `192.168.10.1` · Port : `1704` |
| **Snappy** | iOS | Hôte : `192.168.10.1` · Port : `1704` |

L'application offre un contrôle fin du volume et de la latence, et se reconnecte
automatiquement si le WiFi est coupé brièvement.

> **Limite :** les smartphones ne peuvent pas rejoindre **CYBERCOCHON_MESH**
> (réseau ad-hoc IBSS non supporté sur iOS/Android standard). Seuls les RPi avec
> dongle USB Wi-Fi participent au mesh. Les visiteurs passent obligatoirement par ZICMAMA.

### Voir les enceintes actives

Sur `http://192.168.10.1/mesh.html` → section **Clients Snapcast** : la liste se met à jour
toutes les 5 s et affiche tous les appareils connectés au flux, qu'ils soient sur ZICMAMA
(smartphones visiteurs) ou sur le mesh (satellites RPi distants).

## 3. Split Audio : Radio FM + Vidéoprojecteur

Si vous branchez un émetteur Radio FM sur la prise Jack du RPi, le son risque de ne plus sortir
sur le vidéoprojecteur (HDMI). Pour envoyer le son **aux deux simultanément** :

```bash
ssh pi@soundspot.local
bash /opt/soundspot/backend/system/split_audio.sh
```

Le système fusionne Jack et HDMI via PipeWire. Les festivaliers devant l'écran et les voitures
à 2 km sur la bande FM entendront la même chose, sans décalage.

## 4. L'AutoDJ (Quand le DJ humain fait une pause)

L'AutoDJ pioche des fichiers au hasard dans `/home/pi/Music/` et les diffuse sur Icecast.

**Ajouter de la musique :**

```bash
# Depuis votre ordinateur, transférer des fichiers :
scp mes_fichiers.mp3 pi@soundspot.local:~/Music/
# ou via l'onglet uDRIVE du portail (upload IPFS → copie locale)
```

**Lancer l'AutoDJ :** dans l'onglet **Admin** du portail captif → bouton "Lancer l'AutoDJ".

Formats supportés : `.mp3`, `.ogg`, `.flac`

## 5. Le Jukebox Collaboratif (NOSTR + IPFS)

Les visiteurs peuvent proposer des morceaux depuis leur smartphone (onglet Jukebox du portail) :

1. Le visiteur colle un lien YouTube ou IPFS.
2. Le Maître télécharge et stocke le fichier sur IPFS.
3. Le morceau est ajouté à la file NOSTR locale (relay port 9999).
4. La file se lit automatiquement quand ni DJ ni AutoDJ ne sont actifs.

**Voir la file en cours :**

```bash
# Lister les morceaux en attente
ls /dev/shm/soundspot_queue/ 2>/dev/null || echo "File vide ou non initialisée"
```

## 6. Gestion de l'Énergie (Ce qu'il se passe la nuit)

Quand la batterie solaire passe sous **20 %** (détecté par INA219 via I2C) :

1. La musique se coupe progressivement.
2. Le système annonce vocalement "Énergie critique" sur les enceintes.
3. Tous les nœuds de la flotte (Satellites) s'éteignent proprement via NOSTR Kind 9.
4. **Le relais GPIO 17 coupe l'alimentation générale.** Le système se rallume automatiquement au lever du soleil quand le panneau rechargera la batterie au-dessus du seuil de démarrage.

> **Note :** Le "lever du soleil" ici = tension batterie suffisante pour démarrer le Pi (≥ 12V stable).
> Le système ne connaît pas l'heure du lever — il se rallume simplement quand il peut.

## 7. Plusieurs scènes sur le même festival

### Règle fondamentale : un seul maître par mesh

Le mesh CYBERCOCHON_MESH ne peut héberger qu'un seul maître. Le maître prend l'IP fixe
`10.200.0.1` sur `bat0` — si deux maîtres rejoignent le même mesh, ils entrent en
**conflit ARP** : les satellites changent de source Snapcast de façon imprévisible.
Ce conflit s'applique même si les deux maîtres sont reliés via des satellites intermédiaires
(B.A.T.M.A.N. fait le pont au niveau 2, le domaine de collision reste unique).

### Architecture recommandée : cascade Icecast

Chaque scène a son propre mesh isolé. Les flux audio se synchronisent via l'upstream :

```
[DJ]──Live──► [Maître A]──CYBERCOCHON_MESH──[Sat A1][Sat A2]
                   │
                   │  http://IP-A:8111/live  (via qo-op/Internet)
                   ▼
              [Maître B]──CYBERCOCHON_MESH──[Sat B1][Sat B2]
```

Le Maître B tire le flux Icecast du Maître A au lieu de produire le sien.
Les visiteurs des deux scènes entendent le même mix, avec quelques secondes de décalage
supplémentaires entre les scènes — imperceptible à distance humaine.

**Configurer sur le Maître B** (`soundspot.conf`) :

```
ICECAST_SOURCE_URL="http://192.168.X.Y:8111/live"
```

### Isolation des meshes

| Situation | Action |
|-----------|--------|
| Scènes à > 200 m (plein air) | Rien — les meshes ne se voient pas |
| Scènes proches (même site dense) | Changer le canal dans `mesh_batman.sh` (ex : 36 vs 100) |
| Scènes adjacentes avec dongle directif | Changer canal **et** SSID mesh (ex : `CYBERCOCHON_A` / `CYBERCOCHON_B`) |

Les SSIDs visiteurs ZICMAMA peuvent rester différents (`ZICMAMA_SCENE_A` / `ZICMAMA_SCENE_B`)
via la variable `SPOT_NAME` — les portails sont alors indépendants.

## 8. Modules Expérimentaux (non garantis en production)

> ⚠️ Ces modules sont en développement actif. Ne pas planifier autour d'eux pour un festival critique.

**Meshtastic (LoRa) :** Si un module LoRa USB est branché, les messages du portail peuvent
être diffusés par ondes radio textuelles (module `api/apps/meshtastic`).
→ Portée théorique : 5-15 km hors-ligne.

**Tickets (Brother QL-700) :** Si une imprimante thermique est branchée, l'API
`?action=print_ticket` peut imprimer un QR Code d'accès.
→ Utile pour les entrées payantes en G1.

Pour tester : `bash /opt/soundspot/backend/system/check.sh --modules`

---

Voir aussi : [Configuration DJ](howto-dj-configuration.md) · [Montage matériel](howto-montage-materiel.md) · [Diagnostic](howto-logs-diagnostic.md)
