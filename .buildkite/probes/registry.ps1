. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'

Write-Host "--- What the agent exposes to a job"
& buildkite-agent cache --help 2>&1 | ForEach-Object { Write-Host "  $_" }

# A job should be able to save and restore, and nothing else. There is no
# subcommand to list or inspect other entries.
$help = (& buildkite-agent cache --help 2>&1 | Out-String)
Assert-True ($help -notmatch '(?m)^\s+(list|ls|inspect|delete|rm)\b') 'registry.no.enumeration' 'no list/inspect/delete subcommand is exposed to a job'

Write-Host "--- Registry selection"
$r = Invoke-Cache restore @('--name','neversaved','--registry','~')
Assert-True ($r.Code -eq 0) 'registry.tilde' "exit $($r.Code) selecting the cluster default with ~"

$r = Invoke-Cache restore @('--name','neversaved','--registry','default')
Write-Result 'registry.slug.default' $(if ($r.Code -eq 0) {'PASS'} else {'INFO'}) "exit $($r.Code) selecting slug 'default'"

$r = Invoke-Cache restore @('--name','neversaved','--registry','no-such-registry-here')
Write-Result 'registry.unknown.slug' $(if ($r.Code -ne 0) {'PASS'} else {'FAIL'}) "exit $($r.Code) selecting a registry that does not exist"

$env:BUILDKITE_AGENT_CACHE_REGISTRY = '~'
$r = Invoke-Cache restore @('--name','neversaved')
Assert-True ($r.Code -eq 0) 'registry.env.var' "exit $($r.Code) selecting the registry via BUILDKITE_AGENT_CACHE_REGISTRY"
Remove-Item Env:\BUILDKITE_AGENT_CACHE_REGISTRY

Write-Host "--- Cross-pipeline restore under the default policy"
# The `probe` cache is defined identically here and in the `nothing` pipeline,
# which saved an entry at this address. Both pipelines are in the same cluster.
# Under the permissive default policy this restore should hit an entry that a
# different pipeline created.
Remove-Item -Recurse -Force 'bk-cache-probe' -ErrorAction SilentlyContinue
$r = Invoke-Cache restore @('--name','probe')
Assert-True ($r.Code -eq 0) 'xpipeline.restore.exit0' "exit $($r.Code)"
$hit = Get-Marker 'bk-cache-probe'
if ($hit) {
  Write-Result 'xpipeline.hit' 'PASS' "restored an entry saved by another pipeline: $hit"
} else {
  Write-Result 'xpipeline.hit' 'INFO' 'miss - no entry from the other pipeline was reachable'
}

Complete-Probe -Context 'cache-registry' -Heading 'Registry selection and cross-pipeline reach'
