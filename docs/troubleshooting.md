# Troubleshooting

## claude() wrapper not active after install

**bash/zsh:**
```bash
source ~/.zshrc   # or ~/.bashrc
```

**PowerShell:**
```powershell
. $PROFILE
```

Or open a new terminal window.

---

## Claude exits but doesn't resume correctly

**Check 1:** Is the wrapper active? Verify with:
```bash
echo $CLAUDE_RESURRECT_WRAPPER   # bash -- should print 1
```
```powershell
$env:CLAUDE_RESURRECT_WRAPPER    # PowerShell -- should print 1
```
If it's empty, the wrapper function isn't wrapping the session. Reload your profile and relaunch `claude`.

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

## Windows PowerShell (native Windows Terminal)

Install with `install.ps1` (see README). The PowerShell wrapper works differently from the bash wrapper: it keeps the manifest file on disk and injects a short trigger message on restart. When Claude receives `Resurrection: read .claude/resurrection.md...`, it reads the file and continues.

If Claude wakes up but ignores the manifest:
- Check that `~/.claude/CLAUDE.md` includes the resurrection protocol block (run `install.ps1` again if missing)
- Check that `.claude/resurrection.md` was not deleted before Claude had a chance to read it

---

## WSL2 / Git Bash / MSYS

The automatic restart works on Windows bash shells but through a different mechanism than macOS/Linux.

In WSL, `$PPID` resolves to 1 (WSL init), not the Claude Code Windows process. `kill -HUP 1` fails silently.

The bash wrapper handles this automatically:
1. On startup, it detects a Windows shell by requiring `powershell.exe` and checking environment signals (`WSL_DISTRO_NAME`, `WSL_INTEROP`, `$PPID -eq 1`, or `uname` values containing `mingw`/`msys`)
2. It starts a background shell (`_claude_resurrect_watcher`) that polls for `.claude/resurrect.flag` every 0.3s
3. The skill writes that flag before attempting `kill -HUP $PPID`
4. When the watcher sees the flag, it runs PowerShell to find and stop `claude.exe` (or `node.exe` for npm-only installs)

If the watcher is not triggering, check that `powershell.exe` is accessible from your shell:
```bash
command -v powershell.exe
```
It should print `/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe` or similar. If not, WSL interop is disabled -- enable it in `/etc/wsl.conf` with `[interop] enabled = true`.

---

## Docker

If you're running Claude Code inside Docker, make sure the home directory is mounted:
```yaml
volumes:
  - ./claude-home:/home/node
```
Without this, `~/.claude/projects/` doesn't persist across container restarts and `--resume` has nothing to resume.
