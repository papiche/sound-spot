# Référence — Protocole BRO / Inter-NODE

## Vue d'ensemble

**BRO** est le protocole de communication inter-nœuds d'UPlanet. Il repose sur deux couches NOSTR :

| Couche | Kind | Chiffrement | Usage |
|--------|------|-------------|-------|
| Kind 1 public | 1 | Non | Commandes `#BRO #tag` publiées sur relay public |
| Kind 4 DM | 4 | NIP-44 | DMs chiffrés inter-station (queue `bro_dm_queue/`) |

---

## Flux Copie YouTube (SoundSpot → Home Station)

```
[Visiteur SoundSpot]
        │ 1. ytcopyRequest() vérifie NIP-42 côté serveur
        │    GET /api.sh?action=ytcopy&npub=npub1xxx
        │    → {"status":"ok","relay":"wss://relay.copylaradio.com"}
        │
        │ 2. Browser signe kind 1 via NIP-07 (window.nostr)
        │    content: "#BRO #youtube https://youtube.com/watch?v=..."
        │    tags:   [["u", "<URL>"]]
        │    pubkey: hex du MULTIPASS connecté
        │
        ▼
[relay.copylaradio.com]
        │ strfry writePolicy → filtre kind 1 → accepte
        │
        ▼
[Home Station du MULTIPASS]
        │ UPlanet_IA_Responder.sh reçoit le kind 1
        │   TAGS[BRO]=true, TAGS[youtube]=true
        │   → process_youtube.sh --output-dir APP/uDRIVE/Videos/ <URL>
        │
        ▼
[IPFS Home Station]
        │ Fichier ajouté au uDRIVE du joueur
        │ generate_ipfs_structure.sh → manifest.json mis à jour
        │
        ▼
[AutoDJ SoundSpot] — lecture automatique si MULTIPASS connecté
        │ autodj.sh lit /ipns/npub.../APP/uDRIVE/manifest.json
        │ joue les fichiers type="audio" via ffmpeg → icecast
```

### Format exact du kind 1 BRO YouTube

```json
{
  "kind": 1,
  "content": "#BRO #youtube #mp3 https://youtube.com/watch?v=XXXX",
  "tags": [["u", "https://youtube.com/watch?v=XXXX"]],
  "pubkey": "<hex 64 chars du MULTIPASS>",
  "created_at": 1234567890
}
```

Modificateur de format (optionnel, dans le **content**) :

| Tag content | Résultat | Dossier uDRIVE |
|-------------|----------|----------------|
| `#mp3` | Audio MP3 | `APP/uDRIVE/Music/` |
| *(absent)* | Vidéo MP4 | `APP/uDRIVE/Videos/` |

> **Critique** : `UPlanet_IA_Responder.sh` détecte `#BRO` ET `#youtube` dans le **content**.  
> Un kind 1 avec seulement `tags: [["t","ytcopy"]]` ne sera **pas** traité.

---

## Canaux DM NIP-44 (kind 4)

Traités par `bro_dm_daemon.sh` sur la home station. Chaque DM déposé dans `~/.zen/tmp/bro_dm_queue/` contient un JSON `{"channel":"...","payload":{...}}`.

| Channel | Émetteur | Action |
|---------|----------|--------|
| `plain` | N'importe quel NOSTR user | Question BRO → RAG Qdrant + Ollama → DM réponse |
| `udrive` | Station visiteur | Sync fichier CID dans APP/uDRIVE du joueur |
| `vocals` | Station visiteur | Publication kind 1222/1244 vocal IPFS |
| `webcam` | Station visiteur | Publication webcam |
| `zen_like` | Station visiteur (roaming) | Paiement G1 coopératif (ZEN → G1 via PAYforSURE.sh) |
| `bro_ia` | Station visiteur (roaming) | Relay commande BRO kind 1 vers home station |
| `comfyui_job` | Station Light | Délégation génération vidéo vers Brain |
| `comfyui_result` | Brain | Résultat génération vidéo retour vers home station |

### Payload `bro_ia` (roaming)

```json
{
  "email":    "user@example.com",
  "pubkey":   "<hex 64>",
  "event_id": "<hex 64>",
  "lat":      "48.85",
  "lon":      "2.35",
  "message":  "#BRO #youtube https://...",
  "url":      "",
  "kname":    "user@example.com"
}
```

La station B (visitée) envoie ce DM à la home station A via `nostr_node_intercom.py` channel `bro_ia`.  
La station A appelle alors directement `UPlanet_IA_Responder.sh` avec les paramètres reconstruits.

---

## Session NIP-42 SoundSpot

Un seul MULTIPASS peut être connecté à la fois (`/dev/shm/.nip42_auth_PUBKEYHEX`).

