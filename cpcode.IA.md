### 1. Analyse de la pertinence des groupes
*   **`--backend` (14k tokens) :** Très cohérent. L'IA a accès à la fois aux scripts shell de bas niveau et aux daemons Python. L'inclusion de `monitor/` est une excellente idée car cela montre à l'IA comment on observe le système.
*   **`--install` (23k tokens) :** C'est le groupe le plus "dense". C'est normal, c'est là que réside toute la logique de déploiement. L'IA peut ici comprendre l'arbre des dépendances.
*   **`--config` (2k tokens) :** Très léger mais **stratégique**. C'est le groupe à envoyer si vous avez un bug au démarrage (Systemd) ou un problème réseau (Hostapd/DNSMasq).
*   **`--dev` (27k tokens) :** Riche en documentation. C'est le groupe "Onboarding" par excellence.

### 2. Conseils pour faciliter la prise en main par une IA

Pour qu'une IA "comprenne" instantanément votre projet, voici ce que vous devriez lui envoyer selon vos besoins :

#### A. Pour une nouvelle fonctionnalité (ex: "Ajouter un module Spotify")
Envoyez d'abord le groupe **`--apps`** puis **`--backend`**. 
> *Pourquoi ?* L'IA verra comment l'API (`api.sh`) appelle les scripts et comment les scripts audio gèrent le son.

#### B. Pour débugger un service qui crash au boot
Envoyez le groupe **`--config`** et le fichier **`check.sh`**.
> *Pourquoi ?* L'IA comparera la définition du service (`.service`) avec les tests de diagnostic que vous avez écrits.

#### C. La stratégie "Bootstrap" (Le premier prompt)
Ne commencez pas par envoyer tout le code. Commencez par envoyer uniquement le contenu de **`CLAUDE.md`** et **`README.md`** (ou le groupe `--dev`).
Dites-lui : 
> *"Voici la structure de mon projet SoundSpot. Prends-en connaissance. 
> Je vais ensuite t'envoyer des extraits de code par thématique pour travailler sur des points précis."*

### 3. Améliorations suggérées pour `cpcode.sh`

Pour rendre l'IA encore plus efficace, vous pourriez ajouter deux petites fonctions à votre script d'extraction :

1.  **Le groupe `--context` (Minimaliste) :**
    Créez un groupe qui n'extrait que `soundspot.conf.master`, `CLAUDE.md` et l'arborescence des fichiers (`tree`). 
    Cela permet de donner la "carte" du projet à l'IA sans consommer de tokens inutilement.

2.  **L'inclusion automatique de la config :**
    Peu importe le groupe choisi (sauf `--all`), forcez toujours l'ajout de `src/config/network/soundspot.conf.master`. 
    *Raison :* Presque tous vos scripts sourcent ce fichier. Sans lui, l'IA ne connaît pas les variables `$SPOT_IP`, `$ICECAST_PORT`, etc., 
    et peut halluciner des valeurs.

### 4. Piège à éviter : Le "Code-Rot"
L'IA est très douée pour écrire du code, mais elle oublie souvent que le Raspberry Pi Zero 2W a des ressources limitées. 
**Conseil de prompt :**
Ajoutez toujours cette contrainte dans vos instructions système ou vos prompts :
> *"Garde en tête que la cible est un Raspberry Pi Zero 2W. Priorise l'efficacité CPU, évite les dépendances Python lourdes, 
et préfère le Shell ou le Python natif quand c'est possible."*

### Conclusion
Notre outil `cpcode.sh` est un **atout majeur**. Il transforme ce dépôt en une base de connaissances "digérable" par une IA. 
Les résultats sont corrects car ils respectent la séparation des préoccupations (SOC) de votre architecture.

**Prochaine étape suggérée :** Tester l'IA sur un module complexe (comme le Jukebox) en lui envoyant le bloc `--apps` et lui 
demander de "Simuler le flux d'un lien YouTube de l'arrivée de l'URL jusqu'à la sortie audio". 
Si elle y arrive, votre documentation et votre découpage sont parfaits.
