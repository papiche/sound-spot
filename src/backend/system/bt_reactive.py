#!/usr/bin/env python3
"""
bt_reactive.py — Reconnexion Bluetooth instantanée via D-Bus BlueZ
Remplace la boucle de polling bt-autoconnect.sh (60 s) par une réaction
aux événements PropertiesChanged de BlueZ : dès que l'enceinte apparaît
dans le réseau BT, la connexion est tentée immédiatement.

Variables d'environnement (depuis soundspot.conf) :
  BT_MACS          MACs séparés par espaces (ex: "AA:BB:CC:DD:EE:FF 11:22:33:44:55:66")
  INSTALL_DIR      Répertoire SoundSpot (défaut: /opt/soundspot)
  SOUNDSPOT_USER   Utilisateur système (pour restart snapclient)
"""
import os
import subprocess
import time
import logging
import sys
import signal

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [bt_reactive ] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("bt_reactive")

BT_MACS_ENV = os.getenv("BT_MACS", "") or os.getenv("BT_MAC", "")
TARGET_MACS  = [m.upper() for m in BT_MACS_ENV.split() if m]
INSTALL_DIR  = os.getenv("INSTALL_DIR", "/opt/soundspot")
SOUNDSPOT_USER = os.getenv("SOUNDSPOT_USER", "pi")

# Variable globale pour stocker le processus bluetoothctl monitor
monitor_proc = None

if not TARGET_MACS:
    log.error("BT_MACS non défini dans soundspot.conf — arrêt")
    sys.exit(1)

log.info("Surveillance BT réactive → %s", TARGET_MACS)

def connect_mac(mac: str):
    """Tente bluetoothctl connect + redémarre soundspot-client."""
    log.info("Connexion BT : %s", mac)
    subprocess.run(
        ["bluetoothctl", "connect", mac],
        timeout=15, capture_output=True,
    )
    # Relancer snapclient pour qu'il utilise le nouveau sink A2DP
    subprocess.run(
        ["systemctl", "restart", "soundspot-client"],
        capture_output=True,
    )
    log.info("soundspot-client redémarré après connexion %s", mac)

def is_connected(mac: str) -> bool:
    result = subprocess.run(
        ["bluetoothctl", "info", mac],
        capture_output=True, text=True,
    )
    return "Connected: yes" in result.stdout

def watch_loop():
    """Polling D-Bus simplifié via subprocess bluetoothctl monitor.
    On parse la sortie de `bluetoothctl monitor` pour détecter
    les événements de connexion/déconnexion en temps réel.
    """
    global monitor_proc
    try:
        monitor_proc = subprocess.Popen(
            ["bluetoothctl", "monitor"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        log.info("Écoute des événements BlueZ (bluetoothctl monitor)…")
        for line in monitor_proc.stdout:
            line = line.strip()
            if not line:
                continue
            for mac in TARGET_MACS:
                if mac.lower() in line.lower() or mac.upper() in line:
                    if "Connected: yes" in line or "new" in line.lower():
                        if not is_connected(mac):
                            connect_mac(mac)
                    break
    except Exception as exc:
        log.error("Erreur surveillance BlueZ : %s — reprise dans 10s", exc)
        time.sleep(10)

def handle_sigterm(signum, frame):
    global monitor_proc
    if monitor_proc:
        monitor_proc.terminate()
        monitor_proc.wait(timeout=5)
    sys.exit(0)

def main():
    signal.signal(signal.SIGTERM, handle_sigterm)

    # Connexion initiale au démarrage
    for mac in TARGET_MACS:
        if not is_connected(mac):
            connect_mac(mac)

    while True:
        watch_loop()

if __name__ == "__main__":
    main()