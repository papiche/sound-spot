#!/usr/bin/env python3
import json, time, os, re, websocket

QUEUE_DIR = "/dev/shm/soundspot_queue"
os.makedirs(QUEUE_DIR, exist_ok=True)

# Essaie le tunnel local P2P vers le Brain-Node, puis le relay public
RELAY_URLS = [
    "ws://127.0.0.1:9999",
    "wss://relay.copylaradio.com",
]
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

def make_on_open(relay_url):
    def on_open(ws):
        print(f"🔗 Connecté au relay Nostr ({relay_url})", flush=True)
        ws.send(json.dumps(["REQ", "jukebox_sub", {"kinds": [1], "since": int(time.time())}]))
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