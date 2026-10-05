param([string[]]$Configs, [string[]]$Methods, [string[]]$Levels, [int[]]$NPoly, [string]$Tag = "net", [int]$Reps = 1, [switch]$KeepLog)
$sp = Split-Path -Parent $MyInvocation.MyCommand.Path
$rs = "C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe"
$csv = Join-Path $sp "$Tag.csv"
$sum = Join-Path $sp "$Tag-http.csv"
if (-not (Test-Path $sum)) { "config,method,level,npoly,rep,get_requests,range_requests,mb_requested,exit,head_requests,http_404" | Set-Content $sum }
foreach ($rep in 1..$Reps) { foreach ($lv in $Levels) { foreach ($np in $NPoly) { foreach ($cf in $Configs) { foreach ($m in $Methods) {
  $log = Join-Path $sp "curl-$Tag-$cf-$m-$lv-$np.log"
  & $rs (Join-Path $sp "net_worker.R") $cf $m $lv $np $csv 2> $log | Out-Null
  $code = $LASTEXITCODE
  # libcurl verbose: one "> GET"/"[HTTP/2] ... [:method: GET]" per request; ranges as "range: bytes=a-b".
  $txt = Get-Content $log
  $h2 = @($txt | Select-String -Pattern '\[:method: GET\]').Count
  $h1 = @($txt | Select-String -Pattern '^> GET ').Count
  $reqs = [Math]::Max($h2, $h1)
  $pat = if ($h2 -ge $h1 -and $h2 -gt 0) { '\[range: bytes=(\d+)-(\d+)\]' } else { '^> ?[Rr]ange: bytes=(\d+)-(\d+)' }
  $bytes = 0.0; $nr = 0
  foreach ($mm in ($txt | Select-String -Pattern $pat)) { $g = $mm.Matches[0].Groups; $bytes += ([double]$g[2].Value - [double]$g[1].Value + 1); $nr++ }
  $heads = [Math]::Max(@($txt | Select-String -Pattern '\[:method: HEAD\]').Count, @($txt | Select-String -Pattern '^> HEAD ').Count)
  $n404 = @($txt | Select-String -Pattern '^< HTTP/\S+ 404').Count
  "$cf,$m,$lv,$np,$rep,$reqs,$nr,$([Math]::Round($bytes/1MB,2)),$code,$heads,$n404" | Add-Content $sum
  if (-not $KeepLog) { Remove-Item $log -ErrorAction SilentlyContinue }
} } } } }
"--- timings"; Get-Content $csv
"--- http"; Get-Content $sum
