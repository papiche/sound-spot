#!/bin/bash
# src/templates/portal_index.sh — Version Furtive (No External Fonts)
echo "Content-type: text/html; charset=utf-8"
echo ""

cat <<HTMLEOF
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>SoundSpot — Bien Commun</title>
<style>
  /* Font Stack Système : Moderne & Monospace (Sans Google Fonts) */
  :root { 
    --black:#0a0a0f; 
    --panel:#1a1a24; 
    --accent:#7fff6e; 
    --text:#e8e8f0; 
    --muted:#7a7a99;
    /* Pile Sans-Serif moderne (alternative à Syne) */
    --font-main: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
    /* Pile Monospace (alternative à Space Mono) */
    --font-mono: ui-monospace, 'Cascadia Code', 'Source Code Pro', Menlo, Monaco, Consolas, monospace;
  }

  body { 
    background: var(--black); 
    color: var(--text); 
    font-family: var(--font-main); 
    padding: 20px; 
    display:flex; 
    flex-direction:column; 
    align-items:center; 
  }
  
  .card { 
    background: var(--panel); 
    border: 1px solid #2e2e42; 
    border-top: 3px solid var(--accent); 
    padding: 30px; 
    border-radius: 4px; 
    max-width: 500px; 
    width: 100%; 
    margin-bottom:20px; 
  }
  
  h1, h2 { font-weight: 800; letter-spacing: -0.02em; }
  h1 { font-size: 2rem; margin-bottom: 10px; color: #fff; }
  h2 { font-size: 1.3rem; margin: 20px 0 10px; color: var(--accent); }
  
  p { line-height: 1.6; color: #b0b0c8; margin-bottom: 15px; }
  
  .badge { 
    display: inline-block; 
    background: rgba(127,255,110,0.1); 
    color: var(--accent); 
    padding: 4px 10px; 
    font-family: var(--font-mono); 
    font-size: 12px; 
    margin-bottom: 20px; 
    border-radius:2px; 
    border: 1px solid var(--accent); 
    text-transform: uppercase;
  }

  .btn { 
    display: block; 
    width: 100%; 
    padding: 15px; 
    background: var(--accent); 
    color: var(--black); 
    text-align: center; 
    font-weight: bold; 
    text-decoration: none; 
    border-radius: 2px; 
    border:none; 
    cursor:pointer; 
    font-size: 16px; 
    margin-top:20px; 
    transition: 0.2s;
    font-family: var(--font-main);
  }
  
  .btn:hover { opacity: 0.8; transform: translateY(-2px); }
  .btn-outline { background: transparent; border: 1px solid var(--accent); color: var(--accent); margin-top: 10px; }
  
  code { 
    background: #000; 
    padding: 2px 5px; 
    font-family: var(--font-mono); 
    color: #fff; 
    font-size: 0.9em;
  }
  
  ul { color: #b0b0c8; padding-left: 20px; margin-bottom: 15px; line-height: 1.6; }
  .highlight { color: #fff; font-weight: bold; }
</style>
</head>
<body>

<div class="card">
  <div class="badge">Local Node // No Tracking</div>
  <h1>Bienvenue sur SoundSpot.</h1>
  
  <p>Vous êtes sur un <span class="highlight">bien commun numérique</span>. Ce nœud est géré par le collectif, alimenté par le soleil et ne collecte aucune donnée.</p>
  
  <h2>🎧 Audio Collectif</h2>
  <ul>
    <li><span class="highlight">DJ :</span> Connectez-vous via Mixxx pour diffuser.</li>
    <li><span class="highlight">Auditeurs :</span> Utilisez Snapclient pour écouter.</li>
  </ul>

  <p>L'audio local est disponible en permanence via :<br>
  <code>Serveur : ${SPOT_IP}</code></p>

  <hr style="border:0; border-top:1px solid #2e2e42; margin: 30px 0;">

  <h2>🌐 Internet & Soutien</h2>
  <p>L'accès Internet est <span class="highlight">libre pendant 15 minutes</span>, puis suspendu 1h pour préserver la musique locale.</p>

  <a href="https://opencollective.com/monnaie-libre" class="btn">
    Soutenir sur OpenCollective ❤️
  </a>

  <hr style="border:0; border-top:1px solid #2e2e42; margin: 30px 0;">

  <div style="display:flex; gap: 10px; flex-wrap: wrap;">
    <a href="docs.sh?readme" class="btn btn-outline" style="flex:1; margin-top:0;">Le Projet</a>
    <a href="docs.sh?howto" class="btn btn-outline" style="flex:1; margin-top:0;">Guide DJ</a>
  </div>
</div>

<p style="color:var(--muted); font-size:11px; font-family:var(--font-mono); text-transform:uppercase; letter-spacing:1px;">
  UPlanet ẐEN & G1FabLab // AGPL-3.0
</p>

</body>
</html>
HTMLEOF