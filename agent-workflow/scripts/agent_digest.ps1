param(
    [ValidateSet("Quick", "Full")]
    [string]$Mode = "Quick",
    [string[]]$Scope = @(),
    [string]$ValidationPlan = "<set validation plan>",
    [string]$ExitCriteria = "<set exit criteria>"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$workflowDir = Split-Path -Parent $scriptDir

$scopeText = "<target files>"
if ($Scope.Count -gt 0) {
    $scopeText = $Scope -join ", "
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

$topPending = "- [ ] none recorded"
$pendingMatch = Select-String -Path (Join-Path $workflowDir "task-status.md") -Pattern '^- \[ \]' | Select-Object -First 1
if ($pendingMatch) {
    $topPending = $pendingMatch.Line.Trim()
}

$topIssue = "none recorded"
$issueId = Get-TopOpenIssueId -Path (Join-Path $workflowDir "issues-log.md")
if ($issueId) {
    $topIssue = $issueId
}

Write-Output ("Mode: " + $Mode)
Write-Output ("Scope: " + $scopeText)
Write-Output ("Top Pending: " + $topPending)
Write-Output ("Top Open Issue: " + $topIssue)
Write-Output ("Validation Plan: " + $ValidationPlan)
Write-Output ("Exit Criteria: " + $ExitCriteria)
