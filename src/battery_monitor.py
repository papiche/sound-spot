#!/usr/bin/env python3
"""
SoundSpot — Monitoring batterie solaire (INA219 via I2C)

Si le capteur INA219 n'est pas physiquement câblé, le script quitte proprement
(code 0) sans remplir les logs d'erreurs. Systemd (Restart=on-failure) ne le
relancera pas dans ce cas.

Quand la tension passe sous le seuil critique (défaut : 20 % ≈ 3.4 V pour
LiPo 3.7 V), le message d'accueil est remplacé par une alerte vocale et joué
immédiatement. À la recharge (tension > seuil + 5 %), le message d'origine
est restauré automatiquement.

Variables d'environnement :
  BATTERY_CHECK_INTERVAL   Secondes entre deux lectures  (défaut : 600)
  BATTERY_LOW_THRESHOLD    Pourcentage critique           (défaut : 20)
  BATTERY_SHUNT_OHMS       Valeur du shunt résistif       (défaut : 0.1)
  BATTERY_MAX_EXPECTED_A   Courant max attendu (A)        (défaut : 0.2)
  INSTALL_DIR              Répertoire SoundSpot           (défaut : /opt/soundspot)
"""
import logging
import os
import shutil
import subprocess
import sys
import time

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [battery] %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger()

# ── Configuration ──────────────────────────────────────────────────────
CHECK_INTERVAL  = int(float(os.getenv("BATTERY_CHECK_INTERVAL", "600")))
LOW_THRESHOLD   = int(os.getenv("BATTERY_LOW_THRESHOLD",        "20"))
SHUNT_OHMS      = float(os.getenv("BATTERY_SHUNT_OHMS",         "0.1"))
MAX_EXPECTED_A  = float(os.getenv("BATTERY_MAX_EXPECTED_A",      "0.2"))
INSTALL_DIR     = os.getenv("INSTALL_DIR", "/opt/soundspot")

WELCOME_WAV     = os.path.join(INSTALL_DIR, "welcome.wav")
WELCOME_WAV_BAK = os.path.join(INSTALL_DIR, "welcome_normal.wav")
PLAY_WELCOME    = os.path.join(INSTALL_DIR, "play_welcome.sh")

LOW_TEXT = (
    "Attention, mon énergie est critique. "
    "Je vais bientôt m'éteindre pour recharger mes batteries au soleil."
)

def export_to_prometheus(voltage, percent):
    prom_path = "/var/lib/prometheus/node-exporter/picoport_battery.prom"
    try:
        # On crée le dossier si besoin (doit être fait par l'installeur)
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

# ── Courbe de décharge LiPo 3.7 V simplifiée ──────────────────────────
VOLTAGE_MAX = 4.20   # 100 %
VOLTAGE_MIN = 3.20   # 0 %  (seuil de coupure)


def voltage_to_percent(v: float) -> int:
    pct = (v - VOLTAGE_MIN) / (VOLTAGE_MAX - VOLTAGE_MIN) * 100
    return max(0, min(100, int(pct)))


def backup_normal_wav():
    """Sauvegarde le message d'accueil d'origine (une seule fois)."""
    if os.path.exists(WELCOME_WAV) and not os.path.exists(WELCOME_WAV_BAK):
        shutil.copy2(WELCOME_WAV, WELCOME_WAV_BAK)
        log.info("Sauvegarde du message d'accueil normal → %s", WELCOME_WAV_BAK)


def generate_low_battery_wav():
    """Génère le WAV d'alerte et remplace le message d'accueil."""
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

    # Lecture immédiate pour prévenir l'entourage
    try:
        subprocess.run(
            [PLAY_WELCOME],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception as exc:
        log.error("Impossible de jouer l'alerte : %s", exc)


def restore_normal_wav():
    """Restaure le message d'accueil d'origine de manière atomique."""
    if os.path.exists(WELCOME_WAV_BAK):
        tmp = WELCOME_WAV + ".restore.tmp"
        shutil.copy2(WELCOME_WAV_BAK, tmp)
        os.replace(tmp, WELCOME_WAV)
        log.info("Message d'accueil normal restauré")


def main():
    log.info("Démarrage du monitoring batterie (INA219, shunt=%.2f Ω)", SHUNT_OHMS)

    # ── Tentative d'initialisation du capteur ──────────────────────
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
        sys.exit(0)  # code 0 → Restart=on-failure ne relancera pas

    backup_normal_wav()

    low_state = False  # True quand on est déjà en état d'alerte

    while True:
        try:
            voltage = ina.voltage()
            pct     = voltage_to_percent(voltage)
            log.info("Batterie : %.2f V — %d %%", voltage, pct)

            if pct <= LOW_THRESHOLD and not low_state:
                log.warning("Batterie critique (%d %%) → alerte vocale", pct)
                generate_low_battery_wav()
                low_state = True

            elif pct > LOW_THRESHOLD + 5 and low_state:
                # Marge de +5 % pour éviter le flapping autour du seuil
                log.info("Batterie rétablie (%d %%) → message normal", pct)
                restore_normal_wav()
                low_state = False

        except Exception as exc:
            log.error("Erreur lecture INA219 : %s", exc)

        time.sleep(CHECK_INTERVAL)


if __name__ == "__main__":
    main()
