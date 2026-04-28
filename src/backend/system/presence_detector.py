#!/usr/bin/env python3
"""
SoundSpot — Détecteur de présence (mouvement + son + visage optionnel)
Cible  : Pi Zero 2W — mode motion par défaut (CPU < 5 %)

Modes (PRESENCE_MODE) :
  motion  Différentiel de pixels entre deux frames (défaut, ultra-léger)
  face    Haar cascade visage (ancien comportement, CPU élevé)
  audio   Pic de volume micro USB uniquement (sans caméra)
  any     Motion OU audio — le plus réactif

Variables d'environnement (depuis soundspot.conf) :
  PRESENCE_MODE             motion|face|audio|any   (défaut : motion)
  PRESENCE_MOTION_THRESHOLD Seuil diff pixels       (défaut : 10000)
  PRESENCE_AUDIO_THRESHOLD  Seuil RMS micro         (défaut : 0.05)
  PRESENCE_COOLDOWN         Secondes entre triggers (défaut : 30)
  PRESENCE_BLIND_INTERVAL   Intervalle mode aveugle (défaut : 900)
  PRESENCE_INTERVAL         1 analyse / N frames    (défaut : 5)
  PRESENCE_WIDTH            Largeur caméra px       (défaut : 320)
  PRESENCE_HEIGHT           Hauteur caméra px       (défaut : 240)
  PRESENCE_FPS              FPS caméra demandé      (défaut : 15)
  PRESENCE_SCALE            Haar scaleFactor        (défaut : 1.3)
  PRESENCE_NEIGHBORS        Haar minNeighbors       (défaut : 4)
  PRESENCE_MIN_FACE         Taille min visage px    (défaut : 20)
  PRESENCE_USE_TTS          true → messages vocaux  (défaut : false)
  PRESENCE_WELCOME_CMD      Commande accueil        (défaut : play_welcome.sh)
  PRESENCE_TTS_CMD          Chemin vers tts.sh      (défaut : auto)

Droits requis (groupes de SOUNDSPOT_USER) :
  video, render → accès caméra (picamera2 / V4L2)
  audio         → accès micro USB (sounddevice)
"""
import cv2
import subprocess
import threading
import time
import logging
import os
import signal
import sys
import random

try:
    import numpy as np
    _NP_OK = True
except ImportError:
    _NP_OK = False

# ── Configuration ────────────────────────────────────────────────────
MODE            = os.getenv("PRESENCE_MODE",             "motion").lower()
MOTION_THR      = int(os.getenv("PRESENCE_MOTION_THRESHOLD", "10000"))
AUDIO_THR       = float(os.getenv("PRESENCE_AUDIO_THRESHOLD",  "0.05"))
COOLDOWN_S      = int(os.getenv("PRESENCE_COOLDOWN",         "30"))
BLIND_INTERVAL  = max(1, int(os.getenv("PRESENCE_BLIND_INTERVAL", "900")))
DETECT_INTERVAL = int(os.getenv("PRESENCE_INTERVAL",         "5"))
FRAME_W         = int(os.getenv("PRESENCE_WIDTH",            "320"))
FRAME_H         = int(os.getenv("PRESENCE_HEIGHT",           "240"))
CAMERA_FPS      = int(os.getenv("PRESENCE_FPS",              "15"))
SCALE_FACTOR    = float(os.getenv("PRESENCE_SCALE",           "1.3"))
MIN_NEIGHBORS   = int(os.getenv("PRESENCE_NEIGHBORS",         "4"))
MIN_FACE_PX     = int(os.getenv("PRESENCE_MIN_FACE",          "20"))
USE_TTS         = os.getenv("PRESENCE_USE_TTS", "false").lower() == "true"

INSTALL_DIR = os.getenv("INSTALL_DIR", "/opt/soundspot")
WELCOME_CMD = os.getenv(
    "PRESENCE_WELCOME_CMD",
    os.path.join(INSTALL_DIR, "backend/audio/play_welcome.sh"),
)
TTS_CMD = os.getenv(
    "PRESENCE_TTS_CMD",
    os.path.join(INSTALL_DIR, "backend/audio/tts.sh"),
)

