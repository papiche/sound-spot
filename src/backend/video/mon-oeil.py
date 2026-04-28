#!/usr/bin/env python3
"""
mon-oeil.py — Satellite Sensoriel Distribué (son + vision + IA Ollama)

Détecte le son ambiant. Quand un seuil est dépassé (et après cooldown),
capture une image et demande à Ollama (llava) de décrire la scène.
La réponse est diffusée via l'API /api.sh?action=speak du portail captif.

Accès caméra :
  - Priorité : lit /dev/shm/latest_frame.jpg (écrit par presence_detector.py).
    → Les deux services partagent ainsi la caméra sans conflit.
  - Fallback : appelle libcamera-still directement (si presence_detector
    n'est PAS actif — PRESENCE_ENABLED=false).

Variables d'environnement (depuis soundspot.conf) :
  AUDIO_THRESHOLD   Seuil détection audio    (défaut : 0.03)
  COOLDOWN_S        Délai entre analyses (s) (défaut : 45)
  OLLAMA_URL        URL Ollama locale         (défaut : http://127.0.0.1:11434/api/generate)
  BOUCHE_URL        URL API speak portail     (défaut : http://192.168.10.1/api.sh?action=speak)
  MON_OEIL_VOICE    Voix Orpheus              (défaut : pierre)
  SHARED_FRAME_MAX_AGE_S   Âge max frame partagé (défaut : 30)
  LOG_LEVEL         DEBUG|INFO|WARN|ERROR     (défaut : INFO)
  SOUNDSPOT_LOG     Fichier de log centralisé (défaut : /var/log/sound-spot.log)
"""

import sounddevice as sd
import numpy as np
import requests
import subprocess
import base64
import time
import logging
import threading
import os
import shutil

# ── Configuration ──────────────────────────────────────────────────────
AUDIO_THRESHOLD    = float(os.getenv("AUDIO_THRESHOLD",    "0.03"))
COOLDOWN_S         = int(os.getenv("COOLDOWN_S",           "45"))
OLLAMA_URL         = os.getenv("OLLAMA_URL",               "http://127.0.0.1:11434/api/generate")
BOUCHE_URL         = os.getenv("BOUCHE_URL",               "http://192.168.10.1/api.sh?action=speak")
VOIX_IA            = os.getenv("MON_OEIL_VOICE",           "pierre")

# Frame partagé avec presence_detector.py (accès caméra sans conflit)
SHARED_FRAME_PATH     = os.getenv("PRESENCE_SHARE_FRAME",       "/dev/shm/latest_frame.jpg")
SHARED_FRAME_MAX_AGE  = int(os.getenv("SHARED_FRAME_MAX_AGE_S", "30"))

# ── Logging structuré (même format que presence_detector.py) ───────────
_LOG_LEVEL = {
    "DEBUG": logging.DEBUG, "INFO": logging.INFO,
    "WARN": logging.WARNING, "WARNING": logging.WARNING,
    "ERROR": logging.ERROR,
}.get(os.getenv("LOG_LEVEL", "INFO").upper(), logging.INFO)
_LOG_FILE = os.getenv("SOUNDSPOT_LOG", "/var/log/sound-spot.log")
_FMT  = "%(asctime)s [%(levelname)-5s] [mon-oeil     ] %(message)s"
_DFMT = "%Y-%m-%d %H:%M:%S"

log = logging.getLogger("mon-oeil")
log.setLevel(_LOG_LEVEL)
_sh = logging.StreamHandler()
_sh.setFormatter(logging.Formatter(_FMT, _DFMT))
log.addHandler(_sh)
try:
    _fh = logging.FileHandler(_LOG_FILE, encoding="utf-8")
    _fh.setFormatter(logging.Formatter(_FMT, _DFMT))
    log.addHandler(_fh)
except OSError as _e:
    log.warning("Impossible d'ouvrir le fichier de log %s : %s", _LOG_FILE, _e)

# ── Lock analyse (une seule analyse à la fois) ─────────────────────────
_analysis_lock = threading.Lock()


# ── Micro ──────────────────────────────────────────────────────────────
def find_best_micro():
    """Détecte automatiquement le micro USB ou HAT par son nom."""
    try:
        devices = sd.query_devices()
        patterns = ["Q91", "W-KING", "USB Audio", "seeed", "respeaker"]
        for i, dev in enumerate(devices):
            if any(p.lower() in dev["name"].lower() for p in patterns):
                if dev["max_input_channels"] > 0:
                    log.info("Micro détecté : %s (index %d)", dev["name"], i)
                    return i
        log.warning("Aucun micro reconnu — utilisation du périphérique par défaut")
        return None
    except Exception as exc:
        log.error("Erreur scan audio : %s", exc)
        return None


# ── Ollama ─────────────────────────────────────────────────────────────
def check_swarm_status():
    """Vérifie si Ollama répond (local ou tunnel P2P)."""
    try:
        r = requests.get(OLLAMA_URL.replace("/api/generate", ""), timeout=2)
        return r.status_code == 200
    except Exception:
        return False


