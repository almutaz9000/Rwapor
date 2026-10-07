<#
.SYNOPSIS
    Hand a Claude-written plan to Codex, send a follow-up fix round, or read job state.
.DESCRIPTION
    Thin wrapper around the Codex Claude Code plugin's companion script
    (openai-codex/codex). It builds the standard short delegation prompt so the
    plan text never has to be pasted into a prompt, and runs Codex with write
    access in this repo. Output is Codex's final report (rwapor-plan-executor
    format). Run it as a background command so the caller is notified when
    Codex finishes.
.PARAMETER Plan
    Path to the plan file, e.g. docs/superpowers/plans/2026-09-24-ti-01.md.
.PARAMETER Fix
    Follow-up round: the exact list of problems for Codex to fix. Resumes the
    last Codex thread (same context) instead of starting a new one.
.PARAMETER Effort
    Optional Codex reasoning effort: none, minimal, low, medium, high, xhigh.
.PARAMETER Model
    Optional Codex model name (or 'spark').
.PARAMETER Status
    Show Codex jobs for this repo instead of starting one.
.PARAMETER Result
    Show the stored final output of a finished job (optionally pass -JobId).
.EXAMPLE
    .\codex_task.ps1 -Plan docs/superpowers/plans/2026-09-24-ti-01.md
.EXAMPLE
    .\codex_task.ps1 -Plan docs/superpowers/plans/2026-09-24-ti-01.md -Fix "1. Add a test for NA scale. 2. Revert the rename in R/utils.R."
.EXAMPLE
    .\codex_task.ps1 -Status
#>

param(
    [string]$Plan,
    [string]$Fix,
    [ValidateSet('none', 'minimal', 'low', 'medium', 'high', 'xhigh')]
    [string]$Effort,
    [string]$Model,
    [switch]$Status,
    [switch]$Result,
    [string]$JobId
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$pluginDir = Join-Path $HOME '.claude\plugins\cache\openai-codex\codex'
$companion = Get-ChildItem -Path $pluginDir -Directory -ErrorAction SilentlyContinue |
    Sort-Object { [version]($_.Name -replace '[^0-9.]', '') } -Descending |
    ForEach-Object { Join-Path $_.FullName 'scripts\codex-companion.mjs' } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1
if (-not $companion) {
    throw "Codex companion not found under $pluginDir. Install the openai-codex plugin and run /codex:setup."
}

Push-Location $repoRoot
try {
    if ($Status) { & node $companion status --all; exit $LASTEXITCODE }
    if ($Result) {
        if ($JobId) { & node $companion result $JobId } else { & node $companion result }
        exit $LASTEXITCODE
    }

    if (-not $Plan) { throw 'Pass -Plan <path to plan file> (or -Status / -Result).' }
    $planRel = $Plan -replace '\\', '/'
    if (-not (Test-Path (Join-Path $repoRoot $planRel))) { throw "Plan file not found: $planRel" }

    $taskArgs = @('task', '--write')
    if ($Fix) {
        $taskArgs += '--resume-last'
        $prompt = "Follow-up round for the plan in $planRel. Apply only these fixes, " +
            "rerun the plan's validation commands, and reply in the rwapor-plan-executor " +
            "report format.`n`n$Fix"
    } else {
        $prompt = "Implement the plan in $planRel exactly. Use the rwapor-plan-executor " +
            "and rwapor-r-dev skills. Finish with the rwapor-plan-executor report format. " +
            "Do not commit."
    }
    if ($Effort) { $taskArgs += @('--effort', $Effort) }
    if ($Model) { $taskArgs += @('--model', $Model) }
    $taskArgs += $prompt

    & node $companion @taskArgs
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
