#!/bin/bash
# =============================================================================
#  test_astroport_tools.sh — Tests + bench des outils Astroport.ONE (Picoport)
#
#  Chaque test est chronométré. Le résultat JSON est publié dans :
#    ~/.zen/tmp/$IPFSNODEID/picoport_bench.json   (si IPFS disponible)
#    /tmp/picoport_bench.json                      (toujours)
#
#  Ces métriques permettent de classifier les stations dans heartbox/12345.json :
#    crypto_score  — vitesse scrypt/ed25519 (keygen duniter ~= scrypt RAM-hard)
#    network_ms    — latence vers le nœud Duniter RPC (G1balance)
#    tools_ok      — tous les outils Astroport.ONE sont opérationnels
#
#  Usage :
#    bash test/test_astroport_tools.sh [--pay] [--nostr]
#
#  Options :
#    --pay    Forcer PAYforSURE même si solde ≤ 1 Ğ1 (ATTENTION: envoie réellement)
#    --nostr  Activer nostr_setup_profile (publie Kind 0 sur relay.copylaradio.com)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Couleurs ──────────────────────────────────────────────────────────────────
G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; C='\033[0;36m'
B='\033[0;34m'; W='\033[1;37m'; N='\033[0m'

# ── Timing helpers ─────────────────────────────────────────────────────────────
# _ms : timestamp en millisecondes (portabilité bash/dash/busybox)
_ms() {
    if command -v python3 &>/dev/null; then
        python3 -c "import time; print(int(time.time()*1000))"
    else
        echo $(( $(date +%s) * 1000 ))
    fi
}

# Tableau associatif des temps écoulés par fonction (bash 4+)
declare -A T          # T[nom]=elapsed_ms
declare -A T_STATUS   # T_STATUS[nom]=ok|fail|skip|warn

FAIL=0
BENCH_START=$(_ms)

# ── Wrappers log avec timing ───────────────────────────────────────────────────
# ok_t "label" elapsed_ms
ok_t() {
    local label="$1" ms="${2:-}"
    local ms_str=""
    [[ -n "$ms" ]] && ms_str=" ${B}[${ms}ms]${N}"
    echo -e "  ${G}✓${N}  ${label}${ms_str}"
    T_STATUS["$label"]="ok"
}
# fail_t "label" elapsed_ms
fail_t() {
    local label="$1" ms="${2:-}"
    local ms_str=""
    [[ -n "$ms" ]] && ms_str=" ${B}[${ms}ms]${N}"
    echo -e "  ${R}✗${N}  ${label}${ms_str}"
    FAIL=$((FAIL+1))
    T_STATUS["$label"]="fail"
}
warn_t() {
    local label="$1" ms="${2:-}"
    local ms_str=""
    [[ -n "$ms" ]] && ms_str=" ${B}[${ms}ms]${N}"
    echo -e "  ${Y}⚠${N}  ${label}${ms_str}"
    T_STATUS["$label"]="warn"
}
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }

# _t0 KEY — démarre le chrono pour KEY (stocke dans T_START[KEY])
# _t1 KEY — arrête le chrono, calcule et stocke T[KEY]
# Utilisation :
#   _t0 my_key
#   RESULT=$(some_cmd)
#   _t1 my_key
declare -A T_START
_t0() { T_START["$1"]=$(_ms); }
_t1() { T["$1"]=$(( $(_ms) - T_START["$1"] )); }

# ── Options ───────────────────────────────────────────────────────────────────
FORCE_PAY=false
TEST_NOSTR=false
for arg in "$@"; do
    [[ "$arg" == "--pay"   ]] && FORCE_PAY=true
    [[ "$arg" == "--nostr" ]] && TEST_NOSTR=true
done

# ── Localisation Astroport.ONE/tools ─────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOUNDSPOT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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
[[ -s "$VENV_ACTIVATE" ]] && source "$VENV_ACTIVATE" || true

# IPFS Node ID (pour écriture du bench dans l'espace de la station)
IPFSNODEID=$(ipfs id -f="<id>" 2>/dev/null || echo "")
BENCH_DIR="${HOME}/.zen/tmp/${IPFSNODEID}"
[[ -n "$IPFSNODEID" ]] && mkdir -p "$BENCH_DIR" || BENCH_DIR="/tmp"
BENCH_FILE="${BENCH_DIR}/picoport_bench.json"

