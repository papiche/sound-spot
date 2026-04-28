#!/usr/bin/env python3
import sounddevice as sd
import numpy as np
import requests, subprocess, base64, time, logging, threading, os, shutil

# --- CONFIGURATION DYNAMIQUE ---
AUDIO_THRESHOLD = 0.03       # Seuil auto-calibré possible plus tard
COOLDOWN_S = 45              
OLLAMA_URL = "http://127.0.0.1:11434/api/generate"
BOUCHE_URL = "http://192.168.10.1/api.sh?action=speak"
VOIX_IA = "pierre" 

logging.basicConfig(level=logging.INFO, format='👁 [%(levelname)s] %(message)s')
_analysis_lock = threading.Lock()

def say_error(text):
    logging.error(f"🗣 ALERTE : {text}")
    # On appelle espeak en direct pour ne pas dépendre de l'API web
    try:
        subprocess.Popen(["espeak-ng", "-v", "fr+f3", "-s", "140", f"Erreur oeil : {text}"])
    except:
        pass

def find_best_micro():
    """Détecte automatiquement le micro USB ou HAT par son nom."""
    try:
        devices = sd.query_devices()
        patterns = ["Q91", "W-KING", "USB Audio", "seeed", "respeaker"]
        for i, dev in enumerate(devices):
            if any(p.lower() in dev['name'].lower() for p in patterns):
                if dev['max_input_channels'] > 0:
                    logging.info(f"🎤 Micro détecté : {dev['name']} (Index {i})")
                    return i
        logging.warning("⚠️ Aucun micro reconnu. Utilisation du périphérique par défaut.")
        return None
    except Exception as e:
        logging.error(f"Erreur lors du scan audio : {e}")
        return None

def check_dependencies():
    """Vérifie si les outils nécessaires sont là."""
    if not shutil.which("libcamera-still"):
        logging.error("❌ 'libcamera-still' introuvable. Installation nécessaire : sudo apt install rpicam-apps")
        return False
    return True

def check_swarm_status():
    """Vérifie si le Cerveau IA (Ollama) répond via le tunnel P2P."""
    try:
        r = requests.get(OLLAMA_URL.replace("/api/generate", ""), timeout=2)
        return r.status_code == 200
    except:
        return False

def capture_and_process():
    """La logique métier complète."""
    if not _analysis_lock.acquire(blocking=False): return
    
    try:
        if not check_swarm_status():
            logging.warning("🧠 Cerveau IA injoignable (Ollama/Tunnel KO).")
            return

        img_path = "/dev/shm/eye_capture.jpg"
        logging.info("📸 Capture de l'image...")
        
        # Capture optimisée : 0.2s d'exposition, pas de preview, immédiat
        cmd = ["libcamera-still", "-o", img_path, "--width", "640", "--height", "480", "-t", "200", "--nopreview", "--immediate"]
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        if os.path.exists(img_path):
            with open(img_path, "rb") as f:
                img_b64 = base64.b64encode(f.read()).decode('utf-8')
            
            logging.info("🧠 Envoi au Swarm...")
            payload = {
                "model": "llava", 
                "prompt": "Décris cette scène en une phrase courte et drôle, puis invite à rejoindre le collectif G1FabLab.",
                "images": [img_b64], "stream": False
            }
            res = requests.post(OLLAMA_URL, json=payload, timeout=60).json()
            texte = res.get("response", "Je vois trouble...")
            
            logging.info(f"🤖 IA : {texte}")
            requests.post(BOUCHE_URL, data={"text": texte, "voice": VOIX_IA}, timeout=5)
            
    except Exception as e:
        logging.error(f"💥 Erreur cycle analyse : {e}")
    finally:
        _analysis_lock.release()

last_trigger = 0
def audio_callback(indata, frames, time_info, status):
    global last_trigger
    volume_norm = np.linalg.norm(indata) * 10 # Amplification pour détection
    
    if volume_norm > AUDIO_THRESHOLD:
        now = time.time()
        if now - last_trigger > COOLDOWN_S:
            last_trigger = now
            logging.info(f"👂 !!! SON DÉTECTÉ (Ampli: {volume_norm:.2f}) !!!")
            threading.Thread(target=capture_and_process, daemon=True).start()

def main():
    logging.info("🚀 Réveil du Golem Sensoriel...")
    
    # 1. Test Dépendances
    if not shutil.which("libcamera-still"):
        say_error("Outil caméra manquant. Installez rpicam apps.")
        return

    # 2. Test Micro
    mic_index = find_best_micro()
    if mic_index is None:
        say_error("Aucun micro détecté. Je suis sourd.")
        # On continue quand même en mode dégradé ? Non, on attend.
    
    try:
        with sd.InputStream(device=mic_index, callback=audio_callback, channels=1, samplerate=16000):
            # Annonce de succès au démarrage
            subprocess.Popen(["espeak-ng", "-v", "fr+f2", "-s", "150", "Système de vision et d'écoute prêt."])
            while True: time.sleep(1)
    except Exception as e:
        say_error("Le flux audio a planté.")
        logging.error(f"❌ Crash : {e}")

if __name__ == "__main__":
    main()