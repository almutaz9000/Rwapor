param(
    [switch]$WorkPerformed
)

if (-not $WorkPerformed) {
    Write-Output "No closeout enforcement requested. Use -WorkPerformed after repo changes or validated findings."
    exit 0
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$workflowDir = Split-Path -Parent $scriptDir

$mustExist = @(
    "session-brief.md",
    "task-status.md",
    "issues-log.md",
    "change-log.md",
    "project-memory.md"
)

$missing = @()
foreach ($name in $mustExist) {
    $path = Join-Path $workflowDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        $missing += $name
    }
}

if ($missing.Count -gt 0) {
    Write-Error ("Missing workflow files: " + ($missing -join ", "))
    exit 1
}

$today = (Get-Date).Date
$requiredToday = @("session-brief.md", "task-status.md", "issues-log.md", "change-log.md")
$stale = @()

Write-Output "Closeout check:"
foreach ($name in $requiredToday) {
    $path = Join-Path $workflowDir $name
    $item = Get-Item -LiteralPath $path
    $status = "OK"
    if ($item.LastWriteTime.Date -lt $today) {
        $status = "STALE"
        $stale += $name
    }
    Write-Output ("- {0}: {1} ({2})" -f $name, $status, $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm"))
}

$memoryItem = Get-Item -LiteralPath (Join-Path $workflowDir "project-memory.md")
Write-Output ("- project-memory.md: review if durable lessons changed ({0})" -f $memoryItem.LastWriteTime.ToString("yyyy-MM-dd HH:mm"))

if ($stale.Count -gt 0) {
    Write-Error ("Closeout incomplete. Update these files today: " + ($stale -join ", "))
    exit 1
}

Write-Output "Closeout check passed."
