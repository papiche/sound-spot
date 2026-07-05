#!/usr/bin/env python3
"""
SoundSpot — Monitoring batterie solaire (INA219 via I2C)

Si le capteur INA219 n'est pas physiquement câblé, le script quitte proprement
(code 0) sans remplir les logs d'erreurs. Systemd (Restart=on-failure) ne le
relancera pas dans ce cas.

Quand la tension passe sous le seuil critique (défaut : 20 % ≈ 3.4 V pour
LiPo 3.7 V), le script :
 1. Génère une alerte vocale et l'envoie au Master via l'API speak.
 2. Attend RELAY_WARN_DELAY secondes (le Master et les satellites s'éteignent).
 3. Active le relais GPIO RELAY_PIN pour couper physiquement l'alimentation.

Variables d'environnement :
  BATTERY_CHECK_INTERVAL   Secondes entre deux lectures  (défaut : 60)
  BATTERY_LOW_THRESHOLD    Pourcentage critique           (défaut : 20)
  BATTERY_SHUNT_OHMS       Valeur du shunt résistif       (défaut : 0.1)
  BATTERY_MAX_EXPECTED_A   Courant max attendu (A)        (défaut : 0.2)
  INSTALL_DIR              Répertoire SoundSpot           (défaut : /opt/soundspot)
  RELAY_PIN                GPIO BCM du relais DC          (défaut : 17, 0=désactivé)
  RELAY_WARN_DELAY         Secondes avant coupure relais  (défaut : 20)
  MASTER_IP                IP du Master RPi4              (défaut : 192.168.10.1)
"""
import logging
import os
import shutil
import subprocess
import sys
import time
import requests

_LOG_LEVEL_STR = os.getenv("LOG_LEVEL", "INFO").upper()
_LOG_LEVEL_MAP = {
    "DEBUG": logging.DEBUG,
    "INFO":  logging.INFO,
    "WARN":  logging.WARNING,
    "WARNING": logging.WARNING,
    "ERROR": logging.ERROR,
}
_PY_LOG_LEVEL = _LOG_LEVEL_MAP.get(_LOG_LEVEL_STR, logging.INFO)

_LOG_FILE = os.getenv("SOUNDSPOT_LOG", "/var/log/sound-spot.log")
_FMT = "%(asctime)s [%(levelname)-5s] [battery      ] %(message)s"
_DATEFMT = "%Y-%m-%d %H:%M:%S"

log = logging.getLogger("battery")
log.setLevel(_PY_LOG_LEVEL)

_sh = logging.StreamHandler()
_sh.setFormatter(logging.Formatter(_FMT, _DATEFMT))
log.addHandler(_sh)

try:
    _fh = logging.FileHandler(_LOG_FILE, encoding="utf-8")
    _fh.setFormatter(logging.Formatter(_FMT, _DATEFMT))
    log.addHandler(_fh)
except OSError:
    pass

# ── Configuration ──────────────────────────────────────────────────────
CHECK_INTERVAL  = int(float(os.getenv("BATTERY_CHECK_INTERVAL", "60")))
LOW_THRESHOLD   = int(os.getenv("BATTERY_LOW_THRESHOLD",        "20"))
SHUNT_OHMS      = float(os.getenv("BATTERY_SHUNT_OHMS",         "0.1"))
MAX_EXPECTED_A  = float(os.getenv("BATTERY_MAX_EXPECTED_A",      "0.2"))
INSTALL_DIR     = os.getenv("INSTALL_DIR", "/opt/soundspot")
RELAY_PIN       = int(os.getenv("RELAY_PIN",        "17"))
RELAY_WARN_DELAY = int(os.getenv("RELAY_WARN_DELAY", "20"))
MASTER_IP       = os.getenv("MASTER_IP", "192.168.10.1")
ORPHEUS_PORT    = os.getenv("ORPHEUS_PORT", "5005")

WELCOME_WAV     = os.path.join(INSTALL_DIR, "welcome.wav")
WELCOME_WAV_BAK = os.path.join(INSTALL_DIR, "welcome_normal.wav")
PLAY_WELCOME    = os.path.join(INSTALL_DIR, "play_welcome.sh")

LOW_TEXT = (
    "Attention, mon énergie est critique. "
    "Je vais bientôt m'éteindre pour recharger mes batteries au soleil."
)

