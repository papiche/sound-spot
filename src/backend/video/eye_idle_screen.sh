#!/bin/bash
# eye_idle_screen.sh — Génère le diaporama d'accueil HDMI (rotation d'images)
#
# Priorité absolue de l'essaim : Promotion de l'OpenCollective et du Bien Commun.
#
# Affiché en boucle par rtmp_player.sh tant qu'aucun flux VJ ni photo mon-oeil
# récente n'est actif :
#   1. Focus OpenCollective — Financement du développement de l'essaim
#   2. Portail captif — QR direct pour les téléphones qui ne redirigent pas
#   3. Streamer en DJ — coordonnées Icecast + QR vers le guide complet
#   4. Devenir source VJ — QR flux RTMP + QR app Larix Broadcaster (Android/iOS)
#   5. Les 5 piliers Made In Zion — QR vers chaque page, servie localement
#        via UPassport (/earth/*.html, fonctionne hors-ligne, sans Internet)
#
# Tous les slides intègrent un bandeau persistant incitant au don.
set -e

SPOT_HOST="${SPOT_IP:-192.168.10.1}"
UPASSPORT_URL="http://127.0.0.1:54321"
OUT_DIR="/dev/shm/eye_idle"
RTMP_URL="rtmp://${SPOT_HOST}/live/vj"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
STAGE_DIR="$TMP_DIR/slides"
mkdir -p "$STAGE_DIR"

