# NEXUS Agent — UI 改进交接文档

> **用途**：把当前项目状态、待解决的 UI 问题、实施方案和约束整理成一份自包含文档，
> 供另一个 GPT 会话直接接手实施，无需回溯历史对话。
>
> **适用对象**：接下来要执行 UI 改进的 AI 助手 / 开发者。
>
> **阅读顺序**：第 0 节 → 第 3 节（架构不变量，必读）→ 第 5 节（问题清单）→ 第 6 节（实施方案）→ 第 7 节（坑）。

---

## 0. 30 秒速览

| 项 | 状态 |
|---|---|
| 项目 | NEXUS Agent — Flutter / Dart，**仅 Android** 的移动端 AI Agent 客户端 |
| 代码基线 | `flutter analyze` 零问题；`flutter test` **888 项全通过**；覆盖率 **51.65%**（门槛 48.5%） |
| 最新产物 | `build/app/outputs/flutter-apk/app-debug.apk`（120,863,034 bytes，arm64 Debug） |
| 已完成 | 阶段 A（A1/A2/A3）、阶段 B（B1/B2/B3）、阶段 C 的 C1 / C2 / **C3** |
| **下一步** | **C4：未配置 Provider 时在输入区上方常驻引导条**（详见第 6 节） |
| 工作树 | `main` 上有大量未提交 WIP，**不要执行 `git clean -fd` / `git reset --hard`** |

**如果只做一件事**：做 **C4**，然后跑第 9 节的真机验证清单——功能侧已就绪，剩下的风险
都在真机行为（预算提示可信度、压缩可见性、大字溢出）。

---

## 1. 项目与验证基线

### 1.1 技术栈

- Flutter / Dart，Android-only（`Platform.isAndroid` 有专门分支）
- 状态管理：Riverpod（`NotifierProvider`）
- 存储：Drift / SQLite（schema version **24，已冻结，不要新增表**）
- 网络：Dio（SSE 流式，流式请求不自动重试）
- 其它：secure storage、MCP、Android 前台服务、WorkManager、TTS、Sentry

### 1.2 分层约定

```
domain         纯模型与不变量（models.dart / context_insights.dart）
application    用例与编排（agent_executor / chat_controller / context_* / prompt_budget）
infrastructure  provider、工具、数据库、技能
presentation    UI（chat / dashboard / settings / terminal / workspace ...）
```

**规则**：`presentation` 不直接碰 `infrastructure` 细节；预算计算只在 `domain` + `application`，
UI 只消费 `ContextSnapshot` / `ContextCompressionPlan` 这类数据对象。

### 1.3 最近一次验证结果（基线，不要退回）

```text
flutter analyze --no-pub        → No issues found
flutter test --no-pub           → 888 tests passed
flutter test --coverage         → 51.65%（含生成代码）/ 56.73%（自研代码）
check_coverage 48.5             → 通过
flutter build apk --debug --target-platform android-arm64 → 成功
```

APK 摘要（C3 完成后重建）：

```text
路径    build/app/outputs/flutter-apk/app-debug.apk
大小    120,863,034 bytes
SHA-256 A7EC5830765B4C78B42DBCE675CDE025B72D82E2F3E09B46ADFB8AC28A180C19
已确认包含 lib/arm64-v8a/libsuper_native_extensions.so
```

---

## 2. 环境与常用命令

```powershell
# 日常回归（改完必跑，顺序固定）
dart format <changed dart files>
flutter analyze --no-pub
flutter test --no-pub
flutter test --coverage --no-pub
dart run tool/check_coverage.dart coverage/lcov.info 48.5

# 构建
flutter build apk --debug --target-platform android-arm64

# 真机
adb devices -l
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell monkey -p com.nexusagent.app 1
adb logcat -c ; adb logcat
```

> Windows 环境，注意 CRLF：`git diff --check` 会刷一堆 "LF will be replaced by CRLF" 警告，属正常现象。

---

## 3. 必须先理解的架构不变量

### 3.1 上下文预算语义（最重要，改 UI 前必须懂）

```
总模型窗口 (contextWindow)  =  输入 tokens  +  预留输出 tokens (reservedOutputTokens)
输入预算 (inputBudget)     =  总模型窗口  -  预留输出 tokens
输入 tokens                =  系统消息 + 历史消息 + 工具定义 + 注入内容
```

