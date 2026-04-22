# Politique de Sécurité (Security Policy)

L'écosystème **SoundSpot / UPlanet** prend la sécurité et la souveraineté des données très au sérieux. Bien qu'il s'agisse d'un réseau ouvert destiné à l'espace public, l'architecture est conçue pour isoler les nœuds, protéger les données privées et résister aux attaques réseau.

## Versions Supportées

| Version | Branche | Statut |
| ------- | ------- | ------ |
| v2.x (Picoport) | `main` | ✅ Supporté (Corrections de sécurité actives) |
| v1.x (Legacy) | `v1` | ❌ Non supporté |

## Architecture de Sécurité (Pour les Auditeurs)

SoundSpot n'est pas un point d'accès WiFi classique. Voici les mécanismes de défense embarqués :

### 1. Le WiFi Ouvert (DMZ Isolée)
Le point d'accès WiFi généré par la station (`ZICMAMA`) est intentionnellement ouvert pour permettre la connexion du grand public sans friction.
   - **Isolation (Iptables/IPSet) :** Le réseau visiteur (`uap0`) est strictement séparé du réseau amont (`wlan0`). Le script `soundspot-firewall.sh` rejette tout trafic (`REJECT`) par défaut.
   - **Baux temporaires :** L'accès Internet n'est ouvert qu'après validation du portail captif, via un système de liste blanche `ipset` expirant automatiquement après 900 secondes (15 minutes).

### 2. Identité Cryptographique (Picoport)
Les services sensibles (Paiements Ğ1, Publications NOSTR, Tunnels IA) ne sont pas exposés sur le portail captif public.
   - Le nœud ne se connecte pas à l'IPFS public. Il utilise une `swarm.key` privée (UPlanet ORIGIN) et purge les bootstraps publics. 
   - Les clés de signature (`.ipns`, `dunikey`, `NSEC`) sont générées de manière déterministe via le hash matériel/SSH (`picoport_init_keys.sh`) et ne quittent jamais le nœud.
   - Les communications inter-nœuds (Swarm) utilisent les tunnels chiffrés **IPFS Libp2p**.

3. **Exécution des Services (Principe du moindre privilège) :**
   - Les services audio (PipeWire, Snapclient), IPFS, et UPassport tournent sous un utilisateur non-root (`pi` ou `$SOUNDSPOT_USER`).
   - Le serveur web (`lighttpd`) tourne sous `www-data` et interagit avec le système uniquement via des scripts sudoers restreints sans mot de passe (ex: `set_clock_mode.sh`). Des règles `sudoers` très spécifiques et granulaires lui permettent d'agir sur l'horloge et les baux DHCP sans compromettre le système d'exploitation.

## Signaler une Vulnérabilité

Si vous découvrez une vulnérabilité de sécurité au sein du code SoundSpot, d'Astroport.ONE ou de la configuration système générée, **ne créez pas d'Issue publique sur GitHub**.

Veuillez nous envoyer un rapport détaillé en privé à l'adresse suivante :
📧 **support+security@qo-op.com** (ou contact direct aux mainteneurs de la Ğ1FabLab).

Nous nous engageons à accuser réception de votre rapport dans un délai de 72 heures et à travailler avec vous pour émettre un correctif rapidement.

## Audits et Améliorations

Nous invitons les chercheurs en sécurité et les hackers *white hat* à auditer les aspects suivants :
1. Robustesse du pare-feu `iptables` face à des attaques par MAC-spoofing depuis le réseau captif.
2. Fuites potentielles de données via l'API locale (`api.sh`).
3. Résilience de `snapserver` face à des inondations de paquets multicast/TCP.

*Merci de contribuer à la robustesse du réseau Libre UPlanet !*