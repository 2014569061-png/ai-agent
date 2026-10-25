# NEXUS 桌面 P2：采样修复与流式输入性能续验

> **最新历史续优化**：已加入 Profile CPU 诊断和共享桌面选择区域，1956 项测试通过，覆盖率 65.60%；正式入口已重新构建并烟测。100/1000 档回切对照改善，但 5000 档仍波动、全部历史档仍超 16.667ms，整体性能验收继续失败。详见第 8 节；前 7 节保留为上一轮流式里程碑记录。

日期：2026-10-15。工作区：`D:/AIIIIII/ai-agent/mobile_agent`。

## 结论

- 已修复跨场景帧样本混入、空样本零耗时假通过、旧帧屏障复用及回调批次未排空的问题。原生样本完整：空载输入 25 帧，每档历史场景 36 帧，5 万字符流式更新 100 帧。
- 已定位并修复长流式消息的主要额外等待：消息动作语义原来合并了整段回复；现在动作保留在短标签节点，正文保留独立可读节点，**没有关闭无障碍或桌面选择功能**。
- 同机真实消息列表受控输入到帧 P95：修复前 **193.195ms**；修复后 PowerShell **47.655ms / 39.405ms**，cmd **39.805ms**，降低约 **75%–80%**。三次均通过原有 50ms 门槛。
- 最终 **1948 项测试全部通过**，分析器零问题，8 个相关 Dart 文件格式检查零改动；自编代码覆盖率 **65.57%（31526 / 48083）**，未记录意图的空 catch 为 0。
- 已显式用 `--target lib/main.dart` 恢复正式 Release，构建 88.1 秒成功；实际工作台观察 10 秒后正常关闭，退出码 0，DPI-aware 截图 1920×1200。
- **P2 尚未全部完成，整体性能验收仍失败。** 历史大跨度跳转的 UI P95 仍超过 16.667ms；没有降低门槛，也不能据此宣称发布就绪。

## 1. 最小生产修复

生产改动位于 `lib/presentation/chat/widgets/message_bubble.dart` 的 `_SpeakSemantics`：

1. 为消息动作节点提供短而稳定的角色标签：用户消息、助手回复、工具结果。
2. 设置 `container: true` 和 `explicitChildNodes: true`，不再把所有正文段落合并成同一个巨型语义标签。
3. 复制、重新生成、朗读／停止朗读等自定义语义动作保留；正文内容仍通过子节点可读。
4. 朗读状态变化仍只重建语义外壳，不重建 Markdown 正文。

红／绿回归证明：旧实现的动作节点标签包含 `NEXUS Agent` 及全部 40 个段落；新实现动作节点标签为“助手回复”，全部段落仍可读取，节点标签长度受到测试约束，动作回调与正文 widget 复用均通过。

`StreamingMarkdown` 稳定块缓存原本有效，最终保留 100 个稳定块、49986 字符及 14 字符尾部。没有保留“样式对象身份缓存”猜测性修改。选择分组试验 v16 没有收益，已完整撤回；`streaming_markdown.dart` 恢复至试验前相同内容哈希 `e7b69cd939193d25b69759df9b35df25efcbf2cead8c3555f6484de0350407a3`。

## 2. 可靠采样和门槛

相关实现：

- `tool/desktop_frame_pump.dart`：从新请求帧的 transient 阶段捕获引擎帧号和原始 vsync 时间，在该帧绘制后的回调完成；不复用上一个 `endOfFrame`。
- `tool/frame_timing_window.dart`：以 `(afterFrame, throughFrame]` 引擎帧号分窗、去重并排序，拒绝缺失或不足的样本，使用 nearest-rank／向上取整的百分位数。
- `tool/desktop_acceptance.dart`：等待覆盖窗口终点的 FrameTiming 批次；窗口外每 50ms 请求中性 drain 帧，用于排空最后一批回调，drain 帧不计入已完成场景。
- `tool/run-desktop-acceptance.ps1`：可选 `-BenchmarkForeground`，只作用于本次自有窗口，并记录前台请求及焦点丢失情况，结束时恢复 topmost 状态。默认行为不变。

完整原生场景：

| 场景 | 最低样本数 | 最终实际样本数 |
| --- | ---: | ---: |
| 仅输入更新对照 | 25 | 25 |
| 100 条历史：切换 + 35 次滚动跳转 | 36 | 36 |
| 1000 条历史：切换 + 35 次滚动跳转 | 36 | 36 |
| 5000 条历史：切换 + 35 次滚动跳转 | 36 | 36 |
| 5 万字符流式，100 次更新 | 100 | 100 |

