# claude-resurrect

> Claude kills itself. Then wakes back up. And knows exactly where it left off.

<img width="209" height="195" alt="ezgif com-animated-gif-maker (1)" src="https://github.com/user-attachments/assets/0783012b-ce83-4804-af9d-48c0ca4819c2" />

**Platform support:** macOS, Linux, WSL2, Git Bash/MSYS, and **native Windows PowerShell** (Windows Terminal). The automatic restart uses SIGHUP on Unix and a background process watcher on Windows.

---

When Claude Code needs to restart -- to load an MCP server it just installed, pick up a hook change, apply a config update -- the mechanism already exists. Send SIGHUP to the process, catch exit code 129 in a wrapper, relaunch with `claude -c`. That part works fine.

What didn't work: the context handoff.

When Claude resumes a session, it replays the JSONL transcript. Long sessions get compacted -- summarized down to fit the context window. The gist survives. The exact step you were on, the error you were mid-debugging, whether you were on step 4 or step 6 of 7 -- that stuff gets squeezed out. Claude wakes up roughly oriented but not precisely oriented. You end up re-explaining things.

This repo adds a **Resurrection Manifest** to that flow -- a structured handoff document Claude writes about itself before it dies, injected as its first message when it comes back. Not a compaction summary. Claude's own notes.

---

## What it does

```
You: claude --dangerously-skip-permissions
           |
           v
     Claude installs an MCP server
     Claude notices it needs to restart for the server to load
     Claude invokes /resurrect
           |
           +-- runs `date && echo $CLAUDE_SESSION_ID` to get timestamp + session ID
           +-- writes .claude/resurrection.md
           |    (mission, completed steps, exact resume point, next action)
           +-- reads it back to verify
           +-- runs: touch .claude/resurrect.flag && kill -HUP $PPID
                |
                +-- macOS/Linux: Claude Code exits 129 (SIGHUP)
                +-- Windows shells: background watcher sees the flag,
                     kills node.exe via PowerShell, Claude Code exits
                |
                v
           Claude Code exits
                |
                v
           cr() wrapper catches it
           reads the manifest, deletes it
           runs: claude --resume <session-id> "<manifest content>"
                |
                v
           Claude wakes up. First message IS the manifest.
           Claude reads the resume point, takes the immediate action.
           No user input needed. No re-explaining.
```

The manifest is single-use. Deleted after the wrapper reads it. If you resurrect five times in a session, you get five clean handoffs.

---

## Install

### macOS / Linux / WSL2 / Git Bash

```bash
git clone https://github.com/aadi-joshi/claude-resurrect
cd claude-resurrect
bash install.sh
source ~/.zshrc  # or ~/.bashrc
```

The installer:
- Copies `/resurrect` and `/resurrect-now` to `~/.claude/skills/`
- Copies the pre-compact hook to `~/.claude/hooks/` and registers it in `~/.claude/settings.json`
- Adds a `claude()` shell function to your rc that wraps the real binary transparently
- Patches `~/.claude/CLAUDE.md` with the resurrection protocol so Claude knows when to trigger restarts automatically

```bash
bash install.sh --no-hooks   # skip the pre-compact hook
bash update.sh               # update to the latest version
```

### Windows (PowerShell / Windows Terminal)

```powershell
git clone https://github.com/aadi-joshi/claude-resurrect
cd claude-resurrect
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
.\install.ps1
. $PROFILE
```

The PowerShell installer does the same thing as the bash installer -- skills, hook, wrapper, CLAUDE.md -- but adds a `claude()` function to your `$PROFILE` instead of `.bashrc`.

```powershell
.\install.ps1 -NoHooks   # skip the pre-compact hook
.\uninstall.ps1          # remove everything
```

---

## Usage

After install, use `claude` exactly as you always have. Nothing changes on the outside:

```bash
claude                                # normal launch, resurrection-enabled
claude --dangerously-skip-permissions # any flags pass through unchanged
claude --model claude-opus-4-7
```

The wrapper is a shell function that shadows the real binary. It calls `command claude` internally (which bypasses shell functions and hits the real binary directly), so there's no recursion and no conflict with your existing setup.

**Claude handles restarts automatically.** The installer patches `~/.claude/CLAUDE.md` with instructions telling Claude when to invoke `/resurrect` -- installing an MCP server, editing settings, modifying hooks, running `claude update`. Claude detects these situations and restarts itself without asking you. You just see the session resume.

You can also trigger manually from inside a session:

| Command | What it does |
|---|---|
| `/resurrect` | Write the manifest, then restart. Use for any real task. |
| `/resurrect-now` | Instant hard restart, no manifest. Quick config reload. |

---

## The manifest format

Claude writes this before dying:

```markdown
# Resurrection Manifest
generated: 2026-04-22T14:33:07Z
session_id: a1b2c3d4-e5f6-7890-abcd-ef1234567890
reason: mcp-install

## Original Mission
Build a CLI tool using the GitHub MCP server to auto-label pull requests
based on which files were changed...

## Completed Steps
- [x] Installed @modelcontextprotocol/server-github
- [x] Added entry to ~/.claude.json under mcpServers
- [x] Verified config file syntax
- [x] Created src/ and tsconfig.json

## Exact Resume Point
On step 4/7. src/auto-label.ts does not exist yet.
Needed restart so Claude Code picks up the MCP server.

## Immediate Action After Restart
Run /mcp to confirm github-mcp is connected.
If yes: write src/auto-label.ts using the schema in docs/api.md.
If no: check ~/.claude.json for the github-mcp entry.

## Open Questions / Blockers
GITHUB_TOKEN needs to be exported before testing.
```