# ── Messages d'accueil amusants (choix aléatoire) ────────────────────
MESSAGES = [
    "Tiens, quelqu'un est dans le coin. Bienvenue !",
    "Un mouvement détecté. Bonjour, curieux de la musique libre ?",
    "Je vous ai vu arriver. Bienvenue dans notre réseau coopératif.",
    "Signal capté. Ce son vous a attiré jusqu'ici ? Bonne pioche.",
    "Un humain dans mon champ de vision. Fascinant. Restez donc.",
    "Ah, quelqu'un est là. La constellation UPlanet s'illumine d'un nouveau point.",
    "Vous avez trouvé notre spot. Bien joué. La musique est offerte.",
    "Bonjour ! Ce son voyage via Snapcast jusqu'à vos oreilles en direct.",
    "Présence détectée. Je ne suis plus seul dans ce nœud du réseau.",
    "Le Golem vous salue. Vous êtes chez les aficionados du son libre.",
    "Bienvenue ! Ce nœud fait partie d'un réseau coopératif décentralisé.",
    "Restez, la prochaine annonce sera dans quelques minutes.",
]

# ── Logging ──────────────────────────────────────────────────────────
_LOG_LEVEL = {
    "DEBUG": logging.DEBUG, "INFO": logging.INFO,
    "WARN": logging.WARNING, "WARNING": logging.WARNING,
    "ERROR": logging.ERROR,
}.get(os.getenv("LOG_LEVEL", "INFO").upper(), logging.INFO)
_LOG_FILE = os.getenv("SOUNDSPOT_LOG", "/var/log/sound-spot.log")
_FMT  = "%(asctime)s [%(levelname)-5s] [presence     ] %(message)s"
_DFMT = "%Y-%m-%d %H:%M:%S"

log = logging.getLogger("presence")
log.setLevel(_LOG_LEVEL)
_sh = logging.StreamHandler()
_sh.setFormatter(logging.Formatter(_FMT, _DFMT))
log.addHandler(_sh)
try:
    _fh = logging.FileHandler(_LOG_FILE, encoding="utf-8")
    _fh.setFormatter(logging.Formatter(_FMT, _DFMT))
    log.addHandler(_fh)
except OSError:
    pass

# ── sounddevice (optionnel — micro USB) ──────────────────────────────
_SD_OK = False
_np_audio = None
try:
    import sounddevice as _sd
    import numpy as _np_audio
    _SD_OK = True
    log.info("sounddevice disponible — détection audio active (seuil %.3f)", AUDIO_THR)
except ImportError:
    log.info("sounddevice absent — détection audio désactivée")


# ── Haar XML (mode face uniquement) ──────────────────────────────────
def _find_haar_xml():
    if hasattr(cv2, "data") and hasattr(cv2.data, "haarcascades"):
        return cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    for _p in [
        "/usr/share/opencv4/haarcascades",
        "/usr/share/opencv/haarcascades",
        "/usr/local/share/opencv4/haarcascades",
    ]:
        _f = _p + "/haarcascade_frontalface_default.xml"
        if os.path.isfile(_f):
            return _f
    import glob as _glob
    _m = _glob.glob("/usr/**/haarcascade_frontalface_default.xml", recursive=True)
    return _m[0] if _m else "haarcascade_frontalface_default.xml"


# ── Caméra ────────────────────────────────────────────────────────────
def open_camera():
    """Retourne (type, cam) ou ("blind", None) si aucune caméra détectée."""
    try:
        from picamera2 import Picamera2
        cam = Picamera2()
        config = cam.create_preview_configuration(
            main={"size": (FRAME_W, FRAME_H), "format": "BGR888"}
        )
        cam.configure(config)
        cam.start()
        log.info("picamera2 (libcamera) ouverte — %dx%d", FRAME_W, FRAME_H)
        return "picamera2", cam
    except Exception as exc:
        log.warning("picamera2 non disponible (%s) — essai V4L2 /dev/video0", exc)

    cap = cv2.VideoCapture(0)
    if cap.isOpened():
        cap.set(cv2.CAP_PROP_FRAME_WIDTH,  FRAME_W)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_H)
        cap.set(cv2.CAP_PROP_FPS,          CAMERA_FPS)
        log.info("V4L2 /dev/video0 ouverte — %dx%d", FRAME_W, FRAME_H)
        return "v4l2", cap

    log.warning("Aucune caméra détectée — MODE AVEUGLE (annonce toutes les %ds)", BLIND_INTERVAL)
    return "blind", None


