#!/bin/bash
# api/core/docs.sh — Serveur de documentation Markdown
#
# GET  /api.sh?action=docs&cmd=list              → liste des fichiers .md
# GET  /api.sh?action=docs&cmd=read&file=<name>  → contenu raw d'un .md
#
# Sécurité :
#   - Seuls les fichiers dans DOCS_DIR sont accessibles
#   - Pas de path traversal (basename + whitelist .md)

_SS_SERVICE="portal-docs"
source "${INSTALL_DIR:-/opt/soundspot}/backend/system/log.sh" 2>/dev/null || true

DOCS_DIR="${INSTALL_DIR:-/opt/soundspot}/docs"
CMD=$(echo "$QUERY_STRING" | grep -oP '(?<=cmd=)[a-zA-Z0-9_]+' | head -1)
[ -z "$CMD" ] && CMD="list"

# Nom de fichier : alphanum + tirets + underscores + point — pas de slash
RAW_FILE=$(echo "$QUERY_STRING" | grep -oP '(?<=file=)[^&]+' | head -1)
SAFE_FILE=$(basename "$RAW_FILE" | tr -cd 'a-zA-Z0-9._-')

case "$CMD" in

  list)
    # Retourne la liste des .md avec titre (première ligne H1) et taille
    files_json=$(find "$DOCS_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null \
      | sort | python3 -c "
import sys, os, json, re

files = [l.strip() for l in sys.stdin if l.strip()]
result = []
for f in files:
    name = os.path.basename(f)
    title = name.replace('-', ' ').replace('_', ' ').replace('.md', '').title()
    size = os.path.getsize(f)
    try:
        with open(f, encoding='utf-8', errors='replace') as fh:
            for line in fh:
                m = re.match(r'^#\s+(.+)', line.strip())
                if m:
                    title = m.group(1)
                    break
    except Exception:
        pass
    result.append({'file': name, 'title': title, 'size': size})
print(json.dumps(result))
" 2>/dev/null || echo '[]')
    printf '{"status":"ok","docs":%s}\n' "$files_json"
    ;;

  read)
    if [ -z "$SAFE_FILE" ] || [ "${SAFE_FILE##*.}" != "md" ]; then
        printf '{"error":"invalid_file"}\n'
        exit 0
    fi
    TARGET="$DOCS_DIR/$SAFE_FILE"
    if [ ! -f "$TARGET" ]; then
        printf '{"error":"not_found","file":"%s"}\n' "$SAFE_FILE"
        exit 0
    fi
    # Rendu Markdown → HTML côté serveur (python3-markdown avec extensions GFM)
    python3 -c "
import sys, json, os
path = sys.argv[1]
try:
    with open(path, encoding='utf-8', errors='replace') as f:
        content = f.read()
    try:
        import markdown
        html = markdown.markdown(
            content,
            extensions=['tables', 'fenced_code', 'sane_lists', 'nl2br', 'attr_list'],
            extension_configs={'nl2br': {}}
        )
        rendered = True
    except ImportError:
        html = None
        rendered = False
    result = {'status': 'ok', 'file': os.path.basename(path), 'content': content}
    if rendered:
        result['html'] = html
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" "$TARGET" 2>/dev/null
    ;;

  *)
    printf '{"error":"unknown_cmd","hint":"list|read"}\n'
    ;;

esac
