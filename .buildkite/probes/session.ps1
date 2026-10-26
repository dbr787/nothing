# Q1: does a job run in an interactive desktop session, or as a service in session 0?
$ErrorActionPreference = 'Continue'

function Section($name) { Write-Host "`n--- $name" }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class WinSta {
  [DllImport("user32.dll")] public static extern IntPtr GetProcessWindowStation();
  [DllImport("user32.dll")] public static extern IntPtr GetThreadDesktop(uint id);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("kernel32.dll")] public static extern uint WTSGetActiveConsoleSessionId();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern bool GetUserObjectInformation(IntPtr h, int index, StringBuilder buf, int len, out int needed);
  public static string Name(IntPtr h) {
    var sb = new StringBuilder(256); int n;
    return GetUserObjectInformation(h, 2, sb, 512, out n) ? sb.ToString() : "<error " + Marshal.GetLastWin32Error() + ">";
  }
}
'@

Section 'OS'
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
"ProductName      : $($cv.ProductName)"
"EditionID        : $($cv.EditionID)"
"InstallationType : $($cv.InstallationType)   (Server = Desktop Experience, Server Core = no desktop)"
"Build            : $($cv.CurrentBuild).$($cv.UBR)"
$cs = Get-CimInstance Win32_ComputerSystem
"Model            : $($cs.Manufacturer) / $($cs.Model)"
"HypervisorPresent: $($cs.HypervisorPresent)"
"Container svc    : $((Get-Service cexecsvc -ErrorAction SilentlyContinue).Status)"

Section 'Identity'
whoami
whoami /groups /fo csv | ConvertFrom-Csv | Where-Object { $_.'Group Name' -match 'INTERACTIVE|SERVICE|CONSOLE LOGON|REMOTE INTERACTIVE|BATCH|Administrators|High Mandatory|Medium Mandatory|System Mandatory' } |
  ForEach-Object { "{0,-45} {1}" -f $_.'Group Name', $_.SID }

Section 'Session, window station, desktop'
$me = Get-Process -Id $PID
"Job process SessionId      : $($me.SessionId)"
"Active console SessionId   : $([WinSta]::WTSGetActiveConsoleSessionId())"
"Window station             : $([WinSta]::Name([WinSta]::GetProcessWindowStation()))   (WinSta0 = interactive, Service-0x0-... = non-interactive)"
"Thread desktop             : $([WinSta]::Name([WinSta]::GetThreadDesktop([WinSta]::GetCurrentThreadId())))"
"Environment.UserInteractive: $([Environment]::UserInteractive)"

Section 'Logged-on sessions (qwinsta / quser)'
qwinsta 2>&1
quser 2>&1

Section 'Desktop shell'
Get-CimInstance Win32_Process -Filter "Name='explorer.exe' OR Name='dwm.exe' OR Name='winlogon.exe' OR Name='LogonUI.exe'" |
  ForEach-Object { "{0,-14} pid {1,-6} session {2}  owner {3}" -f $_.Name, $_.ProcessId, $_.SessionId, (Invoke-CimMethod -InputObject $_ -MethodName GetOwner).User }

Section 'Autologon'
$wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
"AutoAdminLogon : $($wl.AutoAdminLogon)"
"DefaultUserName: $($wl.DefaultUserName)"

Section 'How the agent is launched (process ancestry)'
$procs = @{}; Get-CimInstance Win32_Process | ForEach-Object { $procs[[int]$_.ProcessId] = $_ }
$p = $procs[[int]$PID]
while ($p) {
  $owner = (Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction SilentlyContinue).User
  "{0,-28} pid {1,-6} session {2}  owner {3}" -f $p.Name, $p.ProcessId, $p.SessionId, $owner
  if ($p.ParentProcessId -eq $p.ProcessId) { break }
  $p = $procs[[int]$p.ParentProcessId]
}
Get-CimInstance Win32_Service | Where-Object { $_.PathName -match 'buildkite|nsc|namespace|runner' -or $_.Name -match 'buildkite|runner' } |
  ForEach-Object { "service {0}  state {1}  startname {2}`n  {3}" -f $_.Name, $_.State, $_.StartName, $_.PathName }

Section 'Display'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
"SystemInformation.UserInteractive: $([System.Windows.Forms.SystemInformation]::UserInteractive)"
[System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "Screen {0} {1} primary={2}" -f $_.DeviceName, $_.Bounds, $_.Primary }
Get-CimInstance Win32_VideoController | ForEach-Object { "GPU: {0}  {1}x{2}" -f $_.Name, $_.CurrentHorizontalResolution, $_.CurrentVerticalResolution }

Section 'Screenshot test (fails with "The handle is invalid" without an interactive desktop)'
try {
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
  $bmp.Save("$PWD\screenshot.png", [System.Drawing.Imaging.ImageFormat]::Png)
  # A black frame means the capture ran against an empty desktop
  $px = @(0..9 | ForEach-Object { $bmp.GetPixel([int]($b.Width * $_ / 10), [int]($b.Height / 2)).ToArgb() }) | Sort-Object -Unique
  "Captured $($b.Width)x$($b.Height); distinct sampled pixel values: $($px.Count)"
  buildkite-agent artifact upload screenshot.png
} catch { "Screenshot FAILED: $($_.Exception.Message)" }

Section 'GUI window test'
$app = Start-Process notepad -PassThru
Start-Sleep 3
$app.Refresh()
"notepad session $($app.SessionId), MainWindowHandle $($app.MainWindowHandle), title '$($app.MainWindowTitle)'"
Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
