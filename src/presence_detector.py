#!/usr/bin/env python3
"""
SoundSpot — Détecteur de présence caméra (avec mode aveugle)
Caméra : Raspberry Pi Camera Module 3 (SC1223, 75°)
Cible  : Pi Zero 2W — OpenCV Haar cascade (pas de ML lourd, pas de dlib)

Mode NORMAL  : déclenche le message d'accueil quand un visage est détecté.
Mode AVEUGLE : aucune caméra disponible → annonce vocale à intervalle fixe
               (comme un phare : présence régulière sans vision).

Variables d'environnement (depuis /opt/soundspot/soundspot.conf) :
  PRESENCE_COOLDOWN      Secondes entre deux messages (mode normal) (défaut : 30)
  PRESENCE_BLIND_INTERVAL Secondes entre annonces en mode aveugle   (défaut : 900)
  PRESENCE_INTERVAL      Analyser 1 frame sur N                     (défaut : 20)
  PRESENCE_WIDTH         Largeur de capture                         (défaut : 320)
  PRESENCE_HEIGHT        Hauteur de capture                         (défaut : 240)
  PRESENCE_FPS           FPS caméra demandé                         (défaut : 15)
  PRESENCE_SCALE         Haar scaleFactor                           (défaut : 1.3)
  PRESENCE_NEIGHBORS     Haar minNeighbors                          (défaut : 4)
  PRESENCE_MIN_FACE      Taille min visage px (image ÷4)            (défaut : 20)
  PRESENCE_WELCOME_CMD   Commande à exécuter                        (défaut : /opt/soundspot/play_welcome.sh)
"""
import cv2
import subprocess
import threading
import time
import logging
import os
import signal
import sys

# ── Configuration (surchargeable par variables d'environnement) ────
COOLDOWN_S      = int(os.getenv("PRESENCE_COOLDOWN",        "30"))
BLIND_INTERVAL  = max(1, int(os.getenv("PRESENCE_BLIND_INTERVAL", "900")))  # 15 min, min 1s
DETECT_INTERVAL = int(os.getenv("PRESENCE_INTERVAL",        "20"))
FRAME_W         = int(os.getenv("PRESENCE_WIDTH",           "320"))
FRAME_H         = int(os.getenv("PRESENCE_HEIGHT",          "240"))
CAMERA_FPS      = int(os.getenv("PRESENCE_FPS",             "15"))
SCALE_FACTOR    = float(os.getenv("PRESENCE_SCALE",         "1.3"))
MIN_NEIGHBORS   = int(os.getenv("PRESENCE_NEIGHBORS",       "4"))
MIN_FACE_PX     = int(os.getenv("PRESENCE_MIN_FACE",        "20"))  # px sur image downscalée ÷4
WELCOME_CMD     = os.getenv(
    "PRESENCE_WELCOME_CMD", "/opt/soundspot/play_welcome.sh"
)
HAAR_XML = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [presence] %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger()


def open_camera():
    """Ouvre la caméra Pi via picamera2 (libcamera) ou fallback V4L2.

    Si aucune caméra n'est détectée, retourne ("blind", None) au lieu de
    planter — le script passera en mode annonce périodique (phare marin).
    """
    try:
        from picamera2 import Picamera2
        cam = Picamera2()
        config = cam.create_preview_configuration(
            main={"size": (FRAME_W, FRAME_H), "format": "BGR888"}
        )
        cam.configure(config)
        cam.start()
        log.info("picamera2 (libcamera) ouverte — %dx%d @ %d fps",
                 FRAME_W, FRAME_H, CAMERA_FPS)
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

    log.warning(
        "Aucune caméra détectée — passage en MODE AVEUGLE "
        "(annonce toutes les %ds)", BLIND_INTERVAL
    )
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


def detect_face(cascade, frame):
    """Renvoie True si au moins un visage est présent dans la frame.

    Downscale ×4 avant détection : 320×240 → 80×60.
    Coût CPU sur Pi Zero 2W : ~5-10 ms par analyse.
    """
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


def trigger_welcome(reason="visage détecté"):
    log.info("Déclenchement message d'accueil (%s)", reason)

    def _run_cmd():
        try:
            subprocess.run(
                [WELCOME_CMD],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception as exc:
            log.error("Erreur déclenchement message : %s", exc)

    threading.Thread(target=_run_cmd, daemon=True).start()


def main():
    cam_type, cam = open_camera()

    def shutdown(signum, _frame):
        log.info("Signal %d — arrêt propre", signum)
        if cam_type != "blind":
            release_camera(cam_type, cam)
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT,  shutdown)

    # ── MODE AVEUGLE — pas de caméra, annonce périodique ──────────
    if cam_type == "blind":
        log.info(
            "Mode aveugle actif — annonce toutes les %ds (%d min)",
            BLIND_INTERVAL, BLIND_INTERVAL // 60,
        )
        while True:
            trigger_welcome(reason="mode aveugle — timer")
            time.sleep(BLIND_INTERVAL)

    # ── MODE NORMAL — détection par caméra ────────────────────────
    cascade = cv2.CascadeClassifier(HAAR_XML)
    if cascade.empty():
        log.error("Haar cascade introuvable : %s", HAAR_XML)
        sys.exit(1)
    log.info("Haar cascade chargé")

    last_trigger = 0.0
    frame_count  = 0
    frame_sleep  = 1.0 / CAMERA_FPS

    log.info(
        "Détecteur actif — cooldown=%ds  analyse 1 frame / %d  (~toutes les %.1fs)",
        COOLDOWN_S, DETECT_INTERVAL, DETECT_INTERVAL * frame_sleep,
    )

    while True:
        frame = read_frame(cam_type, cam)
        if frame is None:
            time.sleep(0.2)
            continue

        frame_count += 1

        # N'analyser qu'une frame sur DETECT_INTERVAL pour économiser le CPU
        if frame_count % DETECT_INTERVAL != 0:
            time.sleep(frame_sleep)
            continue

        now = time.monotonic()
        if now - last_trigger < COOLDOWN_S:
            continue  # encore dans le cooldown

        if detect_face(cascade, frame):
            trigger_welcome()
            last_trigger = now

        time.sleep(frame_sleep)


if __name__ == "__main__":
    main()
