#!/usr/bin/env python3
import time
import subprocess
import os

# Configuration
LEASE_FILE = "/var/lib/misc/dnsmasq.leases"
LIMIT_SECONDS = 900  # 15 minutes
CHECK_INTERVAL = 30  # Vérifier toutes les 30s

def block_ip(ip):
    print(f"[Limiter] Blocage de l'IP {ip} pour 1 heure")
    subprocess.run(["sudo", "ipset", "add", "soundspot_blocked", ip, "-exist"])

def main():
    start_times = {} # IP -> timestamp de première vue

    print("[Limiter] Surveillance des connexions active...")
    
    while True:
        try:
            if os.path.exists(LEASE_FILE):
                with open(LEASE_FILE, "r") as f:
                    now = time.time()
                    for line in f:
                        parts = line.split()
                        if len(parts) >= 3:
                            ip = parts[2]
                            
                            # Si c'est une nouvelle IP, on commence le chrono
                            if ip not in start_times:
                                print(f"[Limiter] Nouveau client détecté : {ip}. Début des 15 min.")
                                start_times[ip] = now
                            
                            # Si le temps est écoulé
                            elif now - start_times[ip] > LIMIT_SECONDS:
                                block_ip(ip)
                                # On le retire de notre dict local pour ne pas 
                                # spammer la commande ipset
                                start_times[ip] = now + 86400 # Bloqué pour la journée dans le dict
                                
        except Exception as e:
            print(f"Erreur : {e}")
            
        time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    main()