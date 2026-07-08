#!/usr/bin/env python3
"""
stream_commentator.py — Commentateur IA de flux RTMP (Ollama llava + Orpheus TTS)

Surveille le flux vidéo actif (/dev/shm/current_vj). Quand un DJ ou un drone
diffuse, capture une frame via ffmpeg, interroge Ollama (vision) selon le style
choisi, et diffuse le commentaire vocal via l'API speak du portail.

Contrôle runtime (fichiers /dev/shm — modifiables à chaud par l'API) :
  commentator_enabled     présence = actif
  commentator_interval    intervalle entre commentaires (secondes, défaut 60)
  commentator_style       "concert" | "accueil" | "poetic" | "free" (défaut: concert)
  commentator_last        dernier commentaire émis (écrit par ce daemon)
  commentator.pid         PID du daemon (autogestion)

Variables d'environnement (soundspot.conf) :
  OLLAMA_URL          URL Ollama (défaut: http://127.0.0.1:11434/api/generate)
  OLLAMA_VISION_MODEL Modèle vision Ollama (défaut: llama3.2-vision:11b — "llava" n'est
                       pas garanti présent sur le swarm, cf. mon-oeil.py)
  BOUCHE_URL      URL API speak portail (défaut: http://192.168.10.1/api.sh?action=speak)
  MON_OEIL_VOICE  Voix Orpheus (défaut: pierre)
  RTMP_BASE       Base URL RTMP (défaut: rtmp://127.0.0.1/live/)
  LOG_LEVEL       DEBUG|INFO|WARN|ERROR (défaut: INFO)
  SOUNDSPOT_LOG   Fichier log centralisé
"""

import base64
import logging
import os
import shutil
import subprocess
import sys
import time
import threading
import requests

# ── Configuration ────────────────────────────────────────────────────────
OLLAMA_URL   = os.getenv("OLLAMA_URL",    "http://127.0.0.1:11434/api/generate")
OLLAMA_VISION_MODEL = os.getenv("OLLAMA_VISION_MODEL", "llama3.2-vision:11b")
BOUCHE_URL   = os.getenv("BOUCHE_URL",    "http://192.168.10.1/api.sh?action=speak")
VOIX_IA      = os.getenv("MON_OEIL_VOICE","pierre")
RTMP_BASE    = os.getenv("RTMP_BASE",     "rtmp://127.0.0.1/live/")
INSTALL_DIR  = os.getenv("INSTALL_DIR",   "/opt/soundspot")
SPOT_IP      = os.getenv("SPOT_IP",       "192.168.10.1")

FRAME_PATH   = "/dev/shm/commentator_frame.jpg"
PID_FILE     = "/dev/shm/commentator.pid"
ENABLED_FLAG = "/dev/shm/commentator_enabled"
INTERVAL_F   = "/dev/shm/commentator_interval"
STYLE_F      = "/dev/shm/commentator_style"
LAST_F       = "/dev/shm/commentator_last"
CURRENT_VJ   = "/dev/shm/current_vj"

DEFAULT_INTERVAL = 60

STYLE_PROMPTS = {
    "concert": (
        "Tu es un commentateur de scène musical enthousiaste. "
        "Décris en une phrase courte et percutante ce que tu vois sur cette image, "
        "comme si tu commentais un concert live. Langue : français."
    ),
    "accueil": (
        "Tu es un hôte chaleureux accueillant des visiteurs dans un espace festif. "
        "Décris la scène en une phrase conviviale et bienveillante. Langue : français."
    ),
    "poetic": (
        "Tu es un poète surréaliste. Décris cette image en une seule phrase poétique, "
        "imagée et inattendue, sans jamais la décrire littéralement. Langue : français."
    ),
    "free": (
        "Décris ce que tu vois sur cette image en une phrase courte et drôle. "
        "Langue : français."
    ),
}

# ── Logging ──────────────────────────────────────────────────────────────
_LOG_LEVEL = {
    "DEBUG": logging.DEBUG, "INFO": logging.INFO,
    "WARN": logging.WARNING, "WARNING": logging.WARNING, "ERROR": logging.ERROR,
}.get(os.getenv("LOG_LEVEL", "INFO").upper(), logging.INFO)
_LOG_FILE = os.getenv("SOUNDSPOT_LOG", "/var/log/sound-spot.log")
_FMT  = "%(asctime)s [%(levelname)-5s] [commentateur] %(message)s"
_DFMT = "%Y-%m-%d %H:%M:%S"

log = logging.getLogger("commentateur")
log.setLevel(_LOG_LEVEL)
_sh = logging.StreamHandler()
_sh.setFormatter(logging.Formatter(_FMT, _DFMT))
log.addHandler(_sh)
try:
    _fh = logging.FileHandler(_LOG_FILE, encoding="utf-8")
    _fh.setFormatter(logging.Formatter(_FMT, _DFMT))
    log.addHandler(_fh)
except OSError as _e:
    log.warning("Log fichier inaccessible : %s", _e)

# ── Helpers ──────────────────────────────────────────────────────────────

