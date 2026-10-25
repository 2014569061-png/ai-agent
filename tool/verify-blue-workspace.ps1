param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [string]$ReportStem = 'blue-native-window',
    [switch]$NativeProbe,
    [switch]$SkipResize
)

$ErrorActionPreference = 'Stop'
$blueRepo = Split-Path -Parent $PSScriptRoot
$blueExecutable = (Resolve-Path -LiteralPath $Executable).Path
$blueArtifacts = Join-Path $blueRepo 'artifacts\desktop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class BlueWorkspaceWindow {
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
  public delegate bool EnumCallback(IntPtr hwnd, IntPtr param);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumCallback callback, IntPtr param);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, StringBuilder name, int size);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hwnd, out Rect rect);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hwnd, ref Point point);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hwnd, int command);
  [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
  public static IntPtr FindForProcess(uint pid) {
    IntPtr result = IntPtr.Zero;
    EnumWindows((hwnd, param) => {
      uint owner;
      GetWindowThreadProcessId(hwnd, out owner);
      var name = new StringBuilder(256);
      GetClassName(hwnd, name, name.Capacity);
      if (owner == pid && name.ToString() == "FLUTTER_RUNNER_WIN32_WINDOW") { result = hwnd; return false; }
      return true;
    }, IntPtr.Zero);
    return result;
  }
}
'@
$bluePreviousDpi = [BlueWorkspaceWindow]::SetThreadDpiAwarenessContext([IntPtr](-4))
$blueStartedAt = Get-Date
$blueWorkingDirectory = if ($NativeProbe) { $blueRepo } else { Split-Path -Parent $blueExecutable }
$blueProcess = Start-Process -FilePath $blueExecutable -WorkingDirectory $blueWorkingDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $blueArtifacts "$ReportStem.stdout.log") -RedirectStandardError (Join-Path $blueArtifacts "$ReportStem.stderr.log")
$blueProcess.Handle | Out-Null
try {
    $blueHandle = [IntPtr]::Zero
    for ($blueAttempt = 0; $blueAttempt -lt 60; $blueAttempt++) {
        Start-Sleep -Milliseconds 500
        $blueProcess.Refresh()
        if ($blueProcess.HasExited) { throw "App exited at startup: $($blueProcess.ExitCode)" }
        $blueHandle = [BlueWorkspaceWindow]::FindForProcess($blueProcess.Id)
        if ($blueHandle -ne [IntPtr]::Zero) {
            [BlueWorkspaceWindow]::ShowWindowAsync($blueHandle, 5) | Out-Null
            break
        }
    }
    if ($blueHandle -eq [IntPtr]::Zero) { throw 'No application window after 30 seconds' }
    $blueDpi = [BlueWorkspaceWindow]::GetDpiForWindow($blueHandle)
    $blueScreen = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $blueWidth = [Math]::Min(1460 * $blueDpi / 96, $blueScreen.Width - 40)
    $blueHeight = [Math]::Min(940 * $blueDpi / 96, $blueScreen.Height - 40)
    [BlueWorkspaceWindow]::SetWindowPos($blueHandle, [IntPtr]::Zero, ($blueScreen.Left + 20), ($blueScreen.Top + 20), $blueWidth, $blueHeight, 4) | Out-Null
    Start-Sleep -Seconds 3
    $blueProbe = $null
    if ($NativeProbe) {
        $blueProbeFile = Join-Path $blueArtifacts 'blue-native-probe.json'
        for ($blueAttempt = 0; $blueAttempt -lt 60; $blueAttempt++) {
            if ((Test-Path -LiteralPath $blueProbeFile) -and (Get-Item -LiteralPath $blueProbeFile).LastWriteTime -ge $blueStartedAt.AddSeconds(-1)) {
                $blueProbe = Get-Content -LiteralPath $blueProbeFile -Raw -Encoding utf8 | ConvertFrom-Json
                break
            }
            Start-Sleep -Milliseconds 500
        }
        if (-not $blueProbe -or -not $blueProbe.passed) { throw "Native integration probe failed: $($blueProbe | ConvertTo-Json -Compress)" }
        Start-Sleep -Seconds 3
    }
    $blueProcess.Refresh()
    if (-not $blueProcess.Responding) { throw 'Application is not responding' }
    [BlueWorkspaceWindow]::SetForegroundWindow($blueHandle) | Out-Null
    [BlueWorkspaceWindow]::SetWindowPos($blueHandle, [IntPtr](-1), 0, 0, 0, 0, 3) | Out-Null
    Start-Sleep -Seconds 1
    $blueRect = New-Object BlueWorkspaceWindow+Rect
    [BlueWorkspaceWindow]::GetClientRect($blueHandle, [ref]$blueRect) | Out-Null
    $blueOrigin = New-Object BlueWorkspaceWindow+Point
    [BlueWorkspaceWindow]::ClientToScreen($blueHandle, [ref]$blueOrigin) | Out-Null
    $blueBitmap = New-Object Drawing.Bitmap ($blueRect.Right - $blueRect.Left), ($blueRect.Bottom - $blueRect.Top)
    $blueGraphics = [Drawing.Graphics]::FromImage($blueBitmap)
    try {
        $blueGraphics.CopyFromScreen($blueOrigin.X, $blueOrigin.Y, 0, 0, $blueBitmap.Size)
        $blueBitmap.Save((Join-Path $blueArtifacts "$ReportStem.png"))
    } finally {
        $blueGraphics.Dispose(); $blueBitmap.Dispose()
        [BlueWorkspaceWindow]::SetWindowPos($blueHandle, [IntPtr](-2), 0, 0, 0, 0, 3) | Out-Null
    }
    if (-not $SkipResize) {
        [BlueWorkspaceWindow]::SetWindowPos($blueHandle, [IntPtr]::Zero, 20, 20, 300, 200, 4) | Out-Null
        Start-Sleep -Seconds 1
    }
    $blueClient = New-Object BlueWorkspaceWindow+Rect
    [BlueWorkspaceWindow]::GetClientRect($blueHandle, [ref]$blueClient) | Out-Null
    $blueDpi = [BlueWorkspaceWindow]::GetDpiForWindow($blueHandle)
    $blueMinimumWidth = ($blueClient.Right - $blueClient.Left) * 96.0 / $blueDpi
    $blueMinimumHeight = ($blueClient.Bottom - $blueClient.Top) * 96.0 / $blueDpi
    if ($blueMinimumWidth -lt 899 -or $blueMinimumHeight -lt 639) { throw "Minimum window failed: $blueMinimumWidth x $blueMinimumHeight" }
    $blueResult = [ordered]@{executable=$blueExecutable; responding=$blueProcess.Responding; dpi=$blueDpi; minimumClientWidth=$blueMinimumWidth; minimumClientHeight=$blueMinimumHeight; nativeProbe=$blueProbe}
    if (-not [BlueWorkspaceWindow]::PostMessage($blueHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)) { throw 'Could not close application window' }
    if (-not $blueProcess.WaitForExit(10000)) { throw 'Application did not close after 10 seconds' }
    $blueResult.exitCode = $blueProcess.ExitCode
    $blueResult | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $blueArtifacts "$ReportStem.json") -Encoding utf8
    $blueResult | ConvertTo-Json -Depth 5
    if ($blueProcess.ExitCode -ne 0) { throw 'Nonzero application exit code' }
} finally {
    $blueProcess.Refresh()
    if (-not $blueProcess.HasExited) { $blueProcess.Kill(); $blueProcess.WaitForExit() }
    [BlueWorkspaceWindow]::SetThreadDpiAwarenessContext($bluePreviousDpi) | Out-Null
}