门槛保持为：受控输入到帧 P95 ≤ 50000us；UI 和 raster 各自 P95 ≤ 16667us；历史切换首帧 ≤ 300000us。`functionalPassed`、`performancePassed` 和总体 `passed` 分开；总体通过必须包含性能通过。

记录的 build、raster、vsync overhead、total span、相邻帧间隔是不同指标。`jankAtDisplayRate` 统计 UI 或 raster 工作时长超出显示刷新预算的帧，不是原生呈现丢帧数。实际显示报告 240Hz，60Hz 参考门槛独立记录；通过参考门槛不代表达到 240fps。

早期 v11/v12/v13 报告保留用于诊断：分别暴露 99/100 新帧、批次排空等待以及动态 Map 汇总类型问题。完整比较以 v14 及以后、包含帧号边界和完整样本的报告为准，不能把早期异常报告当作正式通过结果。

## 3. 诊断对照

以下均为同机隔离 Release，流式场景 5 万字符、100 次更新。诊断变体显式标为 `diagnosticOnly: true`，不能成为正式性能通过结果。

| 变体与证据版本 | 输入到帧 P95（ms） | UI P95（ms） | 解释 |
| --- | ---: | ---: | --- |
| 真实消息列表，v14 | 193.195 | 6.056 | 修复前基线 |
| 直接增量 Markdown，v14 | 21.597 | 5.179 | 稳定块缓存并非主要瓶颈 |
| 整段普通 Text，v14 | 104.278 | 100.277 | 每次全量文本布局不是解决办法 |
| 单独 MessageBubble，v15 | 195.331 | 6.194 | 不依赖列表或高度弹簧也可复现 |
| 列表禁用动效，v15 | 184.355 | 6.222 | 动效不是主要原因 |
| 直接 Markdown + SelectionArea，v17 | 33.685 | 5.752 | 选择功能本身不产生约 200ms 等待 |
| MessageBubble 移除桌面扩展，v17 | 172.405 | 6.446 | 移除桌面选择外壳仍未解决 |
| MessageBubble 仅诊断排除语义，v17 | 37.876 | 6.632 | 额外等待集中于语义／原生无障碍路径 |

以上 A/B 与语义树回归支持巨型合并语义节点的判断；尚未通过原生 CPU profiler 指认某个具体 Windows UIA 函数。`ExcludeSemantics` 仅存在于隔离诊断变体，不用于生产修复。

## 4. 修复后的真实列表复验

以下全部为 `streamingVariant: chat`、`diagnosticOnly: false`、`semanticsEnabled: true`，均为 100 个完整流式样本：

| 运行 | 受控输入到帧 P95（ms） | UI P95（ms） | raster P95（ms） | 50ms 输入门槛 |
| --- | ---: | ---: | ---: | --- |
| PowerShell v18 | 47.655 | 7.489 | 1.541 | 通过 |
| PowerShell v18 repeat | 39.405 | 7.070 | 1.588 | 通过 |
| cmd v18 repeat | 39.805 | 7.091 | 1.519 | 通过 |

三次同步控制器／状态更新时间 P95 为 31–38us；不是把约 200ms 的时间移到同步更新统计之外。输入仅对照为约 5.5–16.4ms，说明调度环境有波动。全部保留 100 个稳定 Markdown 块。

原生功能：cmd 与 PowerShell 均完成中文输出、shell 状态保持、resize API、中断后续执行及临时目录释放；启动器均记录 freshReport、正常窗口退出、退出码 0、无子进程输出泄漏。日志缓冲、5 万行 diff 和 30 次组件切换检查也已完成。

### 仍未通过的历史 UI 门槛

| 修复后运行 | 100 条 UI P95（ms） | 1000 条 UI P95（ms） | 5000 条 UI P95（ms） |
| --- | ---: | ---: | ---: |
| PowerShell v18 | 19.467 | 47.996 | 40.166 |
| PowerShell repeat | 24.380 | 40.068 | 38.052 |
| cmd repeat | 28.366 | 33.433 | 37.764 |

这些场景都具有完整的 36 帧，不能再归因于“0 帧”或跨场景取样。各次切换首帧均小于 300ms，但滚动大跳转 UI P95 仍超 16.667ms，所以最终报告保持 `performancePassed: false`、`passed: false`。启动器因此返回 1，与应用进程正常退出码 0 并不矛盾。

