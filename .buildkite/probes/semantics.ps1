. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'

Write-Host "--- A cache that is never saved must miss cleanly"
$r = Invoke-Cache restore @('--name','neversaved')
Assert-True ($r.Code -eq 0) 'miss.exit0.powershell' "exit $($r.Code) restoring a key that was never saved"
Assert-True (-not (Test-Path 'bk-neversaved')) 'miss.leaves.target.alone' 'a miss must not create the target'

Write-Host "--- The same miss through cmd.exe, where exit codes travel differently"
cmd /c "buildkite-agent cache restore --name neversaved & exit /b %ERRORLEVEL%" 2>&1 | ForEach-Object { Write-Host "  $_" }
Assert-True ($LASTEXITCODE -eq 0) 'miss.exit0.cmd' "cmd.exe saw exit $LASTEXITCODE"

Write-Host "--- Fallback restore (token=$env:CACHE_FALLBACK_TOKEN)"
$r = Invoke-Cache restore @('--name','fallback')
Assert-True ($r.Code -eq 0) 'fallback.restore.exit0' "exit $($r.Code)"
$hit = Get-Marker 'bk-fallback'
if ($hit) {
  Write-Result 'fallback.hit' 'PASS' "restored with token=$($env:CACHE_FALLBACK_TOKEN): $hit"
} else {
  Write-Result 'fallback.hit' 'INFO' "miss with token=$($env:CACHE_FALLBACK_TOKEN) (expected on the first build)"
}
New-Marker 'bk-fallback' | Out-Null
$s = Invoke-Cache save @('--name','fallback')
Assert-True ($s.Code -eq 0) 'fallback.save.exit0' "exit $($s.Code)"

Write-Host "--- Three caches in one save invocation (default concurrency 2)"
foreach ($n in 'a','b','c') {
  $r = Invoke-Cache restore @('--name',"conc_$n")
  Assert-True ($r.Code -eq 0) "conc.$n.restore.exit0" "exit $($r.Code)"
  $h = Get-Marker "bk-conc-$n"
  Write-Result "conc.$n.hit" $(if ($h) {'PASS'} else {'INFO'}) $(if ($h) { $h } else { 'miss (expected on the first build)' })
  New-Marker "bk-conc-$n" | Out-Null
}
$s = Invoke-Cache save @('--name','conc_a','--name','conc_b','--name','conc_c')
Assert-True ($s.Code -eq 0) 'conc.save.exit0' ("exit $($s.Code) in {0}s" -f $s.Seconds)

Write-Host "--- Rejecting an invalid config: two targets differing only by case"
$r = Invoke-Cache save @('--cache-config-file','.buildkite\cache-casedup.yml','--name','casedup')
if ($r.Code -ne 0) {
  Write-Result 'casedup.rejected' 'PASS' "exit $($r.Code) - overlapping case-variant targets rejected"
} else {
  Write-Result 'casedup.rejected' 'FAIL' 'exit 0 - two targets that are the same directory on Windows were accepted'
}

Complete-Probe -Context 'cache-semantics' -Heading 'Miss, fallback, concurrency and config validation'