def _read_flag(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default

def _interval():
    try:
        return max(15, int(_read_flag(INTERVAL_F, str(DEFAULT_INTERVAL))))
    except ValueError:
        return DEFAULT_INTERVAL

def _style():
    s = _read_flag(STYLE_F, "concert")
    return s if s in STYLE_PROMPTS else "concert"

def _is_enabled():
    return os.path.exists(ENABLED_FLAG)

def _active_stream():
    name = _read_flag(CURRENT_VJ, "").strip()
    return name if name else None


# ── Capture frame RTMP via ffmpeg ────────────────────────────────────────

def capture_frame(stream_name: str) -> bool:
    """Capture une image JPEG depuis le flux RTMP actif."""
    if not shutil.which("ffmpeg"):
        log.error("ffmpeg introuvable — impossible de capturer le flux")
        return False
    url = RTMP_BASE + stream_name
    cmd = [
        "ffmpeg", "-y",
        "-rtmp_live", "live",
        "-i", url,
        "-vframes", "1",
        "-q:v", "3",
        "-f", "image2",
        FRAME_PATH,
    ]
    try:
        subprocess.run(cmd, timeout=12, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return os.path.exists(FRAME_PATH) and os.path.getsize(FRAME_PATH) > 0
    except subprocess.TimeoutExpired:
        log.warning("ffmpeg timeout — flux %s non joignable ?", stream_name)
    except subprocess.CalledProcessError as exc:
        log.warning("ffmpeg code %d pour le flux %s", exc.returncode, stream_name)
    except Exception as exc:
        log.error("Erreur capture : %s", exc)
    return False


# ── Ollama llava ─────────────────────────────────────────────────────────

def _ollama_alive() -> bool:
    base = OLLAMA_URL.replace("/api/generate", "")
    try:
        r = requests.get(base, timeout=3)
        return r.status_code == 200
    except Exception:
        return False


def describe_frame(style: str) -> str | None:
    """Envoie la frame à Ollama llava et retourne le texte généré."""
    if not os.path.exists(FRAME_PATH):
        return None
    try:
        with open(FRAME_PATH, "rb") as f:
            img_b64 = base64.b64encode(f.read()).decode()
    except OSError as exc:
        log.error("Lecture frame : %s", exc)
        return None

    prompt = STYLE_PROMPTS.get(style, STYLE_PROMPTS["concert"])
    payload = {
        "model": OLLAMA_VISION_MODEL,
        "prompt": prompt,
        "images": [img_b64],
        "stream": False,
    }
    try:
        resp = requests.post(OLLAMA_URL, json=payload, timeout=60)
        resp.raise_for_status()
        data = resp.json()
        if "error" in data:
            log.error("Ollama a répondu une erreur (%s) : %s", OLLAMA_VISION_MODEL, data["error"])
            return None
        text = data.get("response", "").strip()
        return text[:300] if text else None
    except requests.Timeout:
        log.warning("Ollama timeout — réponse trop longue")
    except Exception as exc:
        log.error("Erreur Ollama : %s", exc)
    return None


# ── Diffusion vocale via API speak ───────────────────────────────────────

def speak(text: str, voice: str = VOIX_IA):
    """Envoie le texte à l'API speak du portail (Orpheus ou espeak)."""
    import urllib.parse
    body = f"text={urllib.parse.quote_plus(text)}&voice={urllib.parse.quote_plus(voice)}"
    try:
        requests.post(
            BOUCHE_URL,
            data=body,
            headers={"Content-Type": "application/x-www-form-urlencoded",
                     "REMOTE_ADDR": "127.0.0.1"},
            timeout=10,
        )
        log.info("Commentaire diffusé : %s", text[:80])
    except Exception as exc:
        log.warning("API speak inaccessible : %s — fallback espeak", exc)
        try:
            subprocess.run(
                ["espeak-ng", "-v", "fr+f3", "-s", "120", text[:200]],
                timeout=15, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass


# ── Cycle principal ───────────────────────────────────────────────────────

_comment_lock = threading.Lock()


def run_comment_cycle():
    """Capture + describe + speak. Non-bloquant via thread."""
    if not _comment_lock.acquire(blocking=False):
        log.debug("Cycle en cours — ignoré")
        return
    try:
        stream = _active_stream()
        if not stream:
            log.debug("Aucun flux actif — cycle ignoré")
            return

        style = _style()
        log.info("Cycle commentateur : flux=%s style=%s", stream, style)

        if not _ollama_alive():
            log.warning("Ollama injoignable — commentaire annulé")
            return

        if not capture_frame(stream):
            log.warning("Capture frame échouée pour le flux %s", stream)
            return

        text = describe_frame(style)
        if not text:
            log.warning("Ollama n'a pas retourné de texte")
            return

        # Mémoriser le dernier commentaire (lisible par l'API)
        try:
            with open(LAST_F, "w") as f:
                f.write(text)
        except OSError:
            pass

        speak(text)

    except Exception as exc:
        log.error("Erreur cycle commentateur : %s", exc)
    finally:
        _comment_lock.release()


# ── Boucle principale ────────────────────────────────────────────────────

def main():
    # PID file
    try:
        with open(PID_FILE, "w") as f:
            f.write(str(os.getpid()))
    except OSError:
        pass

    log.info("Commentateur IA démarré (pid %d)", os.getpid())
    log.info("Ollama : %s (%s)  |  Speak : %s  |  Voix : %s", OLLAMA_URL, OLLAMA_VISION_MODEL, BOUCHE_URL, VOIX_IA)

    next_run = 0.0

    try:
        while True:
            now = time.monotonic()
            if _is_enabled() and _active_stream() and now >= next_run:
                interval = _interval()
                next_run = now + interval
                threading.Thread(target=run_comment_cycle, daemon=True).start()
            time.sleep(5)
    except KeyboardInterrupt:
        log.info("Arrêt demandé")
    finally:
        try:
            os.unlink(PID_FILE)
        except OSError:
            pass


if __name__ == "__main__":
    main()
