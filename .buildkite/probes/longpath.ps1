. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'

$root = 'bk-longpath'
$r = Invoke-Cache restore @('--name','longpath')
Assert-True ($r.Code -eq 0) 'longpath.restore.exit0' "exit $($r.Code)"

$segment = 'a' * 40
$deepRel = $root
1..8 | ForEach-Object { $deepRel = Join-Path $deepRel ($segment + $_) }
$deepAbs = Join-Path (Get-Location).Path $deepRel
Write-Host ("Deep path length: {0} characters" -f ($deepAbs.Length + 12))

if (Test-Path -LiteralPath ('\\?\' + $deepAbs + '\deep.txt')) {
  $content = (Get-Content -LiteralPath ('\\?\' + $deepAbs + '\deep.txt')) -join '; '
  Write-Result 'longpath.hit' 'PASS' "restored: $content"
} else {
  Write-Result 'longpath.hit' 'INFO' 'miss (expected on the first build)'
}

New-Item -ItemType Directory -Force -Path ('\\?\' + $deepAbs) | Out-Null
Set-Content -LiteralPath ('\\?\' + $deepAbs + '\deep.txt') -Value ('build ' + $env:BUILDKITE_BUILD_NUMBER)
Write-Result 'longpath.created' 'INFO' ("{0} chars: {1}" -f ($deepAbs.Length + 9), $deepAbs)

$s = Invoke-Cache save @('--name','longpath')
Assert-True ($s.Code -eq 0) 'longpath.save.exit0' "exit $($s.Code) archiving a path past MAX_PATH"

Complete-Probe -Context 'cache-longpath' -Heading 'Paths beyond MAX_PATH (260 characters)'