# ── GPIO relais (optionnel) ────────────────────────────────────────────
_gpio_ok = False
if RELAY_PIN > 0:
    try:
        import RPi.GPIO as GPIO  # type: ignore
        GPIO.setmode(GPIO.BCM)
        GPIO.setup(RELAY_PIN, GPIO.OUT, initial=GPIO.HIGH)
        _gpio_ok = True
        log.info("Relais GPIO BCM%d initialisé (HIGH = alimenté)", RELAY_PIN)
    except Exception as _e:
        log.warning("RPi.GPIO indisponible (%s) — relais désactivé", _e)


def export_to_prometheus(voltage, percent):
    # Écriture en RAM (/dev/shm) — zéro écriture SD.
    # Configurer Node Exporter avec --collector.textfile.directory=/dev/shm
    prom_path = "/dev/shm/picoport_battery.prom"
    try:
        with open(prom_path + ".tmp", "w") as f:
            f.write("# HELP picoport_battery_voltage Voltage of the solar battery\n")
            f.write("# TYPE picoport_battery_voltage gauge\n")
            f.write(f"picoport_battery_voltage {voltage:.2f}\n")
            f.write("# HELP picoport_battery_percent Percentage of the solar battery\n")
            f.write("# TYPE picoport_battery_percent gauge\n")
            f.write(f"picoport_battery_percent {percent}\n")
        os.replace(prom_path + ".tmp", prom_path)
    except Exception as e:
        log.error("Failed to export metrics: %s", e)

### LiPO config
# VOLTAGE_MAX = 4.20
# VOLTAGE_MIN = 3.20


# def voltage_to_percent(v: float) -> int:
#     pct = (v - VOLTAGE_MIN) / (VOLTAGE_MAX - VOLTAGE_MIN) * 100
#     return max(0, min(100, int(pct)))

# ── Configuration (LiFePO4 12.8V) ──────────────
VOLTAGE_MAX = 13.80  # Tension pleine charge (repos) LiFePO4 4S
VOLTAGE_MIN = 10.50  # Sécurité avant coupure BMS (souvent 10V)

def voltage_to_percent(v: float) -> int:
    """
    Estimation non-linéaire pour LiFePO4 4S (12.8V nominal).
    Courbe de décharge typique (au repos) :
    > 13.6V  -> 100%
      13.3V  -> 90%
      13.2V  -> 70%
      13.0V  -> 30%
      12.8V  -> 20%  <-- Seuil d'alerte par défaut
      12.0V  -> 9%
      10.5V  -> 0%
    """
    if v >= 13.6: return 100
    elif v >= 13.3: return 90 + int((v - 13.3)/0.3 * 10)
    elif v >= 13.2: return 70 + int((v - 13.2)/0.1 * 20)
    elif v >= 13.0: return 30 + int((v - 13.0)/0.2 * 40)
    elif v >= 12.8: return 20 + int((v - 12.8)/0.2 * 10)
    elif v >= 12.0: return 9 + int((v - 12.0)/0.8 * 11)
    else:
        pct = (v - VOLTAGE_MIN) / (12.0 - VOLTAGE_MIN) * 9
        return max(0, min(100, int(pct)))


def backup_normal_wav():
    if os.path.exists(WELCOME_WAV) and not os.path.exists(WELCOME_WAV_BAK):
        shutil.copy2(WELCOME_WAV, WELCOME_WAV_BAK)
        log.info("Sauvegarde du message d'accueil normal → %s", WELCOME_WAV_BAK)


