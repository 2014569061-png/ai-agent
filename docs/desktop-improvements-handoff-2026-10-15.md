# NEXUS 桌面端开发交接文档

> **P2 最新历史续优化（2026-10-15）**：已取得有效 Profile CPU 证据，保留桌面历史列表共享 SelectionArea 的局部优化，无收益的 Tooltip 试验已回退。原生回切对照 100/1000 档改善，5000 档仍波动，历史 UI P95 仍超 16.667ms，**总体性能验收保持失败，不能宣称 P2 全部完成或可发布**。最新全量 **1956 项测试通过**、覆盖率 **65.60%**、analyze 0；本次 6 文件格式通过，全仓另有 141 文件格式存量未批量处理。已再次显式恢复 `lib/main.dart` 正式 Release，实际工作台观察 10 秒并正常退出 0。详细数据、前台条件差异及剩余边界见 [P2 性能续验报告第 8 节](desktop-p2-performance-2026-10-15.md)。

日期：2026-10-15。工作区：`D:\AIIIIII\ai-agent\mobile_agent`。

> **2026-10-15 P0/P1 阶段归档**：原生 cmd/PowerShell 功能验收已通过，最终全量测试 1937 项全部通过，覆盖率 65.57%；Release 已显式恢复为 `lib/main.dart` 正式应用并验证实际窗口与正常退出。详细证据、性能数据和未完成的 P2 门槛见 [桌面续验记录](desktop-continuation-verification-2026-10-15.md)。以下第 1 节保留为原始交接快照，其中原生失败及 Release 为 harness 的描述不再代表当前状态；仍不能宣称全部验收完成或可以发布。

## 1. 原始交接时结论：已补充大量实现，尚未完成全部验收

本轮任务来自“评估桌面端、对标 GitHub 成熟 Agent，并完成改进”。前期评估和路线见 [桌面端评估与开发路线](desktop-review-roadmap-2026-10-15.md)。随后已经修改桌面工作台、恢复保护、交互、终端、运行配置、工作流、调度和分发脚本，但目前不能标记为“全部完成”或“可以发布”。

**接手时先处理以下事项：**

1. **原生 ConPTY 验收失败。** 临时工作目录删除时报 Windows errno 32，随后验收窗口退出未能在等待期限内完成，最终终止了本轮启动的验收进程。必须排查终端子进程、管道和原生宿主的退出顺序。
2. **当前 `build/windows/x64/runner/Release/mobile_agent.exe` 是 `tool/desktop_acceptance.dart` 构建出的隔离验收程序。** 不能把这个目录直接打包或交付；验收结束后必须用 `lib/main.dart` 重新构建。
3. 最后一次正常应用构建成功后又有代码改动，特别是 `desktop_pty_session.dart` 的会话生命周期重构，**尚未完成最后一轮格式检查、静态分析、回归测试和正常应用构建**。
4. 安装与回滚脚本已写，安装包尚未构建或实机验收；真实模型任务、Android 真机、多 DPI 和长时间稳定性尚未验证。

本轮没有提交、推送或发布。仓库原本已有大量暂存、未暂存和未跟踪改动，当前 `git status` 中的全部文件不能都归因于本轮。接手前保留整个工作区状态，避免 `reset --hard`、`clean` 或批量覆盖。

## 2. 环境和工作约定

| 项目 | 当前信息 |
| --- | --- |
| 技术栈 | Flutter、Dart、Riverpod、Drift / SQLite，Windows 原生 runner |
| 本轮使用版本 | Flutter 3.47.2，Dart 3.13.2；应用版本 `0.9.0+95` |
| 终端 | Windows PowerShell |
| 本地构建入口 | `tool/build-windows.ps1`；NuGet 辅助工具目录 `local/desktop-tools` |
| 原生验收入口 | `tool/desktop_acceptance.dart`，与正式 `lib/main.dart` 不同 |
| 日志 | `artifacts/desktop/implementation-*.log`、`native-acceptance-2026-10-15.json` |

- Flutter 测试和 Windows 构建应串行运行。本轮并行执行时遇到 SQLite native asset DLL 被占用，导致构建失败；停止占用后串行构建成功，不需要因此清空全部缓存。
- 使用与 Flutter 配套的 Dart，先用 `Get-Command flutter,dart` 核对路径，避免误用系统另一套 SDK。
- 本轮未为验收发送真实模型请求，原生验收报告的 `modelRequests` 为 0。
- 原有桌面快捷方式、旧 `dist` 文件和旧截图不能作为本次最新交付的证据。

