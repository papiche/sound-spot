#!/bin/bash
# src/templates/portal_index.sh
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
  @import url('https://fonts.googleapis.com/css2?family=Space+Mono:wght@400;700&family=Syne:wght@400;700;800&display=swap');
  :root { --black:#0a0a0f; --panel:#1a1a24; --accent:#7fff6e; --text:#e8e8f0; --muted:#7a7a99; }
  body { background: var(--black); color: var(--text); font-family: 'Syne', sans-serif; padding: 20px; display:flex; flex-direction:column; align-items:center; }
  .card { background: var(--panel); border: 1px solid #2e2e42; border-top: 3px solid var(--accent); padding: 30px; border-radius: 4px; max-width: 500px; width: 100%; margin-bottom:20px; }
  h1 { font-size: 2rem; margin-bottom: 10px; color: #fff; }
  h2 { font-size: 1.3rem; margin: 20px 0 10px; color: var(--accent); }
  p { line-height: 1.6; color: #b0b0c8; margin-bottom: 15px; }
  .badge { display: inline-block; background: rgba(127,255,110,0.1); color: var(--accent); padding: 4px 10px; font-family: monospace; font-size: 12px; margin-bottom: 20px; border-radius:2px; border: 1px solid var(--accent); }
  .btn { display: block; width: 100%; padding: 15px; background: var(--accent); color: var(--black); text-align: center; font-weight: bold; text-decoration: none; border-radius: 2px; border:none; cursor:pointer; font-size: 16px; margin-top:20px; }
  .btn:hover { opacity: 0.9; }
  code { background: #000; padding: 2px 5px; font-family: monospace; color: #fff; }
  ul { color: #b0b0c8; padding-left: 20px; margin-bottom: 15px; line-height: 1.6; }
</style>
</head>
<body>

<div class="card">
  <div class="badge">🌐 Réseau Local Ouvert</div>
  <h1>Bienvenue sur SoundSpot.</h1>
  
  <p>Vous êtes connecté(e) à un <strong>bien commun numérique</strong>. Ce dispositif n'appartient à personne, il ne collecte pas vos données et ne cherche pas à capter votre attention.</p>
  
  <p>Son unique but est de créer un espace sonore partagé et libre. En ce moment, j'attends :</p>
  <ul>
    <li><strong>Un ou une DJ</strong> pour s'y connecter (via Mixxx) et diffuser sa musique dans l'espace.</li>
    <li><strong>Des enceintes satellites</strong> (comme votre smartphone via l'application Snapclient) pour s'y relier et étendre la portée du son de manière synchronisée.</li>
  </ul>

  <h2>Comment participer ?</h2>
  <p><strong>🎧 Écouter :</strong> Installez <em>Snapdroid</em> (Android) ou lancez <em>Snapclient</em>. Le son arrivera directement sur votre téléphone.<br>
  <code>Serveur : ${SPOT_IP}</code></p>

  <p><strong>🎛️ Mixer :</strong> Diffusez via Icecast depuis votre ordinateur ou smartphone.<br>
  <code>${SPOT_IP}:${ICECAST_PORT} | Mdp: ${ICECAST_PASS} | Montage: /live</code></p>

  <hr style="border:0; border-top:1px solid #2e2e42; margin: 30px 0;">

  <h2>📖 Documentation Locale</h2>
  <p>Ce SoundSpot héberge son propre manuel. Vous pouvez lire comment reproduire, modifier ou utiliser ce système sans avoir besoin d'Internet :</p>
  
  <div style="display:flex; gap: 10px; margin-bottom: 10px; flex-wrap: wrap;">
    <a href="docs.sh?readme" class="btn" style="margin-top:0; padding: 10px; font-size: 14px; background:rgba(127,255,110,0.1); border:1px solid var(--accent); color:var(--accent);">Lire le README</a>
    <a href="docs.sh?howto" class="btn" style="margin-top:0; padding: 10px; font-size: 14px; background:rgba(127,255,110,0.1); border:1px solid var(--accent); color:var(--accent);">Guide / HOWTO</a>
  </div>

  <hr style="border:0; border-top:1px solid #2e2e42; margin: 30px 0;">

  <h2>Accès Internet Limité</h2>
  <p>Vous pouvez débloquer un accès au reste de l'Internet, <strong>limité à 15 minutes</strong> pour économiser la bande passante de la coopérative.</p>

  <form action="auth.sh" method="POST">
    <button type="submit" class="btn">Débloquer Internet (15 minutes) →</button>
  </form>
</div>

</body>
</html>
HTMLEOF