## 5. 最终质量与正式入口恢复

串行执行，无并行 Flutter 测试／构建：

| 检查 | 结果 |
| --- | --- |
| 8 个相关 Dart 文件格式检查 | 0 改动 |
| Flutter analyze --no-pub | No issues found |
| 全量测试 + coverage | 1948 项全部通过 |
| 自编代码覆盖率／55% 门槛 | 65.57%，31526 / 48083，通过 |
| 包含生成代码的覆盖率 | 60.44%，35178 / 58205 |
| 未记录意图的空 catch／上限 0 | 0，通过；另有 111 处注释型有意忽略 |
| 全仓 diff --check | 退出码 0 |
| 显式 lib/main.dart Release 构建 | 88.1 秒，退出码 0 |
| 正式应用实际窗口烟测 | 观察 10 秒，窗口可见，正常退出 0 |
| DPI-aware 正式工作台截图 | 1920×1200，本机 150% 缩放，已人工查看 |

Git 检查曾进入交互分页器，已对自有命令软中断并发送 `q` 退出；没有强杀。另一次临时关闭 autocrlf 的检查把 CRLF 误报为逐行尾空白，未修改任何文件或持久 Git 配置；最终保留项目换行配置、禁用分页器的全仓检查通过。无需为这些误报批量转换换行。

未提交、推送、打包、签名或发布；未 reset／clean，原有脏工作区保持。

## 6. 证据文件与复验

所有证据均在 `artifacts/desktop/`：

- 基线：`p2-chat-v14.json`、`p2-chat-v14-launch.json`、`p2-chat-v14.log`。
- 最终原生复验：`p2-chat-v18*`、`p2-powershell-v18-repeat*`、`p2-cmd-v18-repeat*`。
- 诊断：`p2-{markdown,plain}-v14*`、`p2-{bubble,spring,chat-no-motion}-v15*`、`p2-chat-v16*`、`p2-{no-semantics,bubble-no-desktop,markdown-selection}-v17*`。
- 语义边界红／绿回归：`p2-semantic-boundary-red.log`、`p2-semantic-boundary-v18-tests.log`。
- 最终质量：`p2-final-{format,analyze,tests,coverage,silent-catches,diff-check}.log`。
- 正式入口：`p2-final-production-build.log`、`p2-final-production-smoke.log`、`p2-production-smoke.json`、`p2-production-main-window.png`。

测试入口：

- `test/frame_timing_window_test.dart`：帧后请求下一帧、帧号分窗、去重、空／不足样本、边界唯一归属、百分位数、预算失败。
- `test/streaming_markdown_incremental_test.dart`：增量扫描与稳定块复用，真实 MessageBubble 追加复用，跨段选择、复制、追加期间保持选择与鼠标拖选。
- `test/message_bubble_semantics_test.dart`：完整正文可读、动作节点有界、复制／重新生成／朗读动作及朗读状态切换保持正文复用。

Windows Bash 中复验时，继续串行使用项目的 Flutter SDK 和 `local/desktop-tools`。诊断变体通过单次启动环境变量 `MOBILE_AGENT_P2_VARIANT` 选择；默认 `chat`。任何 harness 构建完成后，结束前仍须显式重建 `--target lib/main.dart` 并运行正式烟测。当前 Release 已完成该恢复，不是 harness。

## 7. 下一步与验收边界

优先继续分析历史大跨度跳转时的首次可见气泡创建、Markdown 布局及分页窗口／缓存策略，保持相同 36 帧场景与 16.667ms 门槛，避免通过减少预渲染、空白占位或隐藏功能伪装通过。

本报告的输入指标是 **TextEditingController 更新到框架帧结束**，不是操作系统键盘事件到屏幕呈现的端到端延迟。前台请求试验被 Windows 拒绝，不能声称排除了焦点或遮挡影响；原生呈现时延也未独立测量。所有模型请求计数为 0，正式烟测只查看已有工作台，没有新发起模型任务。

仍待真实模型／设备、Narrator 或 NVDA 人工巡检、多 DPI、长期稳定性、安装／升级／回滚／签名等验收。不能把单机功能或流式子项通过等同于 P2 全部完成或可发布。

## 8. 历史滚动续优化：CPU 诊断、回切对照与共享选择区域

