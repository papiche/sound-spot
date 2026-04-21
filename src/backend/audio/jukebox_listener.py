#!/usr/bin/env python3
import json, time, os, re, websocket

# ── Identification Astroport (Optimisée : lecture native Python) ──
def get_ipfs_peer_id():
    config_path = os.path.expanduser("~/.ipfs/config")
    try:
        with open(config_path, "r") as f:
            config = json.load(f)
            peer_id = config.get("Identity", {}).get("PeerID")
            if peer_id:
                return peer_id
    except Exception:
        pass
    return "unknown"

IPFSNODEID = get_ipfs_peer_id()
QUEUE_DIR = os.path.expanduser(f"~/.zen/tmp/{IPFSNODEID}/soundspot_queue")
os.makedirs(QUEUE_DIR, exist_ok=True)

RELAY_URL = "ws://127.0.0.1:9999" # Tunnel vers le Brain-Node de l'essaim
seen_urls = set()

def on_message(ws, message):
    try:
        data = json.loads(message)
        if data[0] == "EVENT":
            content = data[2].get("content", "")
            # Cherche un lien IPFS .mp3 envoyé par l'IA (le capitaine du swarm)
            matches = re.findall(r'https?://[^\s]+/ipfs/[a-zA-Z0-9]+/[^\s]+\.mp3', content)
            for url in matches:
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

def on_open(ws):
    print(f"🔗 Connecté au tunnel Nostr ({RELAY_URL})", flush=True)
    ws.send(json.dumps(["REQ", "jukebox_sub", {"kinds": [1], "since": int(time.time())}]))

if __name__ == "__main__":
    while True:
        try:
            ws = websocket.WebSocketApp(RELAY_URL, on_open=on_open, on_message=on_message)
            ws.run_forever(ping_interval=30, ping_timeout=10)
        except Exception: pass
        time.sleep(5)