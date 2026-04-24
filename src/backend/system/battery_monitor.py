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
    prom_path = "/var/lib/prometheus/node-exporter/picoport_battery.prom"
    try:
        with open(prom_path + ".tmp", "w") as f:
            f.write(f"# HELP picoport_battery_voltage Voltage of the solar battery\n")
            f.write(f"# TYPE picoport_battery_voltage gauge\n")
            f.write(f"picoport_battery_voltage {voltage:.2f}\n")
            f.write(f"# HELP picoport_battery_percent Percentage of the solar battery\n")
            f.write(f"# TYPE picoport_battery_percent gauge\n")
            f.write(f"picoport_battery_percent {percent}\n")
        os.replace(prom_path + ".tmp", prom_path)
    except Exception as e:
        log.error("Failed to export metrics: %s", e)


VOLTAGE_MAX = 4.20
VOLTAGE_MIN = 3.20


def voltage_to_percent(v: float) -> int:
    pct = (v - VOLTAGE_MIN) / (VOLTAGE_MAX - VOLTAGE_MIN) * 100
    return max(0, min(100, int(pct)))


def backup_normal_wav():
    if os.path.exists(WELCOME_WAV) and not os.path.exists(WELCOME_WAV_BAK):
        shutil.copy2(WELCOME_WAV, WELCOME_WAV_BAK)
        log.info("Sauvegarde du message d'accueil normal → %s", WELCOME_WAV_BAK)


def generate_low_battery_wav():
    tmp = WELCOME_WAV + ".low.tmp"
    try:
        subprocess.run(
            ["espeak-ng", "-v", "fr+f3", "-s", "110", "-p", "40", LOW_TEXT, "-w", tmp],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        os.replace(tmp, WELCOME_WAV)
        log.info("Message d'alerte batterie installé")
    except Exception as exc:
        log.error("Impossible de générer l'alerte vocale : %s", exc)
        return

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


def notify_master_shutdown():
    """Prévient le Master RPi4 de s'éteindre proprement via l'API."""
    import urllib.request
    url = f"http://{MASTER_IP}/api.sh?action=shutdown"
    try:
        req = urllib.request.Request(url, data=b"", method="POST")
        urllib.request.urlopen(req, timeout=5)
        log.info("Signal d'extinction envoyé au Master (%s)", MASTER_IP)
    except Exception as exc:
        log.warning("Master injoignable pour shutdown (%s)", exc)


def cut_relay():
    """Coupe l'alimentation physique via le relais GPIO."""
    if not _gpio_ok:
        log.warning("Relais GPIO non disponible — coupure physique impossible")
        return
    try:
        import RPi.GPIO as GPIO  # type: ignore
        GPIO.output(RELAY_PIN, GPIO.LOW)
        log.info("Relais GPIO BCM%d ouvert — alimentation coupée", RELAY_PIN)
    except Exception as exc:
        log.error("Erreur GPIO coupure relais : %s", exc)


def graceful_shutdown():
    """Extinction ordonnée : alerte → notification Master → délai → relais."""
    log.warning("BATTERIE CRITIQUE — procédure d'extinction ordonnée")

    # 1. Alerter vocalement (le nœud énergie lui-même via play_welcome si présent)
    generate_low_battery_wav()

    # 2. Envoyer l'ordre d'extinction au Master
    notify_master_shutdown()

    # 3. Laisser le temps au Master (RPi4) de flush sa SD card
    log.info("Attente %ds avant coupure relais…", RELAY_WARN_DELAY)
    time.sleep(RELAY_WARN_DELAY)

    # 4. Couper physiquement
    cut_relay()


def main():
    log.info("Démarrage du monitoring batterie (INA219, shunt=%.2f Ω)", SHUNT_OHMS)

    try:
        from ina219 import INA219  # type: ignore
        ina = INA219(shunt_ohms=SHUNT_OHMS, max_expected_amps=MAX_EXPECTED_A)
        ina.configure()
        log.info("Capteur INA219 initialisé")
    except Exception as exc:
        log.warning(
            "Capteur INA219 introuvable (%s) — "
            "SoundSpot sur secteur ou capteur absent.", exc
        )
        log.info("Arrêt propre du monitoring batterie.")
        sys.exit(0)

    backup_normal_wav()

    low_state = False

    while True:
        try:
            voltage = ina.voltage()
            current = ina.current()
            power   = ina.power()
            pct     = voltage_to_percent(voltage)

            log.info("Batterie : %.2f V — %.1f mA — %.1f mW — %d %%", voltage, current, power, pct)

            # Écriture dans /dev/shm (RAM — zéro écriture SD)
            try:
                with open("/dev/shm/battery_voltage", "w") as f: f.write(f"{voltage:.2f}")
                with open("/dev/shm/battery_percent", "w") as f: f.write(str(pct))
                with open("/dev/shm/battery_current", "w") as f: f.write(f"{current:.1f}")
                with open("/dev/shm/battery_power", "w") as f: f.write(f"{power:.1f}")
            except Exception as exc:
                log.error("Erreur d'écriture des stats dans /dev/shm : %s", exc)

            export_to_prometheus(voltage, pct)

            if pct <= LOW_THRESHOLD and not low_state:
                low_state = True
                graceful_shutdown()
                # Après coupure relais, on boucle normalement
                # (si le relais ne nous coupe pas nous-mêmes, batterie peut remonter)

            elif pct > LOW_THRESHOLD + 5 and low_state:
                log.info("Batterie rétablie (%d %%) → message normal", pct)
                restore_normal_wav()
                low_state = False

        except Exception as exc:
            log.error("Erreur lecture INA219 : %s", exc)

        time.sleep(CHECK_INTERVAL)


if __name__ == "__main__":
    main()