```
GET  /api.sh?action=nip42&cmd=challenge&npub=npub1xxx
     → {"ok":true,"challenge":"<nonce>","ttl":120}

POST /api.sh?action=nip42&cmd=verify&npub=npub1xxx
     body: <event kind 22242 signé contenant le challenge>
     → {"ok":true,"pubkey":"<hex>","expires_in":3600}
```

- Durée session : **3600s**
- Verify détruit tous les markers existants avant d'écrire le nouveau (session unique)
- AutoDJ lit le marker `ls /dev/shm/.nip42_auth_*` → récupère le npub → manifest uDRIVE

---

## bro_common_lib.sh — API

La bibliothèque `Astroport.ONE/IA/bro_common_lib.sh` factorise les fonctions communes.  
À sourcer dans tout script qui interagit avec BRO :

```bash
source "$(dirname "$(realpath "$0")")/bro_common_lib.sh"
```

| Fonction | Description |
|----------|-------------|
| `bro_log MSG` | Log horodaté vers `$BRO_LOG_FILE` (défaut: `~/.zen/tmp/IA.log`) |
| `bro_alert_captain MSG` | Email HTML au capitaine, rate-limité 24h |
| `bro_bech32_to_hex BECH32` | Convertit npub1.../nsec1... → hex 64 chars |
| `bro_load_node_keys` | Exporte `BRO_NODE_NSEC/NPUB/HEX` depuis `secret.nostr` |
| `bro_load_user_keys EMAIL` | Exporte `BRO_USER_NSEC/NPUB/HEX` depuis `.secret.nostr` joueur |
| `bro_resolve_email HEX` | Trouve l'email par grep dans `~/.zen/game/nostr/*/HEX` |
| `bro_resolve_hex EMAIL` | Lit `~/.zen/game/nostr/$email/HEX` |
| `bro_udrive_path EMAIL [SUBDIR]` | Retourne chemin `APP/uDRIVE[/SUBDIR]`, crée si absent |
| `bro_is_roaming EMAIL` | Retourne 0 si `.roaming` présent |
| `bro_send_dm FROM_NSEC TO_HEX MSG [RELAY]` | Envoie DM NIP-44 via `nostr_send_secure_dm.py` |
| `bro_send_intercom TO_HEX CHANNEL PAYLOAD [TTL] [RELAY]` | DM inter-node via `nostr_node_intercom.py` |
| `bro_payload_get JSON FIELD [...]` | Parse JSON → variables `_FIELD` (majuscules) |
| `bro_relay_bro_ia_to_home EMAIL PUBKEY EVENT LAT LON MSG URL KNAME` | Relaie BRO vers home station |

### Variables exportées

| Variable | Source | Description |
|----------|--------|-------------|
| `BRO_NODE_NSEC/NPUB/HEX` | `bro_load_node_keys()` | Clés du NODE courant |
| `BRO_USER_NSEC/NPUB/HEX` | `bro_load_user_keys()` | Clés d'un joueur |
| `BRO_PUBLIC_RELAY` | config | Relay public (défaut: `wss://relay.copylaradio.com`) |
| `BRO_LOG_FILE` | env | Fichier log (défaut: `~/.zen/tmp/IA.log`) |
| `BRO_SCRIPT_ID` | env | Identifiant script dans les logs |

---

## uDRIVE manifest.json

Généré par `generate_ipfs_structure.sh`. Accessible via IPFS :

```
http://127.0.0.1:8080/ipns/<npub>/APP/uDRIVE/manifest.json
```

Structure :
```json
{
  "files": [
    {
      "path": "Videos/song.mp3",
      "ipfs_link": "QmXxx...",
      "type": "audio",
      "size": 4567890,
      "last_modified": "2025-05-23T10:00:00",
      "metadata": {
        "formatted_duration": "3:45"
      }
    }
  ]
}
```

Valeurs de `type` : `"audio"` (mp3/wav/ogg/m4a), `"video"`, `"image"`, `"document"`.  
AutoDJ filtre `type === "audio" && ipfs_link` pour construire la playlist.

---

## Voir aussi

- `Astroport.ONE/IA/bro_dm_daemon.sh` — daemon DM kind 4
- `Astroport.ONE/IA/UPlanet_IA_Responder.sh` — responder kind 1
- `Astroport.ONE/IA/process_youtube.sh` — téléchargement YouTube
- `Astroport.ONE/tools/nostr_node_intercom.py` — transport DM inter-node
- `Astroport.ONE/tools/nostr_send_secure_dm.py` — DM NIP-44 individuel
- `Astroport.ONE/tools/generate_ipfs_structure.sh` — génération manifest.json
- `sound-spot/src/portal/api/core/nip42.sh` — authentification MULTIPASS portail
- `sound-spot/src/portal/api/apps/yt_copy/run.sh` — endpoint vérification NIP-42 ytcopy
- `sound-spot/src/backend/audio/autodj.sh` — lecture uDRIVE manifest
