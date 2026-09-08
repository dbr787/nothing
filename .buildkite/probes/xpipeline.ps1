. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'

# Decisive cross-pipeline test. Both the `poison` and `probe` caches were saved
# by OTHER pipelines in the same cluster, at addresses this pipeline resolves
# identically. If the default registry policy is unscoped, these restores hit.
# If saves are scoped by pipeline, they miss.
Write-Host ("pipeline={0} branch={1} round={2}" -f $env:BUILDKITE_PIPELINE_SLUG, $env:BUILDKITE_BRANCH, $env:CACHE_POISON_ROUND)

Remove-Item -Recurse -Force 'bk-poison' -ErrorAction SilentlyContinue
$r = Invoke-Cache restore @('--name','poison')
Assert-True ($r.Code -eq 0) 'xpipeline.poison.exit0' "exit $($r.Code)"
if (Test-Path 'bk-poison\payload.txt') {
  Write-Result 'xpipeline.poison.hit' 'FAIL' ("restored in pipeline '$env:BUILDKITE_PIPELINE_SLUG' an entry " + ((Get-Content 'bk-poison\payload.txt') -join ''))
} else {
  Write-Result 'xpipeline.poison.hit' 'PASS' "miss - an entry saved by another pipeline was not reachable from '$env:BUILDKITE_PIPELINE_SLUG'"
}

Remove-Item -Recurse -Force 'bk-cache-probe' -ErrorAction SilentlyContinue
$r = Invoke-Cache restore @('--name','probe')
Assert-True ($r.Code -eq 0) 'xpipeline.probe.exit0' "exit $($r.Code)"
$hit = Get-Marker 'bk-cache-probe'
Write-Result 'xpipeline.probe.hit' $(if ($hit) {'FAIL'} else {'PASS'}) $(if ($hit) { "restored the `nothing` pipeline's entry: $hit" } else { 'miss - the other pipeline''s probe entry was not reachable' })

Complete-Probe -Context 'cache-xpipeline' -Heading 'Cross-pipeline reach under the default policy'
