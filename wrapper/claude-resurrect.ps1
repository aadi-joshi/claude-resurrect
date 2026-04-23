# claude-resurrect PowerShell wrapper
# Source this in your PowerShell profile ($PROFILE):
#   . "$HOME\claude-resurrect\wrapper\claude-resurrect.ps1"
# Or let install.ps1 add it automatically.
#
# Defines a 'claude' function that shadows the real binary.
# Uses a background job to watch for .claude/resurrect.flag and kill the
# Claude Code process via Stop-Process when resurrection is requested.
#
# Works with Windows PowerShell 5.1 and PowerShell 7+.
# Does not require WSL or Git Bash.
#
# Restart mechanism:
#   The skill writes .claude/resurrect.flag before attempting kill -HUP.
#   This watcher sees the flag and calls Stop-Process on the claude.exe
#   (or node.exe) process. The wrapper then checks for the flag on return,
#   reads .claude/resurrection.md into $env:CLAUDE_RESURRECT_MANIFEST,
#   deletes the manifest, and restarts claude with a trigger message.
#
# Why env var instead of file or inline content:
#   Keeping the manifest on disk requires Claude to delete it, which triggers
#   a "sensitive file" permission prompt for ~/.claude/ even with
#   --dangerously-skip-permissions. Passing full content as a CLI arg can
#   be truncated on Windows. Env var avoids both problems: wrapper deletes
#   the file, Claude reads the content from the inherited env var.

# claude-resurrect

function global:claude {
    $env:CLAUDE_RESURRECT_WRAPPER = "1"
    $baseDir  = (Get-Location).Path
    $manifest = Join-Path $baseDir ".claude\resurrection.md"
    $flag     = Join-Path $baseDir ".claude\resurrect.flag"
    $firstRun = $true
    $userArgs  = $args

    # Find the real claude binary. -CommandType Application skips this function.
    # Prefer claude.exe (native binary) over claude.cmd (.cmd shim via cmd.exe).
    $claudeBin = $null
    $bin = Get-Command claude.exe -ErrorAction SilentlyContinue
    if ($bin) {
        $claudeBin = $bin.Source
    }
    if (-not $claudeBin) {
        $bin = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue
        if ($bin) { $claudeBin = $bin.Source }
    }
    if (-not $claudeBin) {
        $bin = Get-Command claude.cmd -ErrorAction SilentlyContinue
        if ($bin) { $claudeBin = $bin.Source }
    }
    if (-not $claudeBin) {
        Write-Error "claude-resurrect: 'claude' binary not found in PATH"
        return
    }

    while ($true) {
        # Start background watcher: polls for flag file, kills Claude when found.
        $watcherJob = Start-Job -ScriptBlock {
            param([string]$FlagPath)
            while (-not (Test-Path $FlagPath)) {
                Start-Sleep -Milliseconds 300
            }
            # Claude Code ships as claude.exe on Windows; fall back to node.exe
            # for npm-only installs where Claude runs as node.
            $target = Get-Process -Name claude -ErrorAction SilentlyContinue |
                Sort-Object StartTime -Descending |
                Select-Object -First 1
            if (-not $target) {
                $target = Get-Process -Name node -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        $id  = $_.Id
                        $cmd = try {
                            (Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue).CommandLine
                        } catch { "" }
                        [PSCustomObject]@{ Proc = $_; Cmd = $cmd }
                    } |
                    Where-Object { $_.Cmd -match "claude" } |
                    Sort-Object { $_.Proc.StartTime } -Descending |
                    Select-Object -First 1 -ExpandProperty Proc
            }
            if (-not $target) {
                $target = Get-Process -Name node -ErrorAction SilentlyContinue |
                    Sort-Object StartTime -Descending |
                    Select-Object -First 1
            }
            if ($target) { $target | Stop-Process -Force }
        } -ArgumentList $flag

        # Launch Claude Code
        if ($firstRun) {
            & $claudeBin @userArgs
        } elseif (Test-Path $manifest) {
            # Extract session ID from the manifest
            $sid = ""
            $content = Get-Content $manifest -Raw -ErrorAction SilentlyContinue
            if ($content -and ($content -match "(?m)^session_id:\s*(\S+)")) {
                $sid = $Matches[1].Trim()
            }
            # Fallback: find the most recently modified session JSONL file
            if (-not $sid -or $sid -eq "unknown") {
                $projectsBase = Join-Path $HOME ".claude\projects"
                $recentJsonl  = Get-ChildItem $projectsBase -Filter "*.jsonl" -Recurse -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1
                if ($recentJsonl) {
                    $sid = [System.IO.Path]::GetFileNameWithoutExtension($recentJsonl.Name)
                }
            }

            $resumeArgs = if ($sid -match "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$") {
                @("--resume", $sid)
            } else {
                @("-c")
            }

            Write-Host ""
            Write-Host "  claude-resurrect: manifest found -- resuming with context"
            Write-Host ""
            Start-Sleep -Milliseconds 300

            # Pass manifest via env var and delete the file here so Claude never
            # needs to touch ~/.claude/ (avoids sensitive-file permission prompt).
            $env:CLAUDE_RESURRECT_MANIFEST = $content
            Remove-Item $manifest -ErrorAction SilentlyContinue
            $trigger = "Resurrection: run Bash(printf '%s\n' `"`$CLAUDE_RESURRECT_MANIFEST`") to read your manifest, then execute the Immediate Action immediately without asking for confirmation."
            & $claudeBin @resumeArgs @userArgs $trigger
        } else {
            Write-Host ""
            Write-Host "  claude-resurrect: restarting (no manifest)"
            Write-Host "  Tip: use /resurrect instead of /resurrect-now to preserve task state."
            Write-Host ""
            Start-Sleep -Milliseconds 300
            & $claudeBin -c @userArgs
        }

        $firstRun = $false

        # Stop the watcher job (it may have already exited after triggering)
        Stop-Job  $watcherJob -ErrorAction SilentlyContinue
        Remove-Job $watcherJob -ErrorAction SilentlyContinue

        # Resurrection check: flag file means this was a requested restart
        if (Test-Path $flag) {
            Remove-Item $flag -ErrorAction SilentlyContinue
            Write-Host ""
            Write-Host "  claude-resurrect: caught exit -- checking for manifest..."
            continue
        }

        break
    }
}

function global:claude-yolo {
    claude --dangerously-skip-permissions @args
}

function global:claude-resume {
    if ($args.Count -eq 0) {
        Write-Error "Usage: claude-resume <session-id> [args...]"
        return
    }
    $session   = $args[0]
    $remaining = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
    $bin = Get-Command claude.exe -ErrorAction SilentlyContinue
    if (-not $bin) { $bin = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue }
    if ($bin) { & $bin.Source --resume $session @remaining }
}
