# Probes whether Docker / native Windows containers are usable on a Windows hosted agent.
$ErrorActionPreference = 'Continue'
$rows = New-Object System.Collections.Generic.List[string]
function Row($name, $value) { $rows.Add(('| {0} | {1} |' -f $name, $value)) }
function Safe($block) { try { & $block } catch { $null } }

Write-Host '--- Host virtualisation'
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Row 'HypervisorPresent' $cs.HypervisorPresent
Row 'VirtualizationFirmwareEnabled' $cpu.VirtualizationFirmwareEnabled
Row 'VMMonitorModeExtensions' $cpu.VMMonitorModeExtensions

Write-Host '--- Windows features'
foreach ($f in 'Containers', 'Hyper-V') {
  $state = Safe { (Get-WindowsFeature -Name $f).InstallState }
  Row ($f + ' feature') $(if ($state) { $state } else { 'not queryable' })
}

Write-Host '--- Services'
$services = Get-Service | Where-Object { $_.Name -match 'docker|containerd' }
if ($services) {
  $services | Format-Table Name, Status, StartType -AutoSize | Out-String | Write-Host
  Row 'Container services' (($services | ForEach-Object { $_.Name + '=' + $_.Status }) -join ', ')
} else {
  Row 'Container services' 'none'
}

Write-Host '--- Binaries on PATH'
foreach ($bin in 'docker', 'dockerd', 'containerd', 'ctr', 'nerdctl', 'podman') {
  $cmd = Get-Command $bin -ErrorAction SilentlyContinue
  Row $bin $(if ($cmd) { $cmd.Source } else { 'not installed' })
}

$docker = Get-Command docker -ErrorAction SilentlyContinue
if ($docker) {
  Write-Host '--- docker version'
  docker version 2>&1 | Out-String | Write-Host
  Write-Host '--- docker info'
  docker info 2>&1 | Out-String | Write-Host

  Write-Host '--- Run a process-isolated Windows container'
  docker run --rm --isolation=process mcr.microsoft.com/windows/nanoserver:ltsc2022 cmd /c echo container-ran-ok 2>&1 | Out-String | Write-Host
  Row 'nanoserver, process isolation' $(if ($LASTEXITCODE -eq 0) { 'works' } else { ('failed, exit ' + $LASTEXITCODE) })

  Write-Host '--- Run a Hyper-V-isolated Windows container (expected to fail, no nested virt)'
  docker run --rm --isolation=hyperv mcr.microsoft.com/windows/nanoserver:ltsc2022 cmd /c echo container-ran-ok 2>&1 | Out-String | Write-Host
  Row 'nanoserver, Hyper-V isolation' $(if ($LASTEXITCODE -eq 0) { 'works' } else { ('failed, exit ' + $LASTEXITCODE) })
} else {
  Row 'nanoserver, process isolation' 'skipped, no docker client'
  Row 'nanoserver, Hyper-V isolation' 'skipped, no docker client'
}

$body = @('#### Docker and Windows containers', '', '| Check | Result |', '| --- | --- |') + $rows
($body -join [char]10) | buildkite-agent annotate --style info --context docker
$body | Write-Host
exit 0
