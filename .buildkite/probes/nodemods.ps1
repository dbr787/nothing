. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'

$r = Invoke-Cache restore @('--name','nodemods')
Assert-True ($r.Code -eq 0) 'nodemods.restore.exit0' "exit $($r.Code)"

$restored = Test-Path 'app\node_modules'
if ($restored) {
  $count = (Get-ChildItem -Recurse -Force -File 'app\node_modules' | Measure-Object).Count
  Write-Result 'nodemods.hit' 'PASS' "$count files restored"
} else {
  Write-Result 'nodemods.hit' 'INFO' 'miss (expected on the first build)'
}

Push-Location app
$sw = [Diagnostics.Stopwatch]::StartNew()
& npm install --no-audit --no-fund --loglevel=error 2>&1 | ForEach-Object { Write-Host "  $_" }
$npmCode = $LASTEXITCODE
$sw.Stop()
Pop-Location
Assert-True ($npmCode -eq 0) 'nodemods.npm.install' ("npm install exit $npmCode in {0}s (cache {1})" -f [math]::Round($sw.Elapsed.TotalSeconds,1), $(if ($restored) {'warm'} else {'cold'}))

$fileCount = (Get-ChildItem -Recurse -Force -File 'app\node_modules' | Measure-Object).Count
$bytes = (Get-ChildItem -Recurse -Force -File 'app\node_modules' | Measure-Object -Property Length -Sum).Sum
Write-Result 'nodemods.tree' 'INFO' ("{0} files, {1} MB" -f $fileCount, [math]::Round($bytes/1MB,1))

$s = Invoke-Cache save @('--name','nodemods')
Assert-True ($s.Code -eq 0) 'nodemods.save.exit0' ("exit $($s.Code) in {0}s" -f $s.Seconds)

Complete-Probe -Context 'cache-nodemods' -Heading 'Real npm tree (deep nesting, .bin shims)'
