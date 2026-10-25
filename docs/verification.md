# 验证状态

最近一次本机完整检查：**2026-10-25**。远程 Linux 质量检查、Android 调试构建和 Windows 发布构建，以 [GitHub Actions 对应提交](https://github.com/2014569061-png/ai-agent/actions/workflows/ci.yml?query=branch%3Amain) 的结果为准。

| 检查 | 结果 |
|---|---|
| 静态分析 | 全部受版本控制的 Dart 目录（lib、test、tool）无问题。 |
| 静默异常门禁 | 未记录意图的空 catch 为 0，通过。 |
| 全量测试 | **2,809 项通过、0 项失败**，包含并发运行的预览集成测试。 |
| 手写代码覆盖率 | **60.12%（42,888 / 71,333）**，超过 55% 门槛。 |

本轮修正了测试临时目录、数据库和任务夹具、异步初始化等待、预览端口隔离，以及随当前界面演进而过期的断言。应用同时修复费用账本的数据库绑定、手机触控区域和窄屏暂停布局。费用硬停、任务恢复安全检查、成果文件校验及覆盖率门槛继续执行。

## 复现质量检查

```bash
flutter pub get
flutter analyze --no-pub
dart run tool/count_silent_catches.dart lib 0
flutter test --no-pub --coverage
dart run tool/check_coverage.dart coverage/lcov.info 55.0
```

CI 从干净检出运行完整静态分析。本机包含 SDK、缓存和历史归档时，可用 `flutter analyze --no-pub lib test tool` 检查全部受版本控制的 Dart 代码目录，避免遍历本地工具状态。

Windows 上将测试临时文件保存在仓库内部时，需设置 `GIT_CEILING_DIRECTORIES` 为临时根目录，避免没有独立 `.git` 的样例错误发现父仓库。

```powershell
$env:TEMP = Join-Path (Get-Location) 'local/temp'
New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
$env:TMP = $env:TEMP
$env:GIT_CEILING_DIRECTORIES = $env:TEMP
flutter test --no-pub --coverage
```

## 发布验收

自动化测试、模拟器检查和平台构建不能替代 ARM64 真机与正式安装包验收。正式 APK 继续执行 `tool/release_evidence_gate.py`；缺失证据不能计为通过。后台恢复、无障碍、性能及 Windows 安装与回滚需按目标设备单独验收。

[安全与发布边界](security.md) · [开发与构建](getting-started.md)
