#!/bin/sh
# theme_soundspot.sh — Portail captif SoundSpot (Version Furtive / Offline)
# ThemeSpec pour OpenNDS — exécuté par opennds à chaque connexion visiteur

source /opt/soundspot/soundspot.conf 2>/dev/null || true
SPOT_NAME="${SPOT_NAME:-SoundSpot}"
SPOT_IP="${SPOT_IP:-192.168.10.1}"
SNAP_PORT="${SNAPCAST_PORT:-1704}"
ICECAST_PORT="8111"
ICECAST_PASS="${WIFI_PASS:-0penS0urce!}"

echo "Content-type: text/html"
echo ""
cat <<HTMLEOF
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>SoundSpot — ${SPOT_NAME}</title>
<style>
  /* Suppression de Google Fonts pour la furtivité et la vitesse */

  :root {
    --black:   #0a0a0f;
    --dark:    #111118;
    --panel:   #1a1a24;
    --border:  #2e2e42;
    --accent:  #7fff6e;
    --accent2: #4ecdc4;
    --accent3: #ff6b6b;
    --dj:      #ffb347;
    --sat:     #b47fff;
    --text:    #e8e8f0;
    --muted:   #7a7a99;
    /* Piles de polices système furtives */
    --font-main: system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    --font-mono: ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Monaco, Consolas, monospace;
  }

  * { margin:0; padding:0; box-sizing:border-box; }

  body {
    background: var(--black);
    color: var(--text);
    font-family: var(--font-main);
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 24px 0 40px;
    overflow-x: hidden;
    position: relative;
  }

  body::before {
    content: '';
    position: fixed; inset: 0;
    background-image:
      linear-gradient(var(--border) 1px, transparent 1px),
      linear-gradient(90deg, var(--border) 1px, transparent 1px);
    background-size: 40px 40px;
    opacity: 0.22;
    animation: gridPulse 8s ease-in-out infinite;
    pointer-events: none;
  }
  @keyframes gridPulse { 0%,100%{opacity:0.22} 50%{opacity:0.08} }

  .orb { position:fixed; border-radius:50%; filter:blur(80px); pointer-events:none; animation:float 12s ease-in-out infinite; }
  .orb-1 { width:400px;height:400px; background:radial-gradient(circle,rgba(127,255,110,0.09),transparent 70%); top:-100px;left:-100px; }
  .orb-2 { width:300px;height:300px; background:radial-gradient(circle,rgba(78,205,196,0.07),transparent 70%); bottom:-80px;right:-80px; animation-delay:-4s; }
  @keyframes float { 0%,100%{transform:translate(0,0)} 33%{transform:translate(30px,-20px)} 66%{transform:translate(-20px,15px)} }

  .card {
    position: relative;
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 2px;
    padding: 36px 32px;
    max-width: 540px;
    width: 92vw;
    box-shadow: 0 40px 80px rgba(0,0,0,0.5);
    margin-bottom: 16px;
  }
  .card::before { content:''; position:absolute; top:0;left:0;right:0; height:3px; }
  .card-visitor::before   { background: linear-gradient(90deg, var(--accent),  var(--accent2)); }
  .card-dj::before        { background: linear-gradient(90deg, var(--dj),      var(--accent3)); }
  .card-satellite::before { background: linear-gradient(90deg, var(--sat),      var(--accent2)); }

  .badge {
    display: inline-flex; align-items: center; gap: 6px;
    font-family: var(--font-mono);
    font-size: 10px; letter-spacing: 0.15em; text-transform: uppercase;
    padding: 4px 10px; border-radius: 2px; margin-bottom: 18px;
  }
  .badge::before { content:''; width:6px;height:6px; border-radius:50%; animation:blink 2s ease-in-out infinite; }
  .badge-v  { color:var(--accent); border:1px solid rgba(127,255,110,0.3); background:rgba(127,255,110,0.05); }
  .badge-v::before  { background:var(--accent); }
  .badge-dj { color:var(--dj);     border:1px solid rgba(255,179,71,0.3);  background:rgba(255,179,71,0.05); }
  .badge-dj::before { background:var(--dj); }
  .badge-s  { color:var(--sat);    border:1px solid rgba(180,127,255,0.3); background:rgba(180,127,255,0.05); }
  .badge-s::before  { background:var(--sat); }
  @keyframes blink { 0%,100%{opacity:1} 50%{opacity:0.3} }

  h1 { font-size:clamp(1.8rem,6vw,2.6rem); font-weight:800; line-height:1; letter-spacing:-0.03em; margin-bottom:4px; color:#fff; }
  h2 { font-size:1.5rem; font-weight:800; line-height:1; margin-bottom:4px; color:#fff; }
  .hl-v  { color:var(--accent); }
  .hl-dj { color:var(--dj); }
  .hl-s  { color:var(--sat); }

  .subtitle { font-family: var(--font-mono); font-size: 11px; color: var(--muted); letter-spacing: 0.1em; margin-bottom: 22px; }

  .waveform { display:flex; align-items:center; gap:3px; height:34px; margin-bottom:22px; }
  .bar { width:3px; background:var(--accent); border-radius:2px; opacity:0.7;
         animation:wave var(--d,1s) ease-in-out infinite; animation-delay:var(--delay,0s); }
  @keyframes wave { 0%,100%{height:6px} 50%{height:var(--h,24px)} }

  .net-info { background:var(--dark); border:1px solid var(--border); border-radius:2px; padding:13px 15px; margin-bottom:22px; font-family: var(--font-mono); font-size: 12px; }
  .net-row  { display:flex; justify-content:space-between; padding:3px 0; border-bottom:1px solid var(--border); color:var(--muted); }
  .net-row:last-child { border-bottom:none; }
  .net-row span:last-child { color:var(--text); }

  .steps { display:flex; flex-direction:column; gap:9px; margin-bottom:20px; }
  .step  { display:flex; align-items:flex-start; gap:11px; font-size:14px; color:#b0b0c8; line-height:1.5; }
  .step-num { font-family: var(--font-mono); font-size: 10px; border-radius: 2px; padding: 2px 5px; white-space: nowrap; margin-top: 2px; min-width: 26px; text-align: center; flex-shrink: 0; }
  .n-v  { color:var(--accent); border:1px solid var(--accent); }
  .n-dj { color:var(--dj);     border:1px solid var(--dj); }
  .n-s  { color:var(--sat);    border:1px solid var(--sat); }

  code  { font-family: var(--font-mono); font-size: 0.85em; }
  .val  { color:var(--accent2); }
  .hi   { color:#fff; font-weight:700; }

  .btn {
    display:block; width:100%; padding:15px;
    background:var(--accent); color:var(--black);
    font-family: var(--font-main); font-weight: 700;
    font-size:15px; letter-spacing:0.05em; text-transform:uppercase;
    text-decoration:none; text-align:center; border:none; border-radius:2px;
    cursor:pointer; transition:opacity 0.15s; margin-top:8px;
  }
  .btn:hover { opacity:0.9; }

  hr { border:none; border-top:1px solid var(--border); margin:18px 0; }

  .note { font-size:12px; color:var(--muted); line-height:1.6; margin-top:10px; }
  .note a { color:var(--accent2); text-decoration:none; }

  .footer { max-width:540px; width:92vw; text-align:center; font-family: var(--font-mono); font-size: 10px; color: var(--muted); letter-spacing: 0.06em; }
  .footer a { color:var(--accent2); text-decoration:none; }
</style>
</head>
<body>

<div class="orb orb-1"></div>
<div class="orb orb-2"></div>

<!-- ═══════════════════════════════════════════
     CARTE 1 — VISITEUR / AUDITEUR
     ═══════════════════════════════════════════ -->
<div class="card card-visitor">

  <div class="badge badge-v">Local Node // ${SPOT_NAME}</div>

  <h1>Sound<span class="hl-v">Spot</span></h1>
  <p class="subtitle">// système audio collectif libre — nœud ẐEN</p>

  <div class="waveform" aria-hidden="true">
    <div class="bar" style="--h:12px;--d:0.8s;--delay:0.0s"></div>
    <div class="bar" style="--h:28px;--d:0.9s;--delay:0.1s"></div>
    <div class="bar" style="--h:20px;--d:0.7s;--delay:0.2s"></div>
    <div class="bar" style="--h:36px;--d:1.1s;--delay:0.05s"></div>
    <div class="bar" style="--h:18px;--d:0.85s;--delay:0.3s"></div>
    <div class="bar" style="--h:32px;--d:1.0s;--delay:0.15s"></div>
    <div class="bar" style="--h:24px;--d:0.75s;--delay:0.25s"></div>
    <div class="bar" style="--h:16px;--d:0.9s;--delay:0.4s"></div>
    <div class="bar" style="--h:30px;--d:1.2s;--delay:0.1s"></div>
    <div class="bar" style="--h:22px;--d:0.95s;--delay:0.2s"></div>
  </div>

  <div class="net-info">
    <div class="net-row"><span>Réseau WiFi</span>   <span>${SPOT_NAME} (ouvert)</span></div>
    <div class="net-row"><span>Serveur audio</span> <span><code>${SPOT_IP}:${SNAP_PORT}</code></span></div>
    <div class="net-row"><span>Accès Internet</span><span>Ouvert 15min / Pause 1h</span></div>
  </div>

  <div class="steps">
    <div class="step">
      <div class="step-num n-v">01</div>
      <span>WiFi actif — Connecté à <span class="hi">${SPOT_NAME}</span>.</span>
    </div>
    <div class="step">
      <div class="step-num n-v">02</div>
      <span>Écoute directe via <span class="hi">Snapclient</span> :<br>
        Linux/PC : <code class="val">snapclient -h ${SPOT_IP}</code><br>
        Android : <span class="hi">Snapdroid</span> (Play Store)</span>
    </div>
    <div class="step">
      <div class="step-num n-v">03</div>
      <span>Soutien le collectif ❤️ <a href="https://opencollective.com/monnaie-libre" style="color:var(--accent)">opencollective.com/monnaie-libre</a></span>
    </div>
  </div>

  <hr>

  <a href="https://opencollective.com/monnaie-libre" class="btn">Soutenir le projet →</a>

  <p class="note">
    <strong>Infrastructure Bien Commun.</strong>
    Libre, solaire et décentralisée.
    <a href="https://github.com/papiche/sound-spot">Code source AGPL-3.0</a>
  </p>

</div>

<!-- ═══════════════════════════════════════════
     CARTE 2 — DJ / MIXXX
     ═══════════════════════════════════════════ -->
<div class="card card-dj">

  <div class="badge badge-dj">🎛 Espace DJ — Live Broadcasting</div>

  <h2>Mix sur <span class="hl-dj">ce nœud</span></h2>
  <div class="net-info">
    <div class="net-row"><span>Serveur</span>      <span><code>${SPOT_IP}</code></span></div>
    <div class="net-row"><span>Port / Montage</span><span><code>${ICECAST_PORT}</code> / <code>/live</code></span></div>
    <div class="net-row"><span>Login / Mdp</span>  <span><code>source</code> / <code>${ICECAST_PASS}</code></span></div>
  </div>

  <div class="steps">
    <div class="step"><div class="step-num n-dj">01</div><span>Installe Mixxx & le lanceur via <code class="val">dj_mixxx_setup.sh</code></span></div>
    <div class="step"><div class="step-num n-dj">02</div><span>Configure <span class="hi">Live Broadcasting</span> dans Mixxx</span></div>
    <div class="step"><div class="step-num n-dj">03</div><span>Cale tes mix sur le <span class="hi">Casque (Cue)</span> (latence stream 1s)</span></div>
  </div>
</div>

<div class="footer">
  <p><a href="https://opencollective.com/monnaie-libre">G1FabLab</a> · <a href="https://qo-op.com">UPlanet ẐEN</a></p>
  <p style="margin-top:4px; opacity:0.5; font-size:8px;">PRIVATE NODE // NO GOOGLE FONTS // NO TRACKING</p>
</div>

</body>
</html>
HTMLEOF