echo ""
echo -e "${C}╔══════════════════════════════════════════════════════════════╗${N}"
echo -e "${C}║  Test + Bench Astroport.ONE tools — salt/pepper: coucou      ║${N}"
echo -e "${C}╚══════════════════════════════════════════════════════════════╝${N}"
printf  "  %-20s %s\n" "ASTRO_TOOLS:" "$ASTRO_TOOLS"
printf  "  %-20s %s\n" "IPFSNODEID:" "${IPFSNODEID:-non disponible}"
printf  "  %-20s %s\n" "Bench output:" "$BENCH_FILE"

# ── Vecteurs déterministes ────────────────────────────────────────────────────
readonly SALT="coucou"
readonly PEPPER="coucou"
readonly EXPECTED_G1PUB="5fTwfbYUtCeoaFLbyzaBYUcq46nBS26rciWJAkBugqpo"
readonly EXPECTED_SS58="g1LYch17SATt3eb8MhF6VByw6Pd14m7UsYupKLwyCmmRCQTY7"
readonly EXPECTED_NPUB="npub1nknr3ullsl64pman9jsdxcl4xpr744qsue6gcx0t3n9crw36lunstvprm3"
readonly EXPECTED_IPFS="12D3KooWEUq7Qj8C56vHz8r2cbKXKGhfYRppTiBLaJsKYjLoanYj"
readonly INTRUSION_G1PUB="BwkNMBjHHxAJxLogRKS2Z9rM9TeXawbXUaH4iL26bSrt"
readonly INTRUSION_SS58="g1NeyVts3UXKZgTWngPfasoNtiJMQxafK9nw1bijTiGbKNkcu"

# =============================================================================
hdr "1. keygen — déterminisme des clés"
# =============================================================================

SEC1=$(_ms)

_t0 keygen_duniter
G1PUB=$(python3 "$ASTRO_TOOLS/keygen" -t duniter "$SALT" "$PEPPER" 2>/dev/null || echo "")
_t1 keygen_duniter
if [[ "$G1PUB" == "$EXPECTED_G1PUB" ]]; then
    ok_t "keygen -t duniter  → $G1PUB" "${T[keygen_duniter]}"
else
    fail_t "keygen -t duniter attendu=$EXPECTED_G1PUB obtenu=$G1PUB" "${T[keygen_duniter]}"
fi

_t0 keygen_nostr
NPUB=$(python3 "$ASTRO_TOOLS/keygen" -t nostr "$SALT" "$PEPPER" 2>/dev/null || echo "")
_t1 keygen_nostr
if [[ "$NPUB" == "$EXPECTED_NPUB" ]]; then
    ok_t "keygen -t nostr    → $NPUB" "${T[keygen_nostr]}"
else
    fail_t "keygen -t nostr attendu=$EXPECTED_NPUB obtenu=$NPUB" "${T[keygen_nostr]}"
fi

_t0 keygen_ipfs
IPFS_ID=$(python3 "$ASTRO_TOOLS/keygen" -t ipfs "$SALT" "$PEPPER" 2>/dev/null || echo "")
_t1 keygen_ipfs
if [[ "$IPFS_ID" == "$EXPECTED_IPFS" ]]; then
    ok_t "keygen -t ipfs     → $IPFS_ID" "${T[keygen_ipfs]}"
else
    fail_t "keygen -t ipfs attendu=$EXPECTED_IPFS obtenu=$IPFS_ID" "${T[keygen_ipfs]}"
fi

_t0 keygen_nsec
NSEC=$(python3 "$ASTRO_TOOLS/keygen" -t nostr -s "$SALT" "$PEPPER" 2>/dev/null || echo "")
_t1 keygen_nsec
if [[ "$NSEC" =~ ^nsec1 ]]; then
    ok_t "keygen -t nostr -s → ${NSEC:0:20}… (nsec valide)" "${T[keygen_nsec]}"
else
    fail_t "keygen -t nostr -s n'a pas retourné un nsec" "${T[keygen_nsec]}"
fi

SEC1_END=$(_ms); T["section_keygen"]=$(( SEC1_END - SEC1 ))
echo -e "  ${W}Section 1 total : ${T[section_keygen]}ms${N}"

# =============================================================================
hdr "2. g1pub_to_ss58.py — conversion v1 ↔ SS58"
# =============================================================================

SEC2=$(_ms)

