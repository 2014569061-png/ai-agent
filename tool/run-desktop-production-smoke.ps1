param([int]$ObserveSeconds = 10)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$artifacts = Join-Path $root 'artifacts/desktop'
$exe = Join-Path $root 'build/windows/x64/runner/Release/mobile_agent.exe'
# Build explicitly with --target lib/main.dart before invoking this script.
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NexusProductionSmokeWindow {
  [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
}
'@
$dpiContext = [NexusProductionSmokeWindow]::SetThreadDpiAwarenessContext([IntPtr](-4))
if ($dpiContext -eq [IntPtr]::Zero) { throw 'Cannot enable physical-coordinate DPI-aware window capture.' }
$p = Start-Process -FilePath $exe -WorkingDirectory $root -PassThru -RedirectStandardOutput (Join-Path $artifacts 'production-smoke.stdout.log') -RedirectStandardError (Join-Path $artifacts 'production-smoke.stderr.log')
$null = $p.Handle
$report = [ordered]@{ target='lib/main.dart'; pid=$p.Id; exe=$exe; observedSeconds=$ObserveSeconds; screenshot=$null; windowVisible=$false; normalExit=$false; exitCode=$null }
try {
  Start-Sleep -Seconds $ObserveSeconds
  $p.Refresh()
  if ($p.HasExited) { throw 'Production app exited before the observation period.' }
  $h = $p.MainWindowHandle
  if ($h -eq [IntPtr]::Zero) { throw 'Production app has no main window.' }
  $report.windowVisible = [NexusProductionSmokeWindow]::IsWindowVisible($h)
  $report.windowTitle = $p.MainWindowTitle
  if (-not $report.windowVisible) { throw 'Production window is not visible.' }
  $r = New-Object NexusProductionSmokeWindow+Rect
  if (-not [NexusProductionSmokeWindow]::GetWindowRect($h, [ref]$r)) { throw 'Cannot read production window bounds.' }
  $report.width = $r.Right-$r.Left; $report.height = $r.Bottom-$r.Top
  # Temporarily put only this owned window above other windows for the capture.
  [void][NexusProductionSmokeWindow]::SetWindowPos($h, [IntPtr](-1), 0,0,0,0,0x13)
  try {
    Start-Sleep -Milliseconds 400
    $bitmap = New-Object System.Drawing.Bitmap($report.width, $report.height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
      $graphics.CopyFromScreen($r.Left,$r.Top,0,0,$bitmap.Size)
      $capture = Join-Path $artifacts 'production-main-window.png'
      $bitmap.Save($capture,[System.Drawing.Imaging.ImageFormat]::Png)
      $report.screenshot = $capture
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
  } finally { [void][NexusProductionSmokeWindow]::SetWindowPos($h, [IntPtr](-2), 0,0,0,0,0x13) }
  if (-not $p.CloseMainWindow()) { throw 'Cannot request normal close of owned production window.' }
  $report.normalExit = $p.WaitForExit(20000)
  if ($report.normalExit) { $p.WaitForExit(); $report.exitCode = $p.ExitCode }
  else { throw 'Production normal close did not exit; owned PID is left intact for diagnosis (tray setting or pending approval).' }
} catch { $report.error = $_.Exception.Message }
$report | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $artifacts 'production-smoke.json') -Encoding UTF8
$report | ConvertTo-Json -Depth 5
if ($report.error -or -not $report.normalExit -or $report.exitCode -ne 0) { exit 1 }
