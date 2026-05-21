# Guide Pratique : Configuration Quotidienne et Session DJ

Ce guide explique comment opérer le SoundSpot au quotidien sans toucher au code.

## 1. Appairer une nouvelle enceinte Bluetooth
L'assistant interactif met à jour le fichier `soundspot.conf` et relance le son automatiquement.
`sudo bash /opt/soundspot/backend/system/bt_update.sh`
*(Allumez votre enceinte en mode appairage avant de lancer la commande).*

## 2. Modifier les messages vocaux (Le Clocher)
Les messages aléatoires du clocher sont générés par intelligence artificielle ou synthèse vocale locale.
1. Éditez les fichiers texte : `sudo nano /opt/soundspot/wav/message_01.txt`
2. Supprimez le fichier audio généré : `sudo rm /opt/soundspot/wav/message_01.wav`
Au prochain cycle (ou via le bouton du portail web), le système lira le nouveau texte et regénérera l'audio !

## 3. Démarrer une session DJ Live (PC Linux)
Sur le PC du DJ (connecté au WiFi ZICMAMA) :
1. Lancez l'assistant : `bash dj_mixxx_setup.sh`
2. L'assistant vous génère un script `~/zicmama_play.sh`.
3. Lancez ce script : il active le retour casque sans latence (`snapclient`) et ouvre **Mixxx**.
4. Dans Mixxx, allez dans "Live Broadcasting" et vérifiez la configuration (Icecast2, Port 8111, Mount /live). Cliquez sur l'icône Antenne pour émettre !
