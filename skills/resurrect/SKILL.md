---
name: resurrect
description: >
  Use when you need to restart Claude Code mid-task: MCP server install,
  hook modification, settings update, or claude update. Writes a precise
  handoff manifest so you resume with full context, then restarts.
  For a quick reload with no task state to preserve, use /resurrect-now.
---

# Resurrection Protocol

You are about to restart Claude Code. Follow these steps exactly. Do not skip
any step. Do not add commentary between steps.

## Step 1 -- Check wrapper and get timestamp/session ID

Run this in the Bash tool:

```bash
mkdir -p .claude && date -u +"%Y-%m-%dT%H:%M:%SZ" && echo "${CLAUDE_SESSION_ID:-unknown}" && echo "wrapper:${CLAUDE_RESURRECT_WRAPPER:-0}"
```

Note the output: first line is the timestamp, second is the session ID, third line
is `wrapper:1` if launched via the `claude()` shell wrapper or `wrapper:0` if not.

**If `wrapper:0`:** the auto-restart mechanism is not active. This happens when
Claude Code was launched from the desktop app or directly (not via the wrapper
shell function). The manifest will still be written -- tell the user:
"Manifest written to `.claude/resurrection.md`. Auto-restart is not available
in this launch mode. To resume: close this session, open a terminal, run
`claude -c`, and I will read the manifest and continue." Then stop -- do not
attempt the kill command.

## Step 2 -- Write the Resurrection Manifest

Create or overwrite `.claude/resurrection.md` using the Write tool.
Fill in every section. Do not leave placeholders.

```
# Resurrection Manifest
generated: [timestamp from Step 1]
session_id: [session ID from Step 1]
reason: [one of: mcp-install | config-change | self-update | hook-reload | manual]

## Original Mission
[The full goal the user asked you to accomplish. Be specific -- include file
names, tool names, expected outcomes. One paragraph.]

## Completed Steps
[Bullet list of everything fully done. Include file paths and exact commands
run. Mark each [x]. If nothing is done yet, write "None yet."]

## Exact Resume Point
[One or two sentences: which step, what you were about to do, what state the
filesystem is in right now. Example: "About to write src/index.ts. The MCP
server config was added to ~/.claude.json but not yet loaded -- verify with
/mcp after restart."]

## Immediate Action After Restart
[The first concrete thing to do after reading this. Imperative and specific.
Include conditional paths. Example: "Run /mcp to confirm filesystem-mcp is
listed. If connected: continue with Step 4, writing src/index.ts using the
schema in docs/api.md. If not connected: check ~/.claude.json for the entry
added in Step 2."]

## Open Questions / Blockers
[Anything unresolved the user should know. Write "None." if clean.]
```

## Step 3 -- Verify

Read back `.claude/resurrection.md` with the Read tool. If any section is
missing or vague, rewrite it before continuing.

## Step 4 -- Signal restart

Run this exact command. Nothing else. No output message first.

```bash
mkdir -p .claude && touch .claude/resurrect.flag && kill -HUP $PPID
```

This does two things:
- Writes `.claude/resurrect.flag` -- the Windows/WSL2 watcher polls for this
  file and kills Claude Code via PowerShell when it appears
- Sends SIGHUP to Claude Code -- on macOS/Linux, the process exits with code 129

The `claude` wrapper catches either signal (exit 129 or the flag file), reads
the manifest, deletes it, and restarts Claude with the manifest as the first
message -- so you wake up knowing exactly where you were.

---

After running `kill -HUP $PPID`, this session ends immediately. The wrapper
handles the rest.
