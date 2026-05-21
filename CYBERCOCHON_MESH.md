# 🐷 Architecture Mesh "CyberCochon" (B.A.T.M.A.N.-adv)

Ce document décrit l'architecture réseau spécifique déployée pour relier plusieurs SoundSpots en réseau maillé hors-ligne.

## 1. Séparation des Bandes (Crucial)
- **L'AP public ZICMAMA** (portail captif) tourne sur la puce Wi-Fi interne du Raspberry Pi (`wlan0` / 2.4 GHz).
- **Le réseau Mesh B.A.T.M.A.N.** tourne sur le dongle Vemfay USB 3.0 (`wlan1` / 5 GHz / Canal 36). 
*Attention : Si on mélange le Mesh et l'AP public sur la même bande de fréquences, le réseau s'effondrera sous le trafic de Snapcast (synchronisation audio).*

## 2. La magie d'Avahi (mDNS) sur bat0
Dans le script `mesh_batman.sh`, on génère des IP en `10.200.x.x` totalement aléatoires (basées sur l'adresse MAC). 
**Comment les Satellites trouvent-ils le Master ?** 
B.A.T.M.A.N. est un réseau de Couche 2 (comme un grand switch Ethernet invisible). Il transmet nativement les paquets Multicast. Le service `avahi-daemon` va donc naturellement broadcaster le nom `soundspot.local` à travers tout l'essaim Mesh. Les satellites trouveront le Master automatiquement, sans aucun serveur DHCP sur le Mesh !

## 3. Le Jitter de Snapcast vs la portée du Mesh
Le tampon de Snapcast a été monté à **3000ms** (3 secondes) pour absorber la latence (jitter) des sauts Wi-Fi du Mesh. 
- Avec l'émetteur FM branché au ventre du cochon, le Master (Pi 4) diffuse en temps réel (délai 0).
- Les satellites (autres cochons) auront 3 secondes de délai.
*Astuce : Dans l'interface web de Snapserver (http://soundspot.local:1780), il faudra ajuster le "Delay" (offset) du stream local de l'émetteur FM pour qu'il soit parfaitement calé avec le son qui sort des enceintes des satellites !*

## 4. Le tunnel de Flotte (Port 9999) est Mesh-Ready
Puisque l'interface `bat0` agit comme un switch ethernet géant, le relais NOSTR local (`fleet_relay.py` sur le port 9999) qui gère l'extinction du système écoute déjà sur `0.0.0.0`. L'ordre de *shutdown* global circulera instantanément de Cochon en Cochon à travers tout le festival, et les nœuds Énergie se couperont proprement.
