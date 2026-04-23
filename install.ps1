# install.ps1 -- claude-resurrect installer for Windows PowerShell
#
# Run from the repo directory:
#   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
#   .\install.ps1
#
# Or bypass execution policy for a one-shot install:
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# Flags:
#   -NoHooks    Skip the pre-compact hook installation

param(
    [switch]$NoHooks,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$RepoDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $HOME ".claude"
$SkillsDir = Join-Path $ClaudeDir "skills"
$HooksDir  = Join-Path $ClaudeDir "hooks"

function Write-Info    ([string]$msg) { if (-not $Quiet) { Write-Host "  -> $msg" -ForegroundColor Cyan } }
function Write-Success ([string]$msg) { if (-not $Quiet) { Write-Host "  ok $msg" -ForegroundColor Green } }
function Write-Warn    ([string]$msg) { Write-Host "  !  $msg" -ForegroundColor Yellow }
function Write-Fail    ([string]$msg) { Write-Host "  x  $msg" -ForegroundColor Red; exit 1 }

if (-not $Quiet) {
    Write-Host ""
    Write-Host "  claude-resurrect installer (PowerShell)"
    Write-Host "  ----------------------------------------"
    Write-Host ""
}

# -- Check dependencies -------------------------------------------------------
$claudeFound = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeFound) {
    Write-Fail "claude not found. Install Claude Code first: https://claude.ai/download"
}
$nodeFound = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeFound) {
    Write-Warn "node not found -- pre-compact hook requires Node.js to run"
}

# -- Create directories -------------------------------------------------------
New-Item -ItemType Directory -Force -Path (Join-Path $SkillsDir "resurrect")     | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $SkillsDir "resurrect-now") | Out-Null
New-Item -ItemType Directory -Force -Path $HooksDir                               | Out-Null

# -- Install skills -----------------------------------------------------------
Write-Info "Installing skills..."
Copy-Item (Join-Path $RepoDir "skills\resurrect\SKILL.md")     (Join-Path $SkillsDir "resurrect\SKILL.md")     -Force
Copy-Item (Join-Path $RepoDir "skills\resurrect-now\SKILL.md") (Join-Path $SkillsDir "resurrect-now\SKILL.md") -Force
Write-Success "Skills installed to $SkillsDir"

# -- Install pre-compact hook -------------------------------------------------
if (-not $NoHooks) {
    Write-Info "Installing pre-compact hook..."
    Copy-Item (Join-Path $RepoDir "hooks\pre-compact.mjs") (Join-Path $HooksDir "pre-compact.mjs") -Force
    Write-Success "Hook installed to $HooksDir\pre-compact.mjs"

    if ($nodeFound) {
        # Use Node.js to patch settings.json so paths are always Windows-native
        $patchScript = @'
const fs = require('fs');
const os = require('os');
const p  = require('path');
const settingsPath = p.join(os.homedir(), '.claude', 'settings.json');
let s = {};
try { s = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); } catch {}
s.hooks = s.hooks || {};
s.hooks.PreCompact = s.hooks.PreCompact || [];
const cmd = 'node ' + p.join(os.homedir(), '.claude', 'hooks', 'pre-compact.mjs');
const already = s.hooks.PreCompact.some(h => h.hooks && h.hooks.some(hh => hh.command === cmd));
if (!already) {
    s.hooks.PreCompact.push({ hooks: [{ type: 'command', command: cmd, async: true }] });
}
fs.writeFileSync(settingsPath, JSON.stringify(s, null, 2), 'utf8');
console.log('ok');
'@
        $result = node -e $patchScript 2>$null
        if ($result -eq "ok") {
            Write-Success "Registered PreCompact hook in settings.json"
        } else {
            Write-Warn "Could not auto-register hook. Add it manually -- see docs/how-it-works.md"
        }
    } else {
        Write-Warn "Skipping hook registration (node not found)"
    }
}

# -- Install PowerShell wrapper to $PROFILE -----------------------------------
Write-Info "Installing claude() wrapper to PowerShell profile..."

$profilePath = $PROFILE
$profileDir  = Split-Path -Parent $profilePath

if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
}
if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Force -Path $profilePath | Out-Null
}

$wrapperMarker = "# claude-resurrect"
$wrapperSource = Get-Content (Join-Path $RepoDir "wrapper\claude-resurrect.ps1") -Raw

$profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
if ($profileContent -and $profileContent.Contains($wrapperMarker)) {
    Write-Warn "claude-resurrect already present in PowerShell profile -- skipping (run uninstall.ps1 first to reinstall)"
} else {
    Add-Content $profilePath "`n$wrapperMarker`n$wrapperSource`n" -Encoding utf8
    Write-Success "claude() wrapper added to $profilePath"
}

# -- Patch ~/.claude/CLAUDE.md ------------------------------------------------
Write-Info "Patching CLAUDE.md with resurrection protocol..."

$globalClaudeMd = Join-Path $ClaudeDir "CLAUDE.md"
$claudeMdMarker = "# claude-resurrect: resurrection protocol"

# Filter comment header from the example file
$exampleLines = Get-Content (Join-Path $RepoDir "examples\CLAUDE.md") |
    Where-Object { $_ -notmatch "^# CLAUDE\.md" -and $_ -notmatch "^# Copy this" -and $_ -notmatch "^# This is" }
$exampleContent = $exampleLines -join "`n"

if (Test-Path $globalClaudeMd) {
    $mdContent = Get-Content $globalClaudeMd -Raw -ErrorAction SilentlyContinue
    if ($mdContent -and $mdContent.Contains($claudeMdMarker)) {
        Write-Warn "Resurrection protocol already present in CLAUDE.md -- skipping"
    } else {
        Add-Content $globalClaudeMd "`n$claudeMdMarker`n$exampleContent`n" -Encoding utf8
        Write-Success "Resurrection protocol added to CLAUDE.md"
    }
} else {
    Set-Content $globalClaudeMd "$claudeMdMarker`n$exampleContent`n" -Encoding utf8
    Write-Success "Resurrection protocol written to $globalClaudeMd"
}

# -- Done ---------------------------------------------------------------------
if (-not $Quiet) {
    Write-Host ""
    Write-Host "  Installation complete."
    Write-Host ""
    Write-Host "  Reload your profile:"
    Write-Host "    . `$PROFILE"
    Write-Host ""
    Write-Host "  Then use claude as normal -- the wrapper is transparent:"
    Write-Host "    claude"
    Write-Host "    claude --dangerously-skip-permissions"
    Write-Host ""
    Write-Host "  Claude will now restart itself automatically when needed."
    Write-Host "  Inside a session, you can also trigger manually:"
    Write-Host "    /resurrect      -> write manifest + restart (preserves task context)"
    Write-Host "    /resurrect-now  -> instant hard restart (no manifest)"
    Write-Host ""
}