## 3. 已实现的改动与代码入口

以下“已实现”指代码已经写入工作区；每一项仍需结合第 4、5 节判断验收状态。

### 3.1 检查点和恢复保护

- 新增 `lib/application/session_operation_guard.dart`，恢复期间阻止新的 Agent run 和受管命令启动，并在异常退出时释放锁。
- `change_set_service.dart` 增加回滚预检；`session_checkpoint_service.dart` 使用虚拟文件哈希逆序检查多个任务，处理同一文件连续被修改的情况。
- 检查点存储串行化写入，通过临时文件再重命名，遇到 JSON 解析错误保留原文件并报错。
- `desktop_checkpoint_timeline.dart` 在代码恢复前检查冲突；“代码与消息一起恢复”遇到冲突时保留消息。恢复时检查运行中任务、原生终端和开发服务器。
- `chat_controller.dart` 等待记录检查点，使用数据库真实消息数量；恢复后重新加载会话与上下文。

核心入口：`lib/application/session_checkpoint_service.dart`、`session_operation_guard.dart`、`change_set_service.dart`、`run_coordinator.dart`、`chat_controller.dart`，以及 `lib/presentation/navigation/desktop_checkpoint_timeline.dart`。

仍需补齐跨任务恢复中途失败的原子性、外部编辑并发、缺失 change set 的处理，以及 `editAndResend` 在 run guard 之前修改消息的边界。当前保护不能视为完整文件事务。

### 3.2 命令中心、布局、搜索和隔离工作区

- `app_shell.dart` 将 Ctrl+K 接到实际命令中心，Ctrl+P 打开搜索，加入布局、工作流和隔离会话入口。
- 新安装默认使用专注布局；增加专注、执行、审查布局，侧栏宽度变化带过渡，拖动调整时使用独立状态。
- `desktop_search_service.dart` 增加异步项目文件路径扫描，最多扫描 50,000 项、返回 30 项，排除常见构建和依赖目录；结果可作为文件上下文加入草稿。此功能是路径搜索，不是全文索引。
- `desktop_worktree_service.dart` 接入创建、会话绑定、清理；默认不强制删除，限制路径并检查符号链接边界，在仓库本地 Git exclude 中排除托管 worktree 目录。
- `desktop_git_service.dart` 加入干净工作区检查和 fast-forward 合并。会话切换尝试恢复其绑定目录。

核心入口：`lib/presentation/navigation/app_shell.dart`、`desktop_command_center.dart`，以及 `lib/application/desktop_search_service.dart`、`desktop_worktree_service.dart`、`desktop_git_service.dart`。

会话创建、切换、重启、目录被外部删除、清理和合并仍需贯通验收。绑定目前存在 SharedPreferences，未纳入数据库备份；删除会话后的绑定清理也需检查。隔离会话后新建普通会话的目录继承行为需要重点验证。

### 3.3 桌面交互、设置、无障碍和动画

- 桌面消息正文支持选择，右键菜单按鼠标位置弹出，包含复制、编辑、分叉、引用和重新生成；移动端保留原交互。
- 输入框 Enter 避免在 IME 正在组合输入时提交；Ctrl/Cmd+V 接入图片粘贴和文本插入，Windows 文件拖入接入附件流程。
- 新增双栏桌面设置页，复用模型、工具、MCP、数据更新和设备等现有页面，加入托盘、通知设置。
- 调整减少动态效果和高对比度主题读取；审查面板去除重复预览入口，导航“任务”文案改为“会话”。

核心入口：`lib/presentation/chat/chat_message_actions.dart`、`chat_page.dart`、`widgets/message_bubble.dart`、`widgets/floating_capsule_input.dart`、`lib/presentation/settings/desktop_settings_page.dart`、`lib/presentation/theme/desktop_theme.dart`。

实现后尚未重跑完整视觉验收。需要检查中文输入法、右键和选区、拖放、剪贴板、键盘焦点、大字号、窄窗口、深色、高对比度，以及 125% / 150% / 200% DPI；新对话框可能存在溢出。现有历史截图不是新界面验收结果。

### 3.4 长列表、日志和流式渲染

