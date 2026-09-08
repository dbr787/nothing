. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'

# One cache per link type so a save failure names the exact construct at fault.
# The build number is in each key, so every build is a fresh cold save.

function Test-LinkType {
  param([string]$Name, [string]$Dir, [scriptblock]$Build)
  Remove-Item -Recurse -Force $Dir -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path (Join-Path $Dir 'real') | Out-Null
  Set-Content -LiteralPath (Join-Path $Dir 'real\payload.txt') -Value 'payload'
  $abs = (Resolve-Path $Dir).Path
  & $Build $abs
  Get-ChildItem -Force $Dir | Select-Object Name, LinkType, Attributes |
    Format-Table -AutoSize | Out-String | Write-Host

  $s = Invoke-Cache save @('--name', $Name)
  if ($s.Code -eq 0) {
    Write-Result "$Name.save" 'PASS' 'archived without error'
    $r = Invoke-Cache restore @('--name', $Name)
    Assert-True ($r.Code -eq 0) "$Name.restore" "exit $($r.Code)"
    Get-ChildItem -Force $Dir | Select-Object Name, LinkType, Attributes |
      Format-Table -AutoSize | Out-String | Write-Host
  } else {
    Write-Result "$Name.save" 'FAIL' "exit $($s.Code) - cache save cannot archive this link type"
  }
}

Test-LinkType 'link_junction' 'bk-link-junction' {
  param($abs) cmd /c mklink /J "$abs\link" "$abs\real" 2>&1 | Write-Host
}
Test-LinkType 'link_dirsymlink' 'bk-link-dirsymlink' {
  param($abs) cmd /c mklink /D "$abs\link" "$abs\real" 2>&1 | Write-Host
}
Test-LinkType 'link_symlink' 'bk-link-symlink' {
  param($abs) cmd /c mklink "$abs\link.txt" "$abs\real\payload.txt" 2>&1 | Write-Host
}
Test-LinkType 'link_hardlink' 'bk-link-hardlink' {
  param($abs) cmd /c mklink /H "$abs\link.txt" "$abs\real\payload.txt" 2>&1 | Write-Host
}

Complete-Probe -Context 'cache-linktypes' -Heading 'Which link type breaks cache save'
