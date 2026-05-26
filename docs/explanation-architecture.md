# Explication : Architecture et Survie du SoundSpot

Le SoundSpot n'est pas un simple hotspot. C'est une architecture souveraine conçue pour
l'autonomie en milieu hostile — festivals off-grid, marchés, événements sans infrastructure.

## Les interfaces réseau

Un nœud Maître peut opérer sur **deux ou trois interfaces** selon le matériel disponible.

### Configuration standard (smartphone ou WiFi comme upstream)

```
wlan0  ─── upstream (qo-op / hotspot smartphone)    ← Internet + Snapcast satellites
uap0   ─── AP virtuelle sur wlan0 (ZICMAMA 2,4GHz) ← Portail captif, audio smartphones
wlan1  ─── mesh B.A.T.M.A.N. (dongle USB 5 GHz)    ← Flotte NOSTR, satellites distants
```

### Configuration avec box 4G / routeur en Ethernet

```
eth0   ─── upstream (box 4G ou routeur)              ← Internet (câble)
wlan0  ─── libre (non utilisé comme client WiFi)
uap0   ─── AP virtuelle sur wlan0 (ZICMAMA 2,4GHz)  ← Portail captif
wlan1  ─── mesh B.A.T.M.A.N. (dongle USB 5 GHz)     ← Satellites distants
```

`uap0` est **toujours** l'interface AP, quelle que soit la source upstream.
Le firewall détecte dynamiquement l'interface WAN au démarrage : eth0 si UP, sinon la route par défaut active. Cela rend le basculement **smartphone ↔ routeur Ethernet transparent** sans reconfiguration.

### Snapcast via le mesh (satellites distants)

Un satellite hors de portée du point d'accès ZICMAMA peut recevoir l'audio via B.A.T.M.A.N. :

```
Satellite signal fort (RSSI ≥ -70 dBm) → ZICMAMA (uap0)  → Snapcast via 192.168.10.1:1704
Satellite signal faible ou hors portée  → bat0 (mesh)      → Snapcast via 10.200.0.1:1704
```

Le choix est automatique : au démarrage, `find_master.sh` mesure le RSSI de ZICMAMA via `iw dev wlan0 link`.
Si le signal est suffisant (≥ -70 dBm), il utilise le gateway ZICMAMA. Sinon, il bascule sur bat0.
Ce seuil est ajustable dans `find_master.sh` (variable `RSSI_THRESHOLD`).

Snapserver écoute sur `0.0.0.0:1704` et le firewall autorise explicitement le port 1704 sur bat0.

## Plusieurs maîtres sur un même territoire

### La limite fondamentale : un seul maître par mesh

Le maître prend toujours l'IP fixe **`10.200.0.1/16`** sur `bat0` (défini dans `mesh_batman.sh`).
B.A.T.M.A.N.-adv opère à la couche 2 : tous les nœuds du mesh partagent le même domaine
de diffusion, quelle que soit la distance physique ou le nombre de sauts.

Si deux maîtres rejoignent le même mesh CYBERCOCHON_MESH :

```
Maître A  10.200.0.1 ─── bat0 ─── Maître B  10.200.0.1
                              ↑
               CONFLIT ARP — deux nœuds, même IP
```

Les satellites qui pinguent `10.200.0.1` reçoivent des réponses alternées des deux maîtres
selon l'état du cache ARP. Ils changent de source Snapcast sans prévenir.
Résultat : audio chaotique, pas de panne franche — le pire scénario pour un festival.

Ce problème s'applique **même à distance** : un maître B relié au maître A via plusieurs
satellites intermédiaires reste sur le même domaine L2. B.A.T.M.A.N. fait le pont,
le conflit d'IP persiste.

### Architecture correcte pour plusieurs scènes

La solution est de **ne pas faire coexister deux maîtres sur le même mesh**.
Pour un festival multi-scènes, chaque maître gère sa flotte en isolation et
les flux audio se synchronisent via l'upstream (Internet / qo-op) :

```
Scène A : [Maître A]─── CYBERCOCHON_MESH ───[Sat A1][Sat A2]
               │
               │  Icecast :8111/live (via qo-op / Internet)
               │
Scène B : [Maître B]─── CYBERCOCHON_MESH ───[Sat B1][Sat B2]
```

Le Maître B tire le flux Icecast du Maître A plutôt que de diffuser le sien.
Les visiteurs des deux scènes entendent le même mix, synchronisé à la latence réseau près
(quelques secondes supplémentaires entre les scènes — imperceptible à 50 m de distance).

### Quand deux meshes peuvent porter le même nom

Deux instances de CYBERCOCHON_MESH sur canal 36 (5 GHz) n'interfèrent pas
si les scènes sont séparées de plus de la portée radio (100-300 m en extérieur selon
le matériel, 500 m+ avec adaptateur directif). Au-delà de cette portée, les deux meshes
sont physiquement isolés et fonctionnent indépendamment sans configuration particulière.

