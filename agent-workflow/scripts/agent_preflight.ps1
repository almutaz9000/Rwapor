<#
.SYNOPSIS
    Lightweight session-start check for the agent-workflow hub.
.DESCRIPTION
    Verifies the required agent-workflow files exist, then prints a short
    digest (last session summary, active tasks, open issues) so an agent can
    orient itself without reading every file in full. Read-only; makes no
    changes. Exits 1 only if the hub itself is missing or incomplete.
#>

$ErrorActionPreference = 'Stop'

$hubRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'START-HERE.md',
    'project-memory.md',
    'task-status.md',
    'issues-log.md',
    'session-brief.md',
    'change-log.md'
)

$missing = @()
foreach ($f in $required) {
    $path = Join-Path $hubRoot $f
    if (-not (Test-Path $path -PathType Leaf)) {
        $missing += $f
    }
}

if ($missing.Count -gt 0) {
    Write-Host "[agent-workflow] BROKEN: missing required file(s): $($missing -join ', ')" -ForegroundColor Red
    Write-Host "The agent-workflow hub is incomplete. See docs/superpowers/specs/2026-05-11-agent-workflow-design.md." -ForegroundColor Red
    exit 1
}

Write-Host "=== agent-workflow preflight ===" -ForegroundColor Cyan

$sessionBrief = Join-Path $hubRoot 'session-brief.md'
Write-Host "`n--- session-brief.md ---" -ForegroundColor Yellow
try {
    $content = Get-Content -Path $sessionBrief -Raw
    $match = [regex]::Match($content, '(?s)## Last Session.*?(?=\n## |\z)')
    if ($match.Success) {
        Write-Host $match.Value.Trim()
    } else {
        Write-Host "(no 'Last Session' section found)"
    }
} catch {
    Write-Host "(could not read session-brief.md: $($_.Exception.Message))"
}

$taskStatus = Join-Path $hubRoot 'task-status.md'
Write-Host "`n--- task-status.md: Active / Pending ---" -ForegroundColor Yellow
try {
    Select-String -Path $taskStatus -Pattern '^- ' | Select-Object -First 10 | ForEach-Object { Write-Host $_.Line }
} catch {
    Write-Host "(could not read task-status.md)"
}

$issuesLog = Join-Path $hubRoot 'issues-log.md'
Write-Host "`n--- issues-log.md: Open ---" -ForegroundColor Yellow
try {
    $content = Get-Content -Path $issuesLog -Raw
    $match = [regex]::Match($content, '(?s)## Open.*?(?=\n## |\z)')
    if ($match.Success) {
        Write-Host $match.Value.Trim()
    } else {
        Write-Host "(no 'Open' section found)"
    }
} catch {
    Write-Host "(could not read issues-log.md)"
}

Write-Host "`n=== Reminder ===" -ForegroundColor Cyan
Write-Host "Before editing, produce the digest required by START-HERE.md: Mode, Scope, Relevant open task, Relevant open issue, Validation plan, Exit criteria."
