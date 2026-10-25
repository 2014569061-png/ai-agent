# NEXUS 桌面端续验记录（2026-10-15）

工作区：`D:/AIIIIII/ai-agent/mobile_agent`。

> **后续 P2 历史更新**：最新全量 **1956 项测试通过**，覆盖率 **65.60%**，analyze 0。新增有效 CPU 诊断与共享桌面选择区域；无收益 Tooltip 试验已回退。100/1000 档回切对照改善，5000 档波动，全部历史档仍超 16.667ms，整体性能验收未通过。正式 `lib/main.dart` 已再次构建并烟测正常退出 0。本次 6 文件格式通过；全仓存量格式审计另有 141 文件差异未批量改动。详见 [P2 性能续验报告第 8 节](desktop-p2-performance-2026-10-15.md)。

## P0/P1 阶段结论（归档）

以下计数和 v10 数据是 P0/P1 完成时的历史记录；最新状态以上述 P2 报告为准。

- 本轮已闭环原生终端标准流串线、关闭/目录释放，以及首轮全量测试暴露的 14 项失败。
- 最终全量测试 **1937 项全部通过**，静态分析无问题，本轮 15 个 Dart 文件格式检查无改动。
- 自编代码覆盖率 **65.57%（31529 / 48081）**，高于 55% 门槛；包含生成代码为 60.45%。未记录意图的空 catch 为 0，门槛通过。
- Release 目录已通过显式 `--target lib/main.dart` 恢复为正式应用，**不是隔离验收程序**。
- 实际启动正式应用，观察 10 秒，确认正常桌面工作台可见；截图核验后正常关闭，退出码 0。最新 DPI-aware 截图为 1920×1200 物理像素；仅验证了本机 150% 缩放。
- **尚不能宣称全部桌面路线完成或可以发布。** P2 性能采样/优化、真实模型与设备、多 DPI、安装/升级/回滚/签名等仍未完成。

## 1. 原生故障的证据与修复

此前 cmd 与 PowerShell 看似都没有提示符，然而 cmd 的 `Active code page: 65001` 和真实提示符出现在宿主的 `continuation-acceptance.stdout.log` 中，而不是 ConPTY 输出。这证明 shell 已执行，但标准流被复制到宿主重定向句柄，不能把问题继续归因于单一 CPR、等待不足或 PowerShell 启动失败。

`windows/runner/desktop_host.cpp` 现在显式设置 `STARTF_USESTDHANDLES`，三个标准句柄保持 NULL，让子进程绑定到 pseudoconsole。`bInheritHandles=FALSE` 本身不足以阻止这种标准流复制。参考 Microsoft Terminal 维护者说明： https://github.com/microsoft/terminal/discussions/15814 。

保留之前的独立 reader/writer、有界缓冲、Job Object 管理、异步 close、后代退出等待，以及 Dart PTY 会话生命周期修复。一基 CPR 修复同样保留；它是正确性修复，但不是这次串线的根因。

验收脚本还修正了两处证据问题：

1. Ctrl+C 单独发送，在确认 30 秒长任务已开始、收到中断后的新提示符后，再发送下一条命令；不再让 PSReadLine 清空同批后续输入。提示符/输出匹配使用新输出偏移，不能命中历史结果。
2. 在退出前保留 Process Handle，使退出码可读取；明确检测子进程输出是否泄漏到宿主 stdout。早期 `exitCode: null` 不能视为 0。

### 最新 v10 原生验收

| 项目 | cmd | PowerShell |
| --- | --- | --- |
| 中文实际输出、同一 shell 状态保留 | 通过 | 通过 |
| resize API 调用 | 成功 | 成功 |
| 长任务中断后继续执行 | 通过，124ms | 通过，126ms |
| close 后临时工作目录释放 | true | true |
| 子进程输出泄漏到宿主 stdout | false | false |
| 窗口正常退出 / 退出码 | true / 0 | true / 0 |
| harness 功能断言 | passed: true | passed: true |

边界：resize 目前验证 API 成功，未额外断言子进程返回的窗口尺寸；以上是隔离原生组件验收，不代替所有正式 UI 交互、所有 Windows 版本及长期稳定性测试。两次 harness 均未请求模型（`modelRequests: 0`）。

## 2. 首轮 14 项失败的修复

