#!/usr/bin/env python3
import json, time, os, re, websocket

QUEUE_DIR = "/tmp/soundspot_queue"
os.makedirs(QUEUE_DIR, exist_ok=True)
RELAY_URL = "ws://127.0.0.1:9999" # Tunnel vers le Brain-Node
seen_urls = set()

def on_message(ws, message):
    try:
        data = json.loads(message)
        if data[0] == "EVENT":
            content = data[2].get("content", "")
            # Cherche un lien IPFS .mp3
            matches = re.findall(r'https?://[^\s]+/ipfs/[a-zA-Z0-9]+/[^\s]+\.mp3', content)
            for url in matches:
                if url in seen_urls: continue
                seen_urls.add(url)
                
                files =[f for f in os.listdir(QUEUE_DIR) if f.endswith('.job')]
                if len(files) < 5: # Limite de 5 morceaux
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