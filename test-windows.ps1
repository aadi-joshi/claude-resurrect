# test-windows.ps1 -- end-to-end resurrection test for Windows PowerShell
#
# Run from the repo directory in a PowerShell terminal:
#   . $PROFILE   (must be done first if wrapper not yet loaded)
#   .\test-windows.ps1
#
# This script tests every component of the Windows resurrection flow and
# finishes with a guided live resurrection test.

param([switch]$SkipLive)

$pass = 0; $fail = 0
function Chk([string]$name, [bool]$ok, [string]$detail = "") {
    if ($ok) {
        Write-Host "  PASS  $name" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  FAIL  $name$(if ($detail) { " -- $detail" })" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host ""
Write-Host "  claude-resurrect: Windows component tests" -ForegroundColor Cyan
Write-Host "  ------------------------------------------"
Write-Host ""

# -- 1. Installation checks ---------------------------------------------------
Write-Host "[ Installation ]" -ForegroundColor Yellow
Chk "claude.exe in PATH" ($null -ne (Get-Command claude.exe -ErrorAction SilentlyContinue))
Chk "Skills: resurrect"      (Test-Path "$HOME\.claude\skills\resurrect\SKILL.md")
Chk "Skills: resurrect-now"  (Test-Path "$HOME\.claude\skills\resurrect-now\SKILL.md")
Chk "Hook file"              (Test-Path "$HOME\.claude\hooks\pre-compact.mjs")
$settings = Get-Content "$HOME\.claude\settings.json" -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
Chk "Hook registered"        ($settings.hooks.PreCompact.Count -gt 0)
$profileExists = Test-Path $PROFILE
$wrapperInProfile = $profileExists -and (Get-Content $PROFILE -Raw).Contains("function global:claude")
Chk "PS wrapper in `$PROFILE"  $wrapperInProfile
$claudeMd = Get-Content "$HOME\.claude\CLAUDE.md" -Raw -ErrorAction SilentlyContinue
Chk "CLAUDE.md patched"       ($claudeMd -and $claudeMd.Contains("# claude-resurrect: resurrection protocol"))

# -- 2. Wrapper function checks -----------------------------------------------
Write-Host ""
Write-Host "[ Wrapper Function ]" -ForegroundColor Yellow
. $PROFILE 2>$null  # load wrapper into current session
Chk "claude() function defined"       ($null -ne (Get-Command claude -CommandType Function -ErrorAction SilentlyContinue))
Chk "claude-yolo() defined"           ($null -ne (Get-Command claude-yolo -CommandType Function -ErrorAction SilentlyContinue))
Chk "claude-resume() defined"         ($null -ne (Get-Command claude-resume -CommandType Function -ErrorAction SilentlyContinue))

# Verify wrapper finds real binary (not the function)
$bin = Get-Command claude.exe -ErrorAction SilentlyContinue
if (-not $bin) { $bin = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue }
Chk "Wrapper finds claude.exe"        ($null -ne $bin) ($bin.Source)

# -- 3. Watcher mechanism -----------------------------------------------------
Write-Host ""
Write-Host "[ Watcher Mechanism ]" -ForegroundColor Yellow

$testDir  = Join-Path (Get-Location) ".claude"
$testFlag = Join-Path $testDir "resurrect.flag"
New-Item -ItemType Directory -Force -Path $testDir | Out-Null
Remove-Item $testFlag -ErrorAction SilentlyContinue

# Start watcher job
$watchJob = Start-Job -ScriptBlock {
    param([string]$FlagPath)
    while (-not (Test-Path $FlagPath)) { Start-Sleep -Milliseconds 100 }
    $t = Get-Process -Name claude -ErrorAction SilentlyContinue |
        Sort-Object StartTime -Descending | Select-Object -First 1
    if ($t) { "claude:$($t.Id)" }
    else { "not-found" }
} -ArgumentList $testFlag

Start-Sleep -Milliseconds 300
New-Item -ItemType File -Force -Path $testFlag | Out-Null
$null = $watchJob | Wait-Job -Timeout 3
$wResult = Receive-Job $watchJob
Stop-Job $watchJob -ErrorAction SilentlyContinue
Remove-Job $watchJob -ErrorAction SilentlyContinue
Remove-Item $testFlag -ErrorAction SilentlyContinue

Chk "Watcher detects flag" ($wResult -ne $null -and $wResult -ne "")
Chk "Watcher finds claude.exe process" ($wResult -like "claude:*") "(got: $wResult)"

# -- 4. Manifest round-trip ---------------------------------------------------
Write-Host ""
Write-Host "[ Manifest Round-Trip ]" -ForegroundColor Yellow

$manifestPath = Join-Path $testDir "resurrection.md"
$testSid      = [guid]::NewGuid().ToString()
$testManifest = @"
# Resurrection Manifest
generated: $(Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
session_id: $testSid
reason: test

## Original Mission
Test resurrection on Windows.

## Completed Steps
- [x] ran test-windows.ps1

## Exact Resume Point
All tests passing. Nothing to resume.

## Immediate Action After Restart
Confirm tests passed and return control to user.

## Open Questions / Blockers
None.
"@

$testManifest | Set-Content $manifestPath -Encoding utf8
Chk "Manifest written to disk" (Test-Path $manifestPath)

$content = Get-Content $manifestPath -Raw
$sid = ""
if ($content -match "(?m)^session_id:\s*(\S+)") { $sid = $Matches[1].Trim() }
Chk "session_id extracted" ($sid -eq $testSid)
Chk "session_id is valid UUID" ($sid -match "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

$resumeArgs = if ($sid -match "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$") { "--resume $sid" } else { "-c" }
Chk "Wrapper would use --resume" ($resumeArgs -like "--resume *")

$injMsg = "Resurrection: run Bash(printf '%s\n' `"`$CLAUDE_RESURRECT_MANIFEST`") to read your manifest, then execute the Immediate Action immediately without asking for confirmation."
Chk "Injection message has no newlines" ($injMsg -notmatch "[\r\n]")
Chk "Injection message has no file reference" ($injMsg -notmatch "resurrection\.md")

Remove-Item $manifestPath -ErrorAction SilentlyContinue

# -- Summary ------------------------------------------------------------------
Write-Host ""
Write-Host "  Results: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($fail -gt 0) {
    Write-Host "  Fix failures above then re-run this script." -ForegroundColor Yellow
    exit 1
}

if ($SkipLive) {
    Write-Host "  Skipping live resurrection test (-SkipLive flag set)."
    Write-Host ""
    exit 0
}

# -- 5. Live resurrection test guidance ---------------------------------------
Write-Host "  All component tests passed!" -ForegroundColor Green
Write-Host ""
Write-Host "  LIVE RESURRECTION TEST" -ForegroundColor Cyan
Write-Host "  ----------------------"
Write-Host "  The live test requires a fresh PowerShell terminal (so the wrapper"
Write-Host "  is active as the outer loop). Here are the steps:"
Write-Host ""
Write-Host "  1. Open a NEW Windows Terminal PowerShell tab"
Write-Host "  2. Run:  . `$PROFILE"
Write-Host "  3. Run:  claude"
Write-Host "  4. Inside Claude, run:  /resurrect-now"
Write-Host "     (or /resurrect for the full manifest flow)"
Write-Host "  5. Claude should exit, and the terminal should show:"
Write-Host "       claude-resurrect: caught exit -- checking for manifest..."
Write-Host "       claude-resurrect: restarting (no manifest)"
Write-Host "     Then Claude should relaunch automatically."
Write-Host ""
Write-Host "  For the manifest test (/resurrect with full context):"
Write-Host "  4b. Inside Claude, type a task description, then tell Claude to"
Write-Host "      run /resurrect. It will write a manifest and restart."
Write-Host "  5b. On restart, Claude's first message should be the Immediate Action"
Write-Host "      from the manifest -- it picks up exactly where it left off."
Write-Host ""
