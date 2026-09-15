<#
.SYNOPSIS
    Prints a minimal startup digest from the agent-workflow hub.
.DESCRIPTION
    Shorter than agent_preflight.ps1's output — just the raw last-session
    summary, active/pending task lines, and open-issue headings, with no
    file-existence checks or formatting chrome. Useful when an agent wants
    the digest without the full preflight report. Read-only.
#>

$ErrorActionPreference = 'SilentlyContinue'

$hubRoot = Split-Path -Parent $PSScriptRoot

$sessionBrief = Get-Content (Join-Path $hubRoot 'session-brief.md') -Raw
if ($sessionBrief) {
    $m = [regex]::Match($sessionBrief, '(?s)## Last Session.*?(?=\n## |\z)')
    if ($m.Success) { Write-Host $m.Value.Trim() }
}

Write-Host ""
Select-String -Path (Join-Path $hubRoot 'task-status.md') -Pattern '^(##|- )' |
    ForEach-Object { Write-Host $_.Line }

Write-Host ""
Select-String -Path (Join-Path $hubRoot 'issues-log.md') -Pattern '^(## |### )' |
    ForEach-Object { Write-Host $_.Line }
