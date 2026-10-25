param([int]$TimeoutSeconds = 120, [ValidateSet('powershell', 'cmd')][string]$Shell = 'powershell', [switch]$BenchmarkForeground, [ValidateSet('Release', 'Profile')][string]$BuildConfiguration = 'Release')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$artifacts = Join-Path $root 'artifacts/desktop'
$reportPath = Join-Path $artifacts 'native-acceptance-2026-10-15.json'
$runnerPath = Join-Path $artifacts 'continuation-native-launch.json'
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null
if (Test-Path $reportPath) {
  Copy-Item $reportPath (Join-Path $artifacts 'continuation-native-before-run.json') -Force
}
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class NexusAcceptanceWindow {
  delegate bool Callback(IntPtr window, IntPtr param);
  [DllImport("user32.dll")] static extern bool EnumWindows(Callback callback, IntPtr param);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr window, StringBuilder text, int size);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window, uint message, IntPtr wparam, IntPtr lparam);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
  public static IntPtr Find(int pid) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((window, param) => {
      uint owner; GetWindowThreadProcessId(window, out owner);
      var title = new StringBuilder(256); GetWindowText(window, title, title.Capacity);
      if (owner == (uint)pid && title.ToString() == "NEXUS Agent") { found = window; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
'@
$start = [DateTime]::UtcNow
$process = Start-Process (Join-Path $root "build/windows/x64/runner/$BuildConfiguration/mobile_agent.exe") -ArgumentList "--shell=$Shell" -WorkingDirectory $root -RedirectStandardOutput (Join-Path $artifacts 'continuation-acceptance.stdout.log') -RedirectStandardError (Join-Path $artifacts 'continuation-acceptance.stderr.log') -PassThru
$null = $process.Handle # Retain the process handle before Refresh/exit.
$record = [ordered]@{ startedUtc = $start.ToString('o'); pid = $process.Id; freshReport = $false; closePosted = $false; normalExit = $false }
Write-Output "Harness PID: $($process.Id)"
$record | ConvertTo-Json -Depth 4 | Set-Content $runnerPath -Encoding UTF8
$report = $null
$benchmarkWindow = [IntPtr]::Zero
$record.buildConfiguration = $BuildConfiguration
$record.benchmarkForeground = [bool]$BenchmarkForeground
$record.foregroundSamples = 0
$record.foregroundLostSamples = 0
try {
  $deadline = $start.AddSeconds($TimeoutSeconds)
  while ([DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) {
    if ($BenchmarkForeground) {
      if ($benchmarkWindow -eq [IntPtr]::Zero) {
        $benchmarkWindow = [NexusAcceptanceWindow]::Find($process.Id)
        if ($benchmarkWindow -ne [IntPtr]::Zero) {
          [void][NexusAcceptanceWindow]::SetWindowPos($benchmarkWindow, [IntPtr](-1), 0,0,0,0,0x13)
          $record.foregroundRequestAccepted = [NexusAcceptanceWindow]::SetForegroundWindow($benchmarkWindow)
        }
      }
      if ($benchmarkWindow -ne [IntPtr]::Zero) {
        $record.foregroundSamples++
        if ([NexusAcceptanceWindow]::GetForegroundWindow() -ne $benchmarkWindow) { $record.foregroundLostSamples++ }
      }
    }
    if ((Test-Path $reportPath) -and (Get-Item $reportPath).LastWriteTimeUtc -gt $start) {
      try { $report = Get-Content $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $report = $null }
      if ($null -ne $report) { $record.freshReport = $true; break }
    }
    Start-Sleep -Milliseconds 250
    $process.Refresh()
  }
  $process.Refresh()
  if (-not $process.HasExited) {
    $window = [NexusAcceptanceWindow]::Find($process.Id)
    $record.windowHandle = $window.ToInt64()
    if ($window -ne [IntPtr]::Zero) {
      $record.closePosted = [NexusAcceptanceWindow]::PostMessage($window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    }
    if (-not $process.WaitForExit(20000)) { throw 'Owned harness did not exit normally within 20 seconds.' }
  }
  $record.normalExit = $true
  $process.WaitForExit()
  $record.exitCode = $process.ExitCode
  $parentOutput = Get-Content (Join-Path $artifacts 'continuation-acceptance.stdout.log') -Raw -Encoding UTF8
  $record.childOutputLeaked = [bool]($parentOutput -match 'Active code page|NATIVE_中文|PERSIST_42|AFTER_INTERRUPT|PS .*nexus-native-pty-')
  if ($record.childOutputLeaked) { throw 'Child terminal output leaked into redirected host stdout.' }
  if (-not $record.freshReport) { throw 'No fresh, complete native acceptance report.' }
  $report | ConvertTo-Json -Depth 12 | Write-Output
  if (-not $report.passed) { throw 'Native acceptance assertions failed; inspect the report.' }
} finally {
  $process.Refresh()
  if ($benchmarkWindow -ne [IntPtr]::Zero -and -not $process.HasExited) {
    [void][NexusAcceptanceWindow]::SetWindowPos($benchmarkWindow, [IntPtr](-2), 0,0,0,0,0x13)
  }
  if (-not $process.HasExited) {
    # Only the exact process launched here, never all processes sharing its name.
    $process.Kill()
    $null = $process.WaitForExit(5000)
    $record.forcedOwnedHarness = $true
  }
  $record.finishedUtc = [DateTime]::UtcNow.ToString('o')
  $record | ConvertTo-Json -Depth 4 | Set-Content $runnerPath -Encoding UTF8
  $record | ConvertTo-Json -Depth 4 | Write-Output
  $process.Dispose()
}
