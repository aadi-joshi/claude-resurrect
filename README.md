# claude-resurrect

> Claude kills itself. Then wakes back up. And knows exactly where it left off.

<img width="209" height="195" alt="ezgif com-animated-gif-maker (1)" src="https://github.com/user-attachments/assets/0783012b-ce83-4804-af9d-48c0ca4819c2" />

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
           +-- runs: kill -HUP $PPID
                |
                v
           Claude Code exits 129
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

To skip the hook:

```bash
bash install.sh --no-hooks
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

Inside a session, Claude uses the skills directly:

| Command | What it does |
|---|---|
| `/resurrect` | Write the manifest, then restart. Use for any real task. |
| `/resurrect-now` | Instant hard restart, no manifest. Quick config reload. |

For Claude to trigger these automatically (instead of just telling you to restart), add the resurrection protocol block to your `~/.claude/CLAUDE.md`. Copy it from `examples/CLAUDE.md`.

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

**Windows (native):** SIGHUP doesn't exist on native Windows. Works on macOS, Linux, and WSL2.

**Docker:** Session files live in `~/.claude/`. If the home directory isn't mounted as a volume, `--resume` has nothing to resume. Mount it or bind-mount `.claude/`.

**Session ID fallback:** If `$CLAUDE_SESSION_ID` is not available in Claude's bash environment, the manifest records "unknown" and the wrapper falls back to `claude -c`. This still works in most cases but is slightly less reliable than an explicit `--resume <id>`.

---

## How it works (technical)

`kill -HUP $PPID` from within Claude's Bash tool sends SIGHUP to the Claude Code Node.js process. Exit code is `129` (POSIX: `128 + signal_number`). The `cr()` wrapper loops on this code, checks for `.claude/resurrection.md`, extracts the session ID, deletes the file, then relaunches with `--resume <id> "<manifest>"`.

More detail: [docs/how-it-works.md](./docs/how-it-works.md)
Troubleshooting: [docs/troubleshooting.md](./docs/troubleshooting.md)

---

## File structure

```
claude-resurrect/
├── install.sh                         one-liner install
├── uninstall.sh                       clean removal
├── wrapper/
│   └── claude-resurrect.sh            the cr() shell function
├── skills/
│   ├── resurrect/
│   │   └── SKILL.md                   write manifest -> kill -HUP $PPID
│   └── resurrect-now/
│       └── SKILL.md                   !`kill -HUP $PPID` (instant, no manifest)
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
