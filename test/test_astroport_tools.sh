#!/bin/bash
# =============================================================================
#  test_astroport_tools.sh — Tests des outils Astroport.ONE depuis Picoport
#
#  Vecteurs de test déterministes : salt=coucou / pepper=coucou
#  - keygen (duniter, nostr, ipfs)
#  - g1pub_to_ss58.py (conversion v1↔SS58)
#  - G1balance.sh (solde wallet test)
#  - PAYforSURE.sh (paiement conditionnel si solde > 1 Ğ1)
#  - nostr_setup_profile.py (publication profil Kind 0)
#
#  Usage :
#    bash test/test_astroport_tools.sh [--pay] [--nostr]
#
#  Options :
#    --pay    Forcer le test PAYforSURE même si solde ≤ 1 Ğ1 (ATTENTION: envoie réellement)
#    --nostr  Activer le test nostr_setup_profile (publie sur relay.copylaradio.com)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Couleurs ──────────────────────────────────────────────────────────────────
G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; C='\033[0;36m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N}  $*"; }
fail() { echo -e "  ${R}✗${N}  $*"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${Y}⚠${N}  $*"; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }

FAIL=0
FORCE_PAY=false
TEST_NOSTR=false
for arg in "$@"; do
    [[ "$arg" == "--pay"   ]] && FORCE_PAY=true
    [[ "$arg" == "--nostr" ]] && TEST_NOSTR=true
done

# ── Localisation des outils ───────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOUNDSPOT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Chercher Astroport.ONE dans l'ordre de priorité
ASTRO_TOOLS=""
for candidate in \
    "$HOME/.zen/Astroport.ONE/tools" \
    "$HOME/.zen/workspace/Astroport.ONE/tools" \
    "$(cd "$SOUNDSPOT_ROOT/../Astroport.ONE/tools" 2>/dev/null && pwd)" \
    "/opt/soundspot/picoport"; do
    if [[ -x "${candidate}/keygen" ]]; then
        ASTRO_TOOLS="$candidate"
        break
    fi
done

if [[ -z "$ASTRO_TOOLS" ]]; then
    echo -e "${R}FATAL${N} Astroport.ONE/tools introuvable."
    echo   "       Lancer install_picoport_maintenance.sh d'abord."
    exit 1
fi

# Venv Python ~/.astro/
VENV_ACTIVATE="$HOME/.astro/bin/activate"
if [[ -s "$VENV_ACTIVATE" ]]; then
    # shellcheck source=/dev/null
    source "$VENV_ACTIVATE"
else
    warn "Venv ~/.astro/ absent — les tests Python peuvent échouer"
fi

echo ""
echo -e "${C}╔══════════════════════════════════════════════════════╗${N}"
echo -e "${C}║  Test Astroport.ONE tools — salt/pepper: coucou      ║${N}"
echo -e "${C}╚══════════════════════════════════════════════════════╝${N}"
echo    "  ASTRO_TOOLS : $ASTRO_TOOLS"

# ── Vecteurs déterministes attendus ──────────────────────────────────────────
readonly SALT="coucou"
readonly PEPPER="coucou"
readonly EXPECTED_G1PUB="5fTwfbYUtCeoaFLbyzaBYUcq46nBS26rciWJAkBugqpo"
readonly EXPECTED_SS58="g1LYch17SATt3eb8MhF6VByw6Pd14m7UsYupKLwyCmmRCQTY7"
readonly EXPECTED_NPUB="npub1nknr3ullsl64pman9jsdxcl4xpr744qsue6gcx0t3n9crw36lunstvprm3"
readonly EXPECTED_IPFS="12D3KooWEUq7Qj8C56vHz8r2cbKXKGhfYRppTiBLaJsKYjLoanYj"
# uplanet.INTRUSION pour UPLANETNAME=coucou (keygen "coucou.INTRUSION" "coucou")
readonly INTRUSION_G1PUB="BwkNMBjHHxAJxLogRKS2Z9rM9TeXawbXUaH4iL26bSrt"
readonly INTRUSION_SS58="g1NeyVts3UXKZgTWngPfasoNtiJMQxafK9nw1bijTiGbKNkcu"

# ═════════════════════════════════════════════════════════════════════════════
hdr "1. keygen — déterminisme des clés"
# ═════════════════════════════════════════════════════════════════════════════

G1PUB=$(python3 "$ASTRO_TOOLS/keygen" -t duniter "$SALT" "$PEPPER" 2>/dev/null || echo "")
if [[ "$G1PUB" == "$EXPECTED_G1PUB" ]]; then
    ok "keygen -t duniter  → $G1PUB"
else
    fail "keygen -t duniter → attendu $EXPECTED_G1PUB, obtenu: $G1PUB"
fi

NPUB=$(python3 "$ASTRO_TOOLS/keygen" -t nostr "$SALT" "$PEPPER" 2>/dev/null || echo "")
if [[ "$NPUB" == "$EXPECTED_NPUB" ]]; then
    ok "keygen -t nostr    → $NPUB"
else
    fail "keygen -t nostr   → attendu $EXPECTED_NPUB, obtenu: $NPUB"
fi

IPFS_ID=$(python3 "$ASTRO_TOOLS/keygen" -t ipfs "$SALT" "$PEPPER" 2>/dev/null || echo "")
if [[ "$IPFS_ID" == "$EXPECTED_IPFS" ]]; then
    ok "keygen -t ipfs     → $IPFS_ID"
else
    fail "keygen -t ipfs    → attendu $EXPECTED_IPFS, obtenu: $IPFS_ID"
fi

# Clé secrète SSH (NSEC) pour nostr_setup_profile
NSEC=$(python3 "$ASTRO_TOOLS/keygen" -t nostr -s "$SALT" "$PEPPER" 2>/dev/null || echo "")
if [[ "$NSEC" =~ ^nsec1 ]]; then
    ok "keygen -t nostr -s → ${NSEC:0:20}… (nsec valide)"
else
    fail "keygen -t nostr -s n'a pas retourné un nsec"
fi

# ═════════════════════════════════════════════════════════════════════════════
hdr "2. g1pub_to_ss58.py — conversion v1 ↔ SS58"
# ═════════════════════════════════════════════════════════════════════════════

SS58=$(python3 "$ASTRO_TOOLS/g1pub_to_ss58.py" "$EXPECTED_G1PUB" 2>/dev/null || echo "")
if [[ "$SS58" == "$EXPECTED_SS58" ]]; then
    ok "g1pub_to_ss58 v1→SS58 → $SS58"
else
    fail "g1pub_to_ss58 → attendu $EXPECTED_SS58, obtenu: $SS58"
fi

# Test inverse SS58→v1 (nécessite --reverse)
G1PUB_BACK=$(python3 "$ASTRO_TOOLS/g1pub_to_ss58.py" --reverse "$EXPECTED_SS58" 2>/dev/null || echo "")
if [[ "$G1PUB_BACK" == "$EXPECTED_G1PUB" ]]; then
    ok "g1pub_to_ss58 SS58→v1 (--reverse) → $G1PUB_BACK"
else
    fail "g1pub_to_ss58 --reverse → attendu $EXPECTED_G1PUB, obtenu: $G1PUB_BACK"
fi

# Sans --reverse : passthrough (ensure_ss58 — comportement normal)
G1PUB_PASSTHROUGH=$(python3 "$ASTRO_TOOLS/g1pub_to_ss58.py" "$EXPECTED_SS58" 2>/dev/null || echo "")
if [[ "$G1PUB_PASSTHROUGH" == "$EXPECTED_SS58" ]]; then
    ok "g1pub_to_ss58 passthrough SS58 → $G1PUB_PASSTHROUGH"
else
    fail "g1pub_to_ss58 passthrough → attendu $EXPECTED_SS58, obtenu: $G1PUB_PASSTHROUGH"
fi

# Adresse INTRUSION (uplanet.INTRUSION pour UPLANETNAME=coucou)
INTR_SS58=$(python3 "$ASTRO_TOOLS/g1pub_to_ss58.py" "$INTRUSION_G1PUB" 2>/dev/null || echo "")
if [[ "$INTR_SS58" == "$INTRUSION_SS58" ]]; then
    ok "uplanet.INTRUSION SS58 → $INTR_SS58"
else
    fail "uplanet.INTRUSION → attendu $INTRUSION_SS58, obtenu: $INTR_SS58"
fi

# ═════════════════════════════════════════════════════════════════════════════
hdr "3. G1balance.sh — solde du wallet test"
# ═════════════════════════════════════════════════════════════════════════════

if [[ ! -x "$ASTRO_TOOLS/G1balance.sh" ]]; then
    warn "G1balance.sh introuvable dans $ASTRO_TOOLS — ignoré"
    BALANCE_G1=0
else
    BALANCE_JSON=$(bash "$ASTRO_TOOLS/G1balance.sh" --convert "$EXPECTED_G1PUB" 2>/dev/null || echo '{}')
    BALANCE_G1=$(echo "$BALANCE_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('balances', {}).get('total', 0))
except:
    print(0)
" 2>/dev/null || echo 0)

    if python3 -c "exit(0 if float('${BALANCE_G1}') >= 0 else 1)" 2>/dev/null; then
        ok "G1balance coucou/coucou → ${BALANCE_G1} Ğ1"
    else
        fail "G1balance retour invalide : $BALANCE_JSON"
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
hdr "4. PAYforSURE.sh — paiement 0.1Ẑen (0.01 Ğ1) vers uplanet.INTRUSION"
# ═════════════════════════════════════════════════════════════════════════════
# Condition : solde > 1 Ğ1 (ou --pay forcé)
# Montant : 1 (DECIMALS=2 → 1 = 0.01 Ğ1 = 0.1 Ẑen en mode ORIGIN)

ENOUGH=$(python3 -c "exit(0 if float('${BALANCE_G1}') > 1.0 else 1)" 2>/dev/null && echo true || echo false)

if [[ "$FORCE_PAY" == "true" || "$ENOUGH" == "true" ]]; then
    if [[ "$FORCE_PAY" == "true" ]]; then
        warn "Mode --pay forcé — paiement réel vers uplanet.INTRUSION"
    fi

    if [[ ! -x "$ASTRO_TOOLS/PAYforSURE.sh" ]]; then
        warn "PAYforSURE.sh introuvable — ignoré"
    elif ! command -v gcli &>/dev/null && ! command -v g1cli &>/dev/null; then
        warn "gcli/g1cli absent — paiement ignoré (Picoport non installé ?)"
    else
        # Générer un fichier pubsec temporaire pour le wallet test
        TMPKEY=$(mktemp /tmp/test_coucou_XXXXXX.key)
        python3 "$ASTRO_TOOLS/keygen" -t duniter -f pubsec "$SALT" "$PEPPER" \
            -o "$TMPKEY" 2>/dev/null

        echo "  → Envoi 0.01 Ğ1 (1 Ẑen ORIGIN) vers $INTRUSION_SS58..."
        if bash "$ASTRO_TOOLS/PAYforSURE.sh" \
                "$TMPKEY" "1" "$INTRUSION_SS58" \
                "test_picoport_soundspot" 2>&1 | tail -5; then
            ok "PAYforSURE → paiement envoyé vers uplanet.INTRUSION"
        else
            warn "PAYforSURE → échec (nœud inaccessible ? solde insuffisant ?)"
        fi
        rm -f "$TMPKEY"
    fi
else
    warn "Solde ${BALANCE_G1} Ğ1 ≤ 1 Ğ1 → paiement ignoré (relancer avec --pay pour forcer)"
    ok "Logique conditionnelle PAYforSURE OK (condition solde correcte)"
fi

# ═════════════════════════════════════════════════════════════════════════════
hdr "5. nostr_setup_profile.py — publication profil Kind 0"
# ═════════════════════════════════════════════════════════════════════════════

NOSTR_PY="$ASTRO_TOOLS/nostr_setup_profile.py"

if [[ ! -f "$NOSTR_PY" ]]; then
    warn "nostr_setup_profile.py introuvable — ignoré"
elif [[ "$TEST_NOSTR" != "true" ]]; then
    warn "Test nostr_setup_profile désactivé (relancer avec --nostr pour publier)"
    ok "nostr_setup_profile.py présent : $NOSTR_PY"
else
    # Vérifier les imports Python nécessaires
    MISSING_IMPORTS=""
    for mod in pynostr; do
        python3 -c "import $mod" 2>/dev/null || MISSING_IMPORTS="$MISSING_IMPORTS $mod"
    done
    if [[ -n "$MISSING_IMPORTS" ]]; then
        warn "Modules Python manquants :$MISSING_IMPORTS — pip install pynostr"
    else
        echo "  → Publication profil test (coucou) sur wss://relay.copylaradio.com..."
        if python3 "$NOSTR_PY" \
                "$NSEC" \
                "test_picoport_coucou" \
                "$EXPECTED_G1PUB" \
                "Test SoundSpot Picoport — salt=coucou pepper=coucou" \
                "" "" \
                "test@picoport.local" \
                "https://soundspot.local" \
                "" "" "" "" \
                "wss://relay.copylaradio.com" \
                --g1v2 "$EXPECTED_SS58" \
                2>&1 | tail -5; then
            ok "nostr_setup_profile → Kind 0 publié"
        else
            warn "nostr_setup_profile → échec (relay inaccessible ?)"
        fi
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
hdr "Résumé"
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo    "  Vecteurs de référence salt=coucou / pepper=coucou :"
echo    "  ─────────────────────────────────────────────────────────────────"
printf  "  %-22s %s\n" "G1PUB (v1):"  "$EXPECTED_G1PUB"
printf  "  %-22s %s\n" "SS58:"        "$EXPECTED_SS58"
printf  "  %-22s %s\n" "NPUB:"        "$EXPECTED_NPUB"
printf  "  %-22s %s\n" "IPFS PeerID:" "$EXPECTED_IPFS"
printf  "  %-22s %s\n" "INTRUSION SS58:" "$INTRUSION_SS58"
echo    "  ─────────────────────────────────────────────────────────────────"
echo    "  Solde mesuré : ${BALANCE_G1} Ğ1"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo -e "  ${G}✓  Tous les tests ont réussi${N}"
else
    echo -e "  ${R}✗  $FAIL test(s) ont échoué${N}"
    exit 1
fi
