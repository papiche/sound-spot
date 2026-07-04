#!/bin/bash
# ════════════════════════════════════════════════════════════════════
#  src/dev/install_claude_tools.sh — Claude Code + RTK (outils dev)
# ════════════════════════════════════════════════════════════════════
#
#  Usage :
#    bash src/dev/install_claude_tools.sh          # en tant qu'utilisateur normal
#    sudo bash src/dev/install_claude_tools.sh      # appelé depuis deploy_on_pi.sh
#
#  Extrait de deploy_on_pi.sh (section 11) pour pouvoir installer
#  Claude Code + RTK indépendamment du reste de l'installation
#  SoundSpot (utile si l'install complète est bloquée ailleurs :
#  apt/kernel, réseau, Bluetooth…).
#
#  Ne nécessite PAS root : fonctionne aussi bien lancé directement
#  par l'utilisateur (pi) que via sudo (deploy_on_pi.sh).
# ════════════════════════════════════════════════════════════════════
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Couleurs (compatibles deploy_on_pi.sh) ───────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; M='\033[0;35m'; N='\033[0m'
DIM='\033[2m'
log()  { echo -e "${G}▶${N} $*"; }
warn() { echo -e "${Y}⚠${N}  $*"; }
err()  { echo -e "${R}✗${N}  $*" >&2; exit 1; }
hdr()  { echo -e "\n${C}━━━  $*  ━━━${N}"; }
ask()  { echo -ne "${M}?${N}  $*"; }

# ── Utilisateur cible ─────────────────────────────────────────
# Respecte SOUNDSPOT_USER si déjà exporté (appel depuis deploy_on_pi.sh
# sous sudo) ; sinon utilise l'utilisateur courant.
TARGET_USER="${SOUNDSPOT_USER:-$(id -un)}"
if [ "$(id -u)" -eq 0 ]; then
    RUN_AS_USER() { sudo -u "$TARGET_USER" bash -c "$1"; }
else
    RUN_AS_USER() { bash -c "$1"; }
fi
USER_LOCAL_BIN="$(eval echo "~$TARGET_USER")/.local/bin"

hdr "Claude Code — Outils développeur"
mkdir -p "$USER_LOCAL_BIN"
[ "$(id -u)" -eq 0 ] && chown "$TARGET_USER:$TARGET_USER" "$USER_LOCAL_BIN" 2>/dev/null || true

# ── claude-accounts ─────────────────────────────────────────────
CLAUDE_ACCOUNTS_SRC="$REPO_ROOT/../Astroport.ONE/claude.vscodium.setup.sh"
if [ -f "$CLAUDE_ACCOUNTS_SRC" ]; then
    echo -e "  ${C}[1]${N} claude-accounts — gestionnaire multi-comptes Claude Code"
    echo -e "       ${DIM}Isole chaque organisation dans ~/.claude-{slug} (symlink actif)${N}"
    ask "Installer claude-accounts ? [o/N] : "
    read -r INPUT_CLAUDE_ACCOUNTS
    if [[ "${INPUT_CLAUDE_ACCOUNTS,,}" == "o" ]]; then
        CLAUDE_ACCOUNTS_DEST="$USER_LOCAL_BIN/claude-accounts"
        cp "$CLAUDE_ACCOUNTS_SRC" "$CLAUDE_ACCOUNTS_DEST"
        chmod +x "$CLAUDE_ACCOUNTS_DEST"
        [ "$(id -u)" -eq 0 ] && chown "$TARGET_USER:$TARGET_USER" "$CLAUDE_ACCOUNTS_DEST" 2>/dev/null || true
        log "claude-accounts → ${C}${CLAUDE_ACCOUNTS_DEST}${N}"
        if RUN_AS_USER 'command -v claude &>/dev/null'; then
            log "Lancement de claude-accounts setup..."
            RUN_AS_USER "bash '$CLAUDE_ACCOUNTS_DEST' setup"
        else
            warn "Claude Code absent — installez-le d'abord :"
            echo -e "  ${C}npm install -g @anthropic-ai/claude-code${N}"
            echo -e "  Puis : ${C}claude-accounts setup${N}"
        fi
    else
        log "claude-accounts ignoré."
    fi
else
    warn "claude.vscodium.setup.sh introuvable — Astroport.ONE absent de \$REPO_ROOT/../"
fi

echo ""

# ── RTK — réducteur de tokens ───────────────────────────────────
echo -e "  ${C}[2]${N} RTK — filtre de sortie pour Claude Code (−60 à −90 % de tokens)"
echo -e "       ${DIM}Wraps git/cargo/pytest/jest… pour n'afficher que l'essentiel${N}"
ask "Installer RTK ? [o/N] : "
read -r INPUT_RTK
if [[ "${INPUT_RTK,,}" == "o" ]]; then
    if RUN_AS_USER 'command -v rtk &>/dev/null'; then
        log "RTK déjà présent : $(RUN_AS_USER 'rtk --version' 2>/dev/null || echo '?')"
    else
        log "Installation RTK via script officiel..."
        if RUN_AS_USER "curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh"; then
            log "RTK installé ✓"
        else
            warn "Installation RTK échouée (curl requis, vérifier connectivité)."
        fi
    fi
    # Hook global silencieux — injecte RTK.md dans le contexte Claude Code
    RUN_AS_USER "export PATH=\"$USER_LOCAL_BIN:\$HOME/.local/bin:\$PATH\"; \
         command -v rtk &>/dev/null && rtk init --global --auto-patch 2>/dev/null || true"
    log "RTK hook global activé ✓"
else
    log "RTK ignoré."
fi
