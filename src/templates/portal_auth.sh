#!/bin/bash
# src/templates/portal_auth.sh — Validation du portail captif
# Appelé quand l'utilisateur clique "J'ai lu" sur le portail.
# Ajoute l'IP cliente dans soundspot_auth (timeout 900s = 15 min, géré par ipset).

CLIENT_IP="$REMOTE_ADDR"

if [ -n "$CLIENT_IP" ]; then
    # timeout 900 remet le compteur à zéro depuis le clic (pas depuis le DHCP)
    sudo /usr/sbin/ipset add soundspot_auth "$CLIENT_IP" timeout 900 -exist
fi

echo "Content-type: text/html; charset=utf-8"
echo ""

cat <<HTMLEOF
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Accès Activé — SoundSpot</title>
<style>
  body { background: #0a0a0f; color: #e8e8f0; font-family: system-ui, sans-serif; padding: 20px; display:flex; justify-content:center; align-items:center; min-height:100vh; margin:0; }
  .card { background: #1a1a24; border-top: 3px solid #7fff6e; padding: 30px; max-width: 400px; width:100%; text-align:center; border-radius:4px; }
  h1 { color: #fff; margin-bottom: 10px; }
  p { color: #b0b0c8; line-height: 1.6; }
  .btn { display:inline-block; margin-top:20px; padding:12px 24px; background:#7fff6e; color:#0a0a0f; text-decoration:none; font-weight:bold; border-radius:2px; font-size:15px; }
  .note { margin-top:15px; color:#7a7a99; font-size:0.8em; }
</style>
</head>
<body>
<div class="card">
  <h1>✅ C'est noté !</h1>
  <p>Votre accès internet est ouvert pour <strong>15 minutes</strong>.</p>
  <p class="note">Après ce délai, naviguez à nouveau sur le portail pour revalider.<br>Privilégiez l'écoute de la musique locale pour économiser l'énergie du nœud.</p>
  <a href="https://opencollective.com/monnaie-libre" class="btn">Continuer →</a>
</div>
</body>
</html>
HTMLEOF
