#!/usr/bin/env python3
"""
bt_reactive.py — Reconnexion Bluetooth instantanée (Robust Parsing)
Remplace la boucle de polling bt-autoconnect.sh (60 s).
"""
import os
import subprocess
import time
import logging
import sys
import signal
import re

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [bt_reactive ] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("bt_reactive")

BT_MACS_ENV = os.getenv("BT_MACS", "") or os.getenv("BT_MAC", "")
TARGET_MACS  =[m.upper() for m in BT_MACS_ENV.split() if m]
INSTALL_DIR  = os.getenv("INSTALL_DIR", "/opt/soundspot")

# Regex pour nettoyer les séquences de contrôle ANSI (couleurs terminal)
ANSI_ESCAPE = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
monitor_proc = None

if not TARGET_MACS:
    log.error("BT_MACS non défini dans soundspot.conf — arrêt")
    sys.exit(1)

log.info("Surveillance BT réactive → %s", TARGET_MACS)

def connect_mac(mac: str):
    log.info("Connexion BT : %s", mac)
    res = subprocess.run(["bluetoothctl", "connect", mac],
                         timeout=15, capture_output=True, text=True)
    if "Connected: yes" not in res.stdout and "successful" not in res.stdout.lower():
        log.warning("Connexion %s incertaine : %s", mac, res.stdout.strip())
    # Recombiner les sinks PipeWire (multi-enceintes)
    combine = os.path.join(INSTALL_DIR, "backend/system/bt-combine-sinks.sh")
    if os.path.exists(combine):
        subprocess.run(["bash", combine], capture_output=True, timeout=10)
    subprocess.run(["systemctl", "restart", "soundspot-client"], capture_output=True)
    log.info("soundspot-client redémarré après connexion %s", mac)

def is_connected(mac: str) -> bool:
    result = subprocess.run(["bluetoothctl", "info", mac], capture_output=True, text=True)
    return "Connected: yes" in result.stdout

def watch_loop():
    global monitor_proc
    try:
        # stdbuf -o0 force le vidage du buffer ligne par ligne
        monitor_proc = subprocess.Popen(["stdbuf", "-o0", "bluetoothctl", "monitor"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1
        )
        log.info("Écoute des événements BlueZ…")
        
        for raw_line in monitor_proc.stdout:
            # Nettoyage robuste des couleurs et sauts de ligne
            line = ANSI_ESCAPE.sub('', raw_line).strip()
            if not line:
                continue
                
            for mac in TARGET_MACS:
                if mac in line.upper():
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
    for mac in TARGET_MACS:
        if not is_connected(mac):
            connect_mac(mac)
    while True:
        watch_loop()

if __name__ == "__main__":
    main()