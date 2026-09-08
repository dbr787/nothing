. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'

function New-Blob {
  param([string]$Dir, [int]$Count, [int]$SizeBytes)
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  $rng = [System.Random]::new(42)
  $buf = New-Object byte[] $SizeBytes
  1..$Count | ForEach-Object {
    $rng.NextBytes($buf)
    [System.IO.File]::WriteAllBytes((Join-Path $Dir "chunk-$_.bin"), $buf)
  }
}

Write-Host "--- One large incompressible blob (200 x 1 MB)"
$r = Invoke-Cache restore @('--name','perf_blob')
Assert-True ($r.Code -eq 0) 'perf.blob.restore.exit0' "exit $($r.Code)"
if (Test-Path 'bk-perf-blob') {
  $mb = [math]::Round(((Get-ChildItem -Recurse -File 'bk-perf-blob' | Measure-Object -Property Length -Sum).Sum)/1MB, 0)
  Write-Result 'perf.blob.restore' 'PASS' ("restored {0} MB in {1}s = {2} MB/s" -f $mb, $r.Seconds, [math]::Round($mb / [math]::Max($r.Seconds, 0.01), 1))
} else {
  Write-Result 'perf.blob.restore' 'INFO' "miss in $($r.Seconds)s (expected on the first build)"
  New-Blob -Dir 'bk-perf-blob' -Count 200 -SizeBytes 1048576
}
$s = Invoke-Cache save @('--name','perf_blob')
$mb = [math]::Round(((Get-ChildItem -Recurse -File 'bk-perf-blob' | Measure-Object -Property Length -Sum).Sum)/1MB, 0)
Assert-True ($s.Code -eq 0) 'perf.blob.save.exit0' ("exit $($s.Code): {0} MB in {1}s = {2} MB/s" -f $mb, $s.Seconds, [math]::Round($mb / [math]::Max($s.Seconds, 0.01), 1))

Write-Host "--- Many tiny files (3000 x 4 KB)"
$r = Invoke-Cache restore @('--name','perf_many')
Assert-True ($r.Code -eq 0) 'perf.many.restore.exit0' "exit $($r.Code)"
if (Test-Path 'bk-perf-many') {
  $n = (Get-ChildItem -Recurse -File 'bk-perf-many' | Measure-Object).Count
  Write-Result 'perf.many.restore' 'PASS' ("restored {0} files in {1}s = {2} files/s" -f $n, $r.Seconds, [math]::Round($n / [math]::Max($r.Seconds, 0.01), 0))
} else {
  Write-Result 'perf.many.restore' 'INFO' "miss in $($r.Seconds)s (expected on the first build)"
  New-Blob -Dir 'bk-perf-many' -Count 3000 -SizeBytes 4096
}
$s = Invoke-Cache save @('--name','perf_many')
$n = (Get-ChildItem -Recurse -File 'bk-perf-many' | Measure-Object).Count
Assert-True ($s.Code -eq 0) 'perf.many.save.exit0' ("exit $($s.Code): {0} files in {1}s = {2} files/s" -f $n, $s.Seconds, [math]::Round($n / [math]::Max($s.Seconds, 0.01), 0))

Complete-Probe -Context 'cache-perf' -Heading 'Cache throughput on Windows'
