# Troubleshooting

## cr() not found after install

You need to reload your shell:
```bash
source ~/.zshrc   # or ~/.bashrc
```

Or open a new terminal.

---

## Claude exits with 129 but doesn't resume correctly

**Check 1:** Is `cr` being used instead of `claude`? The loop only works if you launched via `cr`.

**Check 2:** Does `.claude/resurrection.md` exist after the exit?
```bash
cat .claude/resurrection.md
```
If the file is missing, Claude killed itself before writing the manifest — which means `/resurrect-now` was used instead of `/resurrect`, or the Write tool failed. Check Claude's output before the restart.

**Check 3:** Is the session ID in the manifest valid?
```bash
grep "session_id:" .claude/resurrection.md
```
If it says `unknown`, the `cr()` wrapper falls back to `claude -c`. That usually works but can occasionally create a new session in non-interactive edge cases.

---

## Claude wakes up but doesn't continue the task

The manifest was injected, but Claude treated it as informational rather than as an action directive. Add this to your project's `CLAUDE.md`:

```markdown
After resurrection, read the manifest completely and immediately take the
"Immediate Action After Restart" step without asking for confirmation.
```

---

## /mcp shows the new server as "failed" after restart

The MCP server process itself might have an issue unrelated to the restart. Check:
```bash
claude mcp list   # confirms it's registered
```
Then inside the session, run `/mcp` and look at the error. It's usually a missing env var or wrong command path, not a resurrect issue.

---

## The pre-compact hook isn't running

Check that it's registered:
```bash
cat ~/.claude/settings.json | grep pre-compact
```

On Windows/Git Bash, the registered command will use Windows-style paths like
`C:\Users\...\pre-compact.mjs` rather than `~/.claude/...`. That's correct.

If the hook entry is missing entirely, the install likely failed due to a path
conversion issue. Re-run `bash install.sh` or add it manually:
```json
{
  "hooks": {
    "PreCompact": [{
      "hooks": [{
        "type": "command",
        "command": "node /absolute/path/to/.claude/hooks/pre-compact.mjs",
        "async": true
      }]
    }]
  }
}
```

Replace `/absolute/path/to/.claude/hooks/pre-compact.mjs` with the actual full path.
On macOS/Linux: `/Users/yourname/.claude/hooks/pre-compact.mjs`.
On Windows: `C:\Users\yourname\.claude\hooks\pre-compact.mjs` (backslashes).

---

## On macOS: `kill` behaves differently

macOS uses BSD `kill`, which should handle `kill -HUP $PPID` identically to Linux for this purpose. If you see issues, try:
```bash
kill -1 $PPID   # SIGHUP by number instead of name
```

The `cr()` wrapper can be updated to catch exit code 129 on macOS as well — it should already work, but if not, open an issue with your macOS version.

---

## WSL2 / Windows

The automatic restart does **not** work on Windows or WSL2. Claude Code runs as a Windows process, and from inside WSL bash `$PPID` resolves to 1 (the WSL init process), not the Claude Code process. `kill -HUP 1` fails.

You can still use the manifest concept manually:
1. Ask Claude to write the manifest: *"Write a resurrection manifest to `.claude/resurrection.md` summarizing what we've done and what to do next."*
2. Exit Claude (Ctrl+C or just close)
3. Run `claude -c` to resume the session
4. Say: *"Read `.claude/resurrection.md` and continue."*

It's less automatic but the context handoff works the same way.

---

## Docker

If you're running Claude Code inside Docker, make sure the home directory is mounted:
```yaml
volumes:
  - ./claude-home:/home/node
```
Without this, `~/.claude/projects/` doesn't persist across container restarts and `--resume` has nothing to resume.
