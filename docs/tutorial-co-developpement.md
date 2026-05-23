# Tutoriel : Co-développer le SoundSpot (Workflow Live)

L'écosystème SoundSpot a été pensé pour être modifié "en live" sur le terrain, sans temps de compilation.

## 1. Activer l'Environnement de Développement (Workspace)
Par défaut, le code s'exécute dans `/opt/soundspot`. Pour le modifier sans rien casser :
1. Cloner/Préparer votre Workspace : `ss-dev ma-branche-test`
2. Le système crée un lien symbolique : `/var/www/html` pointera désormais vers `~/.zen/workspace/sound-spot/src/portal/`.

## 2. Développer le Frontend (Portail HTML/JS/CSS)
Modifiez les fichiers dans `src/portal/`.
*Magie :* Actualisez simplement la page web sur votre téléphone. Les modifications sont immédiates ! Aucun serveur à redémarrer.

## 3. Développer le Backend (Modules API en Bash)
Les modules API se trouvent dans `src/portal/api/apps/`.
Pour créer un nouveau module :
1. Copiez le module "Hello" : `cp -r src/portal/api/apps/hello src/portal/api/apps/mon_module`
2. Modifiez le `run.sh` pour renvoyer du JSON.
3. Testez votre code directement depuis le terminal du Pi : `ss-api mon_module`
4. Testez depuis le navigateur : `http://192.168.10.1/api.sh?action=mon_module`

## 4. Modifier les Démons Système (Python/Audio)
Si vous modifiez `mon-oeil.py`, `battery_monitor.py` ou des scripts dans `src/backend/`, la modification dans le Workspace ne suffit pas. Vous devez déployer et redémarrer les services.
Tapez simplement l'alias : `ss-reload`
*(Cela applique vos modifications backend et redémarre les processus impactés sans couper l'AP WiFi).*

## 5. Revenir en Production
Une fois le festival terminé, remettez le système dans un état "en dur" (sans lien symbolique) :
Tapez : `ss-prod`
*(Cela supprime le lien symbolique du portail et recopie les fichiers de votre Workspace vers `/opt/soundspot`. Le système repart en production autonome, sans dépendance à votre répertoire de développement.)*

## Récapitulatif des alias de développement

| Alias | Action |
|-------|--------|
| `ss-dev <branche>` | Active le mode dev — lien symbolique du portail vers le Workspace |
| `ss-api <module>` | Teste un module API directement depuis le terminal du Pi |
| `ss-center` | Ouvre l'interface interactive de gestion des processus (Start/Stop/Logs) |
| `ss-reload` | Déploie les modifications backend et redémarre les services impactés |
| `ss-prod` | Repasse en production — supprime les liens symboliques |