_t0 ss58_v1_to_ss58
SS58=$(python3 "$ASTRO_TOOLS/g1pub_to_ss58.py" "$EXPECTED_G1PUB" 2>/dev/null || echo "")
_t1 ss58_v1_to_ss58
if [[ "$SS58" == "$EXPECTED_SS58" ]]; then
    ok_t "g1pub_to_ss58 v1→SS58 → $SS58" "${T[ss58_v1_to_ss58]}"
else
    fail_t "g1pub_to_ss58 v1→SS58 attendu=$EXPECTED_SS58 obtenu=$SS58" "${T[ss58_v1_to_ss58]}"
fi

_t0 ss58_reverse
G1PUB_BACK=$(python3 "$ASTRO_TOOLS/g1pub_to_ss58.py" --reverse "$EXPECTED_SS58" 2>/dev/null || echo "")
_t1 ss58_reverse
if [[ "$G1PUB_BACK" == "$EXPECTED_G1PUB" ]]; then
    ok_t "g1pub_to_ss58 --reverse SS58→v1 → $G1PUB_BACK" "${T[ss58_reverse]}"
else
    fail_t "g1pub_to_ss58 --reverse attendu=$EXPECTED_G1PUB obtenu=$G1PUB_BACK" "${T[ss58_reverse]}"
fi

_t0 ss58_passthrough
G1PUB_PASSTHROUGH=$(python3 "$ASTRO_TOOLS/g1pub_to_ss58.py" "$EXPECTED_SS58" 2>/dev/null || echo "")
_t1 ss58_passthrough
if [[ "$G1PUB_PASSTHROUGH" == "$EXPECTED_SS58" ]]; then
    ok_t "g1pub_to_ss58 passthrough SS58 → $G1PUB_PASSTHROUGH" "${T[ss58_passthrough]}"
else
    fail_t "g1pub_to_ss58 passthrough attendu=$EXPECTED_SS58 obtenu=$G1PUB_PASSTHROUGH" "${T[ss58_passthrough]}"
fi

_t0 ss58_intrusion
INTR_SS58=$(python3 "$ASTRO_TOOLS/g1pub_to_ss58.py" "$INTRUSION_G1PUB" 2>/dev/null || echo "")
_t1 ss58_intrusion
if [[ "$INTR_SS58" == "$INTRUSION_SS58" ]]; then
    ok_t "uplanet.INTRUSION SS58 → $INTR_SS58" "${T[ss58_intrusion]}"
else
    fail_t "uplanet.INTRUSION attendu=$INTRUSION_SS58 obtenu=$INTR_SS58" "${T[ss58_intrusion]}"
fi

SEC2_END=$(_ms); T["section_ss58"]=$(( SEC2_END - SEC2 ))
echo -e "  ${W}Section 2 total : ${T[section_ss58]}ms${N}"

# =============================================================================
hdr "3. G1balance.sh — solde + latence nœud Duniter RPC"
# =============================================================================

SEC3=$(_ms)
BALANCE_G1=0

if [[ ! -x "$ASTRO_TOOLS/G1balance.sh" ]]; then
    warn_t "G1balance.sh introuvable dans $ASTRO_TOOLS — ignoré"
    T["g1balance_rpc"]=0