### 8.1 本次结论与保留改动

本次只完成历史滚动的一轮诊断和局部优化，**历史 P95 仍未达到 16.667ms，P2 整体性能验收继续失败**。

- 桌面 `ChatMessageList` 现在共享一个 `SelectionArea`；`MessageBubble` 优先使用继承的选择 registrar。独立气泡仍提供自己的选择区域，移动场景保持原样，已有父选择区域时不再嵌套。
- 保留完整 Markdown、语义节点、全部标准 Tooltip、复制／朗读／分享／重新生成、右键消息目标和移动端长按菜单。没有减少历史场景的 36 帧、400px 缓存、40／20 分页窗口，也没有关闭动画或用占位隐藏正文。
- 新增 5 项选择区域回归，覆盖区域数量、正文语义、Tooltip、跨消息复制、重建保持选择、真实鼠标拖选、右键目标、独立／继承／移动场景。
- 无收益的 Tooltip 延迟挂载试验已经回退，`DeferredTooltip` 及其试验测试均已移除；`micro_interactions.dart` 恢复到本次开始时的逐字版本。

### 8.2 Profile CPU 证据及解释边界

新增 `tool/desktop_cpu_profile.dart`、`test/desktop_cpu_profile_test.dart`，harness 记录每档历史窗口的原始 VM CPU samples 和摘要。启动器支持 `-BuildConfiguration Profile`，默认仍为 Release。

- 仅显式设置 `MOBILE_AGENT_P2_CPU_PROFILE=1` 且非 Release 时启用；启动当前进程的 loopback VM service，用 `setFlag profiler=true` 后调用正确的 `getCpuSamples`。
- Profile／CPU 诊断强制标记 `diagnosticOnly`，不能被算作 Release 性能验收。没有保存 VM service 认证 URL；原始样本文件用 Timeline 起点区分，避免同档数据被覆盖。
- v19 的 `getCpuProfile` RPC 不存在；v20 的 profiler 默认未开启。这两轮失败已纠正，不能当成有效 CPU 证据。
- v21 才是有效诊断：100／1000／5000 条分别取得 **241／295／303** 个 CPU 样本，UI P95 为 **37.136／39.678／40.276ms**。原始文件路径见报告各档的 `cpuProfile.rawFile`。
- 5000 档的 inclusive ticks 包含 mount 78、`OverlayPortalElement.mount` 63、`flushSemantics` 52、`TextPainter.layout` 37、unmount 33（总样本 303）。**它们互相重叠，不可相加；某祖先出现在调用栈中，不代表开销由祖先自身造成。** 最大栈深 128，另有 117 个 Truncated 样本，样本数量也有限，不能据此直接宣布某个组件是唯一瓶颈。
- Markdown 解析和 IntrinsicWidth 未在该轮主要栈中形成主导证据，因此没有实施猜测性的解析快路径或固定高度。

Tooltip 延迟挂载试验 v23 的 Release 历史 P95 为 24.400／45.147／37.580ms，与既有 24.380／40.068／38.052ms 相比没有可靠改善，故回退。这也否证了“OverlayPortal 的 inclusive 热点等于其自身成本主导”的最初假设。v22 还是语义隔离修正前的中间试验，不计入最终性能证据。试验期间的全量检查曾因新加的嵌套提示测试失败；后来补齐回归，但这套试验已整体删除，不能把该失败日志称作最终质量结果。

### 8.3 Release 原生回切对照

下表全部保留每档 **36 帧**；单位为毫秒。v25 是临时回切到本次优化前的生产气泡／列表源码再编译，随后恢复共享选择区域并编译 v26。不是拿 Profile 与 Release 混比。

| Release 运行 | 100 条 UI P95 | 1000 条 UI P95 | 5000 条 UI P95 | 流式受控输入 P95 |
| --- | ---: | ---: | ---: | ---: |
| v25 基线 first，PowerShell | 29.180 | 45.261 | 36.200 | 38.637 |
| v25 基线 repeat，PowerShell | 28.520 | 44.088 | 39.726 | 37.570 |
| v26 共享 first，PowerShell | 21.903 | 39.936 | 33.786 | 37.277 |
| v26 共享 repeat，PowerShell | 22.548 | 38.541 | 43.567 | 40.244 |
| v26 最终 PowerShell | 24.210 | 34.385 | 34.699 | 34.407 |
| v26 最终 cmd | 24.647 | 38.664 | 31.185 | 33.937 |

