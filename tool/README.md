# 构建与质量工具

公开仓库只保留构建、CI 门禁及自动化测试直接依赖的工具。从仓库根目录运行。

| 用途 | 文件 |
|---|---|
| Android 打包 | [build-apk-tools.ps1](build-apk-tools.ps1)，由根目录 build-apk.bat 调用 |
| Windows 打包与安装器 | [build-windows.ps1](build-windows.ps1)、[build-windows-installer.ps1](build-windows-installer.ps1) |
| 静默异常与覆盖率门禁 | [count_silent_catches.dart](count_silent_catches.dart)、[check_coverage.dart](check_coverage.dart) |
| 发布证据与 Agent 评分 | [release_evidence_gate.py](release_evidence_gate.py)、[score_mobile_agent_eval.py](score_mobile_agent_eval.py) |
| 源码一致性校验 | [verify_source_tokens.dart](verify_source_tokens.dart) |
| 工具回归 | [test_build_apk.py](test_build_apk.py)、[test_release_evidence_gate.py](test_release_evidence_gate.py)、[test_score_mobile_agent_eval.py](test_score_mobile_agent_eval.py)、[test_source_tokens.py](test_source_tokens.py) |
| 应用测试直接依赖 | [agent_live_acceptance.dart](agent_live_acceptance.dart)、[desktop_cpu_profile.dart](desktop_cpu_profile.dart)、[desktop_frame_pump.dart](desktop_frame_pump.dart)、[frame_timing_window.dart](frame_timing_window.dart) |

最后一组由 test/ 中的回归直接导入，保留以便干净克隆后运行完整测试。个人模拟器预览、截图、界面驱动、远程执行器和专项诊断脚本不纳入公开仓库。

运行与构建说明见 [开发文档](../docs/getting-started.md)。新增工具默认忽略；只有构建、CI 或公开测试确实依赖时，才更新 .gitignore 的 tool 白名单。
