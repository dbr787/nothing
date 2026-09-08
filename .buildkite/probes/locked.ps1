. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'

# Restore deletes each target before extracting. Populate the target with a
# read-only file and a file held open by a live process, then restore over it.
$root = 'bk-locked'
Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $root | Out-Null
$ro = Join-Path $root 'readonly-blocker.txt'
Set-Content -LiteralPath $ro -Value 'in the way'
(Get-Item $ro).IsReadOnly = $true

$lockedFile = Join-Path (Resolve-Path $root).Path 'held-open.txt'
Set-Content -LiteralPath $lockedFile -Value 'held'
$fs = [System.IO.File]::Open($lockedFile, 'Open', 'ReadWrite', 'None')
Write-Host "Holding an exclusive handle on $lockedFile"

try {
  $r = Invoke-Cache restore @('--name','locked')
  if ($r.Code -eq 0) {
    Write-Result 'locked.restore.exit0' 'PASS' "exit 0 - restore tolerated a read-only file and an open handle in the target"
  } else {
    Write-Result 'locked.restore.exit0' 'FAIL' "exit $($r.Code) - restore could not clear a target containing a locked or read-only file"
  }
} finally {
  $fs.Close(); $fs.Dispose()
}

# A read-only file alone, no open handle: this is the Go-module-cache case the
# agent explicitly handles by chmod-ing before removal.
Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $root | Out-Null
$ro2 = Join-Path $root 'readonly-only.txt'
Set-Content -LiteralPath $ro2 -Value 'read only, not locked'
(Get-Item $ro2).IsReadOnly = $true
$r2 = Invoke-Cache restore @('--name','locked')
Assert-True ($r2.Code -eq 0) 'locked.readonly.restore.exit0' "exit $($r2.Code) with a read-only file in the target"

Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
New-Marker $root | Out-Null
Set-Content -LiteralPath (Join-Path $root 'payload.txt') -Value ('saved by build ' + $env:BUILDKITE_BUILD_NUMBER)
$s = Invoke-Cache save @('--name','locked')
Assert-True ($s.Code -eq 0) 'locked.save.exit0' "exit $($s.Code)"

Complete-Probe -Context 'cache-locked' -Heading 'Restore over locked and read-only targets'
