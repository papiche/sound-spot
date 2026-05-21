# Explication : Architecture et Survie du CyberCochon

Le SoundSpot n'est pas un simple hotspot. C'est une architecture souveraine conçue pour l'autonomie en milieu hostile (Festivals, Off-grid).

## Le paradoxe du Dual-Wi-Fi (Mesh vs AP)
Pourquoi utiliser deux cartes Wi-Fi ? 
Si le trafic audio (Snapcast) et le trafic des visiteurs (Portail) se croisent sur la même puce Wi-Fi, les paquets entrent en collision. Nous utilisons la puce interne (2.4 GHz) pour le hotspot public **ZICMAMA**, et un dongle USB externe (5 GHz) pour le réseau caché **B.A.T.M.A.N.-adv**. B.A.T.M.A.N. opère à la couche 2 (MAC) : pour les applications, tous les CyberCochons croient être branchés sur le même câble Ethernet géant.

## La Flotte NOSTR et le Suicide Énergétique
Comment éteindre proprement 5 ordinateurs sans écran ni réseau internet ?
Nous utilisons le protocole **NOSTR (Kind 9)** en réseau local (port `9999`). 
Le nœud "Énergie" lit l'état de la batterie via un capteur I2C INA219. Si la tension chute sous un seuil critique, il émet un message chiffré (Clé Amiral) sur la flotte. Tous les nœuds informatiques s'éteignent proprement (halt). Le nœud Énergie attend 15 secondes supplémentaires, puis coupe le relais physique.