关键实现点：

- `ContextBudget`（`lib/domain/context_insights.dart`）
  - `outputReservationFor({contextWindow, requestedOutputTokens})`：把请求的输出 token 夹取到窗口内
  - `inputBudgetFor({contextWindow, reservedOutputTokens})`：`window - reserve`，不小于 0
  - `ratioFor / levelFor`：**分子是 `usedTokens + reservedOutputTokens`**，分母是总窗口
  - 阈值：`0.70 attention` / `0.85 warning` / `0.95 critical`
  - `contextWindow <= 0` 视为未知，返回 `normal` / 比例 0（不要报错）
- `ContextWindow`（`lib/application/context_window.dart`）
  - 构造函数：`ContextWindow({maxTokens, fixedTokens, maxToolResultChars, ...})`
  - `fixedTokens` = 序列化工具定义成本，**与消息 token 一起计入同一输入预算**
  - `apply()` 顺序：系统消息始终保留 → 单条裁剪 → 从最新向前累加到预算 → 截断点只落在 user 消息 → 真的丢弃过历史才插入 `compactionNotice`（不重复插）
- `AgentExecutor.run()`（`lib/application/agent_executor.dart`，约 112~128 行）
  ```dart
  final fixedToolTokens = ContextSnapshotBuilder.estimateToolTokens(requestTools);
  final reservedOutputTokens = ContextBudget.outputReservationFor(
    contextWindow: contextBudgetTokens, requestedOutputTokens: maxTokens);
  final inputBudget = ContextBudget.inputBudgetFor(
    contextWindow: contextBudgetTokens, reservedOutputTokens: reservedOutputTokens);
  final contextWindow = ContextWindow(maxTokens: inputBudget, fixedTokens: fixedToolTokens);
  ```
  每步请求顺序（约 169~199 行，**顺序有意义，不要调换**）：
  ```
  drainCompressionToolCallIds() → ContextCompressionApplier → contextWindow.apply(messages)
  → UnifiedRequest(maxTokens: reservedOutputTokens) → ContextSnapshotBuilder.build(...)
  ```
- `ProviderConfig.contextTokens` 表示**总模型窗口**，不是历史消息预算。
- `ContextSnapshot.remainingTokens` = `contextWindow - usedTokens - reservedOutputTokens`（下限 0），
  含义是"扣掉预留输出后还能用多少"。

### 3.2 压缩链路（用户可审查、非破坏）

```
SessionMetricsSheet(planner) → ChatController.approveContextCompression(plan)
  → AgentRunController.queueCompression(ids) → AgentExecutor.drainCompressionToolCallIds()
  → ContextCompressionApplier.applyToolCallIds() → AgentContextCompressionEvent
  → chat_run_execution 记录 RunEvent(type: 'context_compress')
```

约束（改相关 UI 时必须保持）：

- 只压缩 `role == tool` 且 `toolCallId` 非空的消息；
- 用户消息 / 助手消息永不作为候选；
- `applyToolCallIds` 会校验 role + index + toolCallId，陈旧候选直接忽略；
- 压缩只影响**发给模型的上下文**，不改用户可见的会话历史内容；
- 压缩后的 tool 消息文本含 `ContextWindow.compressedToolResultMark`（这是 A2 的判定依据）；
- `RunEvent` 元数据含 candidateCount / estimatedSavedTokens / originalTokens / compressedTokens。

### 3.3 上下文历史加载策略（性能相关，别改坏）

- 会话切换只恢复**最新一轮** `ContextSnapshot`（`ContextInsightsHistory.latestForConversation`）；
- 完整历史 run 列表只在打开指标面板时按需加载（`loadContextRuns`）；
- 空历史会被缓存；有新 run 或切换会话时用 revision 失效；
- 异步回写有 `conversationId` + revision 双重校验，防止跨会话污染。

---

## 4. 相关文件地图

