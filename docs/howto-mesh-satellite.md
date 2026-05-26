# Guide Pratique : Ajouter un Satellite au réseau Mesh

Pour étendre la portée musicale sans tirer de câbles, ajoutez des Satellites (Raspberry Pi Zero 2W).
Chaque satellite reçoit le flux Snapcast du Maître et le diffuse sur son propre haut-parleur Bluetooth.

## Prérequis

- Le Nœud Maître doit être allumé et opérationnel.
- Un RPi Zero 2W équipé d'un dongle USB Wi-Fi 5 GHz (pour le mesh étendu) et d'un adaptateur BT.

## Topologie réseau

Un satellite emprunte **l'un ou l'autre** de ces chemins selon sa position et la qualité du signal :

```
                            ┌── CHEMIN A : signal ZICMAMA correct ──┐
                            │  wlan0 → AP ZICMAMA → 192.168.10.1    │
Satellite                   │                                         ▼
  wlan0 ─── ZICMAMA (2,4GHz)─┤                               Snapserver :1704
  wlan1 ─── CYBERCOCHON_MESH ─┤
             (ad-hoc 5GHz)  │  wlan1 → bat0 → 10.200.0.1           ▲
                            └── CHEMIN B : signal faible ou absent ──┘
```

Le chemin est choisi **automatiquement** par `find_master.sh` à chaque démarrage du service Snapcast.

## Comment le Satellite choisit son chemin

La logique de routage est la suivante, dans cet ordre :

| Priorité | Condition | Chemin emprunté |
|----------|-----------|----------------|
| 1 | Connecté à ZICMAMA **et** RSSI ≥ -70 dBm | AP directe → `192.168.10.1` |
| 2 | bat0 actif **et** `10.200.0.1` joignable | Mesh B.A.T.M.A.N. → `10.200.0.1` |
| 3 | mDNS disponible | `soundspot-NOM.local` |
| 4 | MASTER_HOST configuré | Nom ou IP fixe |
| 5 | Aucun des précédents | Scan du port 1704 sur le sous-réseau |

> **Seuil RSSI -70 dBm** : en-dessous de ce seuil, le signal ZICMAMA est trop instable
> pour un flux audio continu. Le satellite bascule alors automatiquement sur le mesh.
> Ce seuil est modifiable dans `find_master.sh` (variable `RSSI_THRESHOLD`).

## Procédure d'installation

```bash
# 1. Flasher une carte SD (Hostname: soundspot-sat1, SSH activé)
# 2. Brancher le dongle USB Wi-Fi 5 GHz
ssh pi@soundspot-sat1.local

git clone https://github.com/papiche/sound-spot
cd sound-spot
sudo bash deploy_on_pi.sh --satellite
```

L'installeur vous demande :
- SSID upstream (réseau qo-op ou nom de ZICMAMA)
- MAC de l'enceinte Bluetooth à brancher sur ce satellite

## Le réseau mesh CYBERCOCHON_MESH

Le dongle USB 5 GHz forme automatiquement un réseau B.A.T.M.A.N.-adv en mode ad-hoc IBSS,
canal 36 (5 GHz), nommé **CYBERCOCHON_MESH**. Le Maître prend l'IP `10.200.0.1/16` sur `bat0`.
Les satellites reçoivent une IP dérivée de leur adresse MAC (`10.200.X.Y/16`).

Ce réseau transporte :
- **Le flux Snapcast** (port 1704) pour les satellites hors de portée ZICMAMA
- Les ordres de flotte NOSTR (Kind 9, port 9999)
- Le swarm IPFS de la constellation
- La découverte via mDNS (`soundspot.local` sur toutes les interfaces)

B.A.T.M.A.N.-adv opère à la couche 2 : le routage multi-saut est automatique. Un satellite
qui ne voit qu'un autre satellite peut tout de même atteindre le Maître par rebond.

**Portée typique :** 50-150 m en extérieur (adaptateur directif → 300+ m).

## Voir les satellites sur le portail

Sur le portail du Maître (`http://192.168.10.1/mesh.html`), la page **Radar Mesh** affiche :

- Les voisins directs bat0 (1 saut, couche 2)
- La topologie globale avec la qualité de transmission TQ (0-255)
- **Les clients Snapcast actifs** — incluant aussi bien les satellites via mesh que les visiteurs via ZICMAMA

La page se rafraîchit toutes les 5 secondes.

## Buffer et latence

Le satellite est configuré avec un buffer Snapcast de **3 secondes** pour absorber les variations
de latence. L'audio reste synchronisé avec le Maître à ±1 ms près, quel que soit le chemin.

## Dépannage

| Symptôme | Cause probable | Solution |
|----------|---------------|---------|
| Aucun son sur le satellite | Maître non trouvé | `cat /run/soundspot_master.env` — vérifie l'IP résolue |
| Son présent mais décalé | Buffer trop court | Augmenter `latency` dans `snapclient.conf` |
| RSSI trop faible, mesh non actif | Dongle USB absent ou pilote manquant | `ip link show wlan1` + `dmesg | grep 88x2bu` |
| bat0 sans IP | Mesh démarré mais pas d'IP | `systemctl status soundspot-mesh` |
| `10.200.0.1` injoignable | Maître hors de portée mesh | Vérifier `batctl o` (TQ des voisins) |
| mDNS lent | avahi-daemon non démarré | `systemctl status avahi-daemon` |

---

Voir aussi : [Architecture](explanation-architecture.md) · [Modes Picoport](reference-picoport-modes.md) · [Diagnostic](howto-logs-diagnostic.md)
