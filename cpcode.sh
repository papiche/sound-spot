#!/bin/bash
# ═════════════════════════════════════════════════════════════════════════════
#  cpcode.sh — Extracteur de contexte autonome (SoundSpot Edition)
# ═════════════════════════════════════════════════════════════════════════════
#  Génère des blocs de code thématiques pour aider l'IA à comprendre
#  l'architecture de SoundSpot. Zéro dépendance, 100% autonome.
# ═════════════════════════════════════════════════════════════════════════════

# On retire le '-u' qui fait planter l'évaluation des tableaux vides en Bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Aide ───────────────────────────────────────────────────────────────────
show_help() {
    cat <<'EOF'
Usage : ./cpcode.sh GROUP1 [GROUP2 ...] [options...]

Groupes disponibles (segmentation logique) :
  --install    Scripts de déploiement (maître/satellite) et environnement
  --backend    Logique métier : audio (pipewire/icecast), système (BT), cam/vidéo
  --frontend   Interface web (html, css, js) et routeur API core (api.sh)
  --apps       Modules API additionnels (dossier apps)
  --picoport   Nœud P2P : IPFS, Swarm Sync, UPassport
  --config     Unités systemd et fichiers de conf (.conf, .service)
  --dev        Outils de debug, tests, benchmarks et documentation
  --all        Extraction complète de tout le code du projet

Options :
  --json          Sortie au format JSON (pour outillage avancé)
  --maxfilesize N Limite la taille des fichiers extraits en octets (ex: 51200)

Exemples :
  ./cpcode.sh --backend
  ./cpcode.sh --apps --frontend --config
EOF
    exit 0
}

GROUPS=()
JSON_MODE=false
MAX_FILE_SIZE=0

# ── Parsing des arguments ──────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --install|--backend|--frontend|--apps|--picoport|--config|--dev|--all) 
            GROUPS+=("$arg") ;;
        --json) JSON_MODE=true ;;
        --maxfilesize) MAX_FILE_SIZE="$2"; shift ;;
        --maxfilesize=*) MAX_FILE_SIZE="${arg#*=}" ;;
        --help|-h) show_help ;;
    esac
done

