#!/usr/bin/env bash
# claude-resurrect wrapper
# Source this file in your .zshrc or .bashrc.
# Usage: cr [any flags you'd normally pass to claude]
# Example: cr --dangerously-skip-permissions
#
# How it works:
#   1. Launches claude normally on first run
#   2. If claude exits with code 129 (SIGHUP), a resurrection was requested
#   3. Checks for .claude/resurrection.md written by the /resurrect skill
#   4. Injects that manifest as the first prompt in the resumed session
#   5. Claude wakes up knowing exactly where it left off

cr() {
  local manifest=".claude/resurrection.md"
  local rc
  local first_run=1
  local user_flags=("$@")

  while true; do

    # ── SUBSEQUENT RUNS: look for the resurrection manifest ─────────────────
    if [[ $first_run -eq 0 ]]; then
      if [[ -f "$manifest" ]]; then
        # Extract session ID from the manifest (written by the skill)
        local sid
        sid=$(grep -m1 "^session_id:" "$manifest" 2>/dev/null | awk '{print $2}' | tr -d '[:space:]')

        # Fallback: if skill couldn't capture session ID, find the most recent JSONL
        if [[ -z "$sid" || "$sid" == "unknown" ]]; then
          local recent_jsonl=""
          while IFS= read -r -d '' f; do
            [[ -z "$recent_jsonl" || "$f" -nt "$recent_jsonl" ]] && recent_jsonl="$f"
          done < <(find "${HOME}/.claude/projects" -maxdepth 2 -name "*.jsonl" -print0 2>/dev/null)
          [[ -n "$recent_jsonl" ]] && sid=$(basename "$recent_jsonl" .jsonl)
        fi

        # Read and delete the manifest (single-use)
        local manifest_content
        manifest_content=$(cat "$manifest")
        rm -f "$manifest"

        # Only use --resume if we have a valid UUID; otherwise fall back to -c
        local resume_flags=()
        if [[ "$sid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
          resume_flags=(--resume "$sid")
        else
          resume_flags=(-c)
        fi

        printf '\n  claude-resurrect: manifest found -- resuming with context\n\n'
        sleep 0.3

        claude "${resume_flags[@]}" "${user_flags[@]}" "$manifest_content"

      else
        # Exit 129 but no manifest -- /resurrect-now was used or Write failed
        printf '\n  claude-resurrect: no manifest -- plain resume\n'
        printf '  Tip: use /resurrect (not /resurrect-now) to preserve task state.\n\n'
        sleep 0.3

        claude -c "${user_flags[@]}"
      fi

    # ── FIRST RUN: normal launch ─────────────────────────────────────────────
    else
      claude "${user_flags[@]}"
    fi

    rc=$?
    first_run=0

    # exit code 129 = SIGHUP = resurrection requested
    if [[ $rc -eq 129 ]]; then
      printf '\n  claude-resurrect: caught exit 129 -- checking for manifest...\n'
      continue
    fi

    # Any other exit code: stop the loop and return it cleanly
    return $rc
  done
}

# Convenience aliases -- these just pre-set common flag combos.
# The cr() function handles everything; these are just shortcuts.

# cr-yolo: skip all permission prompts (use carefully)
cr-yolo() {
  cr --dangerously-skip-permissions "$@"
}

# cr-safe: explicit safe mode (default, no extra flags)
cr-safe() {
  cr "$@"
}

# cr-resume: pick up a specific named or UUID session
# Usage: cr-resume my-session-name [extra flags]
cr-resume() {
  local session_name="$1"
  shift
  claude --resume "$session_name" "$@"
}
