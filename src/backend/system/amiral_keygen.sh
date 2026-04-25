#!/bin/bash
# amiral_keygen.sh — Génère la clé Amiral NOSTR déterministe depuis UPLANETNAME
# Chaque nœud du cluster peut calculer la même clé publique sans échange.
# Sortie : $INSTALL_DIR/amiral.nostr  (format NSEC=...; NPUB=...; HEX=...;)
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

# ── Génération via pynostr (même lib que nostr_send_note.py) ─
[ -f "$ASTRO_VENV" ] && source "$ASTRO_VENV" 2>/dev/null || true

python3 - <<PYEOF
import hashlib, sys
try:
    from pynostr.key import PrivateKey
except ImportError:
    print("pynostr non disponible — pip install pynostr dans le venv ~/.astro/", file=sys.stderr)
    sys.exit(1)

uplanetname = "${UPLANETNAME}"
seed = hashlib.sha256(f"{uplanetname}soundspot_fleet".encode()).digest()
priv = PrivateKey(seed)
nsec = priv.bech32()
npub = priv.public_key.bech32()
hex_pub = priv.public_key.hex()

keyfile = "${AMIRAL_KEYFILE}"
with open(keyfile, "w") as f:
    f.write(f"NSEC={nsec}; NPUB={npub}; HEX={hex_pub};\n")

import os
os.chmod(keyfile, 0o600)

with open("${INSTALL_DIR}/amiral.npub", "w") as f:
    f.write(npub + "\n")
with open("${INSTALL_DIR}/amiral.hex", "w") as f:
    f.write(hex_pub + "\n")

print(f"Amiral NPUB : {npub}")
print(f"Amiral HEX  : {hex_pub}")
PYEOF
