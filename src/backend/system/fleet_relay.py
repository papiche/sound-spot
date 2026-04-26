#!/usr/bin/env python3
"""
fleet_relay.py — Micro-relay NOSTR local SoundSpot (port 9999)
Relay éphémère cluster-interne : pas de persistance, broadcast immédiat.
Accepte uniquement les connexions depuis 192.168.10.x et loopback.
Gère uniquement les kind=9 (éphémères) pour les commandes de flotte.
"""
import asyncio
import json
import logging
import os
import sys

try:
    import websockets
except ImportError:
    print("websockets requis : apt install python3-websockets", file=sys.stderr)
    sys.exit(1)

PORT = int(os.getenv("FLEET_RELAY_PORT", "29999"))
ALLOWED_PREFIXES = ("192.168.10.", "127.", "::1", "::ffff:127.", "::ffff:192.168.10.")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [fleet_relay] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("fleet_relay")

clients: set = set()


async def broadcast(message: str, sender=None):
    for ws in list(clients):
        if ws is sender:
            continue
        try:
            await ws.send(message)
        except Exception:
            clients.discard(ws)


async def handler(ws):
    peer = ws.remote_address[0] if ws.remote_address else ""
    if not any(peer.startswith(p) for p in ALLOWED_PREFIXES):
        log.warning("Connexion refusée depuis %s", peer)
        await ws.close(1008, "Unauthorized")
        return

    clients.add(ws)
    log.info("Client connecté : %s (%d total)", peer, len(clients))
    try:
        async for raw in ws:
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if not isinstance(msg, list) or not msg:
                continue

            verb = msg[0]
            if verb == "EVENT" and len(msg) >= 2:
                event = msg[1]
                if not isinstance(event, dict):
                    continue
                if event.get("kind") == 9:
                    eid = event.get("id", "")
                    await ws.send(json.dumps(["OK", eid, True, ""]))
                    await broadcast(json.dumps(["EVENT", "fleet", event]), sender=ws)
                    log.info("Fleet cmd relayé : %s…", str(event.get("content", ""))[:60])
            elif verb == "REQ" and len(msg) >= 3:
                sub_id = msg[1]
                await ws.send(json.dumps(["EOSE", sub_id]))
            elif verb == "CLOSE":
                pass
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        clients.discard(ws)
        log.info("Client déconnecté : %s (%d restants)", peer, len(clients))


async def main():
    log.info("Fleet relay NOSTR → ws://0.0.0.0:%d (cluster-local, kind=9 uniquement)", PORT)
    async with websockets.serve(handler, "0.0.0.0", PORT):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
