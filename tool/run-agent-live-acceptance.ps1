param(
  [string]$Flutter = 'flutter'
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$reportPath = Join-Path $repoRoot 'build\agent-live-acceptance.json'
Push-Location $repoRoot
try {
  & $Flutter assemble --no-version-check --output=build '-dTargetPlatform=windows-x64' '-dBuildMode=debug' '-dTargetFile=tool/agent_live_acceptance.dart' '-dTrackWidgetCreation=true' debug_bundle_windows-x64_assets
  if ($LASTEXITCODE -ne 0) { throw 'Flutter asset assembly failed' }
  & $Flutter build windows --debug --no-pub --target tool/agent_live_acceptance.dart
  if ($LASTEXITCODE -ne 0) { throw '验收程序编译失败' }
  $executable = Join-Path $repoRoot 'build\windows\x64\runner\Debug\mobile_agent.exe'
  $previousReportPath = $env:NEXUS_ACCEPTANCE_REPORT
  $env:NEXUS_ACCEPTANCE_REPORT = $reportPath
  try {
    if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath }
    $process = Start-Process -FilePath $executable -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(300000)) {
      Stop-Process -Id $process.Id
      throw '真实模型验收超过五分钟，已停止验收程序'
    }
    if (-not (Test-Path -LiteralPath $reportPath)) { throw '验收未生成结果文件' }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    $report | ConvertTo-Json -Depth 8
    if ($report.status -eq 'failed') { throw '真实模型验收未通过，详见报告' }
    if ($report.status -eq 'blocked') { Write-Warning '真实模型验收被配置阻塞，未将其计为通过' }
  } finally {
    $env:NEXUS_ACCEPTANCE_REPORT = $previousReportPath
  }
} finally {
  # Restore the regular app entry point after producing the acceptance report.
  & $Flutter assemble --no-version-check --output=build '-dTargetPlatform=windows-x64' '-dBuildMode=debug' '-dTargetFile=lib/main.dart' '-dTrackWidgetCreation=true' debug_bundle_windows-x64_assets
  if ($LASTEXITCODE -eq 0) {
    & $Flutter build windows --debug --no-pub --target lib/main.dart
  }
  Pop-Location
}