| 文件 | 行数 | 职责 |
|---|---|---|
| `lib/presentation/chat/chat_page.dart` | **3396** | 聊天主页（过大，见 P1-2） |
| `lib/presentation/chat/widgets/session_metrics_sheet.dart` | **1575** | 会话指标面板，6 个 tab（总览/步骤/浏览器/事件/文件/网络） |
| `lib/presentation/chat/widgets/session_metrics_bar.dart` | 209 | HUD 一行指标条 |
| `lib/presentation/chat/widgets/session_context_sheet.dart` | 188 | 会话上下文面板（与上面职责重叠，见 P1-3） |
| `lib/presentation/chat/widgets/chat_message_list.dart` | 291 | 消息列表，已用 `ListView.builder` + `ScrollCacheExtent.pixels(400)` + `addAutomaticKeepAlives: false` |
| `lib/presentation/chat/widgets/message_bubble.dart` | 835 | 消息气泡（富文本路径） |
| `lib/presentation/chat/widgets/tool_activity_section.dart` | 489 | 工具活动时间线（A2 改这里） |
| `lib/presentation/chat/widgets/plan_panel.dart` | 682 | 计划面板 |
| `lib/presentation/chat/widgets/tool_approval_sheet.dart` | 599 | 工具审批 |
| `lib/presentation/chat/widgets/chat_catalog_drawer.dart` | 782 | 侧边会话抽屉 |
| `lib/presentation/dashboard/widgets/token_usage_hero.dart` | 481 | 仪表盘 Token 主视觉 |
| `lib/presentation/dashboard/widgets/token_trend_card.dart` | 215 | 仪表盘 Token 趋势 |
| `lib/presentation/dashboard/widgets/token_numbers.dart` | 61 | 仪表盘 Token 数字 |
| `lib/domain/context_insights.dart` | 388 | `ContextBudget` / `ContextSnapshot` / `ContextPart` |
| `lib/application/context_window.dart` | 258 | 预算裁剪 + token 估算 |
| `lib/application/context_compression_planner.dart` | 152 | 压缩候选规划（数据 only） |
| `lib/application/context_compression_applier.dart` | 118 | 压缩执行 |
| `lib/application/context_snapshot_builder.dart` | 171 | 请求级快照拆分 |
| `lib/application/agent_executor.dart` | 788 | Agent 主循环 |
| `lib/application/chat_controller.dart` | 3031 | 聊天状态与编排 |
| `lib/application/chat_run_execution.dart` | 1341 | 单次运行执行体（`part of`） |
| `lib/application/prompt_budget.dart` | 115 | 项目上下文预算分配 |

`session_metrics_sheet.dart` 内关键符号（行号为近似值，改前用搜索确认）：

- `showSessionMetricsSheet(...)` / `SessionMetricsSheet`（顶部，已收 `reservedOutputTokens` 参数）
- `_ContextCapacity`（约 892）：当前上下文大字 + 百分比 + `_ContextBar`
- `_ContextBrowserTab`（约 578）：上下文浏览器 tab
- `_StepsTab`（约 405）+ `_ContextTrend`（约 479）：步骤趋势
- `_CompressionSuggestion`：压缩建议卡
- `_ContextBar`（约 1471）：**A1 的核心**
- `_ContextBar` 共有 5 个调用点（约 467 / 508 / 619 / 956 / 1471 定义处）

---

## 5. 问题清单

### P0 — 正确性缺陷（用户会不信任产品）

#### P0-1 上下文进度条把"输出预留"当成空闲空间

`_ContextBar`（`session_metrics_sheet.dart` 约 1471）当前逻辑：

```dart
final total = parts.fold<int>(0, (sum, part) => sum + part.tokens);
final reserve = math.max(0, limit - total);   // ← 预留输出被算进"剩余空闲"
```

**后果**：窗口 32k、预留输出 2k、输入已用 20k 时，UI 显示 62% + "还剩 11k"，
但那 2k 不可用；预算等级文字（已含预留）和进度条（不含预留）**互相矛盾**。

#### P0-2 压缩生效后用户侧没有任何视觉反馈

`ContextCompressionApplier` 只改发给模型的上下文。`tool_activity_section` 的工具卡片仍显示完整结果。

**后果**：用户点"批准压缩"后看不到任何变化，会认为功能失灵并重复点击。
这是"用户可审查的压缩"闭环上最大缺口。

#### P0-3 遥测面板不可交互

`_StepRow` / `_RunSelector` 只能看不能跳。

**后果**："哪一步把上下文顶爆了"无法定位，遥测价值减半。

### P1 — 结构问题（现在改最便宜）

