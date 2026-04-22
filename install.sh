#!/usr/bin/env bash
# install.sh — claude-resurrect installer
#
# What this does:
#   1. Copies skills to ~/.claude/skills/
#   2. Copies hooks to ~/.claude/hooks/
#   3. Adds the cr() function to your shell rc file
#   4. Optionally adds the PreCompact hook to ~/.claude/settings.json
#
# Run: bash install.sh
# Or:  bash install.sh --no-hooks (skip hook installation)

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
HOOKS_DIR="$CLAUDE_DIR/hooks"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # no color

info()    { printf "${BLUE}  →${NC} %s\n" "$*"; }
success() { printf "${GREEN}  ✓${NC} %s\n" "$*"; }
warn()    { printf "${YELLOW}  !${NC} %s\n" "$*"; }
error()   { printf "${RED}  ✗${NC} %s\n" "$*"; exit 1; }

INSTALL_HOOKS=true
for arg in "$@"; do
  [[ "$arg" == "--no-hooks" ]] && INSTALL_HOOKS=false
done

echo ""
echo "  claude-resurrect installer"
echo "  ─────────────────────────"
echo ""

# ── Check dependencies ───────────────────────────────────────────────────────
command -v claude >/dev/null 2>&1 || error "claude not found. Install Claude Code first: https://code.claude.com"
command -v node   >/dev/null 2>&1 || warn "node not found — pre-compact hook requires Node.js to run"

# ── Detect shell ─────────────────────────────────────────────────────────────
detect_rc() {
  if [[ -n "$ZSH_VERSION" ]] || [[ "$SHELL" == *zsh* ]]; then
    echo "$HOME/.zshrc"
  elif [[ -n "$BASH_VERSION" ]] || [[ "$SHELL" == *bash* ]]; then
    echo "$HOME/.bashrc"
  else
    echo "$HOME/.profile"
  fi
}

RC_FILE=$(detect_rc)
info "Detected shell rc: $RC_FILE"

# ── Create directories ───────────────────────────────────────────────────────
mkdir -p "$SKILLS_DIR/resurrect"
mkdir -p "$SKILLS_DIR/resurrect-now"
mkdir -p "$HOOKS_DIR"

# ── Install skills ───────────────────────────────────────────────────────────
info "Installing skills..."
cp "$REPO_DIR/skills/resurrect/SKILL.md"     "$SKILLS_DIR/resurrect/SKILL.md"
cp "$REPO_DIR/skills/resurrect-now/SKILL.md" "$SKILLS_DIR/resurrect-now/SKILL.md"
success "Skills installed to $SKILLS_DIR/"

# ── Install hooks ────────────────────────────────────────────────────────────
if [[ "$INSTALL_HOOKS" == true ]]; then
  info "Installing pre-compact hook..."
  cp "$REPO_DIR/hooks/pre-compact.mjs" "$HOOKS_DIR/pre-compact.mjs"
  chmod +x "$HOOKS_DIR/pre-compact.mjs"
  success "Hook installed to $HOOKS_DIR/pre-compact.mjs"

  # Patch ~/.claude/settings.json to register the hook
  SETTINGS_FILE="$CLAUDE_DIR/settings.json"
  if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo '{}' > "$SETTINGS_FILE"
  fi

  # Use node to safely merge the hook config.
  # We use os.homedir() inside node rather than shell-interpolated paths,
  # because on Windows (Git Bash / WSL) the shell gives Unix paths like
  # /c/Users/... but Node.js needs Windows paths like C:\Users\...
  node -e "
    const fs = require('fs');
    const os = require('os');
    const p = require('path');
    const settingsPath = p.join(os.homedir(), '.claude', 'settings.json');
    let settings = {};
    try { settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); } catch {}

    settings.hooks = settings.hooks || {};
    settings.hooks.PreCompact = settings.hooks.PreCompact || [];

    const hookCmd = 'node ' + p.join(os.homedir(), '.claude', 'hooks', 'pre-compact.mjs');
    const alreadyInstalled = settings.hooks.PreCompact.some(h =>
      h.hooks?.some(hh => hh.command === hookCmd)
    );

    if (!alreadyInstalled) {
      settings.hooks.PreCompact.push({
        hooks: [{ type: 'command', command: hookCmd, async: true }]
      });
    }

    fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2), 'utf8');
    console.log('ok');
  " 2>/dev/null | grep -q ok && success "Registered PreCompact hook in settings.json" \
              || warn "Could not auto-register hook. Add it manually -- see docs/how-it-works.md"
fi

# ── Install wrapper function ─────────────────────────────────────────────────
info "Installing cr() wrapper function to $RC_FILE..."

WRAPPER_MARKER="# claude-resurrect"
if grep -q "$WRAPPER_MARKER" "$RC_FILE" 2>/dev/null; then
  warn "cr() already present in $RC_FILE — skipping (run uninstall.sh first to reinstall)"
else
  {
    echo ""
    echo "$WRAPPER_MARKER"
    cat "$REPO_DIR/wrapper/claude-resurrect.sh"
    echo ""
  } >> "$RC_FILE"
  success "cr() function added to $RC_FILE"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "  Installation complete."
echo ""
echo "  Reload your shell:"
echo "    source $RC_FILE"
echo ""
echo "  Then start Claude with:"
echo "    cr                              # normal launch"
echo "    cr --dangerously-skip-permissions  # skip permission prompts"
echo "    cr-yolo                         # shortcut for above"
echo ""
echo "  Inside a session, use:"
echo "    /resurrect      → write manifest + restart (preserves task context)"
echo "    /resurrect-now  → instant hard restart (no manifest)"
echo ""
