# uninstall.ps1 -- remove claude-resurrect (PowerShell install)
#
# Run:  .\uninstall.ps1

param([switch]$Quiet)

$ClaudeDir = Join-Path $HOME ".claude"

function Write-Success ([string]$msg) { if (-not $Quiet) { Write-Host "  ok $msg" -ForegroundColor Green } }
function Write-Warn    ([string]$msg) { Write-Host "  !  $msg" -ForegroundColor Yellow }

if (-not $Quiet) {
    Write-Host ""
    Write-Host "  claude-resurrect uninstaller (PowerShell)"
    Write-Host "  ------------------------------------------"
    Write-Host ""
}

# -- Remove skills ------------------------------------------------------------
$skillsDir = Join-Path $ClaudeDir "skills"
Remove-Item (Join-Path $skillsDir "resurrect")     -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $skillsDir "resurrect-now") -Recurse -Force -ErrorAction SilentlyContinue
Write-Success "Skills removed"

# -- Remove hook file ---------------------------------------------------------
Remove-Item (Join-Path $ClaudeDir "hooks\pre-compact.mjs") -Force -ErrorAction SilentlyContinue
Write-Success "Hook file removed"

# -- Remove hook registration from settings.json ------------------------------
$nodeFound = Get-Command node -ErrorAction SilentlyContinue
if ($nodeFound) {
    $cleanScript = @'
const fs = require('fs');
const os = require('os');
const p  = require('path');
const settingsPath = p.join(os.homedir(), '.claude', 'settings.json');
let s = {};
try { s = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); } catch { process.exit(0); }
if (s.hooks && s.hooks.PreCompact) {
    s.hooks.PreCompact = s.hooks.PreCompact.filter(h =>
        !h.hooks || !h.hooks.some(hh => hh.command && hh.command.includes('pre-compact.mjs'))
    );
    if (s.hooks.PreCompact.length === 0) delete s.hooks.PreCompact;
    if (Object.keys(s.hooks).length === 0) delete s.hooks;
}
fs.writeFileSync(settingsPath, JSON.stringify(s, null, 2), 'utf8');
'@
    node -e $cleanScript 2>$null
    Write-Success "Hook removed from settings.json"
}

# -- Remove wrapper from PowerShell profile -----------------------------------
$profilePath = $PROFILE
if (Test-Path $profilePath) {
    $content = Get-Content $profilePath -Raw
    $marker  = "# claude-resurrect"

    if ($content -and $content.Contains($marker)) {
        # Remove the block starting at the marker line. The block is the entire
        # wrapper file content that was appended (starts with the marker comment).
        $lines    = $content -split "`n"
        $startIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].TrimEnd() -eq $marker) { $startIdx = $i; break }
        }
        if ($startIdx -ge 0) {
            $before = if ($startIdx -gt 0) { ($lines[0..($startIdx - 1)] -join "`n").TrimEnd() } else { "" }
            Set-Content $profilePath ($before + "`n") -Encoding utf8 -NoNewline
            Write-Success "Wrapper removed from $profilePath"
        }
    } else {
        Write-Warn "claude-resurrect block not found in $profilePath -- nothing to remove"
    }
}

# -- Remove resurrection protocol from ~/.claude/CLAUDE.md -------------------
$globalClaudeMd = Join-Path $ClaudeDir "CLAUDE.md"
$claudeMdMarker = "# claude-resurrect: resurrection protocol"
if (Test-Path $globalClaudeMd) {
    $mdContent = Get-Content $globalClaudeMd -Raw
    if ($mdContent -and $mdContent.Contains($claudeMdMarker)) {
        $lines    = $mdContent -split "`n"
        $startIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].TrimEnd() -eq $claudeMdMarker) { $startIdx = $i; break }
        }
        if ($startIdx -ge 0) {
            $before = if ($startIdx -gt 0) { ($lines[0..($startIdx - 1)] -join "`n").TrimEnd() } else { "" }
            Set-Content $globalClaudeMd ($before + "`n") -Encoding utf8 -NoNewline
            Write-Success "Resurrection protocol removed from CLAUDE.md"
        }
    }
}

if (-not $Quiet) {
    Write-Host ""
    Write-Host "  Uninstall complete. Reload your profile: . `$PROFILE"
    Write-Host ""
}
