. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'

# Enforcement test for a scoped cache registry policy.
# SCOPED_MODE=save plants an entry; SCOPED_MODE=restore reports what came back.
# The cache key is branch- and pipeline-agnostic, so any isolation is the policy.
$registry = if ($env:SCOPED_REGISTRY) { $env:SCOPED_REGISTRY } else { 'scoped-test' }
$mode     = if ($env:SCOPED_MODE) { $env:SCOPED_MODE } else { 'restore' }
$expect   = $env:SCOPED_EXPECT
Write-Host ("registry={0} mode={1} round={2} pipeline={3} branch={4} expect={5}" -f `
  $registry, $mode, $env:SCOPED_ROUND, $env:BUILDKITE_PIPELINE_SLUG, $env:BUILDKITE_BRANCH, $expect)

if ($mode -eq 'save') {
  Remove-Item -Recurse -Force 'bk-scoped' -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path 'bk-scoped' | Out-Null
  Set-Content -LiteralPath 'bk-scoped\origin.txt' -Value (
    "saved by pipeline '$env:BUILDKITE_PIPELINE_SLUG' branch '$env:BUILDKITE_BRANCH' build $env:BUILDKITE_BUILD_NUMBER")
  $s = Invoke-Cache save @('--registry',$registry,'--name','scoped')
  Assert-True ($s.Code -eq 0) 'scoped.save.allowed' "exit $($s.Code) saving from branch '$env:BUILDKITE_BRANCH'"
  Complete-Probe -Context "scoped-save-$env:BUILDKITE_BRANCH" -Heading "Scoped policy: save from $env:BUILDKITE_BRANCH"
}

Remove-Item -Recurse -Force 'bk-scoped' -ErrorAction SilentlyContinue
$r = Invoke-Cache restore @('--registry',$registry,'--name','scoped')
Assert-True ($r.Code -eq 0) 'scoped.restore.exit0' "exit $($r.Code)"

$origin = if (Test-Path 'bk-scoped\origin.txt') { (Get-Content 'bk-scoped\origin.txt') -join '' } else { $null }
$got = if ($origin) { 'hit' } else { 'miss' }
Write-Host ("OUTCOME: {0}" -f $got)

if ($expect) {
  $status = if ($got -eq $expect) { 'PASS' } else { 'FAIL' }
  Write-Result 'scoped.policy.enforced' $status "expected $expect, got $got$(if ($origin) { " - $origin" })"
} else {
  Write-Result 'scoped.policy.outcome' 'INFO' "$got$(if ($origin) { " - $origin" })"
}

Complete-Probe -Context "scoped-$env:BUILDKITE_PIPELINE_SLUG-$env:BUILDKITE_BRANCH" -Heading "Scoped policy on $env:BUILDKITE_PIPELINE_SLUG / $env:BUILDKITE_BRANCH"
