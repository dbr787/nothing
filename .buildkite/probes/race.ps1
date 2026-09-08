. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'

# Three parallel jobs all create the same brand-new cache address at once.
# The docs allow the last commit to win, but no job may fail.
$idx = [int]$env:BUILDKITE_PARALLEL_JOB
Write-Host ("Parallel job {0} of {1}" -f ($idx + 1), $env:BUILDKITE_PARALLEL_JOB_COUNT)

New-Item -ItemType Directory -Force -Path 'bk-race' | Out-Null
Set-Content -LiteralPath 'bk-race\who.txt' -Value ("written by parallel job $idx of build $env:BUILDKITE_BUILD_NUMBER")
1..50 | ForEach-Object {
  Set-Content -LiteralPath ("bk-race\filler-$_.bin") -Value ('x' * 20000)
}

$s = Invoke-Cache save @('--name','race')
Assert-True ($s.Code -eq 0) "race.job$idx.save.exit0" "exit $($s.Code) racing two other jobs to the same new address"

Remove-Item -Recurse -Force 'bk-race'
$r = Invoke-Cache restore @('--name','race')
Assert-True ($r.Code -eq 0) "race.job$idx.restore.exit0" "exit $($r.Code)"
$who = if (Test-Path 'bk-race\who.txt') { (Get-Content 'bk-race\who.txt') -join '' } else { 'nothing restored' }
Write-Result "race.job$idx.winner" 'INFO' $who

Complete-Probe -Context "cache-race-$idx" -Heading "Concurrent first save, parallel job $idx"
