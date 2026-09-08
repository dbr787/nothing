. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'

# Cross-branch cache poisoning under the default (unscoped) registry policy.
# POISON_MODE=save runs on the "attacker" branch; POISON_MODE=restore runs on
# the branch that consumes the cache.
$mode  = if ($env:POISON_MODE) { $env:POISON_MODE } else { 'restore' }
$round = $env:CACHE_POISON_ROUND
Write-Host ("mode={0} round={1} branch={2}" -f $mode, $round, $env:BUILDKITE_BRANCH)

if ($mode -eq 'save') {
  Remove-Item -Recurse -Force 'bk-poison' -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path 'bk-poison' | Out-Null
  Set-Content -LiteralPath 'bk-poison\payload.txt' -Value (
    "planted by branch '$env:BUILDKITE_BRANCH' in build $env:BUILDKITE_BUILD_NUMBER of pipeline $env:BUILDKITE_PIPELINE_SLUG")
  # A build script a consumer might plausibly execute from a cached directory.
  Set-Content -LiteralPath 'bk-poison\postinstall.cmd' -Value '@echo THIS WOULD HAVE EXECUTED FROM A POISONED CACHE'
  $s = Invoke-Cache save @('--name','poison')
  Assert-True ($s.Code -eq 0) 'poison.save' "exit $($s.Code) from branch $env:BUILDKITE_BRANCH"
  Complete-Probe -Context 'cache-poison' -Heading "Cache poisoning: planted from $env:BUILDKITE_BRANCH"
}

Remove-Item -Recurse -Force 'bk-poison' -ErrorAction SilentlyContinue
$r = Invoke-Cache restore @('--name','poison')
Assert-True ($r.Code -eq 0) 'poison.restore.exit0' "exit $($r.Code)"

if (Test-Path 'bk-poison\payload.txt') {
  $who = (Get-Content 'bk-poison\payload.txt') -join ''
  Write-Result 'poison.crossbranch.hit' 'FAIL' "restored on '$env:BUILDKITE_BRANCH' an entry $who"
  if (Test-Path 'bk-poison\postinstall.cmd') {
    Write-Result 'poison.executable.present' 'FAIL' 'a script planted by another branch is now on disk and runnable'
  }
} else {
  Write-Result 'poison.crossbranch.hit' 'PASS' "no entry from another branch was reachable from '$env:BUILDKITE_BRANCH'"
}

Complete-Probe -Context 'cache-poison' -Heading "Cache poisoning: consumed on $env:BUILDKITE_BRANCH"
