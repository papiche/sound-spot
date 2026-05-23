# Tutoriel : Créer votre premier SoundSpot (Nœud Maître)

Ce tutoriel vous guidera dans la création de votre premier nœud autonome CyberCochon.

## Étape 1 : Préparation matérielle
*(Consultez la [Nomenclature et Guide d'Achats](reference-nomenclature.md) pour la liste exacte des composants et le budget).*
1. Branchez votre Raspberry Pi 4 à une alimentation suffisante (ex: convertisseur 12V/5V 5A).
2. Connectez le dongle Wi-Fi Vemfay sur un port USB 3.0 (bleu).
3. Branchez la Caméra Module 3 sur le port CSI.

## Étape 2 : Flasher la carte SD
Utilisez *Raspberry Pi Imager* pour flasher **Raspberry Pi OS Lite 64-bit (Bookworm)**.
Dans les paramètres avancés (⚙) :
- Hostname : `soundspot`
- Utilisateur : `pi` / Mot de passe de votre choix.
- SSH : Activé.

## Étape 3 : Installation
Insérez la carte SD, allumez le Pi, puis ouvrez un terminal sur votre ordinateur :

```
ssh pi@soundspot.local
git clone https://github.com/papiche/sound-spot
cd sound-spot
sudo bash deploy_on_pi.sh --master
```

Répondez `OUI` à l'activation de Picoport et patientez environ 15 minutes (le Pi compilera les pilotes Wi-Fi). Le système redémarrera automatiquement.

## Étape 4 : Première diffusion
1. Depuis un smartphone, connectez-vous au réseau Wi-Fi ouvert **ZICMAMA**.
2. Le portail captif s'ouvre. Cliquez pour obtenir vos 4 heures d'internet.
3. Le son d'accueil retentit. Vous êtes en ligne !