# ── Caméra : accès partagé via frame de presence_detector.py ──────────
def _read_shared_frame(dest_path):
    """
    Copie /dev/shm/latest_frame.jpg vers dest_path si le fichier est récent.
    Retourne True si succès, False si absent/trop vieux.
    """
    if not os.path.exists(SHARED_FRAME_PATH):
        return False
    age = time.time() - os.path.getmtime(SHARED_FRAME_PATH)
    if age > SHARED_FRAME_MAX_AGE:
        log.warning("Frame partagé trop vieux (%.0fs > %ds) — presence_detector inactif ?",
                    age, SHARED_FRAME_MAX_AGE)
        return False
    try:
        shutil.copy2(SHARED_FRAME_PATH, dest_path)
        log.info("Frame partagé utilisé (âge %.0fs) — aucun conflit caméra", age)
        return True
    except OSError as exc:
        log.error("Impossible de copier le frame partagé : %s", exc)
        return False


def _capture_libcamera(dest_path):
    """
    Capture directe via libcamera-still.
    Utilisé en fallback si presence_detector n'est PAS actif.
    """
    if not shutil.which("libcamera-still"):
        log.error("libcamera-still introuvable — installer : sudo apt install rpicam-apps")
        return False
    try:
        cmd = [
            "libcamera-still", "-o", dest_path,
            "--width", "640", "--height", "480",
            "-t", "200", "--nopreview", "--immediate",
        ]
        subprocess.run(cmd, check=True, timeout=10,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log.info("Capture libcamera-still directe (presence_detector non actif)")
        return os.path.exists(dest_path)
    except subprocess.CalledProcessError as exc:
        log.error("libcamera-still a échoué (code %d) — caméra occupée par un autre service ?",
                  exc.returncode)
        return False
    except subprocess.TimeoutExpired:
        log.error("libcamera-still : timeout — caméra bloquée")
        return False
    except Exception as exc:
        log.error("Erreur capture caméra : %s", exc)
        return False


def capture_image():
    """
    Retourne le chemin d'une image capturée, ou None si impossible.
    Stratégie :
      1. Frame partagé par presence_detector.py (préféré — pas de conflit).
      2. libcamera-still en direct (fallback si presence non actif).
    """
    dest = "/dev/shm/eye_capture.jpg"
    if _read_shared_frame(dest):
        return dest
    log.info("Frame partagé indisponible — tentative libcamera-still directe")
    return dest if _capture_libcamera(dest) else None


# ── Cycle analyse principal ────────────────────────────────────────────
def capture_and_process():
    """Capture + envoi Ollama + diffusion vocale (non bloquant via thread)."""
    if not _analysis_lock.acquire(blocking=False):
        log.debug("Analyse en cours — déclenchement ignoré")
        return
    try:
        if not check_swarm_status():
            log.warning("Cerveau IA injoignable (Ollama/Tunnel KO) — analyse annulée")
            return

        img_path = capture_image()
        if img_path is None:
            log.error("Impossible d'obtenir une image — analyse annulée")
            return

        with open(img_path, "rb") as f:
            img_b64 = base64.b64encode(f.read()).decode("utf-8")

        log.info("Envoi image au Swarm Ollama (llava)…")
        payload = {
            "model": "llava",
            "prompt": "Décris cette scène en une phrase courte et drôle, puis invite à rejoindre le collectif G1FabLab.",
            "images": [img_b64],
            "stream": False,
        }
        res = requests.post(OLLAMA_URL, json=payload, timeout=60).json()
        texte = res.get("response", "Je vois trouble…")

        log.info("Réponse IA : %s", texte[:120])
        try:
            requests.post(BOUCHE_URL, data={"text": texte, "voice": VOIX_IA}, timeout=5)
        except Exception as exc:
            log.warning("Envoi voix échoué : %s", exc)

    except Exception as exc:
        log.error("Erreur cycle analyse : %s", exc)
    finally:
        _analysis_lock.release()


# ── Callback audio ─────────────────────────────────────────────────────
last_trigger = 0.0


def audio_callback(indata, frames, time_info, status):
    global last_trigger
    if status:
        log.debug("sounddevice status : %s", status)
    volume_norm = float(np.linalg.norm(indata)) / max(1, len(indata) ** 0.5) * 10
    if volume_norm > AUDIO_THRESHOLD:
        now = time.monotonic()
        if now - last_trigger > COOLDOWN_S:
            last_trigger = now
            log.info("Son détecté (niveau %.2f) — lancement analyse", volume_norm)
            threading.Thread(target=capture_and_process, daemon=True).start()


# ── Main ───────────────────────────────────────────────────────────────
def main():
    log.info("Réveil du Satellite Sensoriel — seuil audio=%.3f cooldown=%ds",
             AUDIO_THRESHOLD, COOLDOWN_S)
    log.info("Frame partagé : %s (max âge %ds)", SHARED_FRAME_PATH, SHARED_FRAME_MAX_AGE)

    mic_index = find_best_micro()

    try:
        with sd.InputStream(device=mic_index, callback=audio_callback,
                            channels=1, samplerate=16000):
            log.info("Écoute micro active — Ctrl+C pour arrêter")
            subprocess.Popen(
                ["espeak-ng", "-v", "fr+f2", "-s", "150", "Système de vision et d'écoute prêt."],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            while True:
                time.sleep(1)
    except KeyboardInterrupt:
        log.info("Arrêt demandé par l'utilisateur")
    except Exception as exc:
        log.error("Crash flux audio : %s", exc)
        try:
            subprocess.Popen(
                ["espeak-ng", "-v", "fr+f3", "-s", "140", "Erreur oeil : flux audio planté."],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass


if __name__ == "__main__":
    main()
