# Guide Pratique : Lire les logs et Diagnostiquer un nœud

En festival ou en zone isolée, si le son coupe ou si le réseau plante, vous devez savoir où regarder. Ce guide répertorie les outils de diagnostic intégrés au CyberCochon.

## 1. Le Diagnostic Automatique (L'outil "Check")
La commande `check` (ou `sudo bash /opt/soundspot/check.sh`) est votre meilleur ami. Elle teste :
- L'état de tous les services systemd.
- Le réseau amont (5G) et le réseau visiteur (uap0).
- Le maillage B.A.T.M.A.N. (bat0) et ses voisins.
- La présence d'erreurs PipeWire (Xruns).
- L'état des batteries (INA219) et la température du CPU.

*Pour un rapport extrêmement détaillé avec les 50 dernières lignes de tous les journaux système, utilisez :*
`sudo bash /opt/soundspot/check.sh --debug`

## 2. Lire les Logs Centralisés
Tous les services (bash, python, API web) écrivent dans un seul fichier sécurisé en RAM (protège la carte SD).
`tail -f /var/log/sound-spot.log`

## 3. Surveiller le Portail Web (API)
Si vous développez ou dépannez le portail captif, utilisez `journalctl` pour filtrer les accès HTTP et CGI du service lighttpd :
`sudo journalctl -u lighttpd -f`
*Pour filtrer uniquement les erreurs :* `sudo journalctl -u lighttpd -p err -f`

## 4. Les Alias Picoport (Raccourcis)
Si vous êtes connecté avec l'utilisateur `pi`, tapez ces raccourcis dans le terminal :
- `pico-status` : Vue macro (Température, Uptime, Batterie, Peers IPFS).
- `12345` : Affiche la balise de visibilité Swarm (JSON) de votre nœud.
- `svc` : Affiche l'état synthétique des services SoundSpot.
