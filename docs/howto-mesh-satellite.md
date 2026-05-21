# Guide Pratique : Ajouter un Satellite au réseau Mesh B.A.T.M.A.N.

Pour étendre la portée de la musique sans tirer de câbles, vous pouvez ajouter des Satellites (Raspberry Pi Zero 2W).

## Prérequis
- Le Nœud Maître doit être allumé et fonctionnel.
- Un RPi Zero 2W équipé d'un dongle USB Wi-Fi (5GHz) et d'un DAC/Bluetooth.

## Procédure
1. Flashez une carte SD (Hostname: `soundspot-sat1`, SSH activé).
2. Connectez-vous en SSH au satellite :

```bash
ssh pi@soundspot-sat1.local
git clone https://github.com/papiche/sound-spot
cd sound-spot
sudo bash deploy_on_pi.sh --satellite
```

3. L'installeur va configurer `wlan1` en mode B.A.T.M.A.N.
4. Au redémarrage, le satellite s'attachera automatiquement au Maître via l'interface `bat0`.
5. Branchez votre enceinte sur le satellite : le son du Maître y sera diffusé avec un buffer de 3 secondes pour absorber la latence du réseau maillé.