| # | 问题 | 证据 |
|---|---|---|
| P1-1 | 同一指标三套实现、四种命名 | `session_metrics_bar`(209) / `session_context_sheet`(188) / `session_metrics_sheet`(1575) / dashboard 三件套(481+215+61)；Token 可视化出现多种算法与配色 |
| P1-2 | `chat_page.dart` 3396 行单文件 | 单个 `build` 内塞指标条、上下文提示、技能槽、执行状态条 |
| P1-3 | 大消息渲染路径未全部懒加载 | `reasoning_block` 已做"展开才构建"，`message_bubble`(835) / `plan_panel`(682) / `tool_approval_sheet`(599) 的富文本仍是全量构建 |

### P2 — 体验与无障碍

| # | 问题 | 证据 |
|---|---|---|
| P2-1 | 无障碍覆盖不全 | chat 目录仅 30 处 `Semantics`、31 处 `Tooltip`；textScale 溢出守护测试只覆盖 `EmptyStateView` / `ProviderListPage` |
| P2-2 | 会话切换无 pending 态 | `switchConversation()` 有 4~5 个连续 await，期间界面"旧内容突变新内容" |
| P2-3 | 压缩决策路径过长 | 需 打开面板 → 切 tab → 找建议 → 批准，共 4 步 |
| P2-4 | 未配置 Provider 要等运行失败才提示 | 无输入区常驻引导 |

---

## 6. 解决方案与实施计划

**总原则**：A（正确性）→ B（结构）→ C（体验）。每阶段独立可发布、可回滚；
每完成一项跑一次 `analyze` + 相关测试，不要攒到最后。

---

### 阶段 A：修复正确性（P0）

#### A1 上下文进度条三段式

**目标**：让"已用输入 / 输出预留 / 真正剩余"在视觉上可区分，且与预算等级文字一致。

**步骤**：

1. `_ContextBar` 新增参数 `int reservedOutputTokens = 0`，渲染顺序：

   ```
   [各 ContextPart 分段] → [输出预留段] → [真正剩余]
   ```

   - 预留段：`surfaceContainerHighest` 底色 + 1px `outlineVariant` 描边（与"剩余"区分）
   - 预留段 `flex = reservedOutputTokens`，为 0 时自动省略
   - **必须 clamp**：`reserve = max(0, limit - total - reserved)`，避免负 flex 抛异常
2. 5 个调用点全部传值：
   - `_StepsTab`（约 467）：传 `snapshot.reservedOutputTokens`
   - `_ContextTrend`（约 508）：趋势图 `limit = usedTokens`，预留为 0，走省略分支
   - `_ContextBrowserTab`（约 619）：传 `reservedOutputTokens`
   - `_ContextCapacity`（约 956）：传 `effectiveReservedOutput`
3. `_ContextCapacity` 文案：`/ 32k tok` → `/ 输入上限 30k tok`，下方加小字 `含输出预留 ≈2k tok`；
   百分比改用 `ContextBudget.ratioFor(..., reservedOutputTokens:)`（该处已改，确认一致）。
4. 图例区追加一行"输出预留"。

**涉及文件**：`lib/presentation/chat/widgets/session_metrics_sheet.dart`
**验收**：构造 `usedTokens=20000, reservedOutputTokens=2048, contextWindow=32000`，
预留段可见、图例有"输出预留 ≈2k"、百分比为 69%（不是 62%）；`reservedOutputTokens=0` 时与旧行为一致。
**测试**：在 `test/session_metrics_sheet_test.dart` 加一个用例（该文件已有 40+ 项可参照）。
**风险**：低，纯展示层。

#### A2 压缩视觉闭环

**目标**：批准压缩后，用户立即看到工具结果卡标记"已压缩"，可展开原文。

**步骤**：

1. `ToolActivity`（`chat_controller.dart` 约 77 行起）新增字段：
   `final bool compressed;` + `final String? originalResult;`，同步更新构造函数与 `copyWith`
   （现有参数：`status / result / ok / code / effect`）。
2. `_updateToolActivity`（约 2953 行）支持这两个字段。
3. `chat_run_execution.dart` 的 `AgentContextCompressionEvent` 分支（约 522 行）：
   目前只写 RunEvent，需增加——按 `toolCallId` 把对应 activity 置 `compressed: true`，
   原结果存入 `originalResult`（注意 `visible()` / `ownsRun()` 守卫，沿用现有模式）。