Si les scènes sont proches (même festival dense, stands adjacents), changer le canal
dans `mesh_batman.sh` (ex : scène A canal 36, scène B canal 100) suffit à isoler les meshes.

### Évolution possible

Pour permettre plusieurs maîtres sur un même mesh physique, il faudrait :
- Dériver l'IP bat0 du maître depuis son adresse MAC (comme le font déjà les satellites)
- Faire découvrir le maître par mDNS `soundspot-SPOTNAME.local` sur bat0 plutôt que par IP fixe

`find_master.sh` utilise déjà mDNS en fallback (étapes 3-4). Passer mDNS en priorité
sur bat0 suffirait à rendre l'architecture multi-maître cohérente — sans IP fixe.

## Le paradoxe du Dual-Wi-Fi (Mesh vs AP)

Pourquoi deux cartes Wi-Fi ?

Si le trafic audio Snapcast et le trafic des visiteurs (portail captif) partagent la même puce Wi-Fi,
les paquets entrent en collision et l'audio saccade. La séparation par interface est obligatoire :

- **Puce interne 2.4 GHz (`uap0`)** → hotspot public ouvert, portail captif
- **Dongle USB 5 GHz (`wlan0` ou `wlan1`)** → upstream qo-op, Snapcast satellites, mesh B.A.T.M.A.N.

B.A.T.M.A.N.-adv opère à la couche 2 (MAC) : pour les applications, tous les nœuds croient être
branchés sur le même câble Ethernet géant.

## Le Portail Captif (Lighttpd + ipset)

Quand un visiteur se connecte au WiFi ZICMAMA, il est redirigé vers `http://192.168.10.1`.
Le portail lui donne accès à :

- **📻 Radio** — flux Snapcast en direct (via Snapcast.js dans le navigateur ou VLC)
- **🎵 Jukebox** — proposer et voter des morceaux via NOSTR
- **📤 uDRIVE** — uploader photos/vidéos sur IPFS
- **🌐 Internet** — un clic ouvre **4 heures** d'accès complet (via `ipset hash:ip timeout 14400`)
- **🕸️ Mesh** (`mesh.html`) — radar en temps réel : voisins bat0, qualité TQ, et liste des clients Snapcast actifs (mis à jour toutes les 5 s)

L'ouverture Internet se fait sans compte : l'ipset enregistre l'IP privée du visiteur et NAT
son trafic vers l'upstream. Après 4 heures, le timeout expire et l'accès revient en portail seul.

## Pipeline audio et latence

```
Mixxx (Live Broadcasting)
  → Ogg Vorbis → Icecast2 :8111/live
    → ffmpeg (PCM s16le 48 kHz) → /dev/shm/snapfifo  ← RAM, pas /tmp/
      → Snapserver :1704
        → Snapclient casque DJ     (~2 s de latence)
        → Snapclient smartphone    (~2 s de latence)
        → Snapclient satellite BT  (~2-3 s avec buffer mesh)
```

> **Latence Snapcast : 1 à 3 secondes.** C'est inhérent au pipeline Icecast → ffmpeg → Snapserver.
> Les DJs doivent utiliser la **sortie Cue (pré-écoute) de Mixxx** pour beatmatcher — pas le retour Snapcast.

Le FIFO est dans `/dev/shm/snapfifo` (RAM tmpfs, pas `/tmp/`) pour éviter les écritures SD.

## La Flotte NOSTR et le Suicide Énergétique

Comment éteindre proprement 5 ordinateurs sans écran ni réseau Internet ?

Nous utilisons **NOSTR Kind 9** en réseau local (port `9999`).
Le port 9999 héberge un relay NOSTR éphémère (`fleet_relay.py`) — local uniquement, non accessible depuis Internet, Kind 9 seulement.

Le nœud "Énergie" lit l'état de la batterie via INA219 (I2C). Si la tension chute sous 20 % :

1. Il émet un message Kind 9 chiffré (clé de flotte `FLEET_KEY`) sur le relay local.
2. Tous les nœuds reçoivent l'ordre et s'éteignent proprement (`halt`).
3. Le nœud Énergie attend 15 secondes, puis coupe le **relais physique GPIO 17**.

Le système se rallume seul quand le panneau solaire rechargera la batterie au-dessus du seuil de démarrage.

## Identité Picoport (Y-Level)

Chaque nœud génère une identité cryptographique déterministe depuis sa clé SSH :

```
id_ed25519 (SSH)
  → sha512sum → SECRET1 + SECRET2
    → keygen -t ipfs   → IPFS PeerID (swarm constellation)
    → keygen -t nostr  → NPUB/NSEC (identité BRO + DMs)
    → keygen -t g1     → G1PUB / dunikey (portefeuille Ğ1)
```

**Si la clé SSH est sauvegardée, toute l'identité est restaurable.** Sauvegarder
`~/.ssh/id_ed25519` dans un lieu sûr (hors du RPi).

---

Voir aussi : [Modes Picoport](reference-picoport-modes.md) · [Montage matériel](howto-montage-materiel.md) · [API et config](reference-api-config.md)
