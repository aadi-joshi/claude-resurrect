# CLAUDE.md — resurrection protocol block
#
# Copy this into your ~/.claude/CLAUDE.md (global) or your project's CLAUDE.md.
# This is what makes Claude trigger /resurrect automatically instead of asking
# you to restart manually.

## Resurrection Protocol

You have access to `/resurrect` and `/resurrect-now` skills from claude-resurrect.

**Use `/resurrect` when:**
- You run `claude mcp add` and need Claude Code to reload to pick it up
- You edit `.claude/settings.json` or `~/.claude.json` directly
- You run `claude update` (self-update requires restart)
- You modify a hook file (`.claude/hooks/`)
- Any operation explicitly says "restart Claude Code to take effect"

**Do NOT ask the user to restart manually.** If you detect that a restart is
needed, use `/resurrect` on your own. Write a complete manifest -- full mission,
every completed step, exact resume point -- before sending the SIGHUP signal.

**Use `/resurrect-now` only when:**
- You need a quick reload to test a hook or config change and no important
  task state needs to be preserved

**After resurrection:**
When you wake up and see a Resurrection Manifest as your first message, read it
completely before doing anything else. Confirm the resume point, check the
immediate action, then proceed without asking the user to re-explain the task.
