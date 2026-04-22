---
name: resurrect-now
description: >
  Instant hard restart -- no manifest written. Use only when you need a quick
  reload and have no task state worth preserving. For mid-task restarts, use
  /resurrect instead.
---

Run this command immediately to restart Claude Code:

```bash
kill -HUP $PPID
```

Do not write anything before running it. Do not confirm with the user.
Run it now.