同为未获得前台的两轮回切对照中，100／1000 档有改善；**5000 档仍有 43.567ms 的较慢复测，不能声称所有规模均稳定改善**。前台环境也不是完全可控：回切四轮均全部采样失去前台，而最后 PowerShell／cmd 分别仅 1/32、1/28 个采样失去前台。因此最终较低数值只能如实列出，不能把全部变化归因于代码，也不能声称已排除遮挡、焦点或原生呈现因素。

最终 PowerShell／cmd：

- 历史 raster P95 分别为 1.177／1.125／1.294ms 和 1.085／1.321／1.108ms；切换首帧分别 16.189／16.277／37.597ms 和 16.790／18.509／35.932ms，均低于 300ms。
- 流式均完整采样 100 帧；UI／raster 分别 7.449／1.472ms 和 6.601／1.412ms。流式子门槛仍通过，受控输入 34.407／33.937ms 不是实际键盘到屏幕端到端延迟。
- 两种 shell 的本轮原生进程都正常退出 0，但报告 `passed=false`，原因仍为历史 UI 超预算。编排命令完成或进程正常退出不能替代性能门槛。
- 没有发起真实模型任务。真实设备、人工 Narrator／NVDA、多 DPI、长期稳定性与分发验收边界不变。

### 8.4 最终质量与正式入口恢复

| 检查 | 本次最终结果 |
| --- | --- |
| 全量 Flutter 测试含 coverage | **1956 项全部通过**，约 95 秒测试时间 |
| 全量 analyze | 0 问题 |
| 本次 6 个 Dart 文件格式检查 | 0 改动 |
| 自编代码覆盖率 | **65.60%（31543 / 48087）**，高于 55% 门槛 |
| 含生成代码覆盖率 | 60.46%（35195 / 58209） |
| 未记录意图的空 catch | 0；已记录意图 111 |
| 全仓 diff --check | 退出码 0 |
| 显式 `--target lib/main.dart` Release | **88.0 秒，退出码 0** |
| 正式应用烟测 | PID 13032，观察 10 秒，窗口可见，正常退出 0 |
| DPI-aware 正式工作台截图 | 1920×1200，已查看确认为实际工作台，不是 harness |

额外执行的全仓 `dart format --output=none --set-exit-if-changed lib test tool` 审计发现 **737 个文件中 141 个（均在本次 6 文件以外）存在格式差异**。该命令没有写文件；未批量改动其他既有工作，不应称作“全仓格式检查通过”。本次范围内的 6 文件格式门槛单独通过。CMake 仍打印第三方 `webview_windows` 的 CMP0175 开发警告，没有阻止构建。

当前 `Release/mobile_agent.exe` 已再次恢复为正式 `lib/main.dart`；Profile 目录保留诊断 harness，不是交付入口。无运行中的本轮验收／构建进程。未提交、推送、签名、发布、reset 或 clean，原有脏工作区保留。

本次证据均位于 `artifacts/desktop/`：

- 有效 CPU：`p2-history-v21-profile.json` 及其中引用的原始 CPU JSON；错误定位日志 `p2-history-v19*`、`p2-history-v20*`。
- 已回退 Tooltip 试验：`p2-history-v22-release.json`、`p2-history-v23-release*`。
- 共享选择区域初测：`p2-history-v24-release*`、`p2-history-v24-repeat*`。
- 正式回切对照：`p2-history-v25-baseline-{first,repeat}*`、`p2-history-v26-shared-{first,repeat}*`。
- 最终两种 shell：`p2-history-v26-{powershell,cmd}-final*`；各启动记录中的退出状态与前台采样必须一起阅读。
- 最终质量：`p2-history-final-{tests,format,analyze,coverage,silent-catches,diff-check}.log`；全仓格式存量审计另见 `p2-history-repository-format-audit.log`。
- 正式入口：`p2-history-final-production-{build,smoke}.log`、`p2-history-production-smoke.json`、`p2-history-production-main-window.png`。

下一步应优先锁定 5000 条场景波动：控制前台条件，增加诊断重复窗口并按 mount／layout／semantics 的 exclusive CPU 与分配来源归因，再考虑有界复用或 sliver 索引映射；不要仅凭 inclusive 栈继续猜测 Markdown／Tooltip，也不要用全量保活或降低样本门槛掩盖开销。所有历史档均超参考预算，**P2 不能标记为整体完成或可发布**。
