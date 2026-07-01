# Vérifier que tts.sh fonctionne sans Picoport
bash /opt/soundspot/backend/audio/tts.sh "Bonjour test espeak" pierre /tmp/test.wav && aplay /tmp/test.wav

# Avec Picoport actif
bash ~/.zen/Astroport.ONE/IA/services/orpheus.me.sh  # connecter le tunnel
bash /opt/soundspot/backend/audio/tts.sh "Je suis Pierre connecté à UPlanet" pierre /tmp/test_orpheus.wav
