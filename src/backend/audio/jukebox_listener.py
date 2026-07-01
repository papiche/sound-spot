#!/usr/bin/env python3
import json, time, os, re, websocket

QUEUE_DIR = "/dev/shm/soundspot_queue"
os.makedirs(QUEUE_DIR, exist_ok=True)

INSTALL_DIR = os.getenv("INSTALL_DIR", "/opt/soundspot")
LOCAL_GATEWAY = "http://127.0.0.1:8080"

# Auteur autorisé = l'Amiral déterministe du swarm (amiral_keygen.sh), le même
# identifiant que fleet_listener.sh utilise pour les ordres de flotte. Sans ce
# fichier, la jukebox reste désactivée plutôt que d'accepter n'importe quel auteur.
AMIRAL_HEX = ""
try:
    with open(os.path.join(INSTALL_DIR, "amiral.hex")) as f:
        AMIRAL_HEX = f.read().strip()
except OSError:
    pass
if not AMIRAL_HEX:
    print("⚠ Jukebox: amiral.hex absent — exécutez amiral_keygen.sh — jukebox désactivée", flush=True)

# Essaie le tunnel local P2P vers le Brain-Node, puis le relay public
RELAY_URLS = [
    "ws://127.0.0.1:9999",
    "wss://relay.copylaradio.com",
]
seen_urls = set()

# Capture le CID + chemin ; le domaine/port de l'expéditeur est ignoré et
# systématiquement remplacé par la gateway IPFS locale (défense anti-SSRF —
# jukebox_player.sh ne doit jamais atteindre une IP/port arbitraire).
IPFS_MP3_RE = re.compile(r'https?://[^\s/]+/ipfs/([a-zA-Z0-9]+)(/[^\s]*\.mp3)')

def on_message(ws, message):
    if not AMIRAL_HEX:
        return
    try:
        data = json.loads(message)
        if data[0] == "EVENT":
            event = data[2]
            if event.get("pubkey") != AMIRAL_HEX:
                return
            content = event.get("content", "")
            # Cherche un lien IPFS .mp3 envoyé par l'IA (le capitaine du swarm)
            for cid, path in IPFS_MP3_RE.findall(content):
                url = f"{LOCAL_GATEWAY}/ipfs/{cid}{path}"
                if url in seen_urls: continue
                seen_urls.add(url)

                # Vérifie combien de morceaux sont déjà dans la queue
                files = [f for f in os.listdir(QUEUE_DIR) if f.endswith('.job')]
                if len(files) < 5: # Limite de 5 morceaux d'avance max
                    job_id = str(time.time()).replace('.', '')
                    with open(os.path.join(QUEUE_DIR, f"{job_id}.job"), "w") as f:
                        f.write(url)
                    print(f"📥 Jukebox: Morceau reçu via Nostr -> {url}", flush=True)
    except Exception: pass

def make_on_open(relay_url):
    def on_open(ws):
        print(f"🔗 Connecté au relay Nostr ({relay_url})", flush=True)
        _filter = {"kinds": [1], "since": int(time.time())}
        if AMIRAL_HEX:
            _filter["authors"] = [AMIRAL_HEX]
        ws.send(json.dumps(["REQ", "jukebox_sub", _filter]))
    return on_open

if __name__ == "__main__":
    relay_idx = 0
    while True:
        relay_url = RELAY_URLS[relay_idx % len(RELAY_URLS)]
        try:
            ws = websocket.WebSocketApp(
                relay_url,
                on_open=make_on_open(relay_url),
                on_message=on_message,
            )
            ws.run_forever(ping_interval=30, ping_timeout=10)
        except Exception:
            pass
        relay_idx += 1
        time.sleep(5)