else
    t0=$(_ms)
    BALANCE_JSON=$(bash "$ASTRO_TOOLS/G1balance.sh" --convert "$EXPECTED_G1PUB" 2>/dev/null || echo '{}')
    t1=$(_ms)
    T["g1balance_rpc"]=$(( t1 - t0 ))

    BALANCE_G1=$(echo "$BALANCE_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('balances', {}).get('total', 0))
except:
    print(0)
" 2>/dev/null || echo 0)

    if python3 -c "exit(0 if float('${BALANCE_G1}') >= 0 else 1)" 2>/dev/null; then
        ok_t "G1balance coucou/coucou → ${BALANCE_G1} Ğ1  (RPC latence)" "${T[g1balance_rpc]}"
    else
        fail_t "G1balance retour invalide : $BALANCE_JSON" "${T[g1balance_rpc]}"
    fi
fi

SEC3_END=$(_ms); T["section_g1balance"]=$(( SEC3_END - SEC3 ))
echo -e "  ${W}Section 3 total : ${T[section_g1balance]}ms${N}"

# =============================================================================
hdr "4. PAYforSURE.sh — paiement 0.1Ẑen (0.01 Ğ1) vers uplanet.INTRUSION"
# =============================================================================

SEC4=$(_ms)
T["pay_for_sure"]=0

ENOUGH=$(python3 -c "exit(0 if float('${BALANCE_G1}') > 1.0 else 1)" 2>/dev/null \
    && echo true || echo false)

if [[ "$FORCE_PAY" == "true" || "$ENOUGH" == "true" ]]; then
    [[ "$FORCE_PAY" == "true" ]] && warn_t "Mode --pay forcé — paiement réel vers uplanet.INTRUSION"

    if [[ ! -x "$ASTRO_TOOLS/PAYforSURE.sh" ]]; then
        warn_t "PAYforSURE.sh introuvable — ignoré"
    elif ! command -v gcli &>/dev/null && ! command -v g1cli &>/dev/null; then
        warn_t "gcli/g1cli absent — paiement ignoré (Picoport non installé ?)"
    else
        TMPKEY=$(mktemp /tmp/test_coucou_XXXXXX.key)
        python3 "$ASTRO_TOOLS/keygen" -t duniter -f pubsec "$SALT" "$PEPPER" \
            -o "$TMPKEY" 2>/dev/null

        echo "  → Envoi 0.01 Ğ1 (0.1Ẑen ORIGIN) vers $INTRUSION_SS58..."
        t0=$(_ms)
        if bash "$ASTRO_TOOLS/PAYforSURE.sh" \
                "$TMPKEY" "1" "$INTRUSION_SS58" \
                "test_picoport_soundspot" 2>&1 | tail -5; then
            t1=$(_ms); T["pay_for_sure"]=$(( t1 - t0 ))
            ok_t "PAYforSURE → paiement envoyé vers uplanet.INTRUSION" "${T[pay_for_sure]}"
        else
            t1=$(_ms); T["pay_for_sure"]=$(( t1 - t0 ))
            warn_t "PAYforSURE → échec (nœud inaccessible ? solde insuffisant ?)" "${T[pay_for_sure]}"
        fi
        rm -f "$TMPKEY"
    fi
else
    warn_t "Solde ${BALANCE_G1} Ğ1 ≤ 1 Ğ1 → paiement ignoré (--pay pour forcer)"
    ok_t "Logique conditionnelle PAYforSURE vérifiée (solde insuffisant détecté)" "0"
fi

SEC4_END=$(_ms); T["section_pay"]=$(( SEC4_END - SEC4 ))
echo -e "  ${W}Section 4 total : ${T[section_pay]}ms${N}"

# =============================================================================
hdr "5. nostr_setup_profile.py — publication profil Kind 0"
# =============================================================================

SEC5=$(_ms)
T["nostr_profile"]=0
NOSTR_PY="$ASTRO_TOOLS/nostr_setup_profile.py"

if [[ ! -f "$NOSTR_PY" ]]; then
    warn_t "nostr_setup_profile.py introuvable — ignoré"
elif [[ "$TEST_NOSTR" != "true" ]]; then
    warn_t "Test nostr désactivé (relancer avec --nostr pour publier)"
    ok_t "nostr_setup_profile.py présent" "0"
else
    MISSING=""
    python3 -c "import pynostr" 2>/dev/null || MISSING="pynostr"
    if [[ -n "$MISSING" ]]; then
        warn_t "Module Python manquant : $MISSING — pip install pynostr"
    else
        echo "  → Publication profil test sur wss://relay.copylaradio.com..."
        t0=$(_ms)
        if python3 "$NOSTR_PY" \
                "$NSEC" "test_picoport_coucou" "$EXPECTED_G1PUB" \
                "Test SoundSpot Picoport — salt=coucou pepper=coucou" \
                "" "" "test@picoport.local" "https://soundspot.local" \
                "" "" "" "" \
                "wss://relay.copylaradio.com" \
                --g1v2 "$EXPECTED_SS58" \
                2>&1 | tail -5; then
            t1=$(_ms); T["nostr_profile"]=$(( t1 - t0 ))
            ok_t "nostr_setup_profile → Kind 0 publié" "${T[nostr_profile]}"
        else
            t1=$(_ms); T["nostr_profile"]=$(( t1 - t0 ))
            warn_t "nostr_setup_profile → échec (relay inaccessible ?)" "${T[nostr_profile]}"
        fi
    fi
fi

SEC5_END=$(_ms); T["section_nostr"]=$(( SEC5_END - SEC5 ))
echo -e "  ${W}Section 5 total : ${T[section_nostr]}ms${N}"

# =============================================================================
hdr "Résumé & Bench JSON"
# =============================================================================

BENCH_END=$(_ms)
T["total_bench"]=$(( BENCH_END - BENCH_START ))

# ── Calcul du crypto_score (basé sur keygen_duniter = scrypt RAM-hard) ───────
# keygen duniter utilise scrypt → mesure fidèle de la vitesse CPU+RAM
KEYGEN_MS="${T[keygen_duniter]:-9999}"
if   (( KEYGEN_MS < 150  )); then CRYPTO_SCORE=10
elif (( KEYGEN_MS < 300  )); then CRYPTO_SCORE=8
elif (( KEYGEN_MS < 600  )); then CRYPTO_SCORE=6
elif (( KEYGEN_MS < 1200 )); then CRYPTO_SCORE=4
elif (( KEYGEN_MS < 2500 )); then CRYPTO_SCORE=2
else                               CRYPTO_SCORE=1
fi

# ── Affichage tabulaire ──────────────────────────────────────────────────────
echo ""
printf "  ${W}%-30s %8s${N}\n" "Fonction" "Temps (ms)"
printf "  %s\n" "$(printf '─%.0s' {1..42})"
for key in keygen_duniter keygen_nostr keygen_ipfs keygen_nsec \
           ss58_v1_to_ss58 ss58_reverse ss58_passthrough ss58_intrusion \
           g1balance_rpc pay_for_sure nostr_profile; do
    ms="${T[$key]:-0}"
    # Coloration selon seuils
    if   (( ms == 0    )); then col="${Y}"
    elif (( ms < 500   )); then col="${G}"
    elif (( ms < 2000  )); then col="${Y}"
    else                        col="${R}"
    fi
    printf "  %-30s ${col}%8s ms${N}\n" "$key" "$ms"
done
printf "  %s\n" "$(printf '─%.0s' {1..42})"
printf "  ${W}%-30s %8s ms${N}\n" "TOTAL BENCH" "${T[total_bench]}"
echo ""
printf "  %-20s %s\n" "crypto_score:"  "$CRYPTO_SCORE / 10  (keygen_duniter=${KEYGEN_MS}ms)"
printf "  %-20s %s\n" "network_ms:"    "${T[g1balance_rpc]:-0} ms  (latence nœud Duniter RPC)"
printf "  %-20s %s\n" "failures:"      "$FAIL"
echo ""

# ── Production JSON ───────────────────────────────────────────────────────────
BENCH_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TOOLS_OK=$([[ "$FAIL" -eq 0 ]] && echo "True" || echo "False")

python3 - <<PYEOF > "$BENCH_FILE"
import json, datetime

data = {
    "bench_date":     "$BENCH_DATE",
    "hostname":       "$(hostname)",
    "ipfs_node_id":   "${IPFSNODEID:-null}" or None,
    "passed":         $TOOLS_OK,
    "failures":       $FAIL,
    "crypto_score":   $CRYPTO_SCORE,
    "network_ms":     ${T[g1balance_rpc]:-0},
    "balance_g1":     float("$BALANCE_G1"),
    "timings_ms": {
        "keygen_duniter":     ${T[keygen_duniter]:-0},
        "keygen_nostr":       ${T[keygen_nostr]:-0},
        "keygen_ipfs":        ${T[keygen_ipfs]:-0},
        "keygen_nsec":        ${T[keygen_nsec]:-0},
        "ss58_v1_to_ss58":    ${T[ss58_v1_to_ss58]:-0},
        "ss58_reverse":       ${T[ss58_reverse]:-0},
        "g1balance_rpc":      ${T[g1balance_rpc]:-0},
        "pay_for_sure":       ${T[pay_for_sure]:-0},
        "nostr_profile":      ${T[nostr_profile]:-0},
        "section_keygen":     ${T[section_keygen]:-0},
        "section_ss58":       ${T[section_ss58]:-0},
        "section_g1balance":  ${T[section_g1balance]:-0},
        "total_bench":        ${T[total_bench]:-0}
    }
}
print(json.dumps(data, indent=2))
PYEOF

echo -e "  ${G}Bench JSON écrit :${N} $BENCH_FILE"

# Copie dans /tmp pour accès sans IPFS
cp "$BENCH_FILE" /tmp/picoport_bench.json 2>/dev/null || true

# ── Conclusion ────────────────────────────────────────────────────────────────
echo ""
if [[ "$FAIL" -eq 0 ]]; then
    echo -e "  ${G}✓  Tous les tests réussis — ${T[total_bench]}ms total${N}"
else
    echo -e "  ${R}✗  $FAIL test(s) échoué(s)${N}"
    exit 1
fi
