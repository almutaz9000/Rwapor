<#
.SYNOPSIS
    Launch the Rwapor Control Room Streamlit dashboard.
.DESCRIPTION
    Installs agent-workflow/dashboard/requirements.txt (skip with -NoInstall
    once it's already set up) and starts `streamlit run` against
    agent-workflow/dashboard/app.py. The dashboard reads agents-board.json
    live -- leave this running in a terminal and it reflects every
    board_claim.ps1 update from any model without needing a restart.
.PARAMETER NoInstall
    Skip the pip install step (faster relaunch once dependencies are present).
.PARAMETER Port
    Port to serve on. Defaults to 8511 (8501 is used by the package Shiny app).
#>

param(
    [switch]$NoInstall,
    [int]$Port = 8511
)

$ErrorActionPreference = 'Stop'

$hubRoot = Split-Path -Parent $PSScriptRoot
$dashboardDir = Join-Path $hubRoot 'dashboard'
$appPath = Join-Path $dashboardDir 'app.py'
$reqPath = Join-Path $dashboardDir 'requirements.txt'

if (-not (Test-Path $appPath -PathType Leaf)) {
    Write-Host "[run_dashboard] BROKEN: app.py not found at $appPath" -ForegroundColor Red
    exit 1
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Host "[run_dashboard] No 'python' on PATH. Install Python 3.10+ and re-run." -ForegroundColor Red
    exit 1
}

if (-not $NoInstall) {
    Write-Host "[run_dashboard] Installing dashboard dependencies..." -ForegroundColor Cyan
    & python -m pip install --quiet -r $reqPath
}

Write-Host "[run_dashboard] Starting Streamlit -- agents-board.json is read live, so any board_claim.ps1 update from any model shows up on your next browser refresh." -ForegroundColor Green

$streamlitArgs = @('-m', 'streamlit', 'run', $appPath)
if ($Port) {
    $streamlitArgs += @('--server.port', $Port)
}
& python @streamlitArgs
