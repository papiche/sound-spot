#!/bin/bash
# src/portal/index.sh — Portail captif SoundSpot PicoPort
# SPA vanilla JS/HTML. Toute la logique dynamique passe par api.sh.
# Configuration lue depuis soundspot.conf à chaque requête (hot-reload).

source /opt/soundspot/soundspot.conf 2>/dev/null || true
SPOT_NAME="${SPOT_NAME:-SoundSpot}"
SPOT_IP="${SPOT_IP:-192.168.10.1}"
SNAPCAST_PORT="${SNAPCAST_PORT:-1704}"
ICECAST_PORT="${ICECAST_PORT:-8111}"
PICOPORT_ENABLED="${PICOPORT_ENABLED:-true}"

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
    --black:  #080810; --dark:   #0f0f1a; --panel:  #161622;
    --border: #26263a; --deep:   #1c1c2e;
    --accent: #7fff6e; --teal:   #4ecdc4; --dj:    #ffb347;
    --sat:    #b47fff; --red:    #ff6b6b; --gold:  #ffd700;
    --text:   #e0e0f0; --muted:  #6a6a88;
    --font: system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
    --mono: ui-monospace,"Cascadia Code","Source Code Pro",Menlo,Monaco,Consolas,monospace;
  }
  *, *::before, *::after { margin:0; padding:0; box-sizing:border-box; }
  html { scroll-behavior: smooth; }
  body {
    background: var(--black); color: var(--text); font-family: var(--font);
    display: flex; flex-direction: column; align-items: center;
    padding: 0 0 60px;
  }

  /* ── Hero ── */
  .hero {
    width: 100%; background: var(--dark);
    border-bottom: 1px solid var(--border);
    display: flex; flex-direction: column; align-items: center;
    padding: 32px 20px 24px; text-align: center;
  }
  .hero-logo { font-size: clamp(2rem,8vw,3.2rem); font-weight: 900; letter-spacing: -.04em; color: #fff; }
  .hero-logo span { color: var(--accent); }
  .hero-sub { font-family: var(--mono); font-size: 11px; letter-spacing: .15em; text-transform: uppercase; color: var(--muted); margin: 6px 0 18px; }
  .dj-badge {
    display: inline-flex; align-items: center; gap: 8px;
    padding: 7px 16px; border-radius: 20px; font-size: 13px; font-weight: 700;
    border: 1px solid; transition: all .4s;
  }
  .dj-badge.live   { color: var(--dj); border-color: var(--dj); background: rgba(255,179,71,.08); }
  .dj-badge.idle   { color: var(--muted); border-color: var(--border); background: transparent; }
  .pulse { width: 8px; height: 8px; border-radius: 50%; background: var(--dj); animation: pulse 1.4s infinite; }
  @keyframes pulse { 0%,100%{opacity:1;transform:scale(1)} 50%{opacity:.4;transform:scale(1.5)} }

  /* ── Conteneur cartes ── */
  .cards { display: flex; flex-direction: column; align-items: center; width: 100%; gap: 12px; padding: 20px 16px 0; }
  .card {
    background: var(--panel); border: 1px solid var(--border);
    border-radius: 3px; padding: 24px 22px; width: 100%; max-width: 540px;
    position: relative;
  }
  .card::before { content:''; position:absolute; top:0; left:0; right:0; height:3px; border-radius:3px 3px 0 0; }
  .card-what::before  { background: linear-gradient(90deg,#4a4a7a,#2e2e4a); }
  .card-listen::before{ background: linear-gradient(90deg,var(--teal),var(--accent)); }
  .card-pass::before  { background: linear-gradient(90deg,var(--gold),#ff9966); }
  .card-net::before   { background: linear-gradient(90deg,var(--accent),var(--teal)); }
  .card-dj::before    { background: linear-gradient(90deg,var(--dj),var(--red)); }
  .card-sat::before   { background: linear-gradient(90deg,var(--sat),var(--teal)); }
  .card-yt::before    { background: linear-gradient(90deg,#ff0000,#cc0000); }
  .card-clock::before { background: linear-gradient(90deg,#555,#333); }
  .card-audio::before { background: linear-gradient(90deg,#006e7e,#003f4a); }
  .badge-audio { color:#00d4e8; border:1px solid rgba(0,212,232,.3); background:rgba(0,212,232,.05); }

  /* ── Typographie intra-carte ── */
  .badge {
    display: inline-flex; align-items: center; gap: 5px;
    font-family: var(--mono); font-size: 10px; letter-spacing: .14em; text-transform: uppercase;
    padding: 3px 10px; border-radius: 20px; margin-bottom: 14px;
  }
  .badge-what  { color: #8888bb; border: 1px solid #3a3a5a; background: rgba(100,100,180,.06); }
  .badge-listen{ color: var(--teal); border: 1px solid rgba(78,205,196,.3); background: rgba(78,205,196,.05); }
  .badge-pass  { color: var(--gold); border: 1px solid rgba(255,215,0,.3); background: rgba(255,215,0,.05); }
  .badge-net   { color: var(--accent); border: 1px solid rgba(127,255,110,.3); background: rgba(127,255,110,.05); }
  .badge-dj    { color: var(--dj); border: 1px solid rgba(255,179,71,.3); background: rgba(255,179,71,.05); }
  .badge-sat   { color: var(--sat); border: 1px solid rgba(180,127,255,.3); background: rgba(180,127,255,.05); }
  .badge-yt    { color: #ff4444; border: 1px solid rgba(255,68,68,.3); background: rgba(255,68,68,.05); }
  .badge-clk   { color: #888; border: 1px solid rgba(128,128,128,.3); background: rgba(128,128,128,.05); }

  h2 { font-size: 1.15rem; font-weight: 700; color: #fff; margin: 0 0 10px; }
  p  { line-height: 1.65; color: #9090b0; font-size: .93rem; margin-bottom: 10px; }
  .hi { color: #fff; font-weight: 700; }
  .val { color: var(--teal); font-family: var(--mono); font-size: .88em; }

  /* ── Info-box ── */
  .info-box { background: var(--deep); border: 1px solid var(--border); border-radius: 3px; padding: 11px 14px; margin: 12px 0; }
  .info-row { display:flex; justify-content:space-between; align-items:center; padding: 5px 0; border-bottom: 1px solid var(--border); font-size: .84rem; }
  .info-row:last-child { border-bottom: none; }
  .info-row .lbl { color: var(--muted); }
  .info-row .val  { color: var(--text); font-family: var(--mono); }

  /* ── Steps ── */
  .steps { display:flex; flex-direction:column; gap:9px; margin: 12px 0; }
  .step  { display:flex; align-items:flex-start; gap:10px; font-size:.9rem; color:#9090b0; line-height:1.55; }
  .sn    { font-family:var(--mono); font-size:10px; border-radius:2px; padding:2px 6px; white-space:nowrap; margin-top:2px; min-width:26px; text-align:center; flex-shrink:0; }
  .sn-t  { color:var(--teal); border:1px solid var(--teal); }
  .sn-g  { color:var(--gold); border:1px solid var(--gold); }
  .sn-dj { color:var(--dj);   border:1px solid var(--dj); }
  .sn-s  { color:var(--sat);  border:1px solid var(--sat); }
  a { color: var(--teal); text-decoration: none; }
  a:hover { color: var(--accent); }

  /* ── Boutons ── */
  .btn {
    display: block; width: 100%; padding: 14px; text-align: center;
    font-family: var(--font); font-weight: 700; font-size: 14px; letter-spacing: .06em;
    text-transform: uppercase; border: none; border-radius: 3px;
    cursor: pointer; transition: opacity .15s, transform .1s; margin-top: 10px;
    text-decoration: none;
  }
  .btn:active { transform: scale(.98); }
  .btn:hover  { opacity: .85; }
  .btn-green  { background: var(--accent); color: var(--black); }
  .btn-teal   { background: var(--teal);   color: var(--black); }
  .btn-gold   { background: var(--gold);   color: var(--black); }
  .btn-dj     { background: var(--dj);     color: #000; }
  .btn-sat    { background: var(--sat);    color: #000; }
  .btn-red    { background: #cc0000;       color: #fff; }
  .btn-outline{ background: transparent; border: 1px solid var(--border); color: var(--muted); }
  .btn-sm     { padding: 9px 14px; font-size: 12px; margin-top: 6px; }
  .row { display:flex; gap:8px; flex-wrap:wrap; }
  .row .btn   { flex: 1; }

  /* ── Accordéon ── */
  details summary {
    cursor: pointer; list-style: none; display: flex; align-items: center;
    justify-content: space-between; padding: 18px 22px; margin: 0 -22px;
    border-top: 1px solid var(--border); font-size: .9rem; font-weight: 600; color: var(--muted);
  }
  details summary::-webkit-details-marker { display: none; }
  details summary::after { content: '▾'; font-size: 12px; transition: transform .2s; }
  details[open] summary::after { transform: rotate(-180deg); }
  details[open] summary { color: var(--text); }
  .detail-body { padding-top: 14px; }

  /* ── Formulaire yt-dlp ── */
  .yt-input {
    width: 100%; padding: 11px 14px; background: var(--deep); border: 1px solid var(--border);
    border-radius: 3px; color: var(--text); font-family: var(--mono); font-size: .88rem;
    outline: none; margin-top: 8px;
  }
  .yt-input:focus { border-color: #cc0000; }
  #yt-result { margin-top: 10px; font-size: .85rem; font-family: var(--mono); color: var(--teal); display:none; }
  #yt-result.err { color: var(--red); }

  /* ── Toast notification ── */
  #toast {
    position: fixed; bottom: 20px; left: 50%; transform: translateX(-50%) translateY(80px);
    background: var(--panel); border: 1px solid var(--accent); color: var(--accent);
    padding: 10px 22px; border-radius: 20px; font-size: 13px; font-weight: 600;
    transition: transform .3s ease; z-index: 999; pointer-events: none;
  }
  #toast.show { transform: translateX(-50%) translateY(0); }

  /* ── Footer ── */
  .footer {
    max-width: 540px; width: 100%; text-align: center;
    font-family: var(--mono); font-size: 9px; color: var(--muted);
    letter-spacing: .07em; margin-top: 12px; padding: 0 16px;
  }
  .footer a { color: var(--muted); }
  .footer a:hover { color: var(--teal); }

  /* ── Tag CLOCK live ── */
  #clock-label { font-family: var(--mono); font-size: .82rem; }
</style>
</head>
<body>

<!-- ═══ HERO ═══ -->
<div class="hero">
  <div class="hero-logo">Sound<span>Spot</span></div>
  <div class="hero-sub" id="spot-name">Nœud // ${SPOT_NAME}</div>
  <div class="dj-badge idle" id="dj-status">
    <div class="pulse" style="display:none" id="dj-dot"></div>
    <span id="dj-text">Chargement…</span>
  </div>
</div>

<div class="cards">

<!-- ═══ CARTE 1 : C'EST QUOI ? ═══ -->
<div class="card card-what">
  <div class="badge badge-what">Bien Commun Numérique</div>
  <h2>SoundSpot PicoPort</h2>
  <p>Un <span class="hi">nœud coopératif libre</span> : WiFi ouvert, son synchronisé, infrastructure hors-ligne autonome, sans publicité ni collecte de données.</p>
  <p>Il appartient à la constellation <span class="hi">UPlanet</span> — réseau P2P de nœuds IPFS + NOSTR reliés par la monnaie libre <span class="hi">Ğ1</span>.</p>
  <div class="info-box">
    <div class="info-row"><span class="lbl">WiFi</span>       <span class="val">${SPOT_NAME} (ouvert)</span></div>
    <div class="info-row"><span class="lbl">Stream audio</span><span class="val" id="stream-addr">${SPOT_IP}:${SNAPCAST_PORT}</span></div>
    <div class="info-row"><span class="lbl">Picoport IPFS</span><span class="val" id="picoport-status">—</span></div>
  </div>
  <div class="row">
    <a href="docs.sh" class="btn btn-outline btn-sm" style="flex:none;width:auto">README →</a>
    <a href="docs.sh?howto" class="btn btn-outline btn-sm" style="flex:none;width:auto">HOWTO →</a>
  </div>
</div>

<!-- ═══ CARTE 2 : ÉCOUTER ═══ -->
<div class="card card-listen">
  <div class="badge badge-listen">🎧 Écouter en direct</div>
  <h2>Rejoindre le stream audio</h2>
  <p>Synchronisé à la milliseconde sur tous les haut-parleurs de l'espace. Zéro latence perçue.</p>
  <div class="steps">
    <div class="step"><div class="sn sn-t">01</div><span>Connecté à <span class="hi">${SPOT_NAME}</span> ✓</span></div>
    <div class="step"><div class="sn sn-t">02</div>
      <span>Installer <span class="hi">Snapcast</span> :<br>
        📱 Android : <a href="https://f-droid.org/en/packages/de.badaix.snapcast/">Snapdroid (F-Droid)</a>
          · <a href="https://play.google.com/store/apps/details?id=de.badaix.snapcast">Play Store</a><br>
        🍎 iOS : <a href="https://apps.apple.com/app/snapcast-client/id1552559654">Snapcast for iOS</a><br>
        🖥 PC : <code class="val">snapclient -h ${SPOT_IP}</code></span></div>
    <div class="step"><div class="sn sn-t">03</div><span>Serveur : <code class="val">${SPOT_IP}</code> Port : <code class="val">${SNAPCAST_PORT}</code></span></div>
  </div>
</div>

<!-- ═══ CARTE 3 : MULTIPASS ZELKOVA ═══ -->
<div class="card card-pass">
  <div class="badge badge-pass">🪪 Identité coopérative</div>
  <h2>Obtenir son MULTIPASS Ẑelkova</h2>
  <p>Le <span class="hi">MULTIPASS</span> est votre identité dans la constellation UPlanet : identité <span class="hi">Ğ1</span>, compte <span class="hi">NOSTR</span>, accès aux services ẐEN.</p>
  <div class="steps">
    <div class="step"><div class="sn sn-g">01</div>
      <span>Installer l'app <span class="hi">Ẑelkova</span> (wallet ẐEN) :<br>
        📱 Android : <a href="https://github.com/papiche/zelkova/releases/latest">APK GitHub release</a><br>
        <!-- 📱 Play Store : TODO --><br>
        <!-- 🍎 App Store : TODO -->
      </span></div>
    <div class="step"><div class="sn sn-g">02</div>
      <span>Créer votre profil → votre <span class="hi">clé NOSTR</span> + <span class="hi">identité Ğ1</span> sont générés localement.</span></div>
    <div class="step"><div class="sn sn-g">03</div>
      <span>Votre MULTIPASS vous relie à la coopérative <a href="https://opencollective.com/monnaie-libre">G1FabLab</a> et au réseau <span class="hi">UPlanet ẐEN</span>.</span></div>
    <div class="step"><div class="sn sn-g">04</div>
      <span>Ce nœud peut émettre des <span class="hi">ZenCards</span> — demandez à l'opérateur du spot.</span></div>
  </div>
  <a href="https://github.com/papiche/zelkova/releases/latest" class="btn btn-gold btn-sm">Télécharger Ẑelkova →</a>
</div>

<!-- ═══ CARTE 4 : ACCÈS INTERNET ═══ -->
<div class="card card-net">
  <div class="badge badge-net">🌐 Accès Internet</div>
  <h2>Ouvrir l'accès — 15 min</h2>
  <p>Un accès internet limité est proposé. Après 15 min, revenez sur cette page pour revalider.</p>
  <p>Le stream audio reste <span class="hi">accessible sans limite</span> — privilégiez-le.</p>
  <button class="btn btn-green" id="btn-auth" onclick="doAuth()">Ouvrir l'accès Internet →</button>
  <p id="auth-msg" style="margin-top:8px;font-size:.82rem;color:var(--teal);display:none"></p>
</div>

<!-- ═══ CARTE 5 : DEVENIR DJ (accordéon) ═══ -->
<div class="card card-dj">
  <details>
    <summary><span><div class="badge badge-dj" style="margin:0">🎛 Espace DJ</div></span></summary>
    <div class="detail-body">
      <h2>Diffuser votre musique</h2>
      <div class="info-box">
        <div class="info-row"><span class="lbl">Serveur Icecast</span><span class="val">${SPOT_IP}:${ICECAST_PORT}</span></div>
        <div class="info-row"><span class="lbl">Montage</span>         <span class="val">/live</span></div>
        <div class="info-row"><span class="lbl">Login / Mdp</span>     <span class="val">source / (cf. opérateur)</span></div>
      </div>
      <div class="steps">
        <div class="step"><div class="sn sn-dj">01</div><span>Installer <span class="hi">Mixxx</span> + <code class="val">snapclient</code></span></div>
        <div class="step"><div class="sn sn-dj">02</div><span>Retour casque : <code class="val">snapclient -h ${SPOT_IP}</code></span></div>
        <div class="step"><div class="sn sn-dj">03</div>
          <span>Mixxx → Préférences → Live Broadcasting<br>
            Serveur <code class="val">${SPOT_IP}</code> Port <code class="val">${ICECAST_PORT}</code>
            Montage <code class="val">/live</code> Format <code class="val">Ogg Vorbis</code></span></div>
        <div class="step"><div class="sn sn-dj">04</div><span>Cliquer sur l'icône <span class="hi">Antenne</span> → vous êtes en direct</span></div>
      </div>
      <p style="font-size:.8rem;margin-top:4px;color:var(--muted)">⚠ Latence 1–3 s — calez vos transitions sur le casque Cue, pas sur les enceintes.</p>
      <a href="docs.sh?howto" class="btn btn-dj btn-sm">Guide DJ complet →</a>
    </div>
  </details>
</div>

<!-- ═══ CARTE 6 : ÉTENDRE (accordéon) ═══ -->
<div class="card card-sat">
  <details>
    <summary><span><div class="badge badge-sat" style="margin:0">📡 Réseau de Nœuds</div></span></summary>
    <div class="detail-body">
      <h2>Ajouter une enceinte satellite</h2>
      <div class="steps">
        <div class="step"><div class="sn sn-s">01</div><span>Flasher un <span class="hi">RPi Zero 2W</span> avec Raspberry Pi OS Lite</span></div>
        <div class="step"><div class="sn sn-s">02</div><span>Connecter au WiFi <code class="val">${SPOT_NAME}</code> ou <code class="val">qo-op</code></span></div>
        <div class="step"><div class="sn sn-s">03</div>
          <span><code class="val">git clone https://github.com/papiche/sound-spot</code><br>
            <code class="val">sudo bash deploy_on_pi.sh --satellite</code></span></div>
        <div class="step"><div class="sn sn-s">04</div><span>Maître : <code class="val">${SPOT_IP}</code> ou <code class="val">soundspot.local</code></span></div>
      </div>
    </div>
  </details>
</div>

<!-- ═══ CARTE 7 : COPIE YOUTUBE (accordéon) ═══ -->
<div class="card card-yt" id="card-yt" style="display:none">
  <details>
    <summary><span><div class="badge badge-yt" style="margin:0">📥 Copie YouTube → IPFS</div></span></summary>
    <div class="detail-body">
      <h2>Archiver une vidéo (audio MP3)</h2>
      <p>Télécharge l'audio d'une vidéo YouTube et l'épingle sur ce nœud IPFS. Accessible en hors-ligne via la gateway locale.</p>
      <div class="info-box">
        <div class="info-row"><span class="lbl">Format</span><span class="val">MP3 (audio uniquement)</span></div>
        <div class="info-row"><span class="lbl">Gateway</span><span class="val">http://${SPOT_IP}:8080/ipfs/&lt;CID&gt;</span></div>
      </div>
      <input class="yt-input" type="text" id="yt-url" placeholder="Lien YouTube ou recherche (ex: Daft Punk)">
      <button class="btn btn-red btn-sm" onclick="doYtCopy()" id="btn-yt">Télécharger et épingler →</button>
      <div id="yt-result"></div>
    </div>
  </details>
</div>

<!-- ═══ CARTE 8 : CLOCHER (accordéon) ═══ -->
<div class="card card-clock">
  <details>
    <summary><span><div class="badge badge-clk" style="margin:0">⏰ Clocher Numérique</div></span></summary>
    <div class="detail-body">
      <h2 style="color:#aaa">Annonces sonores</h2>
      <p>Toutes les 15 min (sans DJ) : bip 429.62 Hz + heure solaire + message coopératif.</p>
      <div class="info-box">
        <div class="info-row"><span class="lbl">Bip 429.62 Hz</span><span class="val">Toujours actif</span></div>
        <div class="info-row"><span class="lbl">Messages</span>     <span class="val">Toujours actifs</span></div>
        <div class="info-row"><span class="lbl">Coups de cloche</span><span class="val" id="clock-label">…</span></div>
      </div>
      <button class="btn btn-outline btn-sm" id="btn-clock" onclick="toggleClock()" style="margin-top:12px">…</button>
      <p style="font-size:.78rem;color:var(--muted);margin-top:6px">Effectif immédiatement, sans redémarrage.</p>
    </div>
  </details>
</div>

<!-- ═══ CARTE 9 : SORTIE AUDIO (accordéon) ═══ -->
<div class="card card-audio" id="card-audio" style="display:none">
  <details>
    <summary><span><div class="badge badge-audio" style="margin:0">🔊 Sortie Audio</div></span></summary>
    <div class="detail-body">
      <h2>Choisir la sortie sonore</h2>
      <p>Sélectionner vers quelle sortie le son est envoyé. Le service audio redémarre automatiquement (2–3 s).</p>
      <div id="audio-sinks-list" style="margin-top:10px">
        <p style="color:var(--muted);font-size:.85rem">Détection des sorties…</p>
      </div>
    </div>
  </details>
</div>

</div><!-- /cards -->

<div class="footer">
  <a href="https://opencollective.com/monnaie-libre">G1FabLab</a> ·
  <a href="https://qo-op.com">UPlanet ẐEN</a> ·
  <a href="https://github.com/papiche/sound-spot">Code AGPL-3.0</a><br>
  <span style="opacity:.35">NO GOOGLE FONTS // NO TRACKING // SOLAR POWERED</span>
</div>

<div id="toast">✓</div>

<script>
// ── État global ─────────────────────────────────────────────
let clockMode = 'bells';

function toast(msg, ok=true) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.style.borderColor = ok ? 'var(--accent)' : 'var(--red)';
  t.style.color       = ok ? 'var(--accent)' : 'var(--red)';
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 2800);
}

// ── Chargement du statut (api.sh?action=status) ────────────
async function loadStatus() {
  try {
    const r = await fetch('/api.sh?action=status');
    const d = await r.json();
    // DJ
    const badge  = document.getElementById('dj-status');
    const dot    = document.getElementById('dj-dot');
    const txt    = document.getElementById('dj-text');
    if (d.dj_active) {
      badge.className = 'dj-badge live';
      dot.style.display = '';
      txt.textContent = '🎵 DJ en direct';
    } else {
      badge.className = 'dj-badge idle';
      dot.style.display = 'none';
      txt.textContent = 'Pas de diffusion en cours';
    }
    // Picoport
    const pp = document.getElementById('picoport-status');
    if (pp) pp.textContent = d.picoport_active ? '✓ Actif' : '✗ Inactif';
    // Clocher
    clockMode = d.clock_mode || 'bells';
    updateClockUI();
    // Afficher carte yt seulement si Picoport actif
    if (d.picoport_active) {
      document.getElementById('card-yt').style.display = '';
    }
  } catch(e) {
    document.getElementById('dj-text').textContent = 'Connexion…';
  }
}

function updateClockUI() {
  const lbl = document.getElementById('clock-label');
  const btn = document.getElementById('btn-clock');
  if (!lbl || !btn) return;
  if (clockMode === 'bells') {
    lbl.textContent = '🔔 Activées';
    btn.textContent = 'Désactiver les cloches';
  } else {
    lbl.textContent = '🔇 Silencieuses';
    btn.textContent = 'Activer les cloches';
  }
}

// ── Autorisation Internet ───────────────────────────────────
async function doAuth() {
  const btn = document.getElementById('btn-auth');
  const msg = document.getElementById('auth-msg');
  btn.disabled = true;
  btn.textContent = 'Ouverture…';
  try {
    const r = await fetch('/api.sh?action=auth', { method: 'POST' });
    const d = await r.json();
    if (d.status === 'authorized') {
      btn.textContent = '✓ Accès ouvert (15 min)';
      btn.style.background = 'var(--teal)';
      msg.style.display = '';
      msg.textContent = 'Accès internet ouvert pour 15 min. Bonne navigation !';
      toast('✅ Accès Internet ouvert — 15 min');
    } else {
      btn.disabled = false;
      btn.textContent = 'Ouvrir l\'accès Internet →';
      toast('Erreur : ' + (d.error || 'inconnue'), false);
    }
  } catch(e) {
    btn.disabled = false;
    btn.textContent = 'Ouvrir l\'accès Internet →';
    toast('Erreur réseau', false);
  }
}

// ── Toggle clocher ──────────────────────────────────────────
async function toggleClock() {
  const nextMode = clockMode === 'bells' ? 'silent' : 'bells';
  try {
    const r = await fetch('/api.sh?action=clock', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: 'mode=' + nextMode
    });
    const d = await r.json();
    if (d.status === 'ok') {
      clockMode = d.clock_mode;
      updateClockUI();
      toast(clockMode === 'bells' ? '🔔 Cloches activées' : '🔇 Cloches désactivées');
    }
  } catch(e) {
    toast('Erreur réseau', false);
  }
}

// ── Copie YouTube ───────────────────────────────────────────
async function doYtCopy() {
  const url = document.getElementById('yt-url').value.trim();
  const res = document.getElementById('yt-result');
  const btn = document.getElementById('btn-yt');
  if (!url) { toast('URL ou recherche requise', false); return; }

  if (!window.nostr) {
    res.style.display = '';
    res.className = 'err';
    res.innerHTML = "⚠ MULTIPASS introuvable.<br>Installez l'extension Nostr ou l'app Ẑelkova pour vous identifier.";
    return;
  }

  btn.disabled = true;
  btn.textContent = 'Signature MULTIPASS en cours…';
  res.style.display = 'none';

  try {
    let relayUrl = "ws://" + window.location.hostname + ":9999"; 
    if (window.location.hostname.includes("ipfs.")) {
        relayUrl = "wss://" + window.location.hostname.replace("ipfs.", "relay.");
    }

    const event = {
        kind: 1,
        created_at: Math.floor(Date.now() / 1000),
        tags:[["expiration", String(Math.floor(Date.now() / 1000) + 3600)], ["t", "jukebox"]],
        content: `#BRO #youtube #mp3 ${url}`
    };

    const signedEvent = await window.nostr.signEvent(event);
    const ws = new WebSocket(relayUrl);

    ws.onopen = () => {
        ws.send(JSON.stringify(["EVENT", signedEvent]));
        res.style.display = '';
        res.className = '';
        res.innerHTML = "✔ <b>Transmis au Capitaine !</b><br>L'IA distante traite l'audio. Il sera copié dans votre uDRIVE et joué à l'antenne sous peu.";
        toast('✅ Demande envoyée à l\'essaim');
        document.getElementById('yt-url').value = '';
        setTimeout(() => ws.close(), 2000);
    };
    ws.onerror = () => { toast('❌ Impossible de joindre le relai', false); };
  } catch(e) {
    toast('Erreur de signature : ' + e.message, false);
  } finally {
    btn.disabled = false;
    btn.textContent = 'Télécharger et épingler →';
  }
}

// ── Sortie audio ────────────────────────────────────────────
async function loadAudioSinks() {
  try {
    const r = await fetch('/api.sh?action=audio_output');
    const sinks = await r.json();
    const el = document.getElementById('audio-sinks-list');
    if (!Array.isArray(sinks) || !sinks.length) return;
    document.getElementById('card-audio').style.display = '';
    let html = '<div class="row" style="flex-wrap:wrap;gap:8px">';
    sinks.forEach(function(s) {
      var cls = s.active ? 'btn-teal' : 'btn-outline';
      var chk = s.active ? ' \u2713' : '';
      html += '<button class="btn btn-sm ' + cls + '" onclick="setAudioSink(\'' + s.name + '\')"' +
              ' style="flex:none;min-width:130px">' + s.label + chk + '</button>';
    });
    html += '</div>';
    el.innerHTML = html;
  } catch(e) {}
}

async function setAudioSink(sinkName) {
  try {
    const r = await fetch('/api.sh?action=audio_output', {
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: 'sink=' + encodeURIComponent(sinkName)
    });
    const d = await r.json();
    if (d.status === 'ok') {
      toast('🔊 Sortie changée');
      setTimeout(loadAudioSinks, 3500); // laisser soundspot-client redémarrer
    } else {
      toast('Erreur : ' + (d.message || 'inconnue'), false);
    }
  } catch(e) { toast('Erreur réseau', false); }
}

// ── Init ────────────────────────────────────────────────────
loadStatus();
loadAudioSinks();
setInterval(loadStatus, 30000); // rafraîchir toutes les 30s
</script>

</body>
</html>
HTMLEOF
