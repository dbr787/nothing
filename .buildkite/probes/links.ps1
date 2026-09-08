. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'

$root = 'bk-links'
$r = Invoke-Cache restore @('--name','links')
Assert-True ($r.Code -eq 0) 'links.restore.exit0' "exit $($r.Code)"

if (Test-Path $root) {
  Write-Host "--- Restored link types"
  Get-ChildItem -Recurse -Force $root | Select-Object FullName, LinkType, Target, Attributes |
    Format-Table -AutoSize | Out-String | Write-Host
  foreach ($n in 'junction','hardlink.txt','symlink.txt') {
    $p = Join-Path $root $n
    if (Test-Path -LiteralPath $p) {
      $item = Get-Item -LiteralPath $p -Force
      $lt = if ($item.LinkType) { $item.LinkType } else { 'plain file or directory' }
      Write-Result "links.$n.restored" 'INFO' "restored as: $lt"
    } else {
      Write-Result "links.$n.restored" 'FAIL' 'missing after restore'
    }
  }
} else {
  Write-Result 'links.hit' 'INFO' 'miss (expected on the first build)'
}

Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $root 'real') | Out-Null
Set-Content -LiteralPath (Join-Path $root 'real\payload.txt') -Value ('build ' + $env:BUILDKITE_BUILD_NUMBER)
New-Marker $root | Out-Null

$abs = (Resolve-Path $root).Path
cmd /c mklink /J "$abs\junction" "$abs\real" 2>&1 | Write-Host
Write-Result 'links.junction.created' $(if (Test-Path "$abs\junction") {'PASS'} else {'FAIL'}) 'directory junction'

cmd /c mklink /H "$abs\hardlink.txt" "$abs\real\payload.txt" 2>&1 | Write-Host
Write-Result 'links.hardlink.created' $(if (Test-Path "$abs\hardlink.txt") {'PASS'} else {'FAIL'}) 'hardlink'

cmd /c mklink "$abs\symlink.txt" "$abs\real\payload.txt" 2>&1 | Write-Host
Write-Result 'links.symlink.created' $(if (Test-Path "$abs\symlink.txt") {'PASS'} else {'INFO'}) 'symlink (needs SeCreateSymbolicLink or Developer Mode)'

$s = Invoke-Cache save @('--name','links')
Assert-True ($s.Code -eq 0) 'links.save.exit0' "exit $($s.Code) archiving junctions and links"

Complete-Probe -Context 'cache-links' -Heading 'Junctions, hardlinks and symlinks'