- 新增 `bounded_log_buffer.dart`，显示尾部限制为 256 Ki 字符 / 3,000 行；桌面日志使用懒加载列表，完整受管任务日志与显示缓冲分开。
- `streaming_markdown.dart` 缓存已稳定的渲染片段；列表、引用、数学等需要整体语义的内容保留整块处理。
- `host_process_runtime_adapter.dart` 改为流式 UTF-8 解码，完成时读取输出也设上限。
- 增加隔离原生和性能验收程序，准备测量历史消息、流式输出、差异和日志场景。

核心入口：`lib/application/bounded_log_buffer.dart`、`lib/presentation/workspace/terminal_sheet.dart`、`lib/presentation/chat/widgets/streaming_markdown.dart`、`lib/infrastructure/terminal/host_process_runtime_adapter.dart`、`tool/desktop_acceptance.dart`。

没有当前可用的性能达标结论。验收在原生终端阶段失败，后续场景未完成；`firstHarnessFrameMs: 0` 还受顶层 Stopwatch 延迟初始化影响，不能当作真实首帧时间。应先在 `main` 明确启动计时，再采集可重复数据。

### 3.5 Windows 原生终端、托盘和宿主集成

- 新增 `windows/runner/desktop_host.h/.cpp`，通过 `nexus/desktop_host` 提供 ConPTY 创建、读写、resize、关闭，使用读写线程、输入输出队列和 Windows Job Object。
- `flutter_window.cpp/.h`、CMake 接入宿主；加入托盘隐藏 / 打开 / 退出、气泡通知、文件拖放、剪贴板图片读取。
- `desktop_host_service.dart` 负责 Dart 通道、偏好和终端目录记录；`desktop_pty_session.dart` 将终端会话从 UI 生命周期中独立，目标是面板重建和工作区切换后保留 shell。
- `desktop_terminal_panel.dart` 提供显式启动、shell 选择、粘贴、Ctrl+C 和停止；退出时尝试关闭终端、开发服务器和调度器。

核心入口：`windows/runner/desktop_host.cpp`、`lib/application/desktop_host_service.dart`、`desktop_pty_session.dart`、`lib/presentation/terminal/desktop_terminal_panel.dart`。

**此项存在发布阻塞，具体见第 5 节。** 最新会话重构尚未验证，不能宣称中文输出、会话持久化、中断或退出已经通过原生验收。

### 3.6 运行配置、预览、任务结果和工作流

- `desktop_run_service.dart` 保存每个目录的命令与 URL，显式启动本地开发服务，收集有界、脱敏的日志，等待 HTTP 就绪并支持停止进程树。
- `desktop_run_dialog.dart` 和预览面板连接保存、启动、停止、日志与就绪 URL。
- `desktop_task_result_dialog.dart` 展示实际任务摘要、文件、验证命令退出码、输出、产物路径、风险与审查入口。
- `desktop_workflow_service.dart` / `desktop_workflows_dialog.dart` 提供修复、实现、审查模板和自定义模板，支持导入导出。选择后填入草稿，由用户发起执行。

仍需验证开发服务启动失败、端口超时、停止子进程、输出尾部完整性和异常回收。当前工作流是模板复用，尚无独立的工具权限或配置作用域。

### 3.7 调度、通知和 Windows 分发

- `scheduled_task_runner.dart` 抽取共享的到期任务执行函数；`desktop_scheduler.dart` 在桌面进程存活时每 30 秒检查，避免重叠，恢复期间跳过。
- 任务条只对完成、失败和待审批等有意义的状态变化尝试通知；托盘驻留和通知由用户设置控制。
- 新增 `windows/installer/install.ps1`、`rollback.ps1` 与 `tool/build-windows-installer.ps1`，计划使用系统 IExpress 打包，按用户安装、版本目录保留、SHA256 校验和快捷方式切换。
- `.github/workflows/ci.yml`、`release.yml` 加入安装包构建 / 产物入口，尚未推送或在远端执行。

边界：没有登录自启动；退出进程后不会持续调度。睡眠恢复、托盘通知和调度与 Android 逻辑的兼容仍需实测。安装器尚未生成和验收，没有完成卸载能力；现有更新器仍以 ZIP 为主，尚未接入完整安装器升级流程，也没有签名发布。

曾尝试下载并静默安装 Inno Setup 编译器，自动审批返回 `blocked by policy`，没有更详细理由；该工具调用未完成安装。本轮没有创建可用的 Inno 安装包，后续改用系统已有 IExpress 编写脚本。

## 4. 已有验证证据与适用范围

