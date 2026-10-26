# Q2: does the image ship the Windows Audio service and an output device?
# If not, can a job install a signed virtual audio driver (VB-CABLE)?
param([switch]$Install)
$ErrorActionPreference = 'Continue'

function Section($name) { Write-Host "`n--- $name" }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class WinMM {
  [DllImport("winmm.dll")] public static extern uint waveOutGetNumDevs();
  [DllImport("winmm.dll")] public static extern uint waveInGetNumDevs();
  [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
  public static extern int mciSendString(string cmd, StringBuilder ret, int len, IntPtr cb);
  [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
  public static extern bool mciGetErrorString(int err, StringBuilder buf, int len);
  public static string Mci(string cmd) {
    var sb = new StringBuilder(256);
    int r = mciSendString(cmd, sb, 256, IntPtr.Zero);
    if (r == 0) return "ok " + sb;
    var e = new StringBuilder(256); mciGetErrorString(r, e, 256);
    return "error " + r + ": " + e;
  }
}
'@

function Show-AudioState {
  Section 'Audio services'
  Get-Service Audiosrv, AudioEndpointBuilder -ErrorAction SilentlyContinue |
    ForEach-Object { "{0,-22} status {1,-8} start {2}" -f $_.Name, $_.Status, $_.StartType }

  Section 'Sound devices (Win32_SoundDevice)'
  $sd = @(Get-CimInstance Win32_SoundDevice)
  if ($sd.Count) { $sd | ForEach-Object { "{0}  [{1}]" -f $_.Name, $_.Status } } else { '(none)' }

  Section 'PnP audio devices (MEDIA, AudioEndpoint)'
  $pnp = @(Get-PnpDevice -Class MEDIA, AudioEndpoint -ErrorAction SilentlyContinue)
  if ($pnp.Count) { $pnp | ForEach-Object { "{0,-14} {1,-6} {2}" -f $_.Class, $_.Status, $_.FriendlyName } } else { '(none)' }

  Section 'winmm device counts'
  "waveOut devices: $([WinMM]::waveOutGetNumDevs())"
  "waveIn  devices: $([WinMM]::waveInGetNumDevs())"
}

Section 'Privileges'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
"whoami: $(whoami)   elevated admin: $admin"
whoami /priv /fo csv | ConvertFrom-Csv | Where-Object { $_.'Privilege Name' -match 'LoadDriver|SystemEnvironment' } |
  ForEach-Object { "{0,-32} {1}" -f $_.'Privilege Name', $_.State }
"Test signing / integrity: $((bcdedit /enum '{current}' 2>&1 | Select-String 'testsigning|nointegritychecks') -join '; ')"

Section 'Stock image'
Show-AudioState

Section 'Try to start Windows Audio'
try {
  Set-Service Audiosrv -StartupType Automatic -ErrorAction Stop
  Set-Service AudioEndpointBuilder -StartupType Automatic -ErrorAction Stop
  Start-Service AudioEndpointBuilder, Audiosrv -ErrorAction Stop
  Get-Service Audiosrv, AudioEndpointBuilder | ForEach-Object { "{0,-22} {1}" -f $_.Name, $_.Status }
} catch { "Start FAILED: $($_.Exception.Message)" }

if (-not $Install) { exit 0 }

Section 'Download VB-CABLE driver pack'
$dir = Join-Path $env:TEMP 'vbcable'
New-Item -ItemType Directory -Force $dir | Out-Null
$zip = Join-Path $dir 'pack.zip'
$got = $null
foreach ($v in 45, 44, 43) {
  $url = "https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack$v.zip"
  try { Invoke-WebRequest $url -OutFile $zip -UseBasicParsing -TimeoutSec 60; $got = $url; break } catch { "$url -> $($_.Exception.Message)" }
}
if (-not $got) { 'Could not download VB-CABLE'; exit 1 }
"Downloaded $got ($((Get-Item $zip).Length) bytes)"
Expand-Archive $zip -DestinationPath $dir -Force
Get-ChildItem $dir -Recurse -Include *.exe, *.inf, *.cat | ForEach-Object { $_.Name }

Section 'Driver signature'
Get-ChildItem $dir -Recurse -Filter *.cat | ForEach-Object {
  $sig = Get-AuthenticodeSignature $_.FullName
  "{0,-34} {1,-6} {2}" -f $_.Name, $sig.Status, $sig.SignerCertificate.Subject
}

Section 'Trust the publisher (avoids the "install this device software?" prompt)'
$cat = Get-ChildItem $dir -Recurse -Filter *.cat | Where-Object { $_.Name -match 'win10' } | Select-Object -First 1
if (-not $cat) { $cat = Get-ChildItem $dir -Recurse -Filter *.cat | Select-Object -First 1 }
$cert = (Get-AuthenticodeSignature $cat.FullName).SignerCertificate
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store 'TrustedPublisher', 'LocalMachine'
$store.Open('ReadWrite'); $store.Add($cert); $store.Close()
"Added $($cert.Subject) to LocalMachine\TrustedPublisher"

Section 'Silent install: VBCABLE_Setup_x64.exe -i -h'
$setup = Get-ChildItem $dir -Recurse -Filter VBCABLE_Setup_x64.exe | Select-Object -First 1
$p = Start-Process $setup.FullName -ArgumentList '-i', '-h' -PassThru
if (-not $p.WaitForExit(180000)) { 'Setup still running after 180s (likely blocked on a prompt), killing'; $p.Kill() } else { "Setup exit code: $($p.ExitCode)" }
Start-Sleep 5
Restart-Service Audiosrv -Force -ErrorAction SilentlyContinue
Start-Sleep 3

Section 'After install'
Show-AudioState

Section 'Loopback: play a 440 Hz tone into CABLE Input, record from CABLE Output'
$rate = 44100; $secs = 3
$n = $rate * $secs
$tone = Join-Path $dir 'tone.wav'
$ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
$w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $n * 2)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
$w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$rate); $w.Write([int]($rate * 2)); $w.Write([int16]2); $w.Write([int16]16)
$w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]($n * 2))
for ($i = 0; $i -lt $n; $i++) { $w.Write([int16](12000 * [Math]::Sin(2 * [Math]::PI * 440 * $i / $rate))) }
[IO.File]::WriteAllBytes($tone, $ms.ToArray())

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
public static class WaveIn {
  [StructLayout(LayoutKind.Sequential)] public struct WAVEFORMATEX {
    public ushort wFormatTag, nChannels; public uint nSamplesPerSec, nAvgBytesPerSec;
    public ushort nBlockAlign, wBitsPerSample, cbSize; }
  [StructLayout(LayoutKind.Sequential)] public struct WAVEHDR {
    public IntPtr lpData; public uint dwBufferLength, dwBytesRecorded; public IntPtr dwUser;
    public uint dwFlags, dwLoops; public IntPtr lpNext, reserved; }
  [DllImport("winmm.dll")] static extern int waveInOpen(out IntPtr h, uint dev, ref WAVEFORMATEX f, IntPtr cb, IntPtr inst, uint flags);
  [DllImport("winmm.dll")] static extern int waveInPrepareHeader(IntPtr h, IntPtr hdr, int size);
  [DllImport("winmm.dll")] static extern int waveInUnprepareHeader(IntPtr h, IntPtr hdr, int size);
  [DllImport("winmm.dll")] static extern int waveInAddBuffer(IntPtr h, IntPtr hdr, int size);
  [DllImport("winmm.dll")] static extern int waveInStart(IntPtr h);
  [DllImport("winmm.dll")] static extern int waveInReset(IntPtr h);
  [DllImport("winmm.dll")] static extern int waveInClose(IntPtr h);
  // Records ms of 16-bit audio from device 0; returns the peak absolute sample, or throws with the MMRESULT
  public static int Peak(uint rate, ushort ch, int ms, out int bytes) {
    var f = new WAVEFORMATEX { wFormatTag = 1, nChannels = ch, nSamplesPerSec = rate, wBitsPerSample = 16,
      nBlockAlign = (ushort)(ch * 2), nAvgBytesPerSec = rate * (uint)ch * 2 };
    IntPtr h; int r = waveInOpen(out h, 0, ref f, IntPtr.Zero, IntPtr.Zero, 0);
    if (r != 0) throw new Exception("waveInOpen MMRESULT " + r);
    int len = (int)(f.nAvgBytesPerSec * ms / 1000);
    IntPtr data = Marshal.AllocHGlobal(len);
    int sz = Marshal.SizeOf(typeof(WAVEHDR));
    IntPtr hdr = Marshal.AllocHGlobal(sz);
    Marshal.StructureToPtr(new WAVEHDR { lpData = data, dwBufferLength = (uint)len }, hdr, false);
    waveInPrepareHeader(h, hdr, sz); waveInAddBuffer(h, hdr, sz);
    r = waveInStart(h); if (r != 0) throw new Exception("waveInStart MMRESULT " + r);
    Thread.Sleep(ms + 500);
    waveInReset(h);
    var done = (WAVEHDR)Marshal.PtrToStructure(hdr, typeof(WAVEHDR));
    bytes = (int)done.dwBytesRecorded;
    int peak = 0;
    for (int i = 0; i + 1 < bytes; i += 2) { int s = Math.Abs((int)Marshal.ReadInt16(data, i)); if (s > peak) peak = s; }
    waveInUnprepareHeader(h, hdr, sz); waveInClose(h);
    Marshal.FreeHGlobal(hdr); Marshal.FreeHGlobal(data);
    return peak;
  }
}
'@

$consent = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone'
"Microphone consent (HKCU): $((Get-ItemProperty $consent -ErrorAction SilentlyContinue).Value)"
"Microphone consent (HKLM): $((Get-ItemProperty ($consent -replace 'HKCU', 'HKLM') -ErrorAction SilentlyContinue).Value)"

function Try-Loopback($label) {
  $player = New-Object System.Media.SoundPlayer $tone
  foreach ($f in @(@(48000, 2), @(44100, 2), @(48000, 1))) {
    try {
      $player.Play()   # async, so capture overlaps playback
      $bytes = 0
      $peak = [WaveIn]::Peak($f[0], $f[1], 2000, [ref]$bytes)
      $player.Stop()
      "$label $($f[0])/$($f[1]): captured $bytes bytes, peak amplitude $peak of 32767 (0 = silence)"
      return
    } catch { $player.Stop(); "$label $($f[0])/$($f[1]): FAILED $($_.Exception.Message)" }
  }
}

Try-Loopback 'as shipped     '
New-Item -Force $consent | Out-Null
Set-ItemProperty $consent Value Allow
Try-Loopback 'consent=Allow  '
