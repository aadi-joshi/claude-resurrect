# How It Works

## The Problem

Claude Code can restart itself during agentic work — to pick up an MCP server it just installed, reload a hook it modified, or apply a config change. The mechanism for this already exists: send `SIGHUP` to the process, and a shell wrapper can catch exit code `129` and relaunch with `claude -c`.

The part that didn't exist: **context handoff**.

When Claude Code resumes a session, it replays the JSONL transcript. For long sessions, that transcript gets compacted — summarized down to fit the context window. The gist survives. The precision doesn't. The exact step you were on, the half-written file, the specific error you were about to handle — those get squeezed out. Claude wakes up knowing roughly what was happening but not _exactly_ where to pick up.

## The Fix: the Resurrection Manifest

Before killing itself, Claude writes `.claude/resurrection.md` — a structured handoff document containing:

- The original mission (verbatim, not summarized)
- Every completed step (precise, with file paths and commands)
- The exact resume point (what step, what file, what state)
- The first thing to do after restart

After the process dies and the wrapper restarts it, the manifest is injected as the first prompt. Claude wakes up reading exactly what it wrote — not a compaction summary, its own precise notes.

The manifest is deleted after being read (single-use), so it doesn't accumulate.

## Step by Step

```
User runs: claude --dangerously-skip-permissions
     |
     v
claude() wrapper launches claude normally (first_run=1)
On Windows shells: also starts _claude_resurrect_watcher in background,
polling for .claude/resurrect.flag every 0.3s
     |
     v
Claude does work... installs an MCP server...
     |
     v
Claude invokes /resurrect skill
     |
     +-- Step 1: runs `date && echo $CLAUDE_SESSION_ID` in bash
     +-- Step 2: writes .claude/resurrection.md via Write tool
     +-- Step 3: reads it back to verify
     +-- Step 4: runs `touch .claude/resurrect.flag && kill -HUP $PPID`
          |
          +-- macOS/Linux: SIGHUP reaches Claude Code, exits with code 129
          +-- Windows shells: watcher sees the flag, runs PowerShell to
               kill node.exe running Claude, Claude Code exits
          |
          v
     claude() loop: rc=129 OR .claude/resurrect.flag exists -> continue
          |
          v
     claude() finds .claude/resurrection.md
          |
          +-- Extracts session_id from manifest
          +-- Reads full manifest content
          +-- Deletes the file
          +-- Runs: claude --resume <session_id> [original flags] "<manifest content>"
               |
               v
          Claude wakes up. First message IS the manifest.
          Claude reads the resume point and immediate action.
          Claude continues working -- no user intervention needed.
```

## Why `kill -HUP $PPID`

On macOS/Linux, `$PPID` from within Claude's Bash tool points to the Claude Code Node.js process. `SIGHUP` (signal 1) is the Unix convention for "reload configuration." The shell convention for exit codes is `128 + signal_number`, so SIGHUP produces exit code `129`. The `claude()` wrapper checks for this code.

Exit code `129` follows the POSIX standard -- any Unix programmer reading the wrapper immediately understands what it means.

## Why the flag file on Windows

In Windows environments (WSL2/Git Bash/MSYS/PowerShell), Claude Code runs as a native Windows process (`claude.exe`) and `kill -HUP $PPID` is unreliable:
- In WSL2, `$PPID` resolves to `1` (the WSL init process), so `kill -HUP 1` fails silently
- In Git Bash/MSYS, SIGHUP may not propagate to native Windows processes
- In PowerShell, there is no SIGHUP concept at all

The workaround for all Windows environments: the skill writes `.claude/resurrect.flag` before attempting the kill. Both the bash and PowerShell wrappers start a background watcher on launch. When the watcher sees the flag, it calls PowerShell's `Stop-Process -Force` on `claude.exe` (preferred) or the most recent `node.exe` matching "claude" (npm-only fallback). The wrapper detects the flag on return and proceeds with the manifest-based restart.

This adds ~0.3s average latency on Windows versus near-instant on Unix.

### PowerShell wrapper difference

The PowerShell wrapper keeps the manifest file on disk instead of passing its content as a CLI argument. This avoids a Windows limitation: multi-line strings passed through cmd.exe shims (`.cmd` files) are truncated at newlines. By keeping the file on disk and injecting a short trigger message, the PowerShell wrapper avoids all quoting and encoding issues. The CLAUDE.md protocol tells Claude to read and delete the file when it receives the trigger message.

## Why Not Just `claude -c`

`--continue` is convenient but has a known unreliability in non-interactive mode -- it can create a new session instead of resuming the existing one. We use `--resume <session_id>` when the session ID is available in the manifest, falling back to `-c` only when it's not. The session ID comes from the skill's Step 1 bash command: `echo "${CLAUDE_SESSION_ID:-unknown}"`. If `CLAUDE_SESSION_ID` is not set in Claude's bash environment, the value is "unknown" and the wrapper falls back to `claude -c`.

## The Pre-Compact Hook (bonus)

A separate `pre-compact.mjs` hook fires automatically before Claude Code compacts the context. It parses the session JSONL transcript and writes `.claude/compaction-backup.md`. This is not the same as a resurrection manifest — it's a safety net for long sessions where compaction happens unexpectedly and you want a record of what was going on.

## What Doesn't Work

**Subagent PPID:** If Claude spawns a subagent and the subagent's Bash tool runs `kill -HUP $PPID`, it kills the subagent's parent — which might be the subagent orchestrator process, not the main Claude Code session. This is a known limitation. For now: only trigger `/resurrect` from the main agent, not from within a subagent.

**Native Windows (PowerShell):** Supported via `install.ps1` and the PowerShell wrapper. Uses the flag-file mechanism with a file-reference manifest injection. See README for install instructions.

**Very short sessions:** If the session is very short (< ~10 messages), `--resume` might not find enough context to compact, and the manifest injection becomes the dominant context. That's actually fine — it works better in that case.

**Docker without volume mounts:** Session files live in `~/.claude/projects/`. If Claude Code runs in a container without a mounted home directory, sessions don't persist across container restarts. This is a Claude Code limitation, not a resurrect limitation.