所有路径相对仓库根目录。日志主要保存在本地，不能假设只交接 Git 提交就会包含这些文件。

| 检查 | 实际结果 | 证据与限制 |
| --- | --- | --- |
| 桌面关键回归 8 个文件 | 39 项通过 | `artifacts/desktop/implementation-targeted-tests.log`；早于最后的修改 |
| 壳层快捷键 / 默认布局 | 2 项通过 | `implementation-shell-tests.log`；验证 Ctrl+K、审查布局保存、默认专注、Ctrl+P |
| 新增组合测试 | 当时 2 项失败，后续单独修复壳层测试 | `implementation-new-tests.log` 是旧失败记录；修复后的完整组合尚未重跑 |
| 静态分析 | 上次报告 32 个问题 | `implementation-analyze.log`；后续自动修复，但尚无最终干净报告 |
| 自动修复 | lib 22 处 / 14 文件，tool 4 处 / 1 文件 | `implementation-fixes.log`、`implementation-tool-fixes.log`；不是最终验收 |
| 格式化 | 曾格式化 46 个文件，40 个发生变化 | `implementation-format.log`；最新追加代码仍需检查 |
| 正常 Windows Release 构建 | 曾成功，约 97.6 秒 | `implementation-windows-build.log`；早于最新改动 |
| 隔离验收程序构建 | 成功，约 52.1 秒 | `implementation-acceptance-build.log`；覆盖了 Release 输出目录 |
| 原生验收运行 | **失败** | `native-acceptance-2026-10-15.json`，`implementation-acceptance.stdout.log` / `.stderr.log` |
| 当前源码全量测试 / 覆盖率 | **未完成最终运行** | 不能引用 10 月 14 日的 1,879 项历史结果替代 |
| 当前视觉、真实模型 / 设备、安装升级 | **未完成** | 不具备交付结论 |

新增重点用例集中在 `test/desktop_completion_test.dart`；还修改了检查点、搜索、工作区交互和壳层测试。壳层测试曾因清理阶段 timer / 数据库释放等待失败，通过先卸载组件、释放容器并推进异步清理解决，单独重跑 2 项通过。

## 5. 接手优先级和验收标准

### P0：先修原生终端退出，再恢复正式构建

报告内容为 `passed: false`，错误为删除临时目录 `nexus-native-pty-*` 失败，`errno = 32`，栈位于 `tool/desktop_acceptance.dart` 的 `_pty` 清理阶段。报告没有 `conpty` 成功记录，因此尚不能确认终端前面的输出断言是否成功；`finally` 中的清理异常还可能覆盖了原始错误。

建议按以下顺序排查：

1. 拆开验收的业务异常和清理异常，分别记录；关闭终端后等待子进程和工作目录句柄真正释放，再删除临时目录。
2. 审查 `PtySession` 析构的 `TerminateJobObject`、`TerminateProcess`、`ClosePseudoConsole`、`CancelSynchronousIo`、线程 join 和句柄关闭顺序，确认退出等待有界、不会卡住 UI 线程。
3. 检查终端创建失败路径：读线程未启动时关闭伪控制台是否可能阻塞；补充原生错误记录，保留首次错误。
4. 验证中文 UTF-8、跨 chunk 解码、环境变量跨命令持久化、resize、Ctrl+C、停止、重复启动、面板隐藏重开、切换工作区和退出。
5. 退出后确认本轮创建的 shell / 子进程全部结束，临时目录可删除；不得通过杀死所有 PowerShell 或所有同名进程绕过问题。
6. 最后明确以 `lib/main.dart` 重建，确认打开的是正常应用，才允许创建分发包。

### P1：对当前最终源码做完整回归

先格式和 analyze，再定向测试、全量测试 / 覆盖率、截图和原生验收，最后正式构建。任何一轮修复后，重跑受影响检查；不要沿用修复前成功日志。

重点覆盖恢复冲突不删消息、恢复锁释放、同文件多任务恢复、真实 Git hunk 暂存 / 撤销、隔离目录绑定、Ctrl+K / Ctrl+P、选择与右键、IME、剪贴板和设置持久化。确认移动端交互没有被桌面改动破坏。

### P1：补齐运行配置、worktree 和调度贯通测试

