param(
    [string]$Task = ""
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$workflowDir = Split-Path -Parent $scriptDir

$requiredFiles = @(
    "START-HERE.md",
    "project-memory.md",
    "task-status.md",
    "issues-log.md",
    "session-brief.md",
    "change-log.md"
)

$missing = @()
foreach ($name in $requiredFiles) {
    $path = Join-Path $workflowDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        $missing += $name
    }
}

if ($missing.Count -gt 0) {
    Write-Error ("Missing workflow files: " + ($missing -join ", "))
    exit 1
}

function Get-TopOpenIssueId {
    param(
        [string]$Path
    )

    $inOpenSection = $false
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^## ') {
            if ($inOpenSection) {
                break
            }
            $inOpenSection = ($line.Trim() -eq '## Open Issues')
            continue
        }
        if ($inOpenSection -and $line -match 'ISS-\d{8}-\d{3}') {
            return $Matches[0]
        }
    }

    return $null
}

$taskMatch = Select-String -Path (Join-Path $workflowDir "task-status.md") -Pattern '^- \[ \]' | Select-Object -First 1
$topIssueId = Get-TopOpenIssueId -Path (Join-Path $workflowDir "issues-log.md")

Write-Output "Agent workflow preflight OK."
if ($Task) {
    Write-Output ("Task: " + $Task)
}
Write-Output "Read order:"
Write-Output "1. agent-workflow/session-brief.md"
Write-Output "2. agent-workflow/task-status.md"
Write-Output "3. agent-workflow/issues-log.md"
Write-Output "4. agent-workflow/project-memory.md if relevant"

if ($taskMatch) {
    Write-Output ("Top pending: " + $taskMatch.Line.Trim())
}

if ($topIssueId) {
    Write-Output ("Top issue: " + $topIssueId)
} else {
    Write-Output "Top issue: none recorded"
}

Write-Output "Next: run .\agent-workflow\scripts\agent_digest.ps1 -Mode Quick -Scope <files>"