def generate_low_battery_wav():
    tmp = WELCOME_WAV + ".low.tmp"
    try:
        r = requests.post(
            f"http://127.0.0.1:{ORPHEUS_PORT}/v1/audio/speech",
            json={"model": "orpheus", "input": LOW_TEXT, "voice": "pierre",
                  "response_format": "wav", "speed": 1.0},
            timeout=20,
        )
        if not (r.ok and r.content):
            raise RuntimeError(f"HTTP {r.status_code}")
        with open(tmp, "wb") as f:
            f.write(r.content)
    except Exception as exc:
        log.warning("TTS Orpheus échoué (%s) — repli espeak-ng", exc)
        try:
            subprocess.run(
                ["espeak-ng", "-v", "fr+f3", "-s", "110", "-p", "40", LOW_TEXT, "-w", tmp],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception as exc2:
            log.error("Impossible de générer l'alerte vocale : %s", exc2)
            return

    os.replace(tmp, WELCOME_WAV)
    log.info("Message d'alerte batterie installé")

    try:
        subprocess.run(
            [PLAY_WELCOME, "--force"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception as exc:
        log.error("Impossible de jouer l'alerte : %s", exc)


def restore_normal_wav():
    if os.path.exists(WELCOME_WAV_BAK):
        tmp = WELCOME_WAV + ".restore.tmp"
        shutil.copy2(WELCOME_WAV_BAK, tmp)
        os.replace(tmp, WELCOME_WAV)
        log.info("Message d'accueil normal restauré")


def _notify_master_direct():
    """Fallback : POST direct à l'API du Master si fleet_commander indisponible."""
    import urllib.request
    url = f"http://{MASTER_IP}/api.sh?action=shutdown"
    try:
        req = urllib.request.Request(url, data=b"", method="POST")
        urllib.request.urlopen(req, timeout=5)
        log.info("Fallback POST shutdown envoyé au Master (%s)", MASTER_IP)
    except Exception as exc:
        log.warning("Master injoignable pour shutdown direct (%s)", exc)


def notify_fleet_shutdown():
    """Diffuse l'ordre d'extinction à TOUTE la flotte via NOSTR kind 9 (Amiral).
    Le fleet_listener sur chaque nœud reçoit la commande et s'éteint proprement.
    Le nœud Énergie coupe le relais physique EN DERNIER (+15s).
    """
    fleet_cmd = os.path.join(INSTALL_DIR, "backend/system/fleet_commander.sh")
    if os.path.isfile(fleet_cmd):
        try:
            result = subprocess.run(
                ["bash", fleet_cmd, "shutdown", str(RELAY_WARN_DELAY)],
                timeout=15,
                capture_output=True,
                text=True,
            )
            if result.returncode == 0:
                log.info("Ordre d'extinction diffusé à la flotte via NOSTR Amiral")
                return
            log.warning("fleet_commander.sh code=%d : %s", result.returncode, result.stderr[:120])
        except Exception as exc:
            log.warning("fleet_commander.sh exception (%s)", exc)
    else:
        log.warning("fleet_commander.sh introuvable — fallback POST direct")
    _notify_master_direct()


def cut_relay():
    """Coupe l'alimentation physique via le relais GPIO (compatible sysfs Bookworm)."""
    if RELAY_PIN <= 0:
        return
    try:
        os.system(f"echo {RELAY_PIN} > /sys/class/gpio/export 2>/dev/null")
        os.system(f"echo out > /sys/class/gpio/gpio{RELAY_PIN}/direction 2>/dev/null")
        os.system(f"echo 0 > /sys/class/gpio/gpio{RELAY_PIN}/value 2>/dev/null")
        log.info("Relais GPIO BCM%d ouvert via sysfs — alimentation coupée", RELAY_PIN)
    except Exception as exc:
        log.error("Erreur sysfs coupure relais : %s", exc)

def graceful_shutdown():
    log.warning("BATTERIE CRITIQUE — procédure d'extinction ordonnée")
    generate_low_battery_wav()
    notify_fleet_shutdown()
    log.info("Attente %ds avant coupure relais…", RELAY_WARN_DELAY)
    time.sleep(RELAY_WARN_DELAY)
    cut_relay()

def main():
    log.info("Démarrage du monitoring batterie (INA219, shunt=%.2f Ω)", SHUNT_OHMS)
    try:
        from ina219 import INA219
        ina = INA219(shunt_ohms=SHUNT_OHMS, max_expected_amps=MAX_EXPECTED_A)
        ina.configure()
    except Exception as exc:
        log.info("Arrêt propre du monitoring batterie.")
        sys.exit(0)

    backup_normal_wav()
    low_state = False

    while True:
        try:
            voltage = ina.voltage()
            pct = voltage_to_percent(voltage)
            try:
                with open("/dev/shm/battery_voltage", "w") as f: f.write(f"{voltage:.2f}")
                with open("/dev/shm/battery_percent", "w") as f: f.write(str(pct))
            except Exception: pass
            
            export_to_prometheus(voltage, pct)

            if pct <= LOW_THRESHOLD and not low_state:
                low_state = True
                graceful_shutdown()
            elif pct > LOW_THRESHOLD + 5 and low_state:
                restore_normal_wav()
                low_state = False
        except Exception as exc:
            pass
        time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    main()
