#!/bin/bash
# ════════════════════════════════════════════════════════════════════
#  api/apps/hello/run.sh — Module exemple / template de démarrage
# ════════════════════════════════════════════════════════════════════
#
#  COMMENT CRÉER UN NOUVEAU MODULE
#  ────────────────────────────────
#  1. Copier ce dossier :  cp -r api/apps/hello api/apps/mon_module
#  2. Renommer run.sh si besoin (on l'appelle toujours run.sh par convention).
#  3. Modifier le code ci-dessous.
#  4. Tester depuis un terminal :
#       QUERY_STRING="action=mon_module" bash api.sh
#  5. Tester depuis le portail (navigateur) :
#       http://192.168.10.1/api.sh?action=mon_module
#
#  CONTEXTE D'EXÉCUTION
#  ─────────────────────
#  Ce script est lancé par api.sh via `bash "$APP"`.
#  Les variables suivantes sont déjà exportées et disponibles :
#
#    SPOT_NAME      — SSID WiFi du nœud (ex: ZICMAMA)
#    SPOT_IP        — IP du RPi maître (192.168.10.1)
#    SNAPCAST_PORT  — Port Snapcast (1704)
#    ICECAST_PORT   — Port Icecast (8111)
#    CLOCK_MODE     — bells | silent
#    INSTALL_DIR    — /opt/soundspot
#
#  Variables CGI injectées par lighttpd :
#    QUERY_STRING   — paramètres GET (ex: action=hello&name=World)
#    REMOTE_ADDR    — IP du client
#    REQUEST_METHOD — GET | POST
#    CONTENT_LENGTH — longueur du body POST
#
#  CONVENTIONS DE SORTIE
#  ──────────────────────
#  • NE PAS ré-émettre les entêtes HTTP (api.sh les a déjà émis).
#  • Toujours retourner du JSON valide.
#  • Pour les erreurs : {"error":"code_erreur","hint":"message humain"}
#  • Pour le succès  : {"status":"ok", …}
#
#  LIRE UN PARAMÈTRE GET
#  ──────────────────────
#  NAME=$(echo "$QUERY_STRING" | grep -oP '(?<=name=)[^&]+' | head -1)
#
#  LIRE LE BODY D'UN POST
#  ────────────────────────
#  read -r -n "${CONTENT_LENGTH:-0}" POST_DATA 2>/dev/null || true
#  VAL=$(printf '%s' "$POST_DATA" | grep -oP '(?<=key=)[^&]+' | head -1)
#
#  DÉCODER UN PARAMÈTRE URL-ENCODÉ (ex: espaces → %20)
#  ─────────────────────────────────────────────────────
#  DECODED=$(python3 -c "import sys,urllib.parse; print(urllib.parse.unquote_plus(sys.stdin.read().strip()))" <<< "$VAL")
#
# ════════════════════════════════════════════════════════════════════

# Lire un paramètre GET optionnel (ex: /api.sh?action=hello&name=Alice)
NAME=$(echo "$QUERY_STRING" | grep -oP '(?<=name=)[^&]+' | head -1)
NAME="${NAME:-Monde}"

# Heure courante sur le nœud
NOW=$(date '+%Y-%m-%d %H:%M:%S')

# Réponse JSON
cat <<JSON
{
  "status": "ok",
  "message": "Bonjour ${NAME} depuis ${SPOT_NAME} !",
  "node": {
    "spot_ip":   "${SPOT_IP}",
    "spot_name": "${SPOT_NAME}",
    "clock_mode":"${CLOCK_MODE}",
    "install_dir":"${INSTALL_DIR}"
  },
  "server_time": "${NOW}",
  "hint": "Remplacez ce fichier par votre logique dans api/apps/<votre_module>/run.sh"
}
JSON
