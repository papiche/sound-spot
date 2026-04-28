# Bench de référence — Astroport.ONE tools sur Picoport

Résultats de `test/test_astroport_tools.sh` sur différentes architectures.
Sert à calibrer la grille `crypto_score` dans `heartbox_analysis.json`.

---

## Grille crypto_score

Le score est dérivé de `keygen_duniter_ms` (algorithme scrypt, RAM-hard) —
mesure fidèle de la vitesse CPU+RAM d'une station pour les opérations
cryptographiques Ğ1/Nostr/IPFS.

| Score | keygen_duniter | Profil matériel | Rôle UPlanet |
|-------|---------------|-----------------|--------------|
| 10 | < 150 ms | Serveur GPU / Intel i9+ | 🔥 Brain |
| 8 | 150 – 300 ms | PC bureautique moderne | ⚡ Standard |
| 6 | 300 – 600 ms | RPi 4 / ARM Cortex-A55 | ⚡ Standard léger |
| 4 | 600 – 1 200 ms | RPi 3B / ARM Cortex-A53 | 🌿 Light |
| 2 | 1 200 – 2 500 ms | RPi 3A+ / Orange Pi Zero | 🌿 Light |
| 1 | > 2 500 ms | **RPi Zero 2W** / ARM Cortex-A53 @ 1 GHz (1 seul cœur utile pour scrypt) | 🌿 Light |

> Le RPi Zero 2W est toujours `crypto_score=1` et `🌿 Light` —
> il consomme les services IA du swarm, il ne les produit pas.

---

## Mesures de référence

### Station nexus (PC Intel i7, Ubuntu 22.04)

| Fonction | Temps |
|---|---|
| keygen_duniter | 245 ms |
| keygen_nostr | 221 ms |
| keygen_ipfs | 216 ms |
| keygen_nsec | 239 ms |
| ss58_v1_to_ss58 | 33 ms |
| ss58_reverse | 39 ms |
| g1balance_rpc | 1 087 ms |
| **TOTAL BENCH** | **2 438 ms** |

**crypto_score : 8 / 10** — ⚡ Standard

---

### Picoport soundspot (RPi Zero 2W — ARM Cortex-A53 @ 1 GHz, 512 Mo RAM)

Mesuré le 2026-04-18.

| Fonction | Temps | Note |
|---|---|---|
| keygen_duniter | **6 111 ms** | scrypt single-thread sur 512 Mo RAM |
| keygen_nostr | 4 817 ms | |
| keygen_ipfs | 2 949 ms | |
| keygen_nsec | 3 120 ms | |
| ss58_v1_to_ss58 | 336 ms | overhead démarrage Python sur ARM |
| ss58_reverse | 315 ms | |
| ss58_passthrough | 373 ms | |
| ss58_intrusion | 400 ms | |
| g1balance_rpc | **57 749 ms** | nœud Duniter RPC lent (~58s) — voir note réseau |
| **TOTAL BENCH** | **81 628 ms** | |

**crypto_score : 1 / 10** — 🌿 Light

**Note réseau** : `g1balance_rpc=57s` indique que le nœud Duniter RPC sélectionné
était lent au moment du test (réseau WiFi du lieu + nœud distant peu réactif).
En conditions normales sur réseau filaire, la latence RPC devrait être < 5 s.
`duniter_getnode.sh` sélectionne dynamiquement le meilleur nœud disponible —
relancer le test avec une bonne connectivité.

---

## Interprétation pour heartbox / 12345.json

```json
{
  "picoport_bench": {
    "crypto_score": 1,
    "network_ms": 57749,
    "timings_ms": {
      "keygen_duniter": 6111,
      "g1balance_rpc": 57749,
      "total_bench": 81628
    }
  }
}
```

Le `crypto_score` permet à `astrosystemctl` de décider automatiquement :
- `score ≤ 4` → `🌿 Light` : ne pas proposer de services IA locaux,
  utiliser `astrosystemctl connect ollama` pour déléguer au swarm
- `score 5-10` → peut héberger des services selon la RAM disponible

Le `network_ms` reflète la qualité de la connexion Internet du lieu —
utile pour estimer si les tunnels IPFS P2P seront utilisables.
