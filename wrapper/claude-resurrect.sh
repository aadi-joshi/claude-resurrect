#!/usr/bin/env bash
# claude-resurrect wrapper
# Source this in your .zshrc or .bashrc.
#
# Defines a shell function named `claude` that shadows the real binary.
# Inside the function, `command claude` bypasses functions/aliases and calls
# the actual binary directly -- no recursion.
#
# Platform support:
#   macOS / Linux : uses SIGHUP (kill -HUP $PPID, exit 129) for automatic restart
#   Windows / WSL2: uses a background file watcher + PowerShell to kill Claude Code

claude() {
  local manifest=".claude/resurrection.md"
  local resurrect_flag=".claude/resurrect.flag"
  local rc=0
  local first_run=1
  local user_flags=("$@")
  export CLAUDE_RESURRECT_WRAPPER=1

  # Detect Windows/WSL2: in WSL, $PPID resolves to 1 (WSL init), not Claude Code.
  # Additionally check that powershell.exe is reachable (avoids false positives on Linux).
  local is_windows=0
  if [[ "$PPID" -eq 1 ]] && command -v powershell.exe > /dev/null 2>&1; then
    is_windows=1
  fi

  while true; do

    # ── START WINDOWS WATCHER ────────────────────────────────────────────────
    # On Windows/WSL, SIGHUP can't reach Claude Code. Instead, a background
    # subshell polls for .claude/resurrect.flag and kills Claude Code via
    # PowerShell when it appears.
    local watcher_pid=""
    if [[ $is_windows -eq 1 ]]; then
      _claude_resurrect_watcher "$resurrect_flag" &
      watcher_pid=$!
    fi

    # ── LAUNCH CLAUDE ────────────────────────────────────────────────────────
    if [[ $first_run -eq 0 ]]; then

      if [[ -f "$manifest" ]]; then
        # Extract session ID from manifest
        local sid
        sid=$(grep -m1 "^session_id:" "$manifest" 2>/dev/null | awk '{print $2}' | tr -d '[:space:]')

        # Fallback: find from the most recently modified JSONL (shellcheck-safe)
        if [[ -z "$sid" || "$sid" == "unknown" ]]; then
          local recent_jsonl=""
          while IFS= read -r -d '' f; do
            [[ -z "$recent_jsonl" || "$f" -nt "$recent_jsonl" ]] && recent_jsonl="$f"
          done < <(find "${HOME}/.claude/projects" -maxdepth 2 -name "*.jsonl" -print0 2>/dev/null)
          [[ -n "$recent_jsonl" ]] && sid=$(basename "$recent_jsonl" .jsonl)
        fi

        local manifest_content
        manifest_content=$(cat "$manifest")
        rm -f "$manifest"

        # Use --resume <uuid> when we have a valid session ID; otherwise -c
        local resume_flags=()
        if [[ "$sid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
          resume_flags=(--resume "$sid")
        else
          resume_flags=(-c)
        fi

        printf '\n  claude-resurrect: manifest found -- resuming with context\n\n'
        sleep 0.3
        command claude "${resume_flags[@]}" "${user_flags[@]}" "$manifest_content"

      else
        printf '\n  claude-resurrect: restarting (no manifest)\n'
        printf '  Tip: use /resurrect instead of /resurrect-now to preserve task state.\n\n'
        sleep 0.3
        command claude -c "${user_flags[@]}"
      fi

    else
      command claude "${user_flags[@]}"
    fi

    rc=$?
    first_run=0
    # Stop the watcher (it may already be dead if it triggered a kill)
    [[ -n "$watcher_pid" ]] && kill "$watcher_pid" 2>/dev/null

    # ── CHECK FOR RESURRECTION ───────────────────────────────────────────────
    # Unix:    exit 129 = SIGHUP received
    # Windows: resurrect.flag exists (written by skill before watcher killed claude)
    if [[ $rc -eq 129 ]] || [[ -f "$resurrect_flag" ]]; then
      rm -f "$resurrect_flag"
      printf '\n  claude-resurrect: caught exit -- checking for manifest...\n'
      continue
    fi

    return $rc
  done
}

# Background watcher used on Windows/WSL2.
# Polls for the resurrect flag, then kills Claude Code via PowerShell.
_claude_resurrect_watcher() {
  local flag="$1"
  while [[ ! -f "$flag" ]]; do
    sleep 0.3
  done
  # Find the node.exe process running claude (matched by command line)
  # and stop it. Falls back to the most recently started node.exe.
  powershell.exe -Command "
    \$target = Get-Process node -ErrorAction SilentlyContinue |
      ForEach-Object {
        \$id = \$_.Id
        \$cmd = try {
          (Get-CimInstance Win32_Process -Filter \"ProcessId=\$id\").CommandLine
        } catch { '' }
        [PSCustomObject]@{ Proc = \$_; Cmd = \$cmd }
      } |
      Where-Object { \$_.Cmd -match 'claude' } |
      Sort-Object { \$_.Proc.StartTime } -Descending |
      Select-Object -First 1 -ExpandProperty Proc
    if (-not \$target) {
      \$target = Get-Process node -ErrorAction SilentlyContinue |
        Sort-Object StartTime -Descending |
        Select-Object -First 1
    }
    if (\$target) { \$target | Stop-Process -Force }
  " 2>/dev/null
}

# Convenience shortcuts

claude-yolo() {
  claude --dangerously-skip-permissions "$@"
}

claude-resume() {
  local session_name="$1"
  shift
  command claude --resume "$session_name" "$@"
}
