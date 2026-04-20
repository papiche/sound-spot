# Développement SoundSpot sur Picoport

## Principe

```
GitHub main (stable)
    │
    ├── ~/.zen/workspace/sound-spot/   ← dépôt local sur le Pi
    │       └── src/portal/           ← sources vives du portail
    │
    └── /opt/soundspot/portal  →  lien symbolique  →  src/portal/
                ↑
        /var/www/html (lien symlink lighttpd)
```

En mode dev, modifier un fichier dans `src/portal/` = visible
**immédiatement** au rechargement de la page. Aucun déploiement.

---

## Première fois sur un Picoport

```bash
# Depuis n'importe quel dossier contenant le dépôt sound-spot :
bash src/dev/dev_setup.sh [nom-de-branche]

# Exemples :
bash src/dev/dev_setup.sh dev-alice-portal
bash src/dev/dev_setup.sh dev-yt-async
bash src/dev/dev_setup.sh                    # → dev-$(hostname)
```

Après ça :
- Le dépôt est dans `~/.zen/workspace/sound-spot`
- La branche est créée et checkoutée
- `/opt/soundspot/portal` pointe vers `~/.zen/workspace/sound-spot/src/portal`
- Le groupe `soundspot` donne à `www-data` l'accès en lecture

---

## Workflow quotidien

```bash
cd ~/.zen/workspace/sound-spot

# 1. Vérifier où on en est
bash src/dev/dev_switch.sh

# 2. Créer un nouveau module
mkdir -p src/portal/api/apps/mon_module
cp src/portal/api/apps/hello/run.sh src/portal/api/apps/mon_module/run.sh
# → éditer le fichier
# → tester sur http://192.168.10.1/api.sh?action=mon_module

# 3. Tester le portail live
# http://192.168.10.1/   (depuis n'importe quel téléphone sur le WiFi)

# 4. Committer
git add src/portal/
git commit -m 'feat(portal): ajouter module mon_module'
git push origin dev-alice-portal

# 5. Ouvrir une Pull Request sur GitHub
# → merge dans main par l'opérateur du projet
```

---

## Changer de branche

```bash
# Tester la branche d'un autre contributeur
bash src/dev/dev_switch.sh dev-bob-nostr

# Revenir sur sa branche
bash src/dev/dev_switch.sh dev-alice-portal

# Suivre main en production
bash src/dev/dev_switch.sh main
```

Le changement de branche est **instantané** : lighttpd recharge
la configuration sans couper le stream Snapcast.

---

## Revenir en mode production (copie physique)

```bash
# Remet /opt/soundspot/portal en copie réelle de main
# (plus de dépendance au home directory)
bash src/dev/dev_restore.sh
```

Utiliser avant :
- Une mise en production "propre" (nœud sans développeur actif)
- Un changement d'utilisateur sur le Pi
- Un `deploy_on_pi.sh` depuis zéro

---

## Ajouter un module (guide rapide)

```bash
# Copier le template
cp -r src/portal/api/apps/hello src/portal/api/apps/mon_module

# Éditer
nano src/portal/api/apps/mon_module/run.sh

# Tester depuis le terminal
QUERY_STRING="action=mon_module" \
SPOT_NAME="TEST" SPOT_IP="127.0.0.1" ICECAST_PORT="8111" \
SNAPCAST_PORT="1704" CLOCK_MODE="bells" INSTALL_DIR="/opt/soundspot" \
bash src/portal/api.sh

# Tester depuis le navigateur (sur le WiFi du spot)
# http://192.168.10.1/api.sh?action=mon_module
```

---

## Variables d'environnement héritées dans les modules

| Variable        | Valeur typique       | Description                   |
|-----------------|----------------------|-------------------------------|
| `SPOT_NAME`     | `ZICMAMA`            | SSID WiFi du nœud             |
| `SPOT_IP`       | `192.168.10.1`       | IP du RPi maître              |
| `SNAPCAST_PORT` | `1704`               | Port Snapcast                 |
| `ICECAST_PORT`  | `8111`               | Port Icecast                  |
| `CLOCK_MODE`    | `bells` ou `silent`  | État du clocher               |
| `INSTALL_DIR`   | `/opt/soundspot`     | Racine d'installation         |
| `REMOTE_ADDR`   | `192.168.10.42`      | IP du client (CGI lighttpd)   |
| `QUERY_STRING`  | `action=status`      | Paramètres GET                |
| `CONTENT_LENGTH`| `42`                 | Longueur du body POST         |

---

## Structure du dépôt de travail

```
~/.zen/workspace/sound-spot/     ← même structure que le dépôt GitHub
    ├── deploy_on_pi.sh
    ├── src/
    │   ├── dev/
    │   │   ├── dev_setup.sh    ← ce workflow
    │   │   ├── dev_switch.sh
    │   │   └── dev_restore.sh
    │   ├── install/            ← modules d'installation (ne pas toucher)
    │   ├── picoport/           ← outils Astroport.ONE
    │   └── portal/             ← ici on développe !
    │       ├── index.html
    │       ├── api.sh
    │       └── api/
    │           ├── core/       ← fonctions essentielles
    │           └── apps/       ← vos modules ici
    └── .git/
```

Le dépôt est dans `~/.zen/workspace/` pour être visible des outils
Astroport.ONE (`astrosystemctl`, `ai`, `asys*`).

---

## Travailler sur des Forks et mettre à jour le Backend

Contrairement au portail (frontend) qui se met à jour instantanément grâce au lien symbolique `/var/www/html`, le **backend** (les daemons `.py`, les scripts audio `.sh`) est exécuté depuis le dossier isolé `/opt/soundspot/`.

Si vous :
- Testez le fork d'un autre dev via un `git remote add ...` puis `git pull`
- Modifiez un daemon Python (`presence_detector.py`, etc.)
- Touchez aux scripts de l'infrastructure backend

Vous n'avez pas besoin de relancer le gros `deploy_on_pi.sh`. Utilisez simplement la commande de hot-reload :

```bash
# Applique les modifications backend instantanément (copie + restart services)
ss-reload

# (Ce qui équivaut à lancer :)
sudo bash ~/.zen/workspace/sound-spot/src/dev/dev_reload.sh