4. `tool_activity_section.dart`：卡片加"已压缩"徽标，点击展开 `originalResult`。
5. 恢复路径自洽（**不加表、不改 schema**）：`_restoreFromMessages` 里，
   tool 消息文本含 `ContextWindow.compressedToolResultMark` 时同样置 `compressed: true`。
   这样重启后标记不丢。

**涉及文件**：`lib/application/chat_controller.dart`、`lib/application/chat_run_execution.dart`、
`lib/presentation/chat/widgets/tool_activity_section.dart`
**验收**：批准压缩 → 卡片立即出现徽标且可展开原文；杀进程重进该会话 → 徽标仍在；
未压缩的卡片无任何变化；`ToolActivity` 相关既有测试不回归。
**风险**：中低。注意 `ToolActivity` 若参与序列化/落库，新字段必须可空或有默认值。

#### A3 遥测可跳转

**目标**：点指标面板的某一步，消息列表定位到对应消息。

**步骤**：

1. `ContextStepRecord`（`context_insights.dart`）新增可选 `final String? anchorMessageId;`
   （该步请求前的最后一条消息 id），`toJson()` 带上字段。
2. `context_insights_history.dart` 的 `_snapshotRecord` 解析时容错：旧记录无该字段 → `null`。
3. `AgentExecutor` 发 `ContextSnapshotEvent` 时带上锚点（该步 `messages` 里最后一条非 system 消息 id；
   若没有则 null）。
4. `_StepRow` / `_RunSelector` 支持点击：有锚点 → 回调 `onJumpToMessage(anchorMessageId)`；
   无锚点 → 退化为"滚到最新"。
5. `chat_page.dart` 实现 `onJumpToMessage`：在 `state.messages` 中按 id 找 index，
   找不到则滚到底部；复用 `chat_message_list` 的 `ScrollController`。
6. `showSessionMetricsSheet` 增加该回调参数（可选，默认 null → 不显示跳转）。

**涉及文件**：`lib/domain/context_insights.dart`、`lib/application/context_insights_history.dart`、
`lib/application/agent_executor.dart`、`lib/presentation/chat/widgets/session_metrics_sheet.dart`、
`lib/presentation/chat/chat_page.dart`
**验收**：点第 N 步 → 列表定位到该步消息；历史运行（无锚点）不崩溃且退化合理；
`test/context_insights_history_test.dart` 既有用例不回归（旧 JSON 无新字段）。
**风险**：低。字段可选，向后兼容。

---

### 阶段 B：结构治理（P1）

#### B1 抽出共享预算条组件

把 A1 完成的三段式条提为 `lib/presentation/chat/widgets/context_budget_bar.dart`，
供 HUD、指标面板、仪表盘复用；`_contextColor` / `_contextBudgetColor` 上收到 theme 层
（现在散落在 `session_metrics_sheet.dart` 内）。

**收益**：同一指标一种算法、一种配色。后续再改预算语义只改一处。

#### B2 拆分 `chat_page.dart`（3396 行）

按现有 `_build*` 边界抽文件，**先抽后删，分 4 次小步**，每步跑 analyze + test：

| 抽出 | 目标 | 说明 |
|---|---|---|
| `_buildSessionMetricsBar` | 并入 `widgets/session_metrics_bar.dart` | ~250 行 |
| `_buildContextCompressionHint` | 新建 `widgets/context_budget_hint.dart` | ~120 行 |
| `_buildSkillPromptSlot` | 并入 `widgets/composer_skill_slot.dart` | ~150 行 |
| 执行状态条 | 并入 `widgets/chat_execution_stage.dart` | ~100 行 |

**必须遵守的性能约定**（`chat_page.dart` 约 2478~2480 行有注释）：
高频变化的 `liveReply` **不能**在主 build 里订阅，必须下沉到只包裹消息列表的 `Consumer`，
否则每次流式增量都会带着输入胶囊 / 指标条 / 顶栏重建。拆分时保持 `ref.watch(...select...)` 的粒度不变。

#### B3 统一四层命名与职责

| 层 | 唯一组件 | 职责 |
|---|---|---|
| 一行 HUD | `SessionMetricsBar` | 总量 + 预算等级，点击进面板 |
| 会话上下文 | 合并进 `SessionMetricsSheet` | 当前会话请求级明细 |
| 会话指标 | `SessionMetricsSheet`（6 tab） | 遥测 / 历史 / 事件 |
| 跨会话统计 | 仪表盘三件套 | 今日 / 趋势 |

