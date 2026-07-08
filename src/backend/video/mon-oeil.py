#!/usr/bin/env python3
"""
mon-oeil.py — Satellite Sensoriel Distribué (son + vision + IA Ollama)

Détecte le son ambiant. Quand un seuil est dépassé (et après cooldown),
capture une image et demande à Ollama (llava) de décrire la scène.
La réponse est synthétisée directement (Orpheus local, espeak-ng en repli)
— pas de round-trip via l'API /api.sh?action=speak du portail captif, dont
la file d'attente asynchrone ne remonte aucune erreur en cas d'échec TTS.

Accès caméra :
  - Priorité : lit /dev/shm/latest_frame.jpg (écrit par presence_detector.py).
    → Les deux services partagent ainsi la caméra sans conflit.
  - Fallback : appelle libcamera-still directement (si presence_detector
    n'est PAS actif — PRESENCE_ENABLED=false).

Variables d'environnement (depuis soundspot.conf) :
  AUDIO_THRESHOLD   Seuil détection audio    (défaut : 0.03)
  COOLDOWN_S        Délai entre analyses (s) (défaut : 45)
  OLLAMA_URL        URL Ollama locale         (défaut : http://127.0.0.1:11434/api/generate)
  ORPHEUS_PORT      Port Orpheus TTS local    (défaut : 5005)
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
import json
import wave
import textwrap
import io
import glob
import random
from PIL import Image, ImageDraw, ImageFont

# ── Configuration ──────────────────────────────────────────────────────
AUDIO_THRESHOLD    = float(os.getenv("AUDIO_THRESHOLD",    "0.03"))
COOLDOWN_S         = int(os.getenv("COOLDOWN_S",           "45"))
OLLAMA_URL         = os.getenv("OLLAMA_URL",               "http://127.0.0.1:11434/api/generate")
OLLAMA_VISION_MODEL = os.getenv("OLLAMA_VISION_MODEL",      "llama3.2-vision:11b")
VOIX_IA            = os.getenv("MON_OEIL_VOICE",           "pierre")
UPASSPORT_URL      = os.getenv("UPASSPORT_URL",             "http://127.0.0.1:54321")
EYE_LAST_JSON      = "/dev/shm/eye_last.json"
ORPHEUS_PORT       = os.getenv("ORPHEUS_PORT",              "5005")
WAV_DIR            = os.getenv("INSTALL_DIR", "/opt/soundspot") + "/wav"

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
def _shared_frame_available():
    """Vérifie (sans le consommer) qu'un frame partagé récent existe."""
    if not os.path.exists(SHARED_FRAME_PATH):
        return False
    age = time.time() - os.path.getmtime(SHARED_FRAME_PATH)
    return age <= SHARED_FRAME_MAX_AGE


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
    Capture directe via rpicam-still (libcamera-still sur les OS plus anciens).
    Utilisé en fallback si presence_detector n'est PAS actif.
    """
    binary = shutil.which("rpicam-still") or shutil.which("libcamera-still")
    if not binary:
        log.error("rpicam-still/libcamera-still introuvable — installer : sudo apt install rpicam-apps")
        return False
    try:
        cmd = [
            binary, "-o", dest_path,
            "--width", "640", "--height", "480",
            "-t", "200", "--nopreview", "--immediate",
        ]
        subprocess.run(cmd, check=True, timeout=10,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log.info("Capture %s directe (presence_detector non actif)", binary)
        return os.path.exists(dest_path)
    except subprocess.CalledProcessError as exc:
        log.error("%s a échoué (code %d) — caméra occupée par un autre service ?",
                  binary, exc.returncode)
        return False
    except subprocess.TimeoutExpired:
        log.error("%s : timeout — caméra bloquée", binary)
        return False
    except Exception as exc:
        log.error("Erreur capture caméra : %s", exc)
        return False


# Chemin final (lu par rtmp_player.sh pour l'affichage écran) vs chemin de
# travail : la bascule ne se fait qu'une fois photo + description + voix
# prêtes ensemble — jamais de photo affichée seule, sans sa voix, et jamais
# d'interruption du diaporama d'accueil pendant l'attente de l'analyse IA.
EYE_CAPTURE_PATH    = "/dev/shm/eye_capture.jpg"
EYE_CAPTURE_STAGING = "/dev/shm/eye_capture.staging.jpg"


def capture_image():
    """
    Retourne le chemin (de travail) d'une image capturée, ou None si impossible.
    Stratégie :
      1. Frame partagé par presence_detector.py (préféré — pas de conflit).
      2. libcamera-still en direct (fallback si presence non actif).
    """
    dest = EYE_CAPTURE_STAGING
    if _read_shared_frame(dest):
        return dest
    log.info("Frame partagé indisponible — tentative libcamera-still directe")
    return dest if _capture_libcamera(dest) else None


# Voix dédiée à l'annonce (distincte de VOIX_IA utilisée pour la description)
ANNOUNCE_VOICE = "amelie"


def _wav_duration(path):
    """Durée en secondes d'un .wav, ou None si illisible."""
    try:
        with wave.open(path, "rb") as w:
            return w.getnframes() / float(w.getframerate())
    except Exception:
        return None


