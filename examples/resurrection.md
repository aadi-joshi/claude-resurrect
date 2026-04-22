# Resurrection Manifest
generated: 2026-04-22T14:33:07Z
session_id: a1b2c3d4-e5f6-7890-abcd-ef1234567890
reason: mcp-install

## Original Mission
Build a tool that uses the GitHub MCP server to auto-label pull requests based on
which files were changed. Entry point is src/auto-label.ts. Output should be a
standalone CLI: `npx auto-label --repo owner/repo --pr 123`.

## Completed Steps
- [x] Installed @modelcontextprotocol/server-github via `npm install -g @modelcontextprotocol/server-github`
- [x] Added github-mcp entry to ~/.claude.json under mcpServers with GITHUB_TOKEN env var
- [x] Verified ~/.claude.json syntax with `node -e "JSON.parse(require('fs').readFileSync(...))"` — valid
- [x] Created src/ directory and tsconfig.json

## Exact Resume Point
On step 4 of 7. Was about to write src/auto-label.ts. The file does not exist yet
(src/ is empty). Claude Code needed to restart to pick up the newly registered MCP
server — it was not showing in /mcp before the restart.

## Immediate Action After Restart
1. Run `/mcp` to confirm github-mcp appears as connected.
   - If connected: proceed to write src/auto-label.ts (see schema notes below)
   - If NOT connected: check ~/.claude.json for the `github-mcp` entry; the key
     under mcpServers should be "github-mcp" with command "npx" and args
     ["@modelcontextprotocol/server-github"]
2. The labeling logic: map file path prefixes to labels
   (src/auth/** → "auth", src/payments/** → "billing", tests/** → "testing")
3. Use the GitHub MCP `list_pull_request_files` tool to get changed files,
   then `add_labels_to_issue` to apply them.

## Open Questions / Blockers
- GITHUB_TOKEN needs to be set in the environment before running — remind user
  to export it before testing
- Not sure if the MCP server supports `add_labels_to_issue` or if we need REST API
  fallback — check available tools via /mcp after restart
