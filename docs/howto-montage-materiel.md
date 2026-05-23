# Guide Pratique : Montage Électronique et Câblage

Ce document détaille le montage physique du *CyberCochon*. Il explique comment câbler le Nœud Maître (Hub) et le Nœud Énergie (Pi Zero) de manière sécurisée.
Pour la liste de courses exacte (références Amazon, prix, convertisseurs), référez-vous à la [Nomenclature Matérielle](reference-nomenclature.md).

---

## 1. Le Bus d'Énergie Solaire (12V)
C'est le cœur électrique du système.
1. **Panneau Solaire (100W)** ➔ Branché sur l'entrée PV du **Victron SmartSolar MPPT**.
2. **Batterie LiFePO4 (12.8V)** ➔ Branchée sur la sortie Batterie du MPPT.
3. **Boîtier à Fusibles (Vaskula)** ➔ Connecté sur le pôle Positif (+) de la batterie.
   - *Fusible 1 (5A)* ➔ Alimente le Convertisseur 5V du Nœud Maître.
   - *Fusible 2 (5A)* ➔ Alimente le Convertisseur 5V du Nœud Énergie.
   - *Fusible 3 (10A)* ➔ Alimente le Relais du Vidéoprojecteur.
   - *Fusible 4 (5A)* ➔ Alimente le Routeur 5G ZTE (via stabilisateur 12V).

---

## 2. Le Nœud Maître (Hub / Raspberry Pi 4 ou 5)
C'est le "Cerveau" audiovisuel.
- **Alimentation :** Convertisseur Step-Down (ex: QIQIAZI) 12V ➔ 5V/5A branché sur les pins 5V et GND, ou via le port USB-C.
- **Réseau 5G :** Câble Ethernet RJ45 entre le RPi et le routeur ZTE MC888.
- **Réseau Mesh :** Clé Wi-Fi Vemfay 5GHz branchée sur un port **USB 3.0 (Bleu)**.
- **Caméra :** Pi Camera Module 3 branchée sur le port CSI avec la nappe plate.
- **Audio (Radio FM) :** Câble Jack 3.5mm du RPi vers l'Émetteur FM 0.5W.
- **Vidéo (Vidéoprojecteur) :** Câble Micro-HDMI du RPi (port HDMI0, près de l'alim) vers le Nebula Capsule 3.
- **Relais Vidéoprojecteur :** Le fil de commande du Relais Giantdeer (pour couper l'alimentation USB-C 65W du projecteur) se branche sur la pin **GPIO 18** du RPi 4.

---

## 3. Le Nœud Énergie & Survie (Pi Zero 2W)
C'est le "BMS" (Battery Management System). Il surveille la batterie et coupe le courant en cas d'urgence.
- **Alimentation :** Convertisseur 12V ➔ 5V (3A suffisent) branché sur l'USB ou les pins.
- **Capteur de Tension (INA219 via I2C) :**
  - `VCC` ➔ Pin 1 (3.3V)
  - `GND` ➔ Pin 9 (GND)
  - `SDA` ➔ Pin 3 (GPIO 2 / SDA)
  - `SCL` ➔ Pin 5 (GPIO 3 / SCL)
  - `VIN+` (Gros bornier) ➔ Au pôle **+ (Positif) de la Batterie 12V**.
  *⚠️ DANGER : Ne faites passer AUCUN courant d'alimentation dans le `VIN-` de l'INA219. Le shunt résiste à 3.2A max, le projecteur le ferait fondre. Utilisez-le en mode VOLTMÈTRE uniquement (un seul fil sur VIN+).*
- **Relais de Survie (Coupure Générale) :**
  - Le fil de commande (`IN`) du relais se branche sur la pin **GPIO 17**.
  - Lorsque la batterie passe sous 20%, le Pi Zero lance la procédure de *shutdown* de l'essaim, puis met le GPIO 17 sur LOW, ce qui ouvre le circuit 12V et coupe physiquement l'énergie de tous les Raspberry Pi.

---

## Schéma Logique du Câblage

```text
[ BATTERIE 12V ] 
   ├──(Fusible 10A)──[ RELAIS 12V (GPIO 18) ]────(Prise USB-C PD)────► Nebula Projecteur
   │
   ├──(Fusible 5A)───[ CONVERTISSEUR 5V/5A ]─────► RPi 4 (Maître)
   │                                                 ├─ USB3: Clé Vemfay (Mesh)
   │                                                 ├─ HDMI: Nebula Projecteur
   │                                                 └─ Jack: Émetteur FM
   │
   ├──(Fusible 5A)───[ STABILISATEUR 12V ]───────► Routeur 5G ZTE
   │
   └──(Fil Capteur)──► INA219 (VIN+)
                         │ (I2C)
                     [ RPi Zero (Nœud Énergie) ] ──(GPIO 17)──► [ RELAIS DE SURVIE ]