- 会话切换：worktree 偏好读取限制到桌面平台，读取异常记录 NexusGuard 降级；异步 project/worktree 解析后再次检查 switch/run generation，避免旧请求写入新会话。
- 测试夹具：optimization regression 每个测试初始化 SharedPreferences mock，保留原有并发/分页断言。
- 设计 token：两处 180ms 展示动画使用已有 `NexusMotion.pageExit`，未提高质量门槛。
- 分层：恢复/运行互斥规则移到 domain，application 保留兼容导出，基础设施直接依赖 domain，保持同一个锁；增加跨入口一致性断言。
- 变更集页面：使用 application 层 `DevelopmentTaskInfo` 快照，不再直接导入数据库实体；任务查询集中按 project 过滤，增加跨项目/缺失 task ID 回归。
- 消息菜单：新增操作导致“选择文本”超出弹层高度，原列表禁止滚动。现在启用真实滚动，回归测试滚动找到操作并验证进入/退出选择模式，未放宽功能断言。
- 桌面设置：侧栏用 Material 承载 ListTile，修复 ColoredBox 遮挡选择背景与 ink 的框架断言；桌面截图测试已随全量测试通过。

## 3. 最终验证与正式应用

验证按顺序执行，未并行启动 Flutter 构建/测试，避免 SQLite native asset 锁冲突。

| 检查 | 结果 | 证据（相对工作区） |
| --- | --- | --- |
| 本轮 15 个 Dart 文件格式检查 | 0 changed，exit 0 | `artifacts/desktop/continuation-final-format.log` |
| analyze --no-pub | No issues found，exit 0 | `artifacts/desktop/continuation-final-analyze.log` |
| 全量 test --coverage | 1937 passed，exit 0 | `artifacts/desktop/continuation-final-tests.log` |
| coverage 55% 门槛 | 65.57%，exit 0 | `artifacts/desktop/continuation-final-coverage.log` |
| 空 catch 门槛 | 0 <= 0，exit 0 | `artifacts/desktop/continuation-final-silent-catches.log` |
| 正式 main.dart Release 构建 | 成功，exit 0 | `artifacts/desktop/continuation-final-production-build.log` |
| 正式应用启动/绘制/正常退出 | 成功，exit 0 | `artifacts/desktop/production-smoke.json` |

最终正式构建命令：

```bash
/c/src/flutter/bin/cache/dart-sdk/bin/dart.exe /c/src/flutter/bin/cache/flutter_tools.snapshot build windows --release --no-pub --target lib/main.dart
```

正式产物：`build/windows/x64/runner/Release/mobile_agent.exe`。

正式应用截图：`artifacts/desktop/production-main-window.png`。最新冒烟 PID 54232，`windowVisible: true`、`normalExit: true`、`exitCode: 0`。截图是已有会话的恢复显示，**不是本轮发送真实模型请求的证据**。未在正式 UI 中逐项点击全部操作。

`tool/run-desktop-production-smoke.ps1` 仅管理自己启动的进程，使用物理坐标的 DPI-aware 截图；正常关闭超时会保留进程供诊断，不按名称批量结束进程。

原生详细证据：`artifacts/desktop/continuation-{cmd,powershell}-v10.json`、对应 `-launch.json`、`.stdout.log`、`.log`。早期 v6/v7/v8/v9 失败记录保留作诊断，不能冒充当前通过结果。

## 4. P2 尚未完成：性能与发布门槛

最新隔离测量环境：Windows Build 29683，Dart 3.13.2，32 processors，DPR 1.5，240Hz。**harness 的 passed:true 不等于严格性能门槛通过。**

- 5000 消息切换到首帧：cmd 37.270ms / PowerShell 35.379ms；build P95 分别 28.033ms / 35.639ms，240Hz 下存在明显抖动。
- 50k 流式内容下受控输入到帧 P95：199.635ms / 203.643ms。该指标不是完整的 OS 键盘输入延迟验收，不能宣称输入响应达标。
- 部分历史消息场景 `frames: 0`，说明批量 FrameTiming 回调与场景采样边界不可靠；对应 P95=0 不能当作零耗时或性能通过，需先完善采样、暖机和缺样门槛再优化。
- 100k 日志显示缓冲限制在 3000 行 / 44985 字符；这证明当前显示缓冲有界，不证明全应用长期无内存增长。
- 30 次组件切换后的 RSS 约 194–196MB，仅是本轮快照，不是长期泄漏趋势验收。

后续建议：先修正性能采样和门槛，再处理长流式内容/输入延迟；随后补真实模型任务、Android 真机、多 DPI、长稳、干净机安装、覆盖升级/回滚、包签名与下载校验。没有完成这些验收前，不制作“可发布”结论。

## 5. 工作区保护

本轮未 reset、clean、stash、提交、推送或发布，保留原有暂存、未暂存、未跟踪改动。不要把整个 dirty workspace 都归因于本轮。构建过程中现有依赖的 CMake CMP0175 开发警告非致命；未修改依赖缓存来消除警告。
