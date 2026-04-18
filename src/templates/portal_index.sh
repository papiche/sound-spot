#!/bin/bash
# portal_index.sh — Portail captif SoundSpot (Version Furtive / Offline)
# Variables substituées à l'installation : SPOT_IP, SNAPCAST_PORT, ICECAST_PORT, SPOT_NAME
# Variables lues depuis soundspot.conf à chaque requête : CLOCK_MODE

source /opt/soundspot/soundspot.conf 2>/dev/null || true
CLOCK_MODE="${CLOCK_MODE:-bells}"
if [ "$CLOCK_MODE" = "bells" ]; then
    CLOCK_LABEL="🔔 Cloches activées"
    CLOCK_NEXT_MODE="silent"
    CLOCK_BTN_LABEL="Désactiver les cloches"
else
    CLOCK_LABEL="🔇 Cloches silencieuses"
    CLOCK_NEXT_MODE="bells"
    CLOCK_BTN_LABEL="Activer les cloches"
fi

echo "Content-type: text/html; charset=utf-8"
echo ""

cat <<HTMLEOF
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>SoundSpot — ${SPOT_NAME}</title>
<style>
  :root {
    --black:#0a0a0f; --dark:#111118; --panel:#1a1a24; --border:#2e2e42;
    --accent:#7fff6e; --accent2:#4ecdc4; --dj:#ffb347; --sat:#b47fff;
    --text:#e8e8f0; --muted:#7a7a99;
    --font-main: system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
    --font-mono: ui-monospace,"Cascadia Code","Source Code Pro",Menlo,Monaco,Consolas,monospace;
  }
  *{margin:0;padding:0;box-sizing:border-box}
  body{background:var(--black);color:var(--text);font-family:var(--font-main);
       padding:20px 0 40px;display:flex;flex-direction:column;align-items:center}
  .card{background:var(--panel);border:1px solid var(--border);border-radius:2px;
        padding:28px 24px;max-width:520px;width:92vw;margin-bottom:14px;position:relative}
  .card::before{content:'';position:absolute;top:0;left:0;right:0;height:3px}
  .card-main::before  {background:linear-gradient(90deg,var(--accent),var(--accent2))}
  .card-dj::before    {background:linear-gradient(90deg,var(--dj),#ff6b6b)}
  .card-sat::before   {background:linear-gradient(90deg,var(--sat),var(--accent2))}
  .card-clock::before {background:linear-gradient(90deg,#888,#555)}
  h1{font-size:clamp(1.6rem,5vw,2.2rem);font-weight:800;letter-spacing:-0.03em;color:#fff;margin-bottom:4px}
  h2{font-size:1.1rem;font-weight:700;color:#fff;margin:18px 0 10px}
  p{line-height:1.6;color:#b0b0c8;margin-bottom:12px;font-size:.95rem}
  .badge{display:inline-flex;align-items:center;gap:5px;font-family:var(--font-mono);
         font-size:10px;letter-spacing:.12em;text-transform:uppercase;
         padding:3px 9px;border-radius:2px;margin-bottom:16px}
  .badge-v{color:var(--accent);border:1px solid rgba(127,255,110,.3);background:rgba(127,255,110,.05)}
  .badge-dj{color:var(--dj);border:1px solid rgba(255,179,71,.3);background:rgba(255,179,71,.05)}
  .badge-sat{color:var(--sat);border:1px solid rgba(180,127,255,.3);background:rgba(180,127,255,.05)}
  .badge-clk{color:#888;border:1px solid rgba(128,128,128,.3);background:rgba(128,128,128,.05)}
  .steps{display:flex;flex-direction:column;gap:8px;margin:12px 0}
  .step{display:flex;align-items:flex-start;gap:10px;font-size:.9rem;color:#b0b0c8;line-height:1.5}
  .step-n{font-family:var(--font-mono);font-size:10px;border-radius:2px;padding:2px 5px;
          white-space:nowrap;margin-top:2px;min-width:24px;text-align:center;flex-shrink:0}
  .n-v{color:var(--accent);border:1px solid var(--accent)}
  .n-dj{color:var(--dj);border:1px solid var(--dj)}
  .n-sat{color:var(--sat);border:1px solid var(--sat)}
  code{font-family:var(--font-mono);font-size:.85em;background:#000;padding:2px 5px;color:#fff}
  .val{color:var(--accent2)}
  .hi{color:#fff;font-weight:700}
  .row{display:flex;gap:8px;flex-wrap:wrap;margin-top:8px}
  .btn{display:block;width:100%;padding:14px;background:var(--accent);color:var(--black);
       font-family:var(--font-main);font-weight:700;font-size:15px;letter-spacing:.04em;
       text-transform:uppercase;text-decoration:none;text-align:center;
       border:none;border-radius:2px;cursor:pointer;transition:opacity .15s;margin-top:8px}
  .btn:hover{opacity:.85}
  .btn-sm{padding:9px 14px;font-size:12px;margin-top:0}
  .btn-outline{background:transparent;border:1px solid var(--accent);color:var(--accent)}
  .btn-dj{background:var(--dj);color:#000}
  .btn-sat{background:var(--sat);color:#000}
  .btn-clk{background:#333;color:#ccc;border:1px solid #555}
  .info-row{display:flex;justify-content:space-between;padding:5px 0;
            border-bottom:1px solid var(--border);font-size:.85rem;color:var(--muted)}
  .info-row:last-child{border-bottom:none}
  .info-row span:last-child{color:var(--text);font-family:var(--font-mono)}
  .info-box{background:var(--dark);border:1px solid var(--border);border-radius:2px;padding:12px 14px;margin:12px 0}
  hr{border:none;border-top:1px solid var(--border);margin:16px 0}
  .note{font-size:.8rem;color:var(--muted);line-height:1.6;margin-top:10px}
  .note a{color:var(--accent2);text-decoration:none}
  .footer{max-width:520px;width:92vw;text-align:center;font-family:var(--font-mono);
          font-size:10px;color:var(--muted);letter-spacing:.06em;margin-top:8px}
</style>
</head>
<body>

<!-- ═══ CARTE 1 — AUDITEUR / BIEN COMMUN ═══ -->
<div class="card card-main">
  <div class="badge badge-v">Nœud local // ${SPOT_NAME}</div>
  <h1>Sound<span style="color:var(--accent)">Spot</span></h1>
  <p>Vous êtes sur un <span class="hi">bien commun numérique</span>. Infrastructure libre, solaire, sans publicité ni collecte de données.</p>

  <div class="info-box">
    <div class="info-row"><span>WiFi</span>       <span>${SPOT_NAME} (ouvert)</span></div>
    <div class="info-row"><span>Stream audio</span><span>${SPOT_IP}:${SNAPCAST_PORT}</span></div>
    <div class="info-row"><span>Internet</span>   <span>15 min / requête</span></div>
  </div>

  <div class="steps">
    <div class="step"><div class="step-n n-v">01</div>
      <span>Connecté à <span class="hi">${SPOT_NAME}</span> ✓</span></div>
    <div class="step"><div class="step-n n-v">02</div>
      <span>Écouter en direct :<br>
        📱 Android : <a href="https://f-droid.org/en/packages/de.badaix.snapcast/" style="color:var(--accent2)">Snapdroid sur F-Droid</a>
        · <a href="https://play.google.com/store/apps/details?id=de.badaix.snapcast" style="color:var(--accent2)">Play Store</a><br>
        🍎 iPhone : <a href="https://apps.apple.com/app/snapcast-client/id1552559654" style="color:var(--accent2)">Snapcast pour iOS</a><br>
        🖥 PC/Linux : <code class="val">snapclient -h ${SPOT_IP}</code></span></div>
    <div class="step"><div class="step-n n-v">03</div>
      <span>Soutenir le collectif <a href="https://opencollective.com/monnaie-libre" style="color:var(--accent)">monnaie-libre.org</a></span></div>
  </div>

  <hr>

  <form action="auth.sh" method="POST">
    <button type="submit" class="btn">Ouvrir l'accès Internet — 15 min →</button>
  </form>
  <p class="note" style="margin-top:8px">Après 15 min, rouvrir cette page pour revalider. Le stream audio reste accessible sans limite.</p>
</div>

<!-- ═══ CARTE 2 — DEVENIR DJ ═══ -->
<div class="card card-dj">
  <div class="badge badge-dj">🎛 Espace DJ</div>
  <h2>Diffuser votre musique</h2>

  <div class="info-box">
    <div class="info-row"><span>Serveur Icecast</span><span>${SPOT_IP}:${ICECAST_PORT}</span></div>
    <div class="info-row"><span>Montage</span>       <span>/live</span></div>
    <div class="info-row"><span>Login / Mdp</span>   <span>source / (dans soundspot.conf)</span></div>
  </div>

  <h2 style="color:var(--dj);margin-top:14px">Sur PC (Linux/Mac/Windows)</h2>
  <div class="steps">
    <div class="step"><div class="step-n n-dj">01</div>
      <span>Installer <span class="hi">Mixxx</span> (gratuit) et <code class="val">snapclient</code></span></div>
    <div class="step"><div class="step-n n-dj">02</div>
      <span>Lancer <code class="val">snapclient -h ${SPOT_IP}</code> → retour casque (latence 0)</span></div>
    <div class="step"><div class="step-n n-dj">03</div>
      <span>Mixxx → <span class="hi">Préférences → Live Broadcasting</span><br>
        Serveur : <code class="val">${SPOT_IP}</code> Port : <code class="val">${ICECAST_PORT}</code>
        Montage : <code class="val">/live</code> Format : <code class="val">Ogg Vorbis</code></span></div>
    <div class="step"><div class="step-n n-dj">04</div>
      <span>Cliquer sur l'icône <span class="hi">Antenne</span> dans Mixxx → vous êtes en direct</span></div>
  </div>
  <p class="note">⚠ Latence 1–3 s (buffers réseau) — calez vos transitions sur le <span class="hi">casque Cue</span>, pas sur les enceintes.</p>

  <h2 style="color:var(--dj);margin-top:14px">Sur Smartphone</h2>
  <div class="steps">
    <div class="step"><div class="step-n n-dj">01</div>
      <span>📱 Android : <a href="https://www.mixxx.org/download/" style="color:var(--accent2)">Mixxx</a> (Linux/Mac/Win)
        ou <a href="https://play.google.com/store/apps/details?id=com.kh.android.djstudio" style="color:var(--accent2)">DJ Studio 5</a> (gratuit)<br>
        🍎 iPhone : <a href="https://apps.apple.com/app/djay/id1617640764" style="color:var(--accent2)">djay</a>
        ou <a href="https://apps.apple.com/app/koalified/id1554527434" style="color:var(--accent2)">Koalified</a> (Icecast natif)</span></div>
    <div class="step"><div class="step-n n-dj">02</div>
      <span>Configuration identique — même IP/port Icecast que sur PC</span></div>
    <div class="step"><div class="step-n n-dj">03</div>
      <span>Monitoring : <a href="https://f-droid.org/en/packages/de.badaix.snapcast/" style="color:var(--accent2)">Snapdroid</a> sur un 2ème téléphone</span></div>
  </div>

  <div class="row">
    <a href="docs.sh?howto" class="btn btn-dj btn-sm" style="flex:1">Guide complet DJ →</a>
  </div>
</div>

<!-- ═══ CARTE 3 — ÉTENDRE LE RÉSEAU ═══ -->
<div class="card card-sat">
  <div class="badge badge-sat">📡 Réseau de Nœuds</div>
  <h2>Étendre le SoundSpot</h2>
  <p>Chaque nœud supplémentaire = une enceinte Bluetooth synchronisée en plus dans l'espace.</p>

  <h2 style="color:var(--sat);margin-top:14px">Ajouter une enceinte (Satellite RPi)</h2>
  <div class="steps">
    <div class="step"><div class="step-n n-sat">01</div>
      <span>Flasher un <span class="hi">Raspberry Pi Zero 2W</span> (ou Pi 3/4) avec Raspberry Pi OS Lite</span></div>
    <div class="step"><div class="step-n n-sat">02</div>
      <span>Connecter au WiFi <code class="val">${SPOT_NAME}</code> ou au réseau <code class="val">qo-op</code></span></div>
    <div class="step"><div class="step-n n-sat">03</div>
      <span>Cloner le dépôt et lancer :<br>
        <code class="val">git clone https://github.com/papiche/sound-spot</code><br>
        <code class="val">sudo bash deploy_on_pi.sh --satellite</code></span></div>
    <div class="step"><div class="step-n n-sat">04</div>
      <span>Entrer l'adresse du maître : <code class="val">${SPOT_IP}</code> ou <code class="val">soundspot.local</code></span></div>
    <div class="step"><div class="step-n n-sat">05</div>
      <span>Coupler une enceinte Bluetooth → le satellite rejoint le réseau synchronisé</span></div>
  </div>

  <h2 style="color:var(--sat);margin-top:14px">Écoute sur Smartphone</h2>
  <div class="steps">
    <div class="step"><div class="step-n n-sat">01</div>
      <span>Android :
        <a href="https://f-droid.org/en/packages/de.badaix.snapcast/" style="color:var(--accent2)">Snapdroid (F-Droid — sans Google)</a>
        · <a href="https://play.google.com/store/apps/details?id=de.badaix.snapcast" style="color:var(--accent2)">Play Store</a><br>
        iPhone : <a href="https://apps.apple.com/app/snapcast-client/id1552559654" style="color:var(--accent2)">Snapcast for iOS</a></span></div>
    <div class="step"><div class="step-n n-sat">02</div>
      <span>Serveur : <code class="val">${SPOT_IP}</code> Port : <code class="val">${SNAPCAST_PORT}</code></span></div>
    <div class="step"><div class="step-n n-sat">03</div>
      <span>Votre téléphone devient une enceinte synchronisée avec tout l'espace</span></div>
  </div>

  <hr>

  <h2 style="color:var(--sat);margin-top:0">Systèmes Libres recommandés</h2>
  <p style="font-size:.85rem">Ce SoundSpot tourne sur des logiciels <span class="hi">100% libres</span> (GPL/AGPL). Pour aller plus loin :</p>
  <div class="steps">
    <div class="step"><div class="step-n n-sat">🐧</div>
      <span><a href="https://ubuntu.com" style="color:var(--accent2)">Ubuntu</a> /
        <a href="https://debian.org" style="color:var(--accent2)">Debian</a> /
        <a href="https://fedoraproject.org" style="color:var(--accent2)">Fedora</a> —
        PC/laptop sans Windows ni macOS</span></div>
    <div class="step"><div class="step-n n-sat">📱</div>
      <span><a href="https://e.foundation" style="color:var(--accent2)">/e/OS</a> —
        Android <span class="hi">dégooglisé</span>, sans trackers Google, avec apps préinstallées libres.
        Compatible avec de nombreux smartphones Fairphone et Samsung.</span></div>
    <div class="step"><div class="step-n n-sat">📱</div>
      <span><a href="https://lineageos.org" style="color:var(--accent2)">LineageOS</a> —
        Android libre, large compatibilité matérielle, sans services Google</span></div>
    <div class="step"><div class="step-n n-sat">🛒</div>
      <span><a href="https://f-droid.org" style="color:var(--accent2)">F-Droid</a> —
        Boutique d'apps <span class="hi">100% libres</span> pour Android. Alternative au Play Store sans pistage.</span></div>
  </div>
</div>

<!-- ═══ CARTE 4 — MODE HORLOGE (configurable) ═══ -->
<div class="card card-clock">
  <div class="badge badge-clk">⏰ Clocher Numérique</div>
  <h2 style="color:#aaa">Annonces sonores</h2>
  <p>Quand aucun DJ ne diffuse, SoundSpot joue un bip 429.62 Hz + l'heure + un message du collectif toutes les 15 min.<br>
  Le bip et les messages ne peuvent pas être désactivés.</p>

  <div class="info-box">
    <div class="info-row"><span>Bip 429.62 Hz</span>    <span>✓ Toujours actif</span></div>
    <div class="info-row"><span>Messages G1FabLab</span> <span>✓ Toujours actifs</span></div>
    <div class="info-row"><span>Coups de cloche</span>  <span>${CLOCK_LABEL}</span></div>
  </div>

  <form action="set_clock.sh" method="POST">
    <input type="hidden" name="mode" value="${CLOCK_NEXT_MODE}">
    <button type="submit" class="btn btn-clk btn-sm" style="width:100%;margin-top:12px">${CLOCK_BTN_LABEL}</button>
  </form>
  <p class="note">Le changement est effectif immédiatement, même sans redémarrage.</p>
</div>

<div class="footer">
  <p><a href="https://opencollective.com/monnaie-libre" style="color:var(--accent2)">G1FabLab</a> · <a href="https://qo-op.com" style="color:var(--accent2)">UPlanet ẐEN</a> · <a href="https://github.com/papiche/sound-spot" style="color:var(--accent2)">Code source AGPL-3.0</a></p>
  <p style="margin-top:4px;opacity:.4;font-size:9px">NO GOOGLE FONTS // NO TRACKING // SOLAR POWERED</p>
</div>

</body>
</html>
HTMLEOF
