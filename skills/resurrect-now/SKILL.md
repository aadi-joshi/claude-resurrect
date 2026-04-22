---
name: resurrect-now
description: >
  Instant hard restart -- no manifest written. Use only when you need a quick
  reload and have no task state worth preserving. For mid-task restarts, use
  /resurrect instead.
---

First check if the wrapper is active:

```bash
echo "wrapper:${CLAUDE_RESURRECT_WRAPPER:-0}"
```

If the output is `wrapper:1`, run the restart immediately:

```bash
mkdir -p .claude && touch .claude/resurrect.flag && kill -HUP $PPID
```

If the output is `wrapper:0`, tell the user: "Auto-restart is not available --
Claude Code was not launched via the `claude` shell wrapper. To restart: close
this session and run `claude` from a terminal." Do not attempt the kill command.
