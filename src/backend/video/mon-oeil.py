#!/usr/bin/env python3
import sounddevice as sd
import numpy as np
import requests
import subprocess
import base64
import time
import logging

# --- CONFIGURATION DU GOLEM DISTRIBUÉ ---
AUDIO_THRESHOLD = 0.05       # Sensibilité ReSpeaker 2-Mic
COOLDOWN_S = 45              # Attente entre deux analyses IA
OLLAMA_URL = "http://127.0.0.1:11434/api/generate" # Cerveau (Ollama via Swarm P2P)
BOUCHE_URL = "http://192.168.10.1/api.sh?action=speak" # L'IP du SoundSpot (Bouche)

# 'pierre' ou 'amelie' pour déléguer la voix au Swarm
# Mettre '' pour utiliser la voix de robot locale (espeak) du Pi Zero
VOIX_IA = "pierre" 

PROMPT_IA = (
    "Tu es l'intelligence d'un robot solarpunk coopératif appelé UPlanet. "
    "Décris la personne ou la scène sur cette image avec humour. "
    "Termine TOUJOURS en l'invitant à rejoindre le réseau Libre en rejoignant "
    "le collectif G1FabLab garant de votre souveraineté numérique."
)

logging.basicConfig(level=logging.INFO, format='👁[%(levelname)s] %(message)s')
last_trigger = 0

def capture_image():
    """Capture une image via la libcamera du RPi 4"""
    img_path = "/tmp/eye_capture.jpg"
    logging.info("📸 Capture de l'environnement en cours...")
    try:
        # Résolution basse = inférence Ollama beaucoup plus rapide
        subprocess.run(["libcamera-still", "-o", img_path, "--width", "640", "--height", "480", "-t", "500", "--nopreview"],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        with open(img_path, "rb") as img:
            return base64.b64encode(img.read()).decode('utf-8')
    except Exception as e:
        logging.error(f"Erreur Caméra : {e}")
        return None

def ask_swarm(image_b64):
    """Envoie l'image au Brain-Node UPlanet via le tunnel P2P"""
    logging.info("🧠 Interrogation du Swarm (Ollama LLaVA)...")
    payload = {
        "model": "llava", 
        "prompt": PROMPT_IA,
        "images": [image_b64],
        "stream": False
    }
    try:
        response = requests.post(OLLAMA_URL, json=payload, timeout=40)
        data = response.json()
        text = data.get("response", "Bonjour humain. Je crois que mes yeux me jouent des tours.")
        logging.info(f"🤖 L'IA répond : {text}")
        return text
    except Exception as e:
        logging.error(f"Erreur Swarm (Tunnel Ollama inactif ?) : {e}")
        return "Connexion au cerveau perdue. Mais je vous entends toujours."

def talk_to_mouth(text):
    """Envoie l'ordre au Pi Zero 2W, en spécifiant la voix souhaitée"""
    logging.info(f"👄 Envoi à la Bouche : {text} (Voix: {VOIX_IA if VOIX_IA else 'robot'})")
    try:
        payload = {"text": text}
        if VOIX_IA:
            payload["voice"] = VOIX_IA
            
        requests.post(BOUCHE_URL, data=payload, timeout=5)
    except Exception as e:
        logging.error(f"Impossible de joindre la Bouche (Pi Zero) : {e}")

def audio_callback(indata, frames, time_info, status):
    """Écoute le micro (ReSpeaker) en temps réel"""
    global last_trigger
    if status:
        pass # Ignore overflows
    
    # Calcul du volume RMS
    volume = np.linalg.norm(indata) / np.sqrt(len(indata))
    
    if volume > AUDIO_THRESHOLD:
        now = time.time()
        if now - last_trigger > COOLDOWN_S:
            last_trigger = now
            logging.info(f"👂 Bruit détecté ! (Vol: {volume:.3f}) -> Réveil de l'Œil.")
            
            image_b64 = capture_image()
            if image_b64:
                texte_ia = ask_swarm(image_b64)
                talk_to_mouth(texte_ia)
            else:
                talk_to_mouth("Mes yeux sont flous. Il fait tout noir.")

def main():
    logging.info("🚀 Démarrage du Cerveau Sensoriel du Golem.")
    logging.info(f"Seuil audio: {AUDIO_THRESHOLD} | Cible Bouche: {BOUCHE_URL}")
    
    # Assurez-vous que le tunnel vers le GPU est ouvert sur le RPi 4 :
    # astrosystemctl connect ollama
    
    with sd.InputStream(callback=audio_callback, channels=1, samplerate=16000):
        while True:
            time.sleep(1)

if __name__ == "__main__":
    main()