Full example in `examples/resurrection.md`.

---

## Flags and permissions

Everything passes through. If you launch with `--dangerously-skip-permissions`, the resumed session gets the same flag. Any startup flag you use with `cr` is preserved across restarts.

Session-scoped permissions (things you clicked "always allow" during a session) are not inherited on resume -- that's a Claude Code behavior, not something the wrapper can change. The manifest's "Immediate Action" section is where Claude can note anything permission-sensitive so it can re-request cleanly.

---

## The pre-compact hook

Long sessions compact automatically. The `pre-compact.mjs` hook fires just before compaction, parses the JSONL transcript, and writes `.claude/compaction-backup.md` with:
- The original user request
- Recently touched files
- Last 10 commands run
- The last few conversation turns

This is not automatic resurrection -- it's a backup. If you restart manually after a compaction event, tell Claude: "Read `.claude/compaction-backup.md` and pick up where we left off."

---

## Known limitations

**Subagents:** If Claude spawns a subagent and the subagent's Bash tool sends `kill -HUP $PPID`, it signals the subagent's parent process, not the main Claude Code session. Only trigger `/resurrect` from the main agent.

**Windows (WSL2 / Git Bash / MSYS / PowerShell):** Works, but uses a different mechanism. In Windows environments, `kill -HUP $PPID` is unreliable. Both the bash and PowerShell wrappers start a background watcher that polls for `.claude/resurrect.flag`. The skill writes that flag before attempting the kill. When the watcher sees the file, it calls `Stop-Process` on `claude.exe` (or `node.exe` for npm-only installs), triggering the restart. Same result, ~0.3s extra latency.

**Docker:** Session files live in `~/.claude/`. If the home directory isn't mounted as a volume, `--resume` has nothing to resume. Mount it or bind-mount `.claude/`.

**Session ID fallback:** If `$CLAUDE_SESSION_ID` is not available in Claude's bash environment, the manifest records "unknown" and the wrapper falls back to `claude -c`. This still works in most cases but is slightly less reliable than an explicit `--resume <id>`.

---

## How it works (technical)

On macOS/Linux, `kill -HUP $PPID` from within Claude's Bash tool sends SIGHUP to the Claude Code process. Exit code is `129` (POSIX: `128 + signal_number`). The `claude()` wrapper loops on this exit code, checks for `.claude/resurrection.md`, extracts the session ID, deletes the file, then relaunches with `--resume <id> "<manifest>"`.

On Windows, the flag file replaces SIGHUP. The wrapper (bash or PowerShell) starts a background watcher that calls PowerShell's `Stop-Process` on `claude.exe` when the flag appears.

More detail: [docs/how-it-works.md](./docs/how-it-works.md)
Troubleshooting: [docs/troubleshooting.md](./docs/troubleshooting.md)

---

## File structure

```
claude-resurrect/
├── install.sh                         bash install (macOS/Linux/WSL/Git Bash)
├── install.ps1                        PowerShell install (Windows Terminal)
├── uninstall.sh                       bash removal
├── uninstall.ps1                      PowerShell removal
├── update.sh                          git pull + reinstall (bash)
├── wrapper/
│   ├── claude-resurrect.sh            claude() shell function (bash/zsh)
│   └── claude-resurrect.ps1           claude() function (PowerShell)
├── skills/
│   ├── resurrect/
│   │   └── SKILL.md                   write manifest -> restart
│   └── resurrect-now/
│       └── SKILL.md                   instant restart (no manifest)
├── hooks/
│   └── pre-compact.mjs                backup before compaction
├── examples/
│   ├── resurrection.md                example manifest (full, real-looking)
│   └── CLAUDE.md                      block to copy into your CLAUDE.md
└── docs/
    ├── how-it-works.md                technical walkthrough
    └── troubleshooting.md             common issues
```

---

## Prior art

The SIGHUP mechanism -- `kill -HUP $PPID`, exit code 129, the wrapper loop -- was documented by Anthony Panozzo in February 2026: [Building a Reload Command for Claude Code](https://www.panozzaj.com/blog/2026/02/07/building-a-reload-command-for-claude-code/). His post laid the foundation. claude-resurrect adds the manifest layer on top: instead of waking up to a generic "restarted" message, Claude wakes up to its own precise notes about what it was doing and what to do next.

---

## Why this exists

Restarting to reload an MCP server is genuinely painful right now. The current flow: quit Claude, run `claude --resume`, re-select the session, re-explain what you were doing. Every time. The manifest turns that into zero friction -- Claude handles the whole thing and picks up exactly where it left off.

---

## Contributing

Issues and PRs welcome. Most useful contributions right now:

- Testing on different macOS/Linux setups and reporting what breaks
- Improving the `pre-compact.mjs` transcript parser (it's deliberately simple)
- Adding a `--dry-run` mode that writes the manifest but skips the kill

---

MIT License
