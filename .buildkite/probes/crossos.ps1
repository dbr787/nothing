. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'

# The crossos cache deliberately omits os and arch from its key, so an entry
# saved on Linux is addressable from Windows. This is the failure mode when a
# user forgets to key on platform.
$r = Invoke-Cache restore @('--name','crossos')
Assert-True ($r.Code -eq 0) 'crossos.restore.exit0' "exit $($r.Code)"

if (Test-Path 'bk-crossos') {
  Write-Host "--- Restored tree"
  Get-ChildItem -Recurse -Force 'bk-crossos' | Select-Object FullName, Attributes, Length |
    Format-Table -AutoSize | Out-String | Write-Host
  $origin = if (Test-Path 'bk-crossos\origin.txt') { (Get-Content 'bk-crossos\origin.txt') -join '; ' } else { 'no origin.txt' }
  Write-Result 'crossos.hit' 'INFO' "restored an entry saved by: $origin"
} else {
  Write-Result 'crossos.hit' 'INFO' 'miss - no cross-platform entry was addressable'
}

Complete-Probe -Context 'cache-crossos' -Heading 'Cross-platform key collision (restore only)'
