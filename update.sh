#!/usr/bin/env bash
# update.sh -- pull latest changes and reinstall

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { printf "${BLUE}  ->  ${NC}%s\n" "$*"; }
ok()   { printf "${GREEN}  ok  ${NC}%s\n" "$*"; }

echo ""
echo "  claude-resurrect updater"
echo "  ────────────────────────"
echo ""

info "Pulling latest changes..."
git -C "$REPO_DIR" pull --ff-only

info "Reinstalling..."
bash "$REPO_DIR/uninstall.sh" --quiet
bash "$REPO_DIR/install.sh"

ok "Done. Reload your shell to pick up any wrapper changes."
echo ""
echo "  If you also use the PowerShell wrapper, update it with:"
echo "    powershell -ExecutionPolicy Bypass -File uninstall.ps1 -Quiet"
echo "    powershell -ExecutionPolicy Bypass -File install.ps1 -Quiet"
echo "    . \$PROFILE"
echo ""