- 运行配置：有效 / 无效命令、端口已占用、就绪超时、输出尾部、异常回收、停止整个子进程树；检查频繁输出导致的通知 / UI 更新开销。
- Worktree：创建隔离会话、切换目录、重启恢复、外部目录丢失、干净 / 脏状态清理和 ff-only 合并；检查终端或服务仍占用时的处理。
- 调度 / 托盘：最小化、关闭隐藏、明确退出、睡眠恢复、错过触发、恢复期间到期、待审批通知；检查桌面调用共享调度逻辑是否仍依赖 Android 专用服务。

### P2：完成视觉、性能和分发验收

- 用同一机器记录长会话、流式 Markdown、大差异和大量日志的帧时间 / 内存；240 Hz 显示器应按实际刷新率解释帧预算，不能只看 60 Hz。先修复验收计时，再制定达标阈值。
- 覆盖浅色、深色、高对比度、减少动态效果、大字号、窄窗口、多 DPI；检查代码高亮和焦点可见性，补齐新界面截图。
- 安装脚本需验证失败退出码、失败重试、半成品目录清理、升级、回滚和数据保留。IExpress 的完成提示不能在脚本失败时仍宣称成功。
- 在隔离安装目录或干净测试账户完成安装 / 升级 / 回滚；数据库不兼容降级需匹配备份，不能只切换可执行文件。
- 在 CI 实际跑通后再处理卸载、更新器接入和签名。没有签名证书时如实标识，不能宣称已签名。

## 6. 推荐验证命令

在仓库根目录使用 PowerShell，按顺序执行并检查每条退出码。以下是接手后的待执行步骤，不代表已经通过。

```powershell
Set-Location 'D:\AIIIIII\ai-agent\mobile_agent'
$env:PATH = (Join-Path (Get-Location) 'local\desktop-tools') + ';' + $env:PATH
Get-Command flutter,dart
git status --short

# 先修复已知原生问题及最新改动，再检查格式和分析。
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze --no-pub

# 定向回归；失败时先定位，保留真实日志。
flutter test --no-pub test/desktop_shell_test.dart test/desktop_completion_test.dart test/desktop_checkpoint_timeline_test.dart test/session_checkpoint_service_test.dart test/desktop_git_service_test.dart test/desktop_search_service_test.dart test/desktop_worktree_service_test.dart test/desktop_workspace_interaction_test.dart test/desktop_command_center_test.dart test/desktop_a11y_motion_test.dart test/streaming_markdown_incremental_test.dart --reporter expanded

flutter test --coverage --no-pub --reporter expanded
dart run tool/check_coverage.dart coverage/lcov.info 55.0
dart run tool/count_silent_catches.dart lib 0
flutter test --no-pub test/render_desktop_test.dart

# 与测试串行执行；该构建会再次把 Release 目录改成验收程序。
flutter build windows --release --no-pub --target tool/desktop_acceptance.dart
```

运行隔离验收程序，等待报告并验证正常退出，核对新报告时间与 `passed`。检查报告输出位置，以免把旧 JSON 当成本轮结果。关闭本轮验收进程和它创建的子进程后，再执行：

```powershell
# 必须恢复正式入口，并验证实际启动的是正常应用。
flutter build windows --release --no-pub --target lib/main.dart

# 正式构建通过、应用验收完成后，才生成 ZIP 和安装包。
.\tool\build-windows.ps1 -SkipPub
.\tool\build-windows-installer.ps1
```

`build-windows.ps1` 会重新构建并打包；安装器脚本直接使用 Release 目录，因此尤其依赖该目录已经恢复为正式应用。不要将验收程序混入发布资产。

## 7. 完成条件和后续记录

下一位接手者应在新记录中填写：最终 analyze / 测试结果、覆盖率、正式构建入口和时间、原生验收 JSON、截图、安装 / 回滚结果、真实任务验证范围及仍未完成事项。只有通过的检查才能标“通过”；跳过的检查说明原因与影响。

推荐接手提示词：

> 请继续完成 NEXUS 桌面端改进。先阅读 `docs/desktop-improvements-handoff-2026-10-15.md` 和原评估路线，保护当前已有暂存及未提交改动。优先修复 ConPTY 验收失败、临时目录占用和退出阻塞，再验证最新 PTY 会话生命周期。不要并行运行 Flutter 构建与测试。当前 Release 是验收程序，最终必须使用 `lib/main.dart` 重建。随后完成静态分析、定向及全量回归、视觉与性能验证、安装升级回滚测试。逐项报告真实证据，不把历史通过记录或已写代码当成最终验收完成。
