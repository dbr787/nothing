. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'

$rel  = 'bk-anchor-rel'
$home_ = Join-Path $HOME 'bk-anchor-home'
$abs  = 'C:\bk-anchor-abs'

Write-Host "--- Environment"
Write-Host ("checkout : " + (Get-Location).Path)
Write-Host ("home     : " + $HOME)

# Relative + home anchors live in the portable config.
$r = Invoke-Cache restore @('--name','anchors')
Assert-True ($r.Code -eq 0) 'anchors.restore.exit0' "exit $($r.Code)"
$relHit  = Get-Marker $rel
$homeHit = Get-Marker $home_
Write-Result 'anchors.rel.hit'  $(if ($relHit)  {'PASS'} else {'INFO'}) $(if ($relHit)  { $relHit }  else { 'miss (expected on the first build)' })
Write-Result 'anchors.home.hit' $(if ($homeHit) {'PASS'} else {'INFO'}) $(if ($homeHit) { $homeHit } else { 'miss (expected on the first build)' })

# Absolute drive path lives in the Windows-only config.
$r = Invoke-Cache restore @('--cache-config-file','.buildkite\cache-windows.yml','--name','abs')
Assert-True ($r.Code -eq 0) 'anchors.abs.restore.exit0' "exit $($r.Code)"
$absHit = Get-Marker $abs
Write-Result 'anchors.abs.hit' $(if ($absHit) {'PASS'} else {'INFO'}) $(if ($absHit) { $absHit } else { 'miss (expected on the first build)' })

# A cached path with spaces in it.
$spaces = 'C:\bk cache with spaces'
$r = Invoke-Cache restore @('--cache-config-file','.buildkite\cache-windows.yml','--name','spaces')
Assert-True ($r.Code -eq 0) 'anchors.spaces.restore.exit0' "exit $($r.Code)"
$spHit = Get-Marker $spaces
Write-Result 'anchors.spaces.hit' $(if ($spHit) {'PASS'} else {'INFO'}) $(if ($spHit) { $spHit } else { 'miss (expected on the first build)' })

# Confirm each target really is where the anchor says it should be.
New-Marker $rel   | Out-Null
New-Marker $home_ | Out-Null
New-Marker $abs   | Out-Null
New-Marker $spaces | Out-Null
Assert-True ((Resolve-Path $rel).Path.StartsWith((Get-Location).Path)) 'anchors.rel.location' (Resolve-Path $rel).Path
Assert-True ((Resolve-Path $home_).Path.StartsWith($HOME))             'anchors.home.location' (Resolve-Path $home_).Path
Assert-True ((Resolve-Path $abs).Path -ieq $abs)                       'anchors.abs.location' (Resolve-Path $abs).Path

$s = Invoke-Cache save @('--name','anchors')
Assert-True ($s.Code -eq 0) 'anchors.save.exit0' "exit $($s.Code)"
$s = Invoke-Cache save @('--cache-config-file','.buildkite\cache-windows.yml','--name','abs')
Assert-True ($s.Code -eq 0) 'anchors.abs.save.exit0' "exit $($s.Code)"
$s = Invoke-Cache save @('--cache-config-file','.buildkite\cache-windows.yml','--name','spaces')
Assert-True ($s.Code -eq 0) 'anchors.spaces.save.exit0' "exit $($s.Code)"

Complete-Probe -Context 'cache-anchors' -Heading 'Cache path anchors on Windows'
