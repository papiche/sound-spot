#!/usr/bin/env python3
"""
bt_reactive.py — Reconnexion Bluetooth réactive (D-Bus + fallback texte)

Stratégie :
  1. Écoute les signaux D-Bus BlueZ (org.bluez.Device1.PropertiesChanged)
     → fiable, sans polling, sans parse fragile de texte
     → nécessite python3-dbus + python3-gi (apt install)
  2. Fallback : parse bluetoothctl monitor si D-Bus absent

Watchdog audio :
  Thread dédié (toutes les 120 s) — vérifie que chaque enceinte BT
  "Connected: yes" dans BlueZ est bien présente dans PipeWire.
  Si absente, relance WirePlumber (sink perdu silencieusement).

Droits requis : root (ou sudo) pour bluetoothctl + systemctl restart.
"""
import os
import subprocess
import time
import logging
import sys
import signal
import re
import threading

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [bt_reactive ] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("bt_reactive")

BT_MACS_ENV    = os.getenv("BT_MACS", "") or os.getenv("BT_MAC", "")
TARGET_MACS    = [m.upper() for m in BT_MACS_ENV.split() if m]
INSTALL_DIR    = os.getenv("INSTALL_DIR", "/opt/soundspot")
SOUNDSPOT_USER = os.getenv("SOUNDSPOT_USER", "pi")

ANSI_ESCAPE = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')

if not TARGET_MACS:
    log.error("BT_MACS non défini dans soundspot.conf — arrêt")
    sys.exit(1)

log.info("Surveillance BT réactive → %s", TARGET_MACS)

# ── D-Bus disponibilité ───────────────────────────────────────────────
try:
    import dbus                           # python3-dbus
    import dbus.mainloop.glib
    from gi.repository import GLib        # python3-gi
    _DBUS_OK = True
except ImportError:
    _DBUS_OK = False
    log.info("dbus/gi absent — mode fallback bluetoothctl monitor")
    log.info("Pour activer D-Bus : sudo apt install python3-dbus python3-gi")


# ── Actions BT ───────────────────────────────────────────────────────
def connect_mac(mac: str):
    log.info("Connexion BT : %s", mac)
    res = subprocess.run(
        ["bluetoothctl", "connect", mac],
        timeout=15, capture_output=True, text=True,
    )
    if "Connected: yes" not in res.stdout and "successful" not in res.stdout.lower():
        log.warning("Connexion %s incertaine : %s", mac, res.stdout.strip())
    # Recombiner les sinks PipeWire (multi-enceintes)
    combine = os.path.join(INSTALL_DIR, "backend/system/bt-combine-sinks.sh")
    if os.path.exists(combine):
        subprocess.run(["bash", combine], capture_output=True, timeout=10)


def is_connected(mac: str) -> bool:
    result = subprocess.run(
        ["bluetoothctl", "info", mac],
        capture_output=True, text=True,
    )
    return "Connected: yes" in result.stdout


# ── Mode D-Bus (méthode propre) ───────────────────────────────────────
def dbus_watch():
    """Écoute PropertiesChanged via D-Bus — détecte la déconnexion instantanément."""
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()

    def _on_props_changed(interface, changed, invalidated, path):
        if interface != "org.bluez.Device1":
            return
        # path : /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF
        dev_id = path.rsplit("/", 1)[-1]
        if not dev_id.startswith("dev_"):
            return
        mac = dev_id[4:].replace("_", ":").upper()
        if mac not in TARGET_MACS:
            return
        if "Connected" in changed and not bool(changed["Connected"]):
            log.info("D-Bus: %s déconnecté → reconnexion", mac)
            threading.Thread(target=connect_mac, args=(mac,), daemon=True).start()

    bus.add_signal_receiver(
        _on_props_changed,
        dbus_interface="org.freedesktop.DBus.Properties",
        signal_name="PropertiesChanged",
        path_keyword="path",
        bus_name="org.bluez",
    )

    log.info("Écoute D-Bus BlueZ active (org.bluez.Device1.PropertiesChanged)")
    GLib.MainLoop().run()


# ── Mode fallback : parse bluetoothctl monitor ────────────────────────
monitor_proc = None


def watch_loop():
    global monitor_proc
    try:
        monitor_proc = subprocess.Popen(
            ["stdbuf", "-o0", "bluetoothctl", "monitor"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        for raw_line in monitor_proc.stdout:
            line = ANSI_ESCAPE.sub("", raw_line).strip()
            if not line:
                continue
            for mac in TARGET_MACS:
                if mac in line.upper():
                    # Déconnexion = "Connected: no" OU suppression du device
                    if "Connected: no" in line or "[DEL]" in line:
                        log.info("Déconnexion détectée (%s) → reconnexion", mac)
                        threading.Thread(
                            target=connect_mac, args=(mac,), daemon=True
                        ).start()
                    break
    except Exception as exc:
        log.error("Flux Bluetooth interrompu : %s", exc)


# ── Watchdog audio : BT connecté mais absent de PipeWire ─────────────
def watchdog_loop():
    """Vérifie toutes les 2 min que le sink BT est bien dans PipeWire."""
    while True:
        time.sleep(120)
        for mac in TARGET_MACS:
            try:
                bt = subprocess.run(
                    ["bluetoothctl", "info", mac],
                    capture_output=True, text=True, timeout=5,
                )
                if "Connected: yes" not in bt.stdout:
                    continue
                wp = subprocess.run(
                    ["wpctl", "status"],
                    capture_output=True, text=True, timeout=5,
                )
                # PipeWire identifie les sinks BT par "bluez" dans leur chemin
                if "bluez" not in wp.stdout.lower():
                    log.warning(
                        "Watchdog: %s BT connecté mais absent de PipeWire "
                        "— restart WirePlumber", mac,
                    )
                    subprocess.run(
                        ["runuser", "-u", SOUNDSPOT_USER, "--",
                         "systemctl", "--user", "restart", "wireplumber"],
                        timeout=15, capture_output=True,
                    )
                    time.sleep(5)
                    subprocess.run(
                        ["systemctl", "restart", "soundspot-client"],
                        capture_output=True, timeout=10,
                    )
                    break
            except Exception as exc:
                log.debug("Watchdog %s : %s", mac, exc)


# ── Signal SIGTERM ────────────────────────────────────────────────────
def handle_sigterm(signum, frame):
    global monitor_proc
    if monitor_proc:
        monitor_proc.terminate()
        monitor_proc.wait(timeout=5)
    sys.exit(0)


# ── Main ──────────────────────────────────────────────────────────────
def main():
    signal.signal(signal.SIGTERM, handle_sigterm)

    # Connexion initiale au démarrage
    for mac in TARGET_MACS:
        if not is_connected(mac):
            connect_mac(mac)

    # Watchdog audio en arrière-plan (indépendant du mode D-Bus / texte)
    threading.Thread(target=watchdog_loop, daemon=True).start()
    log.info("Watchdog audio PipeWire démarré (vérification toutes les 120 s)")

    if _DBUS_OK:
        # Mode propre D-Bus — bloque dans GLib.MainLoop()
        try:
            dbus_watch()
        except Exception as exc:
            log.error("D-Bus watch interrompu (%s) — bascule sur fallback", exc)

    # Fallback : boucle bluetoothctl monitor (text parsing)
    log.info("Boucle fallback bluetoothctl monitor démarrée")
    while True:
        try:
            watch_loop()
        except Exception as exc:
            log.error("Erreur boucle fallback : %s", exc)
        time.sleep(10)


if __name__ == "__main__":
    main()