def _speak_cached(text, cache_name, voice=None, espeak_voice="fr+f2", espeak_speed="150"):
    """Joue un message système fixe : .wav Orpheus pré-généré en priorité
    (mis en cache dans wav/ au premier passage — un seul appel TTS en direct
    pour toute la vie du nœud), espeak-ng en tout dernier recours si Orpheus
    est injoignable ET le cache absent. Retourne la durée du .wav joué
    (secondes), ou None si repli espeak (durée inconnue).
    """
    cache_path = os.path.join(WAV_DIR, cache_name)
    if os.path.exists(cache_path):
        subprocess.Popen(["paplay", cache_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return _wav_duration(cache_path)
    try:
        r = requests.post(
            f"http://127.0.0.1:{ORPHEUS_PORT}/v1/audio/speech",
            json={"model": "orpheus", "input": text, "voice": voice or VOIX_IA,
                  "response_format": "wav", "speed": 1.0},
            timeout=15,
        )
        if r.ok and r.content:
            with open(cache_path, "wb") as f:
                f.write(r.content)
            subprocess.Popen(["paplay", cache_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return _wav_duration(cache_path)
    except Exception as exc:
        log.warning("TTS Orpheus (%s) échoué : %s — repli espeak-ng", cache_name, exc)
    subprocess.Popen(["espeak-ng", "-v", espeak_voice, "-s", espeak_speed, text],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return None


def _announce_capture():
    """Prévient le passant avant la capture — lui laisse le temps de poser.
    Orpheus (voix ANNOUNCE_VOICE = amelie) en priorité, espeak-ng en repli
    avec une voix féminine distincte (fr+f4) pour rester cohérent avec le
    personnage "Amelie" même quand Orpheus est injoignable.
    """
    texte = "Ne bougez pas, nous allons prendre une photo dans 3, 2, 1, clic !"
    duration = _speak_cached(texte, "mon_oeil_announce.wav",
                              voice=ANNOUNCE_VOICE, espeak_voice="fr+f4", espeak_speed="155")
    # Attend la fin réelle du message (durée du .wav Orpheus) avant de shooter,
    # plutôt qu'un délai fixe qui coupait parfois l'annonce en plein "clic !".
    # Durée inconnue (repli espeak) : estimation généreuse par défaut.
    time.sleep((duration + 0.3) if duration else 5.5)


FLASH_TRIGGER_PATH = "/dev/shm/eye_flash_trigger"

# Durée d'affichage de la photo à l'écran — doit rester synchronisée avec
# rtmp_player.sh (_show_image_for "$PHOTO_PATH" 30). Le verrou d'analyse
# reste tenu tout ce temps (voir fin de capture_and_process) pour qu'un
# nouveau son ne relance pas une séquence par-dessus la photo affichée.
PHOTO_DISPLAY_S = 30


def _trigger_flash():
    """Signale à rtmp_player.sh d'afficher un flash blanc (éclaire la scène
    pour les pièces sombres). Best-effort : rtmp_player.sh sonde ce fichier
    toutes les 2s, et le frame réellement utilisé vient du dernier
    rafraîchissement périodique de presence_detector.py (pas une capture
    fraîche synchronisée) — ça n'illumine donc qu'une partie des captures,
    mais ça ne coûte rien d'essayer sur les scènes sombres.
    """
    try:
        with open(FLASH_TRIGGER_PATH, "w"):
            pass
        # rtmp_player.sh affiche le flash ~2s (poll 0.3s) — capturer avant la
        # fin de cette fenêtre plutôt qu'après (sinon la scène est déjà
        # revenue à l'obscurité quand capture_image() lit le frame partagé).
        time.sleep(1.8)
    except Exception as exc:
        log.warning("Déclenchement flash échoué : %s", exc)


CAPTION_FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def _fetch_qr(data, size):
    """Récupère un QR code (API UPassport) redimensionné, ou None si échec."""
    try:
        r = requests.get(f"{UPASSPORT_URL}/qr", params={"data": data}, timeout=8)
        if r.ok and r.content:
            return Image.open(io.BytesIO(r.content)).convert("RGBA").resize((size, size))
    except Exception as exc:
        log.warning("Récupération QR échouée : %s", exc)
    return None


QR_CORNER_FRACTION = 5   # taille du QR = hauteur photo / cette valeur


def _qr_position(w, h, qr_size):
    """(x, y) coin bas-droit — les deux QR (qo-op.com puis CID) sont dessinés
    exactement au même endroit : le second recouvre entièrement le premier
    dans la version finale republiée.
    """
    return (w - qr_size - 14, h - qr_size - 14)


def _qr_position_left(w, h, qr_size):
    """(x, y) coin bas-gauche — QR de la chaîne (photo « significative »
    précédente), symétrique du coin droit.
    """
    return (14, h - qr_size - 14)


# ── Deux chaînes de photos ──────────────────────────────────────────────
# - CHAIN_FILE_ALL   : toutes les photos, sans filtre — QR en bas à droite,
#                      dessiné avec qo-op.com avant d'être recouvert par le
#                      QR du CID final (même mécanique de double publication).
# - CHAIN_FILE_FILTER : seulement les photos « significatives » (main, visage,
#                       téléphone visible…) — QR dédié en bas à gauche.
# WAV_DIR (pi:soundspot, setgid) — /opt/soundspot lui-même est root:root 755,
# non inscriptible par le service (User=pi).
CHAIN_FILE_ALL = os.path.join(WAV_DIR, "mon_oeil_chain_all.json")
CHAIN_FILE_FILTER = os.path.join(WAV_DIR, "mon_oeil_chain_filtered.json")
CHAIN_KEYWORDS = ["main", "mains", "doigt", "doigts", "téléphone", "telephone",
                  "smartphone", "portable", "geste", "salue", "salut",
                  "visage", "visages", "sourire", "sourit"]
CHAIN_MAX_ENTRIES = 200


def _get_ipfsnodeid():
    """PeerID du nœud IPFS local — $IPFSNODEID si exporté (convention
    Astroport.ONE, ex. _12345.sh), sinon lu depuis ~/.ipfs/config (même
    source que Ustats.sh)."""
    env_id = os.getenv("IPFSNODEID")
    if env_id:
        return env_id
    try:
        with open(os.path.expanduser("~/.ipfs/config")) as f:
            return json.load(f)["Identity"]["PeerID"]
    except Exception as exc:
        log.warning("PeerID IPFS introuvable — journal caméra désactivé : %s", exc)
        return None


IPFSNODEID = _get_ipfsnodeid()
# Journal caméra — convention Astroport.ONE : ~/.zen/tmp/<IPFSNODEID>/ est le
# dossier d'état propre à ce nœud (déjà utilisé par swarm_sync.sh, picoport.sh…).
CAMERA_LOG_PATH = (os.path.join(os.path.expanduser("~/.zen/tmp"), IPFSNODEID, "camera_log.json")
                   if IPFSNODEID else None)


def _text_matches_chain(text):
    low = text.lower()
    return any(kw in low for kw in CHAIN_KEYWORDS)


def _load_chain(chain_file):
    try:
        with open(chain_file) as f:
            return json.load(f)
    except Exception:
        return []


def _append_chain(chain_file, entry):
    chain = _load_chain(chain_file)
    chain.append(entry)
    chain = chain[-CHAIN_MAX_ENTRIES:]
    tmp = chain_file + ".tmp"
    try:
        with open(tmp, "w") as f:
            json.dump(chain, f)
        os.replace(tmp, chain_file)
    except Exception as exc:
        log.warning("Écriture chaîne (%s) échouée : %s", chain_file, exc)


def _caption_photo(img_path, text, chain_all_prev_cid=None, chain_filtered_prev_cid=None):
    """Incruste la description IA en bandeau au bas de la photo (affichage
    écran) — pas de lecture vocale de ce texte, l'incrustation suffit.
    Ajoute aussi :
      - l'horodatage (coin haut-gauche)
      - en bas à droite : QR qo-op.com — _add_qr_to_photo le recouvrira
        avec le QR du CID final
      - en bas à gauche : QR de la chaîne temporelle (photo précédente,
        toutes photos confondues) — permet de remonter tout l'historique.
        Si un mot-clef a été détecté (chain_filtered_prev_cid fourni), le QR
        de cette chaîne filtrée est dessiné par-dessus, au même endroit :
        priorité à l'historique le plus pertinent pour cette photo.
    """
    try:
        img = Image.open(img_path).convert("RGB")
        w, h = img.size
        try:
            font = ImageFont.truetype(CAPTION_FONT_PATH, max(14, h // 24))
            small_font = ImageFont.truetype(CAPTION_FONT_PATH, max(12, h // 32))
        except Exception:
            font = small_font = ImageFont.load_default()

        line_h = (font.getbbox("Ay")[3] - font.getbbox("Ay")[1]) + 8
        qr_size = max(50, h // QR_CORNER_FRACTION)
        left_reserved = (qr_size + 28) if chain_all_prev_cid else 0

        text_w_budget = w - qr_size - 28 - left_reserved
        wrapped = textwrap.wrap(text, width=max(16, text_w_budget // 13)) or [text]
        band_h = min(h // 2, max(line_h * len(wrapped) + 20, qr_size + 20))

        overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        draw.rectangle([(0, h - band_h), (w, h)], fill=(8, 8, 16, 190))
        y = h - band_h + 10
        for line in wrapped:
            draw.text((14 + left_reserved, y), line, font=font, fill=(255, 255, 255, 255))
            y += line_h

        # Horodatage discret, coin haut-gauche
        stamp = time.strftime("%d/%m/%Y %H:%M")
        draw.text((14, 10), stamp, font=small_font, fill=(255, 255, 255, 220))

        composed = Image.alpha_composite(img.convert("RGBA"), overlay)

        # Coin bas-droit : qo-op.com (le CID final recouvrira via _add_qr_to_photo)
        qoop_qr = _fetch_qr("https://qo-op.com", qr_size)
        if qoop_qr:
            composed.paste(qoop_qr, _qr_position(w, h, qr_size), qoop_qr)

        # Coin bas-gauche : chaîne temporelle, puis chaîne filtrée par-dessus
        # si un mot-clef a été détecté sur cette photo.
        if chain_all_prev_cid:
            all_qr = _fetch_qr(f"https://ipfs.copylaradio.com/ipfs/{chain_all_prev_cid}", qr_size)
            if all_qr:
                composed.paste(all_qr, _qr_position_left(w, h, qr_size), all_qr)
        if chain_filtered_prev_cid:
            filtered_qr = _fetch_qr(f"https://ipfs.copylaradio.com/ipfs/{chain_filtered_prev_cid}", qr_size)
            if filtered_qr:
                composed.paste(filtered_qr, _qr_position_left(w, h, qr_size), filtered_qr)

        composed.convert("RGB").save(img_path, "JPEG", quality=88)
    except Exception as exc:
        log.warning("Incrustation description échouée : %s", exc)


def _add_qr_to_photo(img_path, ipfs_cid):
    """Colle le QR du lien CID (1ère publication IPFS, avant ce QR) exactement
    à l'endroit du QR qo-op.com, qu'il recouvre entièrement. Un QR ne peut
    pas s'auto-référencer : il pointe vers la version texte+qo-op seule, la
    version finale (QR CID visible) est republiée par-dessus pour devenir
    la photo réellement affichée/gardée.
    """
    try:
        img = Image.open(img_path).convert("RGBA")
        w, h = img.size
        qr_size = max(50, h // QR_CORNER_FRACTION)
        qr_img = _fetch_qr(f"https://ipfs.copylaradio.com/ipfs/{ipfs_cid}", qr_size)
        if not qr_img:
            return
        img.paste(qr_img, _qr_position(w, h, qr_size), qr_img)
        img.convert("RGB").save(img_path, "JPEG", quality=88)
    except Exception as exc:
        log.warning("Incrustation QR échouée : %s", exc)


def _publish_to_ipfs(img_path):
    """Publie la photo sur IPFS via UPassport (contrat /api/upload/image).
    Retourne (cid, url) ou (None, None) si UPassport/IPFS est indisponible.
    """
    try:
        with open(img_path, "rb") as f:
            files = {"file": ("eye_capture.jpg", f, "image/jpeg")}
            res = requests.post(f"{UPASSPORT_URL}/api/upload/image",
                                 files=files, data={"type": "media"}, timeout=20).json()
        if res.get("ipfs_cid"):
            return res["ipfs_cid"], res.get("ipfs_url")
        log.warning("Publication IPFS : pas de cid en retour (%s)", res.get("ipfs_status"))
    except Exception as exc:
        log.warning("Publication IPFS échouée : %s", exc)
    return None, None


def _play_random_archive_message():
    """Joue une phrase aléatoire en accompagnement de l'affichage de la
    photo — pas de lecture de la description IA elle-même (l'incrustation
    suffit), mais une ambiance sonore piochée dans les messages du clocher :
    les 19 nouveaux textes recrutement (wav/message_*.wav) et les anciens
    enregistrements Homer conservés (wav/Homer/*.mp3).
    """
    candidates = (glob.glob(os.path.join(WAV_DIR, "message_*.wav"))
                  + glob.glob(os.path.join(WAV_DIR, "Homer", "*.mp3")))
    if not candidates:
        return
    choice = random.choice(candidates)
    if choice.lower().endswith(".mp3"):
        subprocess.Popen(["mpg123", "-q", choice], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        subprocess.Popen(["paplay", choice], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _write_eye_last(caption, ipfs_url, ipfs_cid):
    """Écrit l'état pour le portail (api/core/eye.sh) — écriture atomique."""
    tmp = EYE_LAST_JSON + ".tmp"
    try:
        with open(tmp, "w") as f:
            json.dump({"caption": caption, "ipfs_url": ipfs_url,
                       "ipfs_cid": ipfs_cid, "ts": time.time()}, f)
        os.replace(tmp, EYE_LAST_JSON)
    except Exception as exc:
        log.warning("Écriture %s échouée : %s", EYE_LAST_JSON, exc)


# ── Cycle analyse principal ────────────────────────────────────────────
def capture_and_process():
    """Capture + envoi Ollama + diffusion vocale (non bloquant via thread)."""
    if not _analysis_lock.acquire(blocking=False):
        log.debug("Analyse en cours — déclenchement ignoré")
        return
    cycle_start = time.time()
    try:
        if not check_swarm_status():
            log.warning("Cerveau IA injoignable (Ollama/Tunnel KO) — analyse annulée")
            return

        # Vérifié AVANT l'annonce : jamais promettre une photo qui ne viendra
        # pas (presence_detector inactif ou frame trop vieux → capture_image()
        # échouerait de toute façon, la caméra étant déjà tenue par ce process).
        if not _shared_frame_available():
            log.warning("Aucun frame caméra disponible — annonce et capture annulées")
            return

        _announce_capture()
        _trigger_flash()

        img_path = capture_image()
        if img_path is None:
            log.error("Impossible d'obtenir une image — analyse annulée")
            return

        with open(img_path, "rb") as f:
            img_b64 = base64.b64encode(f.read()).decode("utf-8")

        log.info("Envoi image au Swarm Ollama (%s)…", OLLAMA_VISION_MODEL)
        payload = {
            "model": OLLAMA_VISION_MODEL,
            "prompt": ("Respond only in French, never in English. "
                       "Décris cette scène en une phrase courte et drôle, "
                       "puis invite à rejoindre le collectif G1FabLab. "
                       "Réponds uniquement en français."),
            "images": [img_b64],
            "stream": False,
            # Borne la génération : évite les dérives en boucle observées sur
            # ce modèle quantifié (répétition d'espaces insécables jusqu'à la
            # limite), et raccourcit d'autant l'attente déjà pénalisée par le
            # tunnel P2P swarm.
            "options": {"num_predict": 60},
        }
        # Le calcul Ollama lui-même est rapide (eval_duration ~0.1s mesuré) —
        # le délai vient du tunnel P2P swarm (~140s observés même sur un
        # prompt texte trivial, sans image). 240s de marge pour absorber ça.
        res = requests.post(OLLAMA_URL, json=payload, timeout=240).json()
        if "error" in res:
            log.error("Ollama a répondu une erreur (%s) : %s", OLLAMA_VISION_MODEL, res["error"])
        texte = res.get("response", "Je vois trouble…").strip()
        texte = " ".join(texte.split())        # espaces multiples/insécables → un seul
        texte = texte.strip(' "\'“”')          # guillemets parfois ajoutés par le modèle
        if not texte:
            texte = "Je vois trouble…"

        log.info("Réponse IA : %s", texte[:120])

        # Deux chaînes : la complète (toutes les photos, sans filtre) et la
        # filtrée (main/visage/téléphone…). Les précédentes sont déjà
        # publiées, pas de souci d'auto-référence à les référencer ici.
        is_chain_photo = _text_matches_chain(texte)
        chain_all = _load_chain(CHAIN_FILE_ALL)
        chain_all_prev = chain_all[-1] if chain_all else None
        chain_filtered_prev = None
        if is_chain_photo:
            existing_filtered = _load_chain(CHAIN_FILE_FILTER)
            chain_filtered_prev = existing_filtered[-1] if existing_filtered else None

        # Publication de la photo brute (avant incrustation description/QR) —
        # sert uniquement au journal caméra (camera_log.json), pour garder une
        # trace du cliché original indépendamment des republications qui suivent.
        raw_cid, raw_ipfs_url = _publish_to_ipfs(img_path)
        if raw_cid:
            log.info("Photo brute publiée sur IPFS : %s", raw_ipfs_url)

        _caption_photo(
            img_path, texte,
            chain_filtered_prev_cid=(chain_filtered_prev["cid"] if chain_filtered_prev else None),
            chain_all_prev_cid=(chain_all_prev["cid"] if chain_all_prev else None),
        )

        # Double publication IPFS : un QR ne peut pas s'auto-référencer.
        # 1) publie la version texte-seul → CID1
        # 2) colle un QR pointant vers CID1 dans le coin déjà réservé
        # 3) republie la version finale (texte+QR) → CID2, c'est celle-ci
        #    qui devient réellement la photo affichée/gardée.
        cid, ipfs_url = _publish_to_ipfs(img_path)
        if cid:
            _add_qr_to_photo(img_path, cid)
            cid2, ipfs_url2 = _publish_to_ipfs(img_path)
            if cid2:
                cid, ipfs_url = cid2, ipfs_url2
        if ipfs_url:
            log.info("Photo publiée sur IPFS : %s", ipfs_url)

        # Bascule uniquement maintenant que tout est prêt (texte + QR déjà
        # incrustés) : tant que Ollama/IPFS travaillaient, le diaporama
        # d'accueil de rtmp_player.sh n'a pas été interrompu (il ne réagit
        # qu'au mtime de EYE_CAPTURE_PATH, jamais touché avant ce point).
        # Pas de lecture vocale de la description : l'incrustation suffit.
        # À la place, une phrase du clocher piochée au hasard accompagne
        # l'affichage (ambiance sonore, pas un résumé de la photo).
        os.replace(img_path, EYE_CAPTURE_PATH)
        # Laisse le temps à rtmp_player.sh (poll 0.3s) de basculer l'écran
        # sur la nouvelle photo avant de lancer la voix d'ambiance — sinon
        # le son démarre pendant que l'ancien slide est encore affiché.
        time.sleep(0.5)
        _play_random_archive_message()

        _write_eye_last(texte, ipfs_url, cid)

        if cid:
            entry = {"cid": cid, "ipfs_url": ipfs_url, "caption": texte, "ts": time.time()}
            _append_chain(CHAIN_FILE_ALL, entry)
            if is_chain_photo:
                _append_chain(CHAIN_FILE_FILTER, entry)
            log.info("Chaînes mises à jour (complète=%d, filtrée=%d)",
                      len(_load_chain(CHAIN_FILE_ALL)), len(_load_chain(CHAIN_FILE_FILTER)))

        if CAMERA_LOG_PATH:
            try:
                os.makedirs(os.path.dirname(CAMERA_LOG_PATH), exist_ok=True)
                _append_chain(CAMERA_LOG_PATH, {
                    "ts": time.time(),
                    "cid_brut": raw_cid,
                    "descriptif": texte,
                    "cid_filtre": cid if is_chain_photo else None,
                    "cid_total": cid,
                    "duree_s": round(time.time() - cycle_start, 1),
                })
            except Exception as exc:
                log.warning("Écriture camera_log.json échouée : %s", exc)

        # Garde le verrou tant que la photo est affichée à l'écran : sinon un
        # nouveau son (même après COOLDOWN_S) déclenche une nouvelle annonce
        # et un nouveau flash par-dessus la séquence en cours d'affichage.
        time.sleep(PHOTO_DISPLAY_S)

    except Exception as exc:
        log.error("Erreur cycle analyse : %s", exc)
    finally:
        _analysis_lock.release()


# ── Callback audio ─────────────────────────────────────────────────────
last_trigger = 0.0

# Posé/rafraîchi par idle_announcer.sh (et tout autre script de lecture)
# pendant qu'il joue du son sur les haut-parleurs du nœud — sans ça, le
# clocher (bip/cloches/voix) est capté par ce micro et se déclenche
# lui-même en boucle. Basé sur l'mtime (pas de nettoyage explicite requis :
# un flag figé après un crash du script qui l'a posé s'auto-expire).
SPEAKER_ACTIVE_FLAG = "/dev/shm/soundspot_speaker_active"
SPEAKER_ACTIVE_MAX_AGE_S = 8


def _speaker_active():
    try:
        return (time.time() - os.path.getmtime(SPEAKER_ACTIVE_FLAG)) <= SPEAKER_ACTIVE_MAX_AGE_S
    except OSError:
        return False


def audio_callback(indata, frames, time_info, status):
    global last_trigger
    if status:
        log.debug("sounddevice status : %s", status)
    volume_norm = float(np.linalg.norm(indata)) / max(1, len(indata) ** 0.5) * 10
    if volume_norm > AUDIO_THRESHOLD:
        if _speaker_active():
            log.debug("Son détecté (niveau %.2f) mais le nœud parle actuellement — ignoré", volume_norm)
            return
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
            _speak_cached("Système de vision et d'écoute prêt.", "mon_oeil_ready.wav")
            while True:
                time.sleep(1)
    except KeyboardInterrupt:
        log.info("Arrêt demandé par l'utilisateur")
    except Exception as exc:
        log.error("Crash flux audio : %s", exc)
        try:
            _speak_cached("Erreur oeil : flux audio planté.", "mon_oeil_error.wav",
                          espeak_voice="fr+f3", espeak_speed="140")
        except Exception:
            pass


if __name__ == "__main__":
    main()
