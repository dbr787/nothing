# Shared helpers for the Buildkite Cache Windows probes.
# Every probe prints machine-readable lines so the results can be collected
# from the logs:  RESULT: <test> | <PASS|FAIL|INFO> | <detail>

$script:Failures = 0
$script:Rows = New-Object System.Collections.Generic.List[string]

function Write-Result {
  param([string]$Test, [string]$Status, [string]$Detail)
  Write-Host ("RESULT: {0} | {1} | {2}" -f $Test, $Status, $Detail)
  $script:Rows.Add(('| {0} | {1} | {2} |' -f $Test, $Status, ($Detail -replace '\|', '/')))
  if ($Status -eq 'FAIL') { $script:Failures++ }
}

function Assert-True {
  param([bool]$Condition, [string]$Test, [string]$Detail)
  if ($Condition) { Write-Result $Test 'PASS' $Detail } else { Write-Result $Test 'FAIL' $Detail }
}

# Runs a buildkite-agent cache subcommand and returns the exit code, echoing
# the output. Never throws: the caller decides what a non-zero code means.
function Invoke-Cache {
  param([string]$Action, [string[]]$CacheArgs)
  $all = @('cache', $Action) + $CacheArgs
  Write-Host ("> buildkite-agent " + ($all -join ' '))
  $sw = [Diagnostics.Stopwatch]::StartNew()
  & buildkite-agent @all 2>&1 | ForEach-Object { Write-Host "  $_" }
  $code = $LASTEXITCODE
  $sw.Stop()
  Write-Host ("  exit {0} in {1}s" -f $code, [math]::Round($sw.Elapsed.TotalSeconds, 2))
  return [pscustomobject]@{ Code = $code; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 2) }
}

function New-Marker {
  param([string]$Dir, [string]$Name = 'marker.txt')
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  $p = Join-Path $Dir $Name
  Add-Content -Path $p -Value ('build ' + $env:BUILDKITE_BUILD_NUMBER + ' at ' + (Get-Date -Format o))
  return $p
}

function Get-Marker {
  param([string]$Dir, [string]$Name = 'marker.txt')
  $p = Join-Path $Dir $Name
  if (Test-Path -LiteralPath $p) { return ((Get-Content -LiteralPath $p) -join '; ') }
  return $null
}

function Publish-Annotation {
  param([string]$Context, [string]$Heading)
  $style = if ($script:Failures -gt 0) { 'error' } else { 'success' }
  $body = @("#### $Heading", '', '| Test | Status | Detail |', '| --- | --- | --- |') + $script:Rows
  ($body -join [char]10) | buildkite-agent annotate --style $style --context $Context
  $body | Write-Host
}

function Complete-Probe {
  param([string]$Context, [string]$Heading)
  Publish-Annotation -Context $Context -Heading $Heading
  Write-Host ("SUMMARY: {0} failures" -f $script:Failures)
  if ($script:Failures -gt 0) { exit 1 } else { exit 0 }
}