`session_context_sheet.dart`（188 行）评估合并或明确差异定位，消除"该点哪个"的困惑。

---

### 阶段 C：体验补强（P2）

| # | 项 | 做法 | 状态 |
|---|---|---|---|
| C1 | 无障碍 | 图标-only 按钮（模式磁贴、审批磁贴、发送/附件、返回最新）补 `semanticsLabel`；把 chat 主列 + metrics sheet 加入 `ui_refactor_regression_test.dart` 的 `360x800 + textScale 1.3` 溢出守护 | ✅ 已完成 |
| C2 | 会话切换骨架屏 | `switchConversation` / `newConversation` 期间显示"正在恢复会话…"骨架 | ✅ 已完成 |
| C3 | HUD 快捷压缩 | `ContextBudgetLevel.warning` 以上时 HUD 条直接出"压缩上下文"按钮，弹确认（列出预计节省 token），从 4 步降到 2 步 | ✅ 已完成（见下） |
| C4 | 未配置 Provider 引导 | 输入区上方常驻可关闭引导条，直达设置；配置完成后自动消失 | ⬜ 待做 |

#### C3 实现记录（已完成，不要重做）

**关键设计决策（最容易做错的地方）**：快捷入口放在 **`SessionMetricsHud`**，而不是
`ContextBudgetHint`。原因：

```
approveContextCompression() 要求 state.running == true
ContextBudgetHint 在 running == true 时自我隐藏
→ 两者互斥：把入口挂在 ContextBudgetHint 上，用户永远点不到
```

`SessionMetricsHud`（运行期间可见的那条指标条）才是正确落点。

改动的文件与内容：

| 文件 | 改动 |
|---|---|
| `lib/application/context_compression_planner.dart` | 新增 `ToolResultRef`（中立值类型：toolCallId + result）与 `planForConversation({messages, liveToolResults, contextWindow, fixedTokens, reservedOutputTokens, targetTokens})`；把「消息 + 运行时工具结果」的合并与去重集中到 planner |
| `lib/presentation/chat/widgets/session_metrics_sheet.dart` | 原来的内联合并逻辑改为调用 `planForConversation`，两个入口共用同一候选集 |
| `lib/presentation/chat/widgets/session_metrics_bar.dart` | `SessionMetricsHud` / `SessionMetricsBar` 新增 `onCompress`；`_compressLevel()` 只在 `warning` / `critical` 返回非空；新增 `_CompressAction` 胶囊（`Semantics(button, label: '压缩上下文')` + Tooltip，自带 InkWell 抢点击） |
| `lib/presentation/chat/chat_page.dart` | 新增 `_requestContextCompression()`：构造 plan → `showConfirmAction` 列出「当前输入 / 预计节省 / 压缩后 / 目标」→ `approveContextCompression`；HUD 调用处传 `onCompress: running ? _requestContextCompression : null` |

新增测试：

```text
test/session_metrics_hud_compress_test.dart   6 项：warning/critical 出现、normal 不出现、
                                              无回调/无快照不出现、点击真回调、360x800+1.3 不溢出
test/context_compression_planner_test.dart    新增 planForConversation 组 3 项：
                                              合入运行时结果、同 toolCallId 不重复计数、忽略空白结果
```

**设计约束（后续维护别破坏）**：

- 入口只在 `warning` / `critical` 出现——`attention` / `normal` 下不占位，避免"永远点不动的操作"；
- `_CompressAction` 必须自带 `InkWell`，否则会同时触发外层"打开指标面板"的 onTap；
- 确认文案必须说明"只影响发给模型的上下文，聊天记录保持不变"——这是用户敢点的前提。

---

## 7. 实施注意事项（坑）

1. **不要动数据库 schema**（version 24）。上下文遥测走既有 `RunEvents`，不新增表。
   A2/A3 的新字段要么可选、要么运行时派生。
2. **`ProviderConfig.contextTokens` 是总窗口**，不是历史消息预算；别在 UI 里把它当"输入上限"直接除。
   要显示输入上限，用 `ContextBudget.inputBudgetFor(...)`。
