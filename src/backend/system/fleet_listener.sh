#!/bin/bash
# fleet_listener.sh — Écoute les commandes de la flotte NOSTR (kind 9, clé Amiral)
# S'exécute sur tous les nœuds : Maître, Satellites, Énergie.
# Le nœud Énergie (hostname contient "energy") coupe le relais en dernier.

INSTALL_DIR="${INSTALL_DIR:-/opt/soundspot}"
source "$INSTALL_DIR/soundspot.conf" 2>/dev/null || true

SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
ASTRO_VENV="${USER_HOME}/.astro/bin/activate"
[ -f "$ASTRO_VENV" ] && source "$ASTRO_VENV" 2>/dev/null || true

AMIRAL_HEX_FILE="${INSTALL_DIR}/amiral.hex"
if [ ! -f "$AMIRAL_HEX_FILE" ]; then
    logger -t fleet_listener "amiral.hex absent — exécutez amiral_keygen.sh — flotte désactivée"
    exit 0
fi
AMIRAL_HEX=$(cat "$AMIRAL_HEX_FILE")

# Sur le Maître, relay est local ; sur satellite, via IP résolue du maître
IS_MASTER=false
[ -f /etc/hostapd/hostapd.conf ] && IS_MASTER=true
PY_IS_MASTER=$([ "$IS_MASTER" = "true" ] && echo "True" || echo "False")
if $IS_MASTER; then
    RELAY_HOST="127.0.0.1"
else
    source /run/soundspot_master.env 2>/dev/null || true
    RELAY_HOST="${MASTER_RESOLVED:-${MASTER_HOST:-soundspot.local}}"
fi
FLEET_PORT="${FLEET_RELAY_PORT:-29999}"
RELAY="ws://${RELAY_HOST}:${FLEET_PORT}"

logger -t fleet_listener "Écoute flotte → ${RELAY} (Amiral: ${AMIRAL_HEX:0:16}…)"

exec python3 - <<PYEOF
import asyncio, json, os, subprocess, logging, socket

try:
    import websockets
except ImportError:
    import sys; print("websockets requis", file=sys.stderr); sys.exit(1)

try:
    from pynostr.event import Event
except ImportError:
    import sys; print("pynostr requis pour la sécurité", file=sys.stderr); sys.exit(1)

RELAY      = "${RELAY}"
AMIRAL_HEX = "${AMIRAL_HEX}"
INSTALL_DIR = "${INSTALL_DIR}"
IS_ENERGY  = "energy" in socket.gethostname().lower()
IS_MASTER  = ${PY_IS_MASTER}

logging.basicConfig(level=logging.INFO,
    format="%(asctime)s [fleet_listener] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S")
log = logging.getLogger("fleet_listener")

async def execute_command(event: dict):
    try:
        payload = json.loads(event.get("content", "{}"))
    except json.JSONDecodeError:
        return
    cmd = payload.get("cmd")
    log.info("Commande flotte reçue : %s", cmd)

    if cmd == "shutdown":
        delay = int(payload.get("delay_s", 30))
        log.info("Extinction dans %ds…", delay)
        subprocess.run(["systemctl", "stop", "soundspot-client", "snapserver", "soundspot-decoder"],
            capture_output=True,
        )
        await asyncio.sleep(delay)
        if IS_ENERGY:
            log.info("Nœud Énergie — attente 15s supplémentaires avant coupure relais")
            await asyncio.sleep(15)
        subprocess.run(["sudo", "/usr/sbin/poweroff"])

    elif cmd == "restart_client":
        subprocess.run(["systemctl", "restart", "soundspot-client"], capture_output=True)
        log.info("soundspot-client redémarré")

    elif cmd == "announce":
        text = payload.get("text", "")
        if text:
            tts = f"{INSTALL_DIR}/backend/audio/tts.sh"
            if os.path.isfile(tts):
                subprocess.Popen(["bash", tts, text], stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
            log.info("Annonce : %s", text[:80])

async def listen():
    while True:
        try:
            async with websockets.connect(RELAY, ping_interval=30, ping_timeout=10) as ws:
                sub_id = "fleet"
                await ws.send(json.dumps(["REQ", sub_id, {"kinds": [9]}]))
                log.info("Connecté au relay flotte %s", RELAY)
                async for raw in ws:
                    try:
                        msg = json.loads(raw)
                    except Exception:
                        continue
                    if not isinstance(msg, list) or len(msg) < 3:
                        continue
                    if msg[0] == "EVENT":
                        event = msg[2] if len(msg) > 2 else {}
                        # 1. Vérification de l'Auteur
                        if isinstance(event, dict) and event.get("pubkey") == AMIRAL_HEX:
                            # 2. Vérification Cryptographique de la Signature
                            try:
                                ev_obj = Event.from_dict(event)
                                if ev_obj.verify():
                                    await execute_command(event)
                                else:
                                    log.warning("ALERTE SÉCURITÉ: Signature NOSTR falsifiée rejetée ! (id: %s)", event.get("id"))
                            except Exception as e:
                                log.warning("Erreur vérification NOSTR : %s", e)
        except Exception as exc:
            log.warning("Relay déconnecté : %s — reconnexion dans 15s", exc)
            await asyncio.sleep(15)

asyncio.run(listen())
PYEOF