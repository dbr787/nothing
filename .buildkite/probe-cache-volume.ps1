# Probes whether hosted-agent cache volumes attach on Windows.
# The step declares `cache: cache-probe`, so the agent should link .\cache-probe to the volume.
$ErrorActionPreference = 'Continue'
$rows = New-Object System.Collections.Generic.List[string]
function Row($name, $value) { $rows.Add(('| {0} | {1} |' -f $name, $value)) }

Write-Host '--- Filesystem drives'
Get-PSDrive -PSProvider FileSystem | Format-Table Name, Used, Free, Root -AutoSize | Out-String | Write-Host

Write-Host '--- Cache-related environment'
Get-ChildItem Env: | Where-Object { $_.Name -match 'CACHE|MIRROR|VOLUME' } | Format-Table -AutoSize | Out-String | Write-Host

Write-Host '--- Known mount points'
foreach ($p in 'C:\cache\bkcache', 'D:\cache\bkcache', 'C:\cache', 'D:\cache', 'K:\gitmirror') {
  $exists = Test-Path $p
  Write-Host ('{0} exists: {1}' -f $p, $exists)
  Row $p $exists
}

Write-Host '--- Volume contents from previous builds'
$marker = 'cache-probe\marker.txt'
if (Test-Path $marker) {
  $previous = (Get-Content $marker) -join '; '
  Write-Host ('Marker found: ' + $previous)
  Row 'Volume hit' $previous
} else {
  Write-Host 'No marker from a previous build'
  Row 'Volume hit' 'miss, first build or volume not attached'
}

New-Item -ItemType Directory -Force -Path 'cache-probe' | Out-Null
Add-Content -Path $marker -Value ('build ' + $env:BUILDKITE_BUILD_NUMBER + ' at ' + (Get-Date -Format o))
Write-Host ('Wrote marker for build ' + $env:BUILDKITE_BUILD_NUMBER)

$link = Get-Item 'cache-probe' -Force
Row 'cache-probe link type' $(if ($link.LinkType) { $link.LinkType + ' -> ' + ($link.Target -join ',') } else { 'plain directory, not linked to a volume' })

$body = @('#### Cache volumes on Windows', '', '| Check | Result |', '| --- | --- |') + $rows
($body -join [char]10) | buildkite-agent annotate --style info --context cache-volume
$body | Write-Host
exit 0
