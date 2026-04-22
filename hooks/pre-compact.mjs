#!/usr/bin/env node
/**
 * pre-compact.mjs
 * Claude Code PreCompact hook.
 *
 * Fires before Claude Code compacts the context window.
 * Reads the JSONL session transcript and writes a structured backup
 * to .claude/compaction-backup.md — so if you restart after a compaction
 * event, you have a human-readable record of what was happening.
 *
 * This is NOT the same as the resurrection manifest (which Claude writes
 * intentionally before killing itself). This is a safety net for unexpected
 * compactions during long agentic sessions.
 *
 * Installation: see install.sh or add to .claude/settings.json manually:
 * {
 *   "hooks": {
 *     "PreCompact": [{ "hooks": [{ "type": "command", "command": "node ~/.claude/hooks/pre-compact.mjs" }] }]
 *   }
 * }
 */

import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync } from 'fs';
import { join, resolve } from 'path';
import { homedir } from 'os';

// ── Read hook input from stdin ───────────────────────────────────────────────
// Use fd 0 (not /dev/stdin) -- works on both Unix and Windows
let hookInput = '';
try {
  hookInput = readFileSync(0, 'utf8');
} catch {
  // stdin unavailable -- still run but with no hook context
}

let hookData = {};
try {
  hookData = JSON.parse(hookInput);
} catch {
  // not JSON or empty — that's fine
}

const sessionId = hookData.session_id || process.env.CLAUDE_SESSION_ID || 'unknown';
const projectDir = process.cwd();
const claudeDir = join(projectDir, '.claude');

// ── Parse the session JSONL transcript ──────────────────────────────────────
function findSessionFile(sessionId) {
  const projectHash = Buffer.from(resolve(projectDir)).toString('base64url').slice(0, 20);
  const projectsBase = join(homedir(), '.claude', 'projects');

  // Try to find by session ID across all project dirs
  try {
    const projectDirs = readdirSync(projectsBase);
    for (const dir of projectDirs) {
      const sessionFile = join(projectsBase, dir, `${sessionId}.jsonl`);
      try {
        statSync(sessionFile);
        return sessionFile;
      } catch { /* not here */ }
    }
  } catch { /* projects dir not found */ }

  return null;
}

function parseTranscript(filePath) {
  const lines = readFileSync(filePath, 'utf8').split('\n').filter(Boolean);
  const userMessages = [];
  const toolUses = [];
  const fileEdits = [];

  for (const line of lines) {
    try {
      const record = JSON.parse(line);

      // Collect user messages
      if (record.type === 'user' && record.message?.content) {
        const content = record.message.content;
        if (typeof content === 'string' && content.trim()) {
          userMessages.push(content.trim().slice(0, 200));
        } else if (Array.isArray(content)) {
          for (const block of content) {
            if (block.type === 'text' && block.text?.trim()) {
              userMessages.push(block.text.trim().slice(0, 200));
            }
          }
        }
      }

      // Collect tool uses (bash commands, file writes)
      if (record.type === 'assistant' && record.message?.content) {
        for (const block of (record.message.content || [])) {
          if (block.type === 'tool_use') {
            if (block.name === 'Bash' && block.input?.command) {
              toolUses.push(block.input.command.slice(0, 150));
            }
            if ((block.name === 'Write' || block.name === 'Edit') && block.input?.file_path) {
              fileEdits.push(block.input.file_path);
            }
          }
        }
      }
    } catch { /* malformed line — skip */ }
  }

  return { userMessages, toolUses, fileEdits };
}

// ── Build and write the backup manifest ─────────────────────────────────────
function buildManifest(transcript) {
  const { userMessages, toolUses, fileEdits } = transcript;
  const now = new Date().toISOString();

  const uniqueFiles = [...new Set(fileEdits)];
  const recentCommands = toolUses.slice(-10);
  const firstMessage = userMessages[0] || '(not captured)';
  const lastMessages = userMessages.slice(-3);

  return `# Compaction Backup
generated: ${now}
session_id: ${sessionId}
trigger: pre-compact hook (automatic)

## Original Request
${firstMessage}

## Recently Touched Files
${uniqueFiles.length > 0 ? uniqueFiles.map(f => `- ${f}`).join('\n') : '- (none captured)'}

## Last Commands Run
${recentCommands.length > 0 ? recentCommands.map(c => `\`${c}\``).join('\n') : '(none captured)'}

## Recent Conversation Tail
${lastMessages.map(m => `> ${m}`).join('\n\n')}

---
This file was written automatically before context compaction.
If you restart Claude Code after a compaction, read this file first to restore context.
To resume with this context: start claude, then say "Read .claude/compaction-backup.md and pick up where we left off."
`;
}

try {
  mkdirSync(claudeDir, { recursive: true });

  let manifest = `# Compaction Backup\ngenerated: ${new Date().toISOString()}\nsession_id: ${sessionId}\ntrigger: pre-compact hook\n\n(transcript not available)\n`;

  const sessionFile = sessionId !== 'unknown' ? findSessionFile(sessionId) : null;
  if (sessionFile) {
    const transcript = parseTranscript(sessionFile);
    manifest = buildManifest(transcript);
  }

  writeFileSync(join(claudeDir, 'compaction-backup.md'), manifest, 'utf8');
  process.exit(0);
} catch (err) {
  // Never block compaction — exit 0 regardless
  process.stderr.write(`pre-compact hook error: ${err.message}\n`);
  process.exit(0);
}
