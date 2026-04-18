#!/bin/bash
# src/templates/portal_docs.sh — Version Furtive (No External Fonts)

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
  :root { 
    --black:#0a0a0f; 
    --panel:#1a1a24; 
    --accent:#7fff6e; 
    --text:#e8e8f0; 
    --muted:#7a7a99;
    /* Piles de polices système (Stealth & Speed) */
    --font-main: system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    --font-mono: ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Monaco, Consolas, monospace;
  }

  body { 
    background: var(--black); 
    color: var(--text); 
    font-family: var(--font-main); 
    padding: 20px; 
    line-height: 1.6; 
    -webkit-font-smoothing: antialiased;
  }

  .card { 
    background: var(--panel); 
    padding: 30px; 
    max-width: 800px; 
    margin: 0 auto; 
    border-top: 3px solid var(--accent); 
    border-radius: 4px; 
    box-shadow: 0 10px 30px rgba(0,0,0,0.5); 
  }

  a { color: #4ecdc4; text-decoration: none; transition: 0.2s; }
  a:hover { color: var(--accent); text-decoration: underline; }

  pre { 
    background: #000; 
    padding: 15px; 
    overflow-x: auto; 
    border-radius: 4px; 
    border: 1px solid #2e2e42; 
    margin: 1.5em 0;
  }

  code { 
    font-family: var(--font-mono); 
    color: #4ecdc4; 
    font-size: 0.9em; 
    background: rgba(0,0,0,0.3);
    padding: 2px 4px;
    border-radius: 3px;
  }
  
  pre code { background: none; padding: 0; color: inherit; }

  h1, h2, h3 { color: #fff; margin-top: 1.5em; margin-bottom: 0.5em; font-weight: 700; }
  h1 { font-size: 2.2rem; color: var(--accent); border-bottom: 1px solid #2e2e42; padding-bottom: 10px; }
  h2 { font-size: 1.6rem; border-bottom: 1px solid rgba(255,255,255,0.05); padding-bottom: 5px; }

  table { width: 100%; border-collapse: collapse; margin: 20px 0; font-size: 0.9em; font-family: var(--font-mono); }
  th, td { padding: 12px; border-bottom: 1px solid #2e2e42; text-align: left; }
  th { color: var(--accent); background: rgba(127,255,110,0.05); text-transform: uppercase; font-size: 0.8em; letter-spacing: 1px; }

  blockquote { 
    border-left: 4px solid var(--accent); 
    margin: 1.5em 0; 
    padding: 0.5em 15px; 
    color: var(--muted); 
    background: rgba(255,255,255,0.02);
  }

  .back-btn { 
    display: inline-block; 
    margin-bottom: 20px; 
    color: var(--muted); 
    text-decoration: none; 
    font-weight: bold; 
    border: 1px solid var(--muted); 
    padding: 5px 15px; 
    border-radius: 2px; 
    font-family: var(--font-mono);
    font-size: 0.8em;
    text-transform: uppercase;
    letter-spacing: 1px;
  }
  .back-btn:hover { color: #fff; border-color: #fff; background: rgba(255,255,255,0.05); }

  /* Ajustements pour le rendu Markdown */
  li { margin-bottom: 0.5em; }
  hr { border: 0; border-top: 1px solid #2e2e42; margin: 2em 0; }
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
<p style="text-align:center; color:var(--muted); font-size:10px; font-family:var(--font-mono); margin-top:20px; text-transform:uppercase;">
  SoundSpot Furtif // Offline Documentation
</p>
</body>
</html>
HTMLEOF