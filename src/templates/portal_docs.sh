#!/bin/bash
# src/templates/portal_docs.sh

# Déterminer quel document afficher via l'URL (ex: docs.sh?howto)
DOC="README"
if [[ "$QUERY_STRING" == "howto" ]]; then
    DOC="HOWTO"
fi

echo "Content-type: text/html; charset=utf-8"
echo ""

cat <<HTMLEOF
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>SoundSpot — $DOC</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Space+Mono:wght@400;700&family=Syne:wght@400;700;800&display=swap');
  :root { --black:#0a0a0f; --panel:#1a1a24; --accent:#7fff6e; --text:#e8e8f0; --muted:#7a7a99; }
  body { background: var(--black); color: var(--text); font-family: 'Syne', sans-serif; padding: 20px; line-height: 1.6; }
  .card { background: var(--panel); padding: 30px; max-width: 800px; margin: 0 auto; border-top: 3px solid var(--accent); border-radius: 4px; box-shadow: 0 10px 30px rgba(0,0,0,0.5); }
  a { color: #4ecdc4; text-decoration: none; }
  a:hover { text-decoration: underline; }
  pre { background: #000; padding: 15px; overflow-x: auto; border-radius: 4px; border: 1px solid #2e2e42; }
  code { font-family: 'Space Mono', monospace; color: #4ecdc4; font-size: 0.9em; }
  h1, h2, h3 { color: #fff; margin-top: 1.5em; margin-bottom: 0.5em; }
  h1 { font-size: 2.2rem; color: var(--accent); border-bottom: 1px solid #2e2e42; padding-bottom: 10px; }
  table { width: 100%; border-collapse: collapse; margin: 20px 0; font-size: 0.9em; }
  th, td { padding: 12px; border-bottom: 1px solid #2e2e42; text-align: left; }
  th { color: var(--accent); background: rgba(127,255,110,0.05); }
  blockquote { border-left: 4px solid var(--accent); margin: 0; padding-left: 15px; color: var(--muted); }
  .back-btn { display: inline-block; margin-bottom: 20px; color: var(--muted); text-decoration: none; font-weight: bold; border: 1px solid var(--muted); padding: 5px 15px; border-radius: 2px; }
  .back-btn:hover { color: #fff; border-color: #fff; text-decoration: none; }
</style>
</head>
<body>
<div class="card">
  <a href="index.sh" class="back-btn">← Retour au Portail</a>
HTMLEOF

FILE_PATH="/opt/soundspot/${DOC}.md"

if [ -f "$FILE_PATH" ]; then
    # Python3 convertit le markdown en HTML. 
    # Les extensions "tables" et "fenced_code" gèrent les tableaux et blocs de code (```bash)
    python3 -m markdown -x tables -x fenced_code "$FILE_PATH"
else
    echo "<p>Document <strong>${DOC}.md</strong> introuvable sur ce nœud.</p>"
fi

cat <<HTMLEOF
</div>
</body>
</html>
HTMLEOF