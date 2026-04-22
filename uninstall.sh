#!/usr/bin/env bash
# uninstall.sh — remove claude-resurrect

set -e

QUIET=false
for arg in "$@"; do [[ "$arg" == "--quiet" ]] && QUIET=true; done

CLAUDE_DIR="$HOME/.claude"
GREEN='\033[0;32m'; NC='\033[0m'
ok() { $QUIET || printf "${GREEN}  ✓${NC} %s\n" "$*"; }

detect_rc() {
  if [[ "$SHELL" == *zsh* ]]; then echo "$HOME/.zshrc"
  elif [[ "$SHELL" == *bash* ]]; then echo "$HOME/.bashrc"
  else echo "$HOME/.profile"; fi
}
RC_FILE=$(detect_rc)

if ! $QUIET; then
  echo ""
  echo "  claude-resurrect uninstaller"
  echo "  ────────────────────────────"
  echo ""
fi

# Remove skills
rm -rf "$CLAUDE_DIR/skills/resurrect" "$CLAUDE_DIR/skills/resurrect-now"
ok "Skills removed"

# Remove hook file
rm -f "$CLAUDE_DIR/hooks/pre-compact.mjs"
ok "Hook file removed"

# Remove hook registration from settings.json
node -e "
  const fs = require('fs');
  const os = require('os');
  const p = require('path');
  const settingsPath = p.join(os.homedir(), '.claude', 'settings.json');
  let s = {};
  try { s = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); } catch { process.exit(0); }
  if (s.hooks?.PreCompact) {
    s.hooks.PreCompact = s.hooks.PreCompact.filter(h =>
      !h.hooks?.some(hh => hh.command?.includes('pre-compact.mjs'))
    );
    if (s.hooks.PreCompact.length === 0) delete s.hooks.PreCompact;
    if (Object.keys(s.hooks).length === 0) delete s.hooks;
  }
  fs.writeFileSync(settingsPath, JSON.stringify(s, null, 2), 'utf8');
" 2>/dev/null
ok "Hook removed from settings.json"

# Remove wrapper from shell rc (everything between the marker and the next blank
# line after the last function in the block)
if grep -q "# claude-resurrect" "$RC_FILE" 2>/dev/null; then
  perl -i -0pe 's/\n# claude-resurrect\n.*?\n\n/\n/s' "$RC_FILE" 2>/dev/null \
    || sed -i '/# claude-resurrect/,/^[[:space:]]*$/d' "$RC_FILE" 2>/dev/null \
    || echo "  Could not auto-remove claude() wrapper from $RC_FILE -- remove the '# claude-resurrect' block manually"
  ok "Wrapper removed from $RC_FILE"
fi

# Remove resurrection protocol from ~/.claude/CLAUDE.md
GLOBAL_CLAUDE_MD="$HOME/.claude/CLAUDE.md"
CLAUDE_MD_MARKER="# claude-resurrect: resurrection protocol"
if grep -q "$CLAUDE_MD_MARKER" "$GLOBAL_CLAUDE_MD" 2>/dev/null; then
  perl -i -0pe "s/\n${CLAUDE_MD_MARKER}\n.*?\n\n/\n/s" "$GLOBAL_CLAUDE_MD" 2>/dev/null \
    || sed -i "/${CLAUDE_MD_MARKER}/,/^[[:space:]]*$/d" "$GLOBAL_CLAUDE_MD" 2>/dev/null \
    || echo "  Could not auto-remove protocol from $GLOBAL_CLAUDE_MD -- remove the '${CLAUDE_MD_MARKER}' block manually"
  ok "Resurrection protocol removed from $GLOBAL_CLAUDE_MD"
fi

if ! $QUIET; then
  echo ""
  echo "  Uninstall complete. Reload your shell: source $RC_FILE"
  echo ""
fi