def read_frame(cam_type, cam):
    if cam_type == "picamera2":
        return cam.capture_array()
    ret, frame = cam.read()
    return frame if ret else None


def release_camera(cam_type, cam):
    if cam_type == "picamera2":
        cam.stop()
        cam.close()
    else:
        cam.release()


# ── Détection visuelle ────────────────────────────────────────────────
def detect_motion(frame1, frame2):
    """Différentiel de pixels — CPU < 5 % sur Pi Zero 2W."""
    if not _NP_OK:
        return False
    diff = cv2.absdiff(frame1, frame2)
    gray = cv2.cvtColor(diff, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    _, thresh = cv2.threshold(blur, 20, 255, cv2.THRESH_BINARY)
    return int(np.sum(thresh)) > MOTION_THR


def detect_face(cascade, frame):
    """Haar cascade sur image downscalée ×4 : 320×240 → 80×60."""
    gray  = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    small = cv2.resize(gray, (FRAME_W // 4, FRAME_H // 4))
    faces = cascade.detectMultiScale(
        small,
        scaleFactor  = SCALE_FACTOR,
        minNeighbors = MIN_NEIGHBORS,
        minSize      = (MIN_FACE_PX, MIN_FACE_PX),
        flags        = cv2.CASCADE_SCALE_IMAGE,
    )
    return len(faces) > 0


# ── Lecture WAV via PipeWire/PulseAudio ──────────────────────────────
def _play_wav(path):
    """Lit un fichier WAV via paplay → pw-play → aplay (cascade)."""
    env = os.environ.copy()  # XDG_RUNTIME_DIR déjà positionné par systemd
    for cmd in (["paplay", path], ["pw-play", path], ["aplay", "-q", path]):
        try:
            r = subprocess.run(
                cmd, env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=30,
            )
            if r.returncode == 0:
                return
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue


# ── Déclenchement accueil ─────────────────────────────────────────────
_welcome_lock = threading.Lock()


def trigger_welcome(reason="présence"):
    if not _welcome_lock.acquire(blocking=False):
        log.debug("Déclenchement ignoré (précédent toujours en cours)")
        return
    log.info("Déclenchement accueil (%s)", reason)

    def _run():
        try:
            if USE_TTS and os.path.isfile(TTS_CMD):
                msg = random.choice(MESSAGES)
                try:
                    res = subprocess.run(
                        [TTS_CMD, msg],
                        capture_output=True,
                        text=True,
                        timeout=25,
                    )
                    wav = res.stdout.strip()
                    if wav and os.path.isfile(wav):
                        _play_wav(wav)
                        # Nettoyage du fichier temporaire généré par tts.sh
                        try:
                            os.unlink(wav)
                        except OSError:
                            pass
                        return
                except Exception as exc:
                    log.warning("TTS échoué (%s) — fallback welcome.wav", exc)
            # Fallback : play_welcome.sh (WAV statique pré-enregistré)
            subprocess.run(
                [WELCOME_CMD],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception as exc:
            log.error("Erreur déclenchement accueil : %s", exc)
        finally:
            _welcome_lock.release()

    threading.Thread(target=_run, daemon=True).start()


# ── Boucle audio (mode audio ou any) ─────────────────────────────────
def _start_audio_listener(cooldown_ref):
    """Lance un InputStream sounddevice en arrière-plan. Thread-safe."""
    if not _SD_OK:
        return None

    def _audio_cb(indata, frames, time_info, status):
        vol = float(_np_audio.linalg.norm(indata)) / max(1, len(indata) ** 0.5)
        if vol > AUDIO_THR:
            now = time.monotonic()
            if now - cooldown_ref[0] > COOLDOWN_S:
                cooldown_ref[0] = now
                log.info("Bruit détecté (RMS %.3f) → accueil", vol)
                trigger_welcome(reason="son détecté")

    try:
        stream = _sd.InputStream(callback=_audio_cb, channels=1, samplerate=16000)
        stream.start()
        log.info("Écoute micro active (seuil RMS %.3f)", AUDIO_THR)
        return stream
    except Exception as exc:
        log.warning("Micro USB inaccessible (%s) — détection audio désactivée", exc)
        return None


# ── Main ──────────────────────────────────────────────────────────────
def main():
    need_camera = MODE in ("motion", "face", "any")
    cam_type, cam = ("blind", None) if not need_camera else open_camera()

    def shutdown(sig, _frame):
        log.info("Signal %d — arrêt propre", sig)
        if cam_type not in ("blind",) and cam:
            release_camera(cam_type, cam)
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT,  shutdown)

    log.info(
        "Détecteur démarré — MODE=%s  USE_TTS=%s  COOLDOWN=%ds  MOTION_THR=%d",
        MODE, USE_TTS, COOLDOWN_S, MOTION_THR,
    )

    # ── MODE AVEUGLE (pas de caméra ET pas audio seul) ──────────────
    if cam_type == "blind" and MODE in ("motion", "face"):
        log.info("Mode aveugle — annonce toutes les %ds (%d min)",
                 BLIND_INTERVAL, BLIND_INTERVAL // 60)
        while True:
            trigger_welcome(reason="mode aveugle")
            time.sleep(BLIND_INTERVAL)

    # ── MODE AUDIO SEUL ─────────────────────────────────────────────
    if MODE == "audio":
        if not _SD_OK:
            log.error("PRESENCE_MODE=audio mais sounddevice absent. "
                      "Installer : sudo apt install python3-sounddevice")
            sys.exit(1)
        _audio_last = [0.0]
        stream = _start_audio_listener(_audio_last)
        if stream is None:
            log.error("Impossible d'ouvrir le micro — vérifier les droits (groupe audio)")
            sys.exit(1)
        log.info("Mode audio seul actif (seuil %.3f) — Ctrl+C pour arrêter", AUDIO_THR)
        try:
            while True:
                time.sleep(1)
        finally:
            stream.stop()
        return

    # ── MODES MOTION / FACE / ANY — nécessitent la caméra ───────────
    cascade = None
    if MODE in ("face", "any"):
        haar_xml = _find_haar_xml()
        cascade = cv2.CascadeClassifier(haar_xml)
        if cascade.empty():
            log.error("Haar cascade introuvable : %s", haar_xml)
            sys.exit(1)
        log.info("Haar cascade chargé")

    # Thread audio parallèle pour mode "any"
    _audio_shared_last = [0.0]
    _audio_stream = None
    if MODE == "any" and _SD_OK:
        _audio_stream = _start_audio_listener(_audio_shared_last)

    prev_frame   = None
    last_trigger = 0.0
    frame_count  = 0
    frame_sleep  = 1.0 / CAMERA_FPS

    log.info(
        "Boucle active — cooldown=%ds  analyse 1/%d frames (~toutes les %.1fs)",
        COOLDOWN_S, DETECT_INTERVAL, DETECT_INTERVAL * frame_sleep,
    )

    try:
        while True:
            frame = read_frame(cam_type, cam)
            if frame is None:
                time.sleep(0.2)
                continue

            frame_count += 1

            if frame_count % DETECT_INTERVAL != 0:
                time.sleep(frame_sleep)
                continue

            now = time.monotonic()
            if now - last_trigger < COOLDOWN_S:
                prev_frame = frame.copy()
                time.sleep(frame_sleep)
                continue

            triggered = False
            reason    = ""

            if MODE == "motion":
                if prev_frame is not None and detect_motion(prev_frame, frame):
                    triggered, reason = True, "mouvement détecté"

            elif MODE == "face":
                if cascade and detect_face(cascade, frame):
                    triggered, reason = True, "visage détecté"

            elif MODE == "any":
                if prev_frame is not None and detect_motion(prev_frame, frame):
                    triggered, reason = True, "mouvement détecté"
                elif cascade and detect_face(cascade, frame):
                    triggered, reason = True, "visage détecté"

            if triggered:
                trigger_welcome(reason=reason)
                last_trigger = now
                # Synchroniser avec le thread audio en mode "any"
                _audio_shared_last[0] = now

            prev_frame = frame.copy()
            time.sleep(frame_sleep)
    finally:
        if _audio_stream:
            _audio_stream.stop()
        if cam_type not in ("blind",) and cam:
            release_camera(cam_type, cam)


if __name__ == "__main__":
    main()
