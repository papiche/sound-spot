#!/bin/bash
# src/templates/portal_auth.sh

CLIENT_IP="$REMOTE_ADDR"
# Extraire l'adresse MAC du client via la table ARP
CLIENT_MAC=$(/usr/sbin/arp -n "$CLIENT_IP" | grep -oE "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}" | head -1)

if [ -n "$CLIENT_MAC" ]; then
    # L'ajouter à l'ipset (sudo autorisé via visudo dans le setup)
    sudo /usr/sbin/ipset add soundspot_auth "$CLIENT_MAC" 2>/dev/null
fi

echo "Content-type: text/html; charset=utf-8"
echo ""

cat <<HTMLEOF
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Accès Débloqué</title>
<style>
  body { background: #0a0a0f; color: #e8e8f0; font-family: 'Syne', sans-serif; padding: 20px; display:flex; justify-content:center; }
  .card { background: #1a1a24; border-top: 3px solid #7fff6e; padding: 30px; max-width: 500px; text-align:center; }
  h1 { color: #fff; margin-bottom:20px;}
</style>
</head>
<body>
<div class="card">
  <h1>✅ Accès Internet Débloqué</h1>
  <p>Votre accès est activé pour les <strong>15 prochaines minutes</strong>.</p>
  <p style="margin-top:20px; color:#7a7a99; font-size:0.9em;">(L'accès se coupera automatiquement pour laisser de la bande passante aux flux audio locaux).</p>
  <a href="https://g1sms.fr" style="display:inline-block; margin-top:30px; color:#7fff6e; text-decoration:none;">Naviguer vers l'écosystème ẐEN →</a>
</div>
</body>
</html>
HTMLEOF