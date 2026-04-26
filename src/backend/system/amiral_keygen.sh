#!/bin/bash
# amiral_keygen.sh — Clé NOSTR Amiral déterministe depuis UPLANETNAME
# Utilise keygen (Astroport.ONE) — conforme à la constellation UPlanet.
# Chaque nœud du cluster calcule la même clé publique sans échange.
# Sortie : $INSTALL_DIR/amiral.nostr  (NSEC=...; NPUB=...; HEX=...)
#          $INSTALL_DIR/amiral.npub   (npub bech32 — diffusé publiquement)
#          $INSTALL_DIR/amiral.hex    (pubkey hex — utilisé par fleet_listener)

INSTALL_DIR="${INSTALL_DIR:-/opt/soundspot}"
SOUNDSPOT_USER="${SOUNDSPOT_USER:-pi}"
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)
ASTRO_TOOLS="${USER_HOME}/.zen/Astroport.ONE/tools"
ASTRO_VENV="${USER_HOME}/.astro/bin/activate"

AMIRAL_KEYFILE="${INSTALL_DIR}/amiral.nostr"

if [ -f "$AMIRAL_KEYFILE" ]; then
    echo "Clé Amiral déjà générée : $AMIRAL_KEYFILE"
    cat "$AMIRAL_KEYFILE"
    exit 0
fi

# ── UPLANETNAME : secret partagé du cluster ──────────────────
SWARM_KEY="${USER_HOME}/.ipfs/swarm.key"
if [ -f "$SWARM_KEY" ]; then
    UPLANETNAME=$(tail -n 1 "$SWARM_KEY")
else
    UPLANETNAME=$(printf '%064d' 0)
    echo "⚠ swarm.key absent — UPLANETNAME = 64 zéros (cluster non sécurisé)"
fi

# ── Vérification de keygen (Astroport.ONE) ──────────────────
if [ ! -f "${ASTRO_TOOLS}/keygen" ]; then
    echo "❌ keygen introuvable dans ${ASTRO_TOOLS} — Astroport light non installé ?" >&2
    exit 1
fi

[ -f "$ASTRO_VENV" ] && source "$ASTRO_VENV" 2>/dev/null || true

# ── Dérivation déterministe : sha512("soundspot_fleet" + UPLANETNAME) ──
HASH=$(echo -n "soundspot_fleet${UPLANETNAME}" | sha512sum | cut -d ' ' -f 1)
SECRET1=$(echo "$HASH" | cut -c 1-64)
SECRET2=$(echo "$HASH" | cut -c 65-128)

# ── Génération via keygen (conforme Astroport.ONE) ──────────
npub=$(python3 "${ASTRO_TOOLS}/keygen" -t nostr "$SECRET1" "$SECRET2")
nsec=$(python3 "${ASTRO_TOOLS}/keygen" -t nostr -s "$SECRET1" "$SECRET2")
hex=$(python3 "${ASTRO_TOOLS}/nostr2hex.py" "$npub")

# ── Écriture des fichiers de sortie ─────────────────────────
echo "NSEC=${nsec}; NPUB=${npub}; HEX=${hex};" > "${AMIRAL_KEYFILE}"
chmod 600 "${AMIRAL_KEYFILE}"

echo "${npub}" > "${INSTALL_DIR}/amiral.npub"
echo "${hex}" > "${INSTALL_DIR}/amiral.hex"

echo "Amiral NPUB : ${npub}"
echo "Amiral HEX  : ${hex}"
