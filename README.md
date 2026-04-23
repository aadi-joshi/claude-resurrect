# claude-resurrect

> Claude kills itself. Then wakes back up. And knows exactly where it left off.

<img width="209" height="195" alt="ezgif com-animated-gif-maker (1)" src="https://github.com/user-attachments/assets/0783012b-ce83-4804-af9d-48c0ca4819c2" />

**Platform support:** macOS, Linux, WSL2, Git Bash/MSYS, and **native Windows PowerShell** (Windows Terminal). Automatic restart uses SIGHUP on Unix and a background process watcher on Windows.

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
                     kills claude.exe via PowerShell, Claude Code exits
                |
                v
           wrapper catches it
           reads manifest, stores content, deletes the file
           sets CLAUDE_RESURRECT_MANIFEST env var (Windows)
           runs: claude --resume <session-id> [manifest or trigger]
                |
                v
           Claude wakes up. First message IS the manifest.
           Claude reads the resume point, takes the immediate action.
           No user input needed. No re-explaining.
```

The manifest is single-use. Deleted after the wrapper reads it. If you resurrect five times in a session, you get five clean handoffs.

---

## Quick tutorial

Install it (see below), then open a terminal:

```bash
claude --dangerously-skip-permissions
# PowerShell: claude-yolo
```

Give Claude a real multi-step task:

> "I'm building a GitHub PR labeler. Steps 1-2 are done (created src/ and tsconfig.json). Step 3 is to install the GitHub MCP server. Do it now, then continue."

Claude installs the server, notices it needs to restart to load it, and invokes `/resurrect` on its own. It writes a manifest:

```
## Completed Steps
- [x] Installed GitHub MCP server
- [x] Added entry to ~/.claude.json

## Exact Resume Point
MCP install complete. Need restart for server to load. src/auto-label.ts not yet written.

## Immediate Action After Restart
Run /mcp to confirm github-mcp is connected. If yes: write src/auto-label.ts.
```

Then it kills itself. The wrapper catches the exit, reads the manifest, relaunches. Claude wakes up, reads the resume point, runs `/mcp`, and continues writing `src/auto-label.ts`. You never touch the keyboard. The restart is about 2 seconds.

To trigger it manually inside any session:

| Command | What it does |
|---|---|
| `/resurrect` | Write the manifest, then restart. Use for any real task. |
| `/resurrect-now` | Instant hard restart, no manifest. Quick config reload. |

Use `--dangerously-skip-permissions` (or `claude-yolo`) so Claude never pauses mid-cycle. With that flag, the whole thing -- manifest write, kill, resume, immediate action -- runs without prompts.

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
- Adds a `claude()` shell function to your rc file that wraps the real binary transparently
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

Same as the bash installer -- skills, hook, wrapper, CLAUDE.md -- but adds a `claude()` function to `$PROFILE` instead of `.bashrc`.

```powershell
.\install.ps1 -NoHooks   # skip the pre-compact hook
.\uninstall.ps1          # remove everything
```

---

## Usage

After install, use `claude` as you normally would:

```bash
claude                                # normal launch, resurrection-enabled
claude --dangerously-skip-permissions # flags pass through unchanged
claude --model claude-opus-4-7
```

The wrapper shadows the real binary. It calls `command claude` internally, which bypasses shell functions and hits the actual binary -- no recursion, no conflict with your existing aliases.

**Claude handles restarts automatically.** The installer patches `~/.claude/CLAUDE.md` with instructions telling Claude when to use `/resurrect` -- installing an MCP server, editing settings, modifying hooks, running `claude update`. Claude detects these situations and handles the restart on its own. From your side, the session just resumes.

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

Everything passes through. `--dangerously-skip-permissions` is recommended for autonomous sessions and carries over to every restart. The `claude-yolo` alias (installed by the wrapper) makes it convenient:

```bash
claude-yolo
claude-yolo --model claude-opus-4-7
```

```powershell
claude-yolo   # PowerShell
```

On restart, the wrapper deletes the manifest before launching Claude. Claude reads the content from an environment variable (`CLAUDE_RESURRECT_MANIFEST`), so it never touches any sensitive files. No prompts during a resurrection cycle.

Session-scoped permissions (the "always allow" clicks from the previous session) don't carry over on resume -- that's Claude Code behavior, not something the wrapper can change. The manifest's "Immediate Action" section is where Claude can flag anything that needs re-approval.

---

## The pre-compact hook

Long sessions compact automatically. The `pre-compact.mjs` hook fires just before compaction, parses the JSONL transcript, and writes `.claude/compaction-backup.md` with:
- The original user request
- Recently touched files
- Last 10 commands run
- The last few conversation turns

This isn't automatic resurrection -- it's a safety net. If you restart manually after a compaction event, tell Claude: "Read `.claude/compaction-backup.md` and pick up where we left off."

---

## Known limitations

**Subagents:** If Claude spawns a subagent and the subagent's Bash tool sends `kill -HUP $PPID`, it signals the subagent's parent, not the main Claude Code session. Only trigger `/resurrect` from the main agent.

**Windows (WSL2 / Git Bash / MSYS / PowerShell):** Works, but differently. `kill -HUP $PPID` is unreliable in Windows environments. Both wrappers start a background watcher that polls for `.claude/resurrect.flag`. When the flag appears, it calls `Stop-Process` on `claude.exe` (or `node.exe` for npm-only installs). Same result, ~0.3s extra latency.

**Docker:** Session files live in `~/.claude/`. If the home directory isn't mounted as a volume, `--resume` has nothing to resume. Mount it or bind-mount `.claude/`.

**Session ID fallback:** If `$CLAUDE_SESSION_ID` isn't available in Claude's bash environment, the manifest records "unknown" and the wrapper falls back to `claude -c`. This works in most cases but is slightly less reliable than `--resume <id>`.

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
