<#
.SYNOPSIS
    Lightweight session-end reminder/check for the agent-workflow hub.
.PARAMETER WorkPerformed
    Pass this switch when the session made repo changes or produced
    validated findings. It checks whether any agent-workflow/*.md file
    shows as changed in git and reminds you to update them if not.
.DESCRIPTION
    This is a reminder tool, not a hard gate: it never blocks or reverts
    anything, and it exits 0 in every case except a genuinely broken hub.
#>

param(
    [switch]$WorkPerformed
)

$ErrorActionPreference = 'Stop'

$hubRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $hubRoot
$required = @(
    'START-HERE.md', 'project-memory.md', 'task-status.md',
    'issues-log.md', 'session-brief.md', 'change-log.md'
)

$missing = $required | Where-Object { -not (Test-Path (Join-Path $hubRoot $_) -PathType Leaf) }
if ($missing.Count -gt 0) {
    Write-Host "[agent-workflow] BROKEN: missing required file(s): $($missing -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host "=== agent-workflow closeout ===" -ForegroundColor Cyan

if ($WorkPerformed) {
    $changedWorkflowFiles = @()
    try {
        Push-Location $repoRoot
        $status = git status --porcelain -- 'agent-workflow/*.md' 2>$null
        if ($status) {
            $changedWorkflowFiles = $status -split "`n" | Where-Object { $_.Trim() -ne '' }
        }
    } catch {
        # git not available or not a repo; skip silently, this is a reminder tool only
    } finally {
        Pop-Location
    }

    if ($changedWorkflowFiles.Count -eq 0) {
        Write-Host "[REMINDER] -WorkPerformed was passed, but no agent-workflow/*.md file shows as changed." -ForegroundColor Yellow
        Write-Host "If repo state or findings changed this session, update session-brief.md, task-status.md, and issues-log.md now." -ForegroundColor Yellow
    } else {
        Write-Host "Changed workflow files this session:" -ForegroundColor Green
        $changedWorkflowFiles | ForEach-Object { Write-Host "  $_" }
    }
} else {
    Write-Host "(no -WorkPerformed flag; skipping git-diff reminder check)"
}

Write-Host "`n=== Closeout checklist ===" -ForegroundColor Cyan
Write-Host "1. Update session-brief.md (replace the 'Last Session' section, don't append)."
Write-Host "2. Update task-status.md and issues-log.md if state changed."
Write-Host "3. Append one short line to change-log.md if this was a meaningful workflow/repo change."
Write-Host "4. Add to project-memory.md only if a durable, confirmed lesson was found."
