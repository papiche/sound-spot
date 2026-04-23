# Supprimer les wav existants pour forcer espeak-ng à retravailler
sudo rm /opt/soundspot/wav/*.wav
# Redémarrer le service pour déclencher la génération
sudo systemctl restart soundspot-idle
# Vérifier les logs pour voir la génération
tail -f /var/log/sound-spot.log | grep idle