<#
.SYNOPSIS
    Claim, update, or release a task in the shared agents-board.json.
.DESCRIPTION
    Convenience helper so any model can update agents-board.json correctly
    without hand-editing JSON. Read-modify-write: loads the file, updates the
    one matching task (by -Id), stamps -Model/-Status/-Notes, and rewrites the
    file with stable key order. Also bumps the top-level "updated_utc".
.PARAMETER Id
    The task id to update (must already exist in agents-board.json's "tasks").
.PARAMETER Model
    Your model slug: claude, codex, gemini, hermes, antigravity, warp, qwen,
    copilot, cursor, cline, goose, human, or any other value -- it is added to
    "known_models" automatically if not already listed.
.PARAMETER Status
    One of: pending, active, blocked, done.
.PARAMETER Notes
    Optional short status note (what changed, why blocked, etc.).
.PARAMETER List
    Print all tasks (id, status, model, title) instead of updating anything.
.EXAMPLE
    .\board_claim.ps1 -Id 1.5 -Model claude -Status active -Notes "starting L3 UI wiring"
.EXAMPLE
    .\board_claim.ps1 -Id 1.5 -Model claude -Status done -Notes "Shiny L3 selector wired, 0 fail / 12 passed"
.EXAMPLE
    .\board_claim.ps1 -List
#>

param(
    [string]$Id,
    [string]$Model,
    [ValidateSet('pending', 'active', 'blocked', 'done')]
    [string]$Status,
    [string]$Notes,
    [switch]$List
)

$ErrorActionPreference = 'Stop'

$hubRoot = Split-Path -Parent $PSScriptRoot
$boardPath = Join-Path $hubRoot 'agents-board.json'

if (-not (Test-Path $boardPath -PathType Leaf)) {
    Write-Host "[board_claim] BROKEN: agents-board.json not found at $boardPath" -ForegroundColor Red
    exit 1
}

# ConvertFrom-Json (Windows PowerShell 5.1 / PowerShell 7 both support -Depth on ConvertTo-Json)
$board = Get-Content -Path $boardPath -Raw | ConvertFrom-Json

if ($List) {
    Write-Host "=== agents-board.json tasks ===" -ForegroundColor Cyan
    $board.tasks | ForEach-Object {
        $modelStr = if ($_.model) { $_.model } else { "unassigned" }
        Write-Host ("[{0,-8}] {1,-22} {2,-10} {3}" -f $modelStr, $_.id, $_.status, $_.title)
    }
    exit 0
}

if (-not $Id) {
    Write-Host "[board_claim] -Id is required (or pass -List). See -? for examples." -ForegroundColor Red
    exit 1
}

$task = $board.tasks | Where-Object { $_.id -eq $Id }
if (-not $task) {
    Write-Host "[board_claim] No task with id '$Id' in agents-board.json. Run -List to see valid ids." -ForegroundColor Red
    exit 1
}

$nowUtc = (Get-Date).ToUniversalTime()
$nowIso = $nowUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
$today = $nowUtc.ToString("yyyy-MM-dd")

if ($Model) {
    $task.model = $Model
    $task.attribution = "recorded"
    if ($board.known_models -notcontains $Model) {
        $board.known_models = @($board.known_models) + $Model
    }
    if (-not $task.claimed_utc) {
        $task.claimed_utc = $nowIso
    }
}
if ($Status) {
    $task.status = $Status
}
if ($PSBoundParameters.ContainsKey('Notes')) {
    $task.notes = $Notes
}
$task.updated_utc = $today
$board.updated_utc = $nowIso

$board | ConvertTo-Json -Depth 10 | Set-Content -Path $boardPath -Encoding utf8

Write-Host "[board_claim] Updated '$Id': status=$($task.status) model=$($task.model)" -ForegroundColor Green
Write-Host "Remember: mirror this into task-status.md (and session-brief.md / issues-log.md if relevant) -- agents-board.json is not a replacement for them." -ForegroundColor Yellow