3. **压缩只影响模型上下文**，不要改用户可见的会话历史文本；A2 只是加标记，不是替换内容。
4. **`AgentExecutor` 每步顺序有意义**（3.1 节）：压缩 → 裁剪 → 建请求 → 建快照。不要为了"优化"调换。
5. **`chat_page.dart` 的订阅粒度**是流式性能的关键（见 B2），拆分时不要顺手把 `liveReply` 提上去。
6. **测试异步初始化**用 `await pumpEventQueue()` 等 `loading == false`（见 `chat_controller_test.dart`）。
7. **Drift "multiple databases" 警告**在测试里是既有现象，不是回归，别去"修"它。
8. **`super_native_extensions` / `link.exe` 警告**：本机缺 Windows MSVC linker，
   Rust 构建脚本编译失败，但 Gradle 复用预编译 `.so` 仍能产出可用 APK。
   影响：换机器 / `flutter clean` 后可能真失败；高级剪贴板能力未验证。
   当前源码只用 Flutter 自带 `Clipboard.setData`，普通复制不受影响。**不要在文档外的时间花在这上面**，
   正式 Release 前装 Visual Studio Build Tools（C++ 工作负载 + MSVC + Windows SDK）再重建即可。
9. **Git 卫生**：`main` 有大量未提交 WIP；根目录 `smoke_*.png` / `fixed_*.png` / `final_agent_*.png`
   是真机证据，已加入 `.gitignore`，**不要删除、不要 `git clean -fd`、不要 `git reset --hard`**。
10. **覆盖率门槛 48.5%**（当前 51.30%）。新增 UI 组件一律配 widget 测试，否则会把覆盖率拉低。

---

## 8. 测试策略与回归命令

### 必跑（每个阶段结束）

```powershell
dart format <changed dart files>
flutter analyze --no-pub
flutter test --no-pub
flutter test --coverage --no-pub
dart run tool/check_coverage.dart coverage/lcov.info 48.5
```

### 新测试要求

| 改动 | 需要的测试 |
|---|---|
| A1 | `session_metrics_sheet_test.dart`：预留段渲染 + 图例 + 百分比；`reservedOutputTokens=0` 退化 |
| A2 | controller 测试：压缩事件 → activity 标记；恢复路径标记；未压缩不变 |
| A3 | `context_insights_history_test.dart`：旧 JSON 无 `anchorMessageId` 不崩 |
| B1/B2 | 拆分后的组件 widget 测试 + chat_page 既有测试不回归 |
| C1 | textScale 1.3 溢出守护 |
| C2 | 会话恢复骨架屏渲染 + `restoringConversation` 生命周期 |
| C3 | `session_metrics_hud_compress_test.dart`：warning/critical 出现、normal 不出现、无回调/无快照不出现、点击真回调、大字不溢出；`context_compression_planner_test.dart` 的 `planForConversation` 组：合入运行时结果 / 同 toolCallId 不重复计数 / 忽略空白结果 |
| C4 | 未配置 Provider 时引导条出现、配置后消失、点击能进设置 |

### 相关既有测试文件

```text
test/session_metrics_sheet_test.dart          指标面板（40+ 项）
test/context_insights_test.dart               预算阈值与快照语义
test/context_window_test.dart                 裁剪与固定 token
test/context_compression_planner_test.dart    压缩候选
test/context_compression_applier_test.dart    压缩执行
test/context_snapshot_builder_test.dart       快照拆分
test/context_insights_history_test.dart       历史遥测解析
test/chat_controller_test.dart                会话/初始化/切换
test/agent_executor_test.dart                 Agent 主循环（含压缩链路）
test/run_controller_test.dart                 压缩队列生命周期
test/ui_refactor_regression_test.dart         布局/触摸目标/textScale 守护
```

---

## 9. 真机验证清单

装 APK 后按序验证（覆盖上述所有风险点）：

- [ ] 长会话滚到底部是否掉帧；"回到最新"按钮是否出现
- [ ] 打开会话指标：**确认"输出预留"是否被当成空闲**（修复前会，属待修项）
- [ ] 触发一次工具调用 → 批准压缩 → **观察工具卡片是否有"已压缩"标记**（修复前无，属待修项）
- [ ] 点指标面板某一步 → 是否定位到对应消息（A3 后）
- [ ] 切到无 Agent 的老会话 → 顶部是否残留上一个 Agent 的名称/系统提示词（代码已修，需确认）
- [ ] 系统字体放大到 1.3 → 聊天主列与指标面板是否溢出
- [ ] 深色模式 + Liquid Glass 三档 → 指标面板可读性
- [ ] 杀进程重进 → 压缩标记、上下文快照是否保持
- [ ] 网络断开 / 取消 / 重启后的任务恢复
- [ ] 超大工具结果、超长参数、多工具调用

