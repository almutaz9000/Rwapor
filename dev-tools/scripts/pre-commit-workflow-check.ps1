# pre-commit-workflow-check.ps1
# Script to validate that no active tasks are left in task-status.md and that R package tests pass.

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Running Workflow and Test Validation Check" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# 1. Check for active tasks in agent-workflow/task-status.md
# Relative path from dev-tools/scripts/ to agent-workflow/task-status.md is ../../agent-workflow/task-status.md
$taskStatusPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\agent-workflow\task-status.md"))
if (Test-Path $taskStatusPath) {
    Write-Host "Checking task status in agent-workflow/task-status.md..." -ForegroundColor Yellow
    $content = Get-Content $taskStatusPath -Raw
    # Search for active tasks indicated by - [/] or * [/]
    if ($content -match '-\s+\[\/\]') {
        Write-Host "ERROR: You have active tasks marked with '[- [/]]' in agent-workflow/task-status.md." -ForegroundColor Red
        Write-Host "Please complete the tasks or change their status before committing." -ForegroundColor Red
        exit 1
    }
    Write-Host "No active tasks found. Valid." -ForegroundColor Green
} else {
    Write-Host "Warning: agent-workflow/task-status.md not found, skipping check." -ForegroundColor Yellow
}

# 2. Find Rscript executable
function Find-Rscript {
    $paths = @()
    if (Test-Path "C:\Program Files\R") {
        $paths += Get-ChildItem "C:\Program Files\R\R-*\bin\Rscript.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    }
    if (Test-Path "$env:USERPROFILE\AppData\Local\Programs\R") {
        $paths += Get-ChildItem "$env:USERPROFILE\AppData\Local\Programs\R\R-*\bin\Rscript.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    }
    if ($paths.Count -eq 0) {
        $cmd = Get-Command Rscript -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        return $null
    }
    # Sort descending so the highest version comes first
    $sorted = $paths | Sort-Object -Descending
    return $sorted[0]
}

$rscript = Find-Rscript
if (-not $rscript) {
    Write-Host "Warning: Rscript.exe not found on the system. Skipping test validations." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found Rscript: $rscript" -ForegroundColor Gray
Write-Host "Running R Package tests..." -ForegroundColor Yellow

$rExpression = "res <- devtools::test(pkg = '.', reporter = 'summary'); df <- as.data.frame(res); failures <- sum(df`$failed) + sum(df`$error); if (failures > 0) quit(status = 1) else quit(status = 0)"

& $rscript -e $rExpression
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Unit tests failed or errored out. Commit blocked." -ForegroundColor Red
    exit 1
}

Write-Host "All checks passed successfully!" -ForegroundColor Green
exit 0
