. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'

$root = 'bk-attrs'
$r = Invoke-Cache restore @('--name','attrs')
Assert-True ($r.Code -eq 0) 'attrs.restore.exit0' "exit $($r.Code)"

if (Test-Path $root) {
  Write-Host "--- Restored tree"
  Get-ChildItem -Recurse -Force $root | Select-Object FullName, Attributes, Length |
    Format-Table -AutoSize | Out-String | Write-Host

  Assert-True (Test-Path (Join-Path $root 'empty-dir'))                  'attrs.emptydir.restored'  'empty directory survived the round trip'
  Assert-True (Test-Path (Join-Path $root 'dir with spaces\file.txt'))   'attrs.spaces.restored'    'path with spaces survived'
  $ro = Join-Path $root 'readonly.txt'
  if (Test-Path $ro) {
    $isRo = (Get-Item $ro -Force).IsReadOnly
    Write-Result 'attrs.readonly.preserved' $(if ($isRo) {'PASS'} else {'INFO'}) "IsReadOnly=$isRo (zip carries no Windows ACL or attribute data)"
  } else { Write-Result 'attrs.readonly.preserved' 'FAIL' 'readonly.txt missing after restore' }
  $hid = Join-Path $root 'hidden.txt'
  if (Test-Path $hid -PathType Leaf) {
    $a = (Get-Item $hid -Force).Attributes
    Write-Result 'attrs.hidden.preserved' 'INFO' "attributes=$a"
  } else { Write-Result 'attrs.hidden.preserved' 'FAIL' 'hidden.txt missing after restore' }
} else {
  Write-Result 'attrs.hit' 'INFO' 'miss (expected on the first build)'
}

# (Re)build the fixture.
Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $root 'empty-dir')        | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $root 'dir with spaces')  | Out-Null
Set-Content -LiteralPath (Join-Path $root 'dir with spaces\file.txt') -Value ('build ' + $env:BUILDKITE_BUILD_NUMBER)
New-Marker $root | Out-Null
$ro = Join-Path $root 'readonly.txt'
Set-Content -LiteralPath $ro -Value 'read only'
(Get-Item $ro).IsReadOnly = $true
$hid = Join-Path $root 'hidden.txt'
Set-Content -LiteralPath $hid -Value 'hidden'
(Get-Item $hid -Force).Attributes = 'Hidden'
$sys = Join-Path $root 'system.txt'
Set-Content -LiteralPath $sys -Value 'system'
(Get-Item $sys -Force).Attributes = 'System'

$s = Invoke-Cache save @('--name','attrs')
Assert-True ($s.Code -eq 0) 'attrs.save.exit0' "exit $($s.Code)"

Complete-Probe -Context 'cache-attrs' -Heading 'File attributes, empty dirs and spaces'