[ ${#GROUPS[@]} -eq 0 ] && show_help

# ── Tableau de déduplication ───────────────────────────────────────────────
declare -A FILES_LIST

# Fonction pour ajouter intelligemment des fichiers ou des dossiers
add_target() {
    local target="$1"
    
    # Si le globbing échoue (ex: *.md qui ne trouve rien), le texte littéral arrive ici
    [ ! -e "$target" ] && return 0

    # Si c'est un dossier, on cherche récursivement les fichiers texte
    if [ -d "$target" ]; then
        while IFS= read -r f; do
            # Exclusion des dossiers cachés (ex: .git) et fichiers binaires/audio
            if [[ ! "$f" =~ /\.[^/]+$ ]] && [[ ! "$f" =~ \.(wav|png|jpg|mp3|zip|gz|tar|pyc)$ ]]; then
                # Vérification rapide si c'est bien du texte
                if grep -Iq . "$f" 2>/dev/null; then
                    FILES_LIST["$f"]=1
                fi
            fi
        done < <(find "$target" -type f 2>/dev/null)
        
    # Si c'est un fichier direct
    elif [ -f "$target" ]; then
        if grep -Iq . "$target" 2>/dev/null; then
            FILES_LIST["$target"]=1
        fi
    fi
}

# ── Routage des Groupes ────────────────────────────────────────────────────
for GROUP in "${GROUPS[@]}"; do
    case "$GROUP" in
        --install)
            echo "Cible : Installation & Déploiement" >&2
            add_target "deploy_on_pi.sh"
            add_target "dj_mixxx_setup.sh"
            add_target "setup_uninstall.sh"
            add_target "check.sh"
            add_target "cpcode.sh"
            for f in src/install_*.sh; do add_target "$f"; done
            add_target "src/install"
            ;;
        --backend)
            echo "Cible : Backend (Audio, Video, System)" >&2
            add_target "src/backend"
            add_target "monitor"
            add_target "src/backend/system/bt_manage.sh"
            add_target "src/backend/system/bt_update.sh"
            add_target "src/backend/system/log.sh"
            add_target "code_reload.sh"
            ;;
        --frontend)
            echo "Cible : Frontend (Portail Captif)" >&2
            for f in src/portal/*.html src/portal/*.js src/portal/*.sh src/portal/*.css; do add_target "$f"; done
            add_target "src/portal/api/core"
            ;;
        --apps)
            echo "Cible : API & Apps" >&2
            add_target "src/portal/api.sh"
            add_target "src/portal/api/apps"
            ;;
        --picoport)
            echo "Cible : Picoport & Swarm" >&2
            add_target "src/picoport"
            ;;
        --config)
            echo "Cible : Configurations & Systemd" >&2
            add_target "src/config"
            add_target "src/templates"
            add_target "src/wpa_supplicant.conf"
            ;;
        --dev)
            echo "Cible : Développement & Docs" >&2
            add_target "src/dev"
            add_target "test"
            for f in *.md; do add_target "$f"; done
            ;;
        --all)
            echo "Cible : Projet Complet" >&2
            add_target "src"
            add_target "monitor"
            add_target "test"
            for f in *.sh *.md *.html *.js *.py *.conf; do add_target "$f"; done
            ;;
    esac
done

if [ ${#FILES_LIST[@]} -eq 0 ]; then
    echo "Erreur : Aucun fichier trouvé pour les groupes spécifiés." >&2
    exit 1
fi

# ── Génération de la Sortie ────────────────────────────────────────────────
MOATS=$(date -u +"%Y%m%d%H%M%S%4N")
FINAL_OUT="/tmp/ss_context_${MOATS}.txt"
[ "$JSON_MODE" = true ] && FINAL_OUT="/tmp/ss_context_${MOATS}.json"

> "$FINAL_OUT"
JSON_COMMA=""

if $JSON_MODE; then echo "{" >> "$FINAL_OUT"; echo '  "files": [' >> "$FINAL_OUT"; fi

# Tri alphabétique des fichiers pour un rendu constant
mapfile -t SORTED_FILES < <(printf "%s\n" "${!FILES_LIST[@]}" | sort)

for FILE in "${SORTED_FILES[@]}"; do
    FILENAME=$(basename "$FILE")
    EXT="${FILENAME##*.}"
    
    # Langage Markdown adapté selon l'extension
    case "$EXT" in
        py) md_lang="python" ;;
        html) md_lang="html" ;;
        js) md_lang="javascript" ;;
        css) md_lang="css" ;;
        json) md_lang="json" ;;
        md) md_lang="markdown" ;;
        service|conf|env) md_lang="ini" ;;
        *) md_lang="bash" ;; # par défaut
    esac

    # Gestion de la taille max
    if [ "$MAX_FILE_SIZE" -gt 0 ]; then
        FILE_BYTES=$(wc -c < "$FILE")
        CONTENT=$(head -c "$MAX_FILE_SIZE" "$FILE")
        if [ "$FILE_BYTES" -gt "$MAX_FILE_SIZE" ]; then
            CONTENT+=$'\n'"[... TRONQUÉ : ${FILE_BYTES} octets → max ${MAX_FILE_SIZE} ...]"
        fi
    else
        CONTENT=$(cat "$FILE")
    fi

    if $JSON_MODE; then
        CONTENT_JSON=$(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$CONTENT")
        echo "${JSON_COMMA}    {" >> "$FINAL_OUT"
        echo "      \"path\": \"$FILE\"," >> "$FINAL_OUT"
        echo "      \"filename\": \"$FILENAME\"," >> "$FINAL_OUT"
        echo "      \"content\": $CONTENT_JSON" >> "$FINAL_OUT"
        echo "    }" >> "$FINAL_OUT"
        JSON_COMMA=","
    else
        {
            echo "Chemin : $FILE"
            echo "Titre : $FILENAME"
            echo ""
            echo "\`\`\`$md_lang"
            echo "$CONTENT"
            echo "\`\`\`"
            echo ""
        } >> "$FINAL_OUT"
    fi
done

if $JSON_MODE; then echo '  ]' >> "$FINAL_OUT"; echo "}" >> "$FINAL_OUT"; fi

# ── Copie dans le presse-papiers et Affichage ──────────────────────────────
COPIED=false
if ! $JSON_MODE; then
    if [ -n "${DISPLAY:-}" ] && command -v xclip &>/dev/null; then
        cat "$FINAL_OUT" | xclip -selection clipboard 2>/dev/null && COPIED=true
    elif [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy &>/dev/null; then
        cat "$FINAL_OUT" | wl-copy 2>/dev/null && COPIED=true
    elif command -v pbcopy &>/dev/null; then
        cat "$FINAL_OUT" | pbcopy 2>/dev/null && COPIED=true
    fi
    
    TOTAL_CHARS=$(wc -c < "$FINAL_OUT" 2>/dev/null || echo 0)
    TOTAL_TOKENS=$(( TOTAL_CHARS / 4 ))
    
    if [ "$COPIED" = true ]; then
        echo -e "\n✅ Contenu extrait (${#FILES_LIST[@]} fichiers) et copié dans le presse-papiers !" >&2
    else
        echo -e "\n⚠️ Extraction terminée (${#FILES_LIST[@]} fichiers), mais copie dans le presse-papiers impossible." >&2
    fi
    
    echo "=== Fichier final : ${TOTAL_CHARS} chars (~${TOTAL_TOKENS} tokens) ===" >&2
    echo "Résultat écrit dans : $FINAL_OUT"
else
    # Mode JSON : on crache sur Stdout pour permettre l'usage par des scripts tiers
    cat "$FINAL_OUT"
    echo "Résultat écrit dans : $FINAL_OUT" >&2
fi