_urlencode() {
    python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

_qr() {
    # _qr <data> <out.png>
    curl -sf --max-time 10 "${UPASSPORT_URL}/qr?data=$(_urlencode "$1")" -o "$2"
}

# Filigrane de promotion globale appliqué à chaque slide (Soutien OpenCollective)
_apply_footer() {
    local img="$1"
    convert "$img" \
        -fill '#161628' -draw "rectangle 0,660 1280,720" \
        -font "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" \
        -gravity South -pointsize 18 -fill '#7fff6e' \
        -annotate +0+32 "Soutenez le développement logiciel et notre constellation libre de stations" \
        -gravity South -pointsize 14 -fill '#aaaacc' \
        -annotate +0+10 "Faites un don sur : opencollective.com/monnaie-libre" \
        "$img"
}

# ── Slide 1 : Rejoindre la coopérative & Financement de la constellation ────
# C'est la première image visible au démarrage et la plus fréquente du carrousel.
COLLECTIVE_URL="https://opencollective.com/monnaie-libre"
_qr "$COLLECTIVE_URL" "$TMP_DIR/qr_collectif.png"

convert -size 1280x720 xc:'#080810' \
    -font "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" \
    -gravity North -pointsize 42 -fill '#7fff6e' -annotate +0+40 "CONSTELLATION LIBRE UPLANET" \
    -gravity North -pointsize 20 -fill '#e0d0d8' -annotate +0+100 "Cette station et son logiciel libre survivent grâce à vos dons." \
    \( "$TMP_DIR/qr_collectif.png" -resize 350x360 -bordercolor white -border 12 \) -gravity Center -geometry +0+40 -composite \
    -gravity South -pointsize 22 -fill '#ffffff' -annotate +0+110 "Scannez pour financer l'essaim et les mises à jour" \
    "jpg:$STAGE_DIR/01_collectif.jpg"
_apply_footer "$STAGE_DIR/01_collectif.jpg"

# ── Slide 2 : portail captif (accès direct si l'auto-redirection échoue) ───
PORTAL_URL="http://${SPOT_HOST}/"
_qr "$PORTAL_URL" "$TMP_DIR/qr_portail.png"
convert -size 1280x720 xc:'#080810' \
    -font "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" \
    -gravity North -pointsize 40 -fill white -annotate +0+50 "Pas de redirection automatique ?" \
    \( "$TMP_DIR/qr_portail.png" -resize 350x350 -bordercolor white -border 12 \) -gravity Center -geometry +0+20 -composite \
    -gravity South -pointsize 26 -fill '#7fff6e' -annotate +0+115 "Scannez pour ouvrir le portail" \
    -gravity South -pointsize 18 -fill '#aaaacc' -annotate +0+90 "${PORTAL_URL}" \
    "jpg:$STAGE_DIR/02_portail.jpg"
_apply_footer "$STAGE_DIR/02_portail.jpg"

# ── Slide 3 : streamer en DJ (Icecast) ──────────────────────────────────────
DOCS_DJ_URL="http://${SPOT_HOST}/docs.html#howto-dj-configuration.md"
_qr "$DOCS_DJ_URL" "$TMP_DIR/qr_dj.png"

convert -size 1280x720 xc:'#080810' \
    -font "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" \
    -gravity North -pointsize 40 -fill white -annotate +0+40 "Streamer en DJ (Icecast)" \
    \( "$TMP_DIR/qr_dj.png" -resize 320x320 -bordercolor white -border 10 \) \
        -gravity West -geometry +100+40 -composite \
    -size 600x400 -gravity East -pointsize 28 -fill '#ffb347' \
    -annotate +100+10 "Broadcaster → Icecast2" \
    -gravity East -pointsize 24 -fill '#dcdce8' \
    -annotate +100+60  "Hôte : ${SPOT_HOST}" \
    -annotate +100+100 "Port : 8111" \
    -annotate +100+140 "Montage : /live" \
    -annotate +100+180 "Login : source" \
    -gravity SouthEast -pointsize 18 -fill '#7a7a95' \
    -annotate +100+90 "$DOCS_DJ_URL" \
    "jpg:$STAGE_DIR/03_dj.jpg"
_apply_footer "$STAGE_DIR/03_dj.jpg"

# ── Slide 4 : devenir source VJ (flux RTMP + app Larix Broadcaster) ────────
_qr "$RTMP_URL" "$TMP_DIR/qr_rtmp.png"
_qr "https://play.google.com/store/apps/details?id=com.wmspanel.larix_broadcaster" "$TMP_DIR/qr_android.png"
_qr "https://apps.apple.com/us/app/larix-broadcaster/id1042474385" "$TMP_DIR/qr_ios.png"

convert -size 1280x720 xc:'#080810' \
    -font "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" \
    -gravity North -pointsize 40 -fill white -annotate +0+40 "Devenir source VJ (RTMP)" \
    \( "$TMP_DIR/qr_rtmp.png"    -resize 260x260 -bordercolor white -border 10 \) -gravity NorthWest -geometry +100+160 -composite \
    \( "$TMP_DIR/qr_android.png" -resize 260x260 -bordercolor white -border 10 \) -gravity NorthWest -geometry +510+160 -composite \
    \( "$TMP_DIR/qr_ios.png"     -resize 260x260 -bordercolor white -border 10 \) -gravity NorthWest -geometry +920+160 -composite \
    -gravity NorthWest -pointsize 18 -fill '#aaaacc' \
    -annotate +125+455 "Flux RTMP" \
    -annotate +515+455 "Android — Larix" \
    -annotate +925+455 "iPhone — Larix" \
    -gravity South -pointsize 16 -fill '#7a7a95' \
    -annotate +0+90 "Larix Broadcaster — app gratuite pour diffuser votre caméra en RTMP" \
    "jpg:$STAGE_DIR/04_vj.jpg"
_apply_footer "$STAGE_DIR/04_vj.jpg"

# ── Slides 5-9 : les 5 piliers Made In Zion ─────────────────────────────────
_slide_pillar() {
    local num="$1" slug="$2" title="$3" quote="$4"
    local page_url="http://${SPOT_HOST}:54321/earth/${slug}.html"
    _qr "$page_url" "$TMP_DIR/qr_${slug}.png"
    convert -size 1280x720 xc:'#080810' \
        -font "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" \
        -gravity North -pointsize 36 -fill white -annotate +0+45 "$title" \
        \( "$TMP_DIR/qr_${slug}.png" -resize 320x320 -bordercolor white -border 10 \) \
            -gravity West -geometry +100+40 -composite \
        \( -size 600x400 -background none -fill '#c0aaff' -pointsize 26 caption:"« ${quote} »" \) \
            -gravity East -geometry +100+40 -composite \
        -gravity SouthEast -pointsize 18 -fill '#7a7a95' -annotate +100+90 "$page_url" \
        "jpg:$STAGE_DIR/${num}_${slug}.jpg"
    _apply_footer "$STAGE_DIR/${num}_${slug}.jpg"
}

_slide_pillar 05 miz       "Académie Made In Zion — Les 4 Piliers"  "Une école pour hacker la Matrice. Démystifier la matière pour libérer l'esprit."
_slide_pillar 06 vaisseau  "Le Vaisseau — Habitat Moulé Autonome"   "Un dôme géodésique moulé se construit en 3 à 5 jours en collectif, sans engin lourd."
_slide_pillar 07 moteur    "Le Moteur — Énergie & Thermodynamique"  "L'énergie est partout — il suffit de la transformer."
_slide_pillar 08 mouvement "Le Mouvement — Mobilité Libre"          "Nous ne traçons plus de routes, nous épousons les vents."
_slide_pillar 09 oasis     "L'Oasis — Forêt-Jardin & Abondance"     "L'abondance est un choix de design, pas un miracle qu'on attend passivement."

# ── Bascule atomique ─────────────────────────────────────────────────────
rm -rf "$OUT_DIR"
mv "$STAGE_DIR" "$OUT_DIR"