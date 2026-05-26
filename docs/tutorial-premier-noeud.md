# Tutoriel : Créer votre premier SoundSpot (Nœud Maître)

Ce tutoriel vous guidera dans la création de votre premier nœud autonome SoundSpot.

## Étape 1 : Préparation matérielle

*(Consultez la [Nomenclature et Guide d'Achats](reference-nomenclature.md) pour la liste exacte des composants et le budget).*

1. Branchez votre Raspberry Pi 4 à une alimentation suffisante (convertisseur 12V→5V 5A minimum).
2. Connectez le dongle Wi-Fi Vemfay sur un port USB 3.0 (port **bleu**).
3. Branchez la Caméra Module 3 sur le port CSI (nappe plate, contacts vers le bas).
4. **Appairez votre enceinte Bluetooth** avant d'installer :
   - Allumez l'enceinte en mode appairage.
   - Depuis un autre appareil, notez l'adresse MAC (ex: `AA:BB:CC:DD:EE:FF`) pour l'avoir sous la main.

## Étape 2 : Flasher la carte SD

Utilisez *Raspberry Pi Imager* pour flasher **Raspberry Pi OS Lite 64-bit (Bookworm)**.

Dans les paramètres avancés (⚙) :

| Paramètre | Valeur |
|-----------|--------|
| Hostname | `soundspot` |
| Utilisateur | `pi` |
| Mot de passe | votre choix |
| SSH | **Activé** |

## Étape 3 : Installation

Insérez la carte SD, allumez le Pi, puis ouvrez un terminal sur votre ordinateur :

```bash
ssh pi@soundspot.local
git clone https://github.com/papiche/sound-spot
cd sound-spot
sudo bash deploy_on_pi.sh --master
```

L'installeur vous posera quelques questions :

- **SSID** du réseau upstream (votre WiFi Internet, ex: `qo-op`)
- **Adresse MAC** de l'enceinte Bluetooth (notée à l'étape 1)
- **Activer Picoport ?** → `OUI` pour rejoindre la constellation UPlanet (IPFS + identité NOSTR + paiements G1)

La compilation des pilotes WiFi prend **environ 15 minutes**. Pendant ce temps, le Pi est silencieux. C'est normal.

## Étape 4 : Redémarrage et vérification

Le système redémarre automatiquement à la fin de l'installation. Pour confirmer que tout est en ordre :

```bash
# Se reconnecter après le reboot (~2 min)
ssh pi@soundspot.local

# Vérifier les services
check.sh
# ou depuis l'alias :
svc
```

**Indicateurs de succès :**

| Signal | Signification |
|--------|--------------|
| Réseau WiFi `ZICMAMA` visible | L'AP est active |
| `http://192.168.10.1` accessible | Portail captif en ligne |
| `systemctl status snapserver` → active | Audio prêt |
| Son d'accueil sur l'enceinte BT | Appairage Bluetooth réussi |

> **Si le son d'accueil ne sort pas** : lancez `sudo bash /opt/soundspot/backend/system/bt_update.sh` pour appairer l'enceinte interactivement après l'installation.

## Étape 5 : Première diffusion

1. Depuis un smartphone, connectez-vous au WiFi ouvert **ZICMAMA**.
2. Le portail captif s'ouvre automatiquement (ou naviguez vers `http://192.168.10.1`).
3. Cliquez **Ouvrir l'accès Internet** pour obtenir 4 heures d'accès.
4. Écoutez le flux audio depuis l'onglet **📻 Radio**.

## Dépannage de base

| Problème | Solution |
|----------|---------|
| `ssh: no route to host` après reboot | Attendre 2 min, le Pi démarre lentement |
| WiFi ZICMAMA absent | `systemctl status soundspot-ap` — vérifier `hostapd` |
| Portail 192.168.10.1 inaccessible | `systemctl status lighttpd` |
| Enceinte BT sans son | `sudo bash /opt/soundspot/backend/system/bt_update.sh` |
| Picoport non démarré | `systemctl status picoport` · logs : `journalctl -u picoport -n 50` |

---

Voir aussi : [Configuration DJ](howto-dj-configuration.md) · [Ajouter un Satellite](howto-mesh-satellite.md) · [Diagnostic](howto-logs-diagnostic.md)