```powershell
adb logcat -c
adb logcat | findstr /i "UnsatisfiedLinkError dlopen No implementation found"
```

---

## 10. 范围控制（明确不要做）

- 不改 `domain` 层语义与数据库 schema（保持 version 24）
- 不重构配色 / 字体体系，只把散落常量上收
- 不引入新依赖
- 不做"重新设计视觉风格"——当前 Liquid Glass + 双轨字号已成体系，只修一致性
- 不要顺手"优化" `AgentExecutor` 的步骤顺序、`ContextWindow` 的裁剪算法
- 不要删除真机截图或执行破坏性 git 命令

---

## 11. 近期已完成工作记录（避免重复）

以下已完成并通过验证，**不要重做**：

**阶段 A（正确性）**

- A1：`ContextBudgetBar` 三段式（已用输入 / 输出预留 / 真正剩余），5 个调用点全部传
  `reservedOutputTokens`；`_ContextCapacity` 标题改为输入上限口径
- A2：`ToolActivity.compressed` + `originalResult`；`tool_activity_section.dart` L266 有"已压缩"
  徽标，L400+ 可展开原文；恢复路径靠 `compressedToolResultMark` 判定，未加表、未改 schema
- A3：`ContextStepRecord.anchorMessageId`（可选字段，旧 JSON 容错为 null）+ 指标面板
  `onJumpToMessage` → 消息列表定位；无锚点退化为滚到底部

**阶段 B（结构）**

- B1：`context_budget_bar.dart` 抽出，HUD / 指标面板共用；`contextBudgetColor` 上收
- B2：`chat_page.dart` 从 3396 行降到约 3235 行；`context_budget_hint.dart`、
  `chat_execution_stage.dart`、`composer_skill_slot.dart` 抽出；`liveReply` 订阅粒度未变
- B3：`session_context_sheet.dart` → `session_configuration_sheet.dart`，职责重新定位

**阶段 C**

- C1：图标-only 按钮补 `semanticsLabel`；`ui_refactor_regression_test.dart` 增加
  chat 主列 + metrics sheet 的 `360x800 + textScale 1.3` 溢出守护
- C2：`conversation_restore_skeleton.dart` + `ChatState.restoringConversation`，
  会话切换 / 新建期间显示骨架屏
- C3：HUD 快捷压缩入口（详见第 6 节「C3 实现记录」）

**更早的上下文预算重构**

- `ContextBudget` 引入 `outputReservationFor` / `inputBudgetFor`，`ratioFor` / `levelFor`
  支持 `reservedOutputTokens`；`ContextSnapshot.ratio / budgetLevel / remainingTokens` 同步
- `ContextWindow` 新增 `fixedTokens`（工具定义成本），计入输入预算；避免重复插入压缩告示
- `AgentExecutor` 夹取输出预留、从输入预算扣除、请求下发夹取后的值
- `PromptBudgetAllocator` 改用 `ContextSnapshotBuilder.estimateToolTokens` 与同一夹取规则
- 压缩 planner 携带 `reservedOutputTokens`，拒绝无 `toolCallId` 的候选
- `ChatState.contextReservedOutputTokens`（默认 2048）及初始化/切换/选择 Agent 的填充
- `AgentExecutor` 中压缩先于历史裁剪执行
- `AgentRunController` 压缩队列（queue / drain / cancel / seal）+ 生命周期测试
- 普通会话切换 / 新建时清理旧 Agent 名称、系统提示词、`agentId` 与输出预算
- 真机截图加入 `.gitignore`

---

## 12. 建议执行顺序

```
阶段 A（A1 → A2 → A3）   ← 正确性，独立可发布，先做；做完即可再出 APK 上真机
        ↓
阶段 B（B1 → B2 → B3）   ← 成本治理；A1 的组件正好被 B1 复用
        ↓
阶段 C（C1 → C4）        ← 体验增强，按真机反馈挑选
```

**每完成一项**：`dart format` → `flutter analyze --no-pub` → 相关 `flutter test` → 通过后继续下一项。
**阶段 A 完成后**：跑全量 + 覆盖率 + 构建 APK，再进入阶段 B。
