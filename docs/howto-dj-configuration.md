# Guide Pratique : Configuration Quotidienne et Session DJ

Ce guide explique comment opérer le SoundSpot au quotidien sans toucher au code.

## 1. Appairer une nouvelle enceinte Bluetooth

L'assistant interactif met à jour le fichier `soundspot.conf` et relance le son automatiquement.

```bash
sudo bash /opt/soundspot/backend/system/bt_update.sh
```

*(Allumez votre enceinte en mode appairage avant de lancer la commande).*

## 2. Modifier les messages vocaux (Le Clocher)

Les messages aléatoires du clocher sont régénérés par `espeak-ng` (synthèse vocale locale) ; si un tunnel Orpheus TTS est actif via Picoport, une voix naturelle est utilisée à la place.

1. Éditez le texte : `sudo nano /opt/soundspot/wav/message_01.txt`
2. Supprimez le `.wav` correspondant : `sudo rm /opt/soundspot/wav/message_01.wav`

Au prochain cycle (ou via le bouton Admin du portail), le système relit le texte et régénère l'audio.

## 3. Démarrer une session DJ Live

> **Prérequis :** exécutez `dj_mixxx_setup.sh` sur votre **PC** (Linux/Mac/Windows), pas sur le RPi.

```bash
bash dj_mixxx_setup.sh   # à lancer UNE seule fois sur le PC DJ
~/zicmama_play.sh         # démarre la session (snapclient + Mixxx)
```

### Configuration Mixxx

Dans Mixxx → **Préférences → Live Broadcasting** :

| Paramètre | Valeur |
|-----------|--------|
| Type | Icecast2 |
| Hôte | `192.168.10.1` |
| Port | `8111` |
| Mount | `/live` |
| Format | **Ogg Vorbis** (obligatoire — le décodeur ffmpeg du RPi l'attend) |
| Mot de passe | `hackme` (sauf si modifié dans `soundspot.conf`) |

Cliquez sur l'icône **Antenne** pour diffuser.

### Latence et retour casque

Le retour casque via `snapclient` a une latence de **1 à 3 secondes**. C'est normal :
le son passe par Icecast → ffmpeg → Snapserver avant de revenir sur le casque.

**Pour beatmatcher proprement :** utilisez la **sortie Cue (pré-écoute) de Mixxx** dans votre casque — c'est le son direct, sans latence. Snapcast sert uniquement à entendre ce que les visiteurs écoutent.

## 4. Priorité des sources audio

Quand plusieurs sources sont actives, l'ordre de priorité est :

| Priorité | Source | Condition |
|----------|--------|-----------|
| 1 | **DJ en Live** | Stream Icecast actif (`/live`) |
| 2 | **AutoDJ** | Activé depuis le portail, fichiers dans `/home/pi/Music/` |
| 3 | **Jukebox P2P** | File NOSTR locale, aucun DJ ni AutoDJ actif |

## 5. Dépannage rapide

| Symptôme | Vérification |
|----------|-------------|
| Pas de son sur les enceintes | `systemctl status soundspot-client-master` — BT connecté ? |
| Icecast n'accepte pas le stream | Port 8111 ouvert ? Mot de passe Mixxx correct ? |
| Retard > 5s entre Mixxx et enceintes | Réduire le buffer Snapcast dans `snapserver.conf` |
| Audio haché (xruns) | Réseau surchargé — réduire la qualité Ogg Vorbis dans Mixxx |

---

Voir aussi : [Architecture générale](explanation-architecture.md) · [Configuration API](reference-api-config.md)
