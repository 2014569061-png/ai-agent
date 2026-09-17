# NEXUS Agent 全面代码审查报告

**日期**：2026-09-17
**场景**：全维度代码审查（代码质量 / UI 设计 / 系统交互动画 / 底层架构 / 系统性能）
**基准**：当前工作区（含未提交修改），Git HEAD `34eef40`，`pubspec.yaml` = `0.8.9+93`
**参与成员**：主理人（沽思航）+ 安全官（gstack-security-officer）+ 设计顾问（gstack-designer）+ 排障手（gstack-investigator，超时未交付，其负责的代码质量/架构/性能三维由主理人独立核实补足）

---

## 📌 TL;DR（执行摘要）

- **整体结论：🟡 有条件通过。** 这是一个**架构成熟度明显高于平均水平**的项目——分层清晰、审批策略已收敛为单一权威、流式渲染做了刻意的重建隔离、消息列表用 `ListView.builder` + 稳定 key + 缓存调优。前次审计的 10 条 P1/P2 **已全部修复且修复质量良好**。
- **真正的硬伤只有一类：安全边界"建好了但没接上"。** 统一的 `NetworkAccessPolicy` 存在且实现良好，但**最高频的 `http_request` 工具完全没用它**，MCP 出口（HTTP + stdio）更是零校验。这是发布前必须修的。
- **最系统性的问题是"体系建好但没推广"的采用率问题**，而非能力缺失：动效体系 `NexusMotion` 仅 16 处引用、设计 token 被 162 处硬编码色值绕过、共享组件（`AsyncStateView`/`NexusAsyncContent`）已存在但 30 个页面各自手写 `_load`。
- **最被低估的风险是"看不见"**：测试覆盖率实测 **47.5%**（2026-09-17 复测），其中 `android_shell_runtime_adapter.dart` **整体 0%**、PRoot/Termux 适配器仅 7.9%/17.6%；同时 Sentry 已接入但全库 `captureException` **零调用**，叠加 87 处静默 `catch (_) {}`，导致失败无声消失。CI 有门禁但**无覆盖率阈值**。
- **阻塞项 4 条**（P0），**高优先级 12 条**（P1）。建议：修完 P0 即可发布。

---

## 🎯 核心结论卡片

| 项目 | 内容 |
|------|------|
| Go / No-Go | 🟡 条件 Go（修完 4 条 P0 后可发布） |
| 严重度分布 | 🔴 4 / 🟠 12 / 🟡 16 / 🟢 9 |
| 关键行动项 | 41 条（P0 4 / P1 12 / P2 16 / P3 9） |
| 建议负责人 | 安全边界 → 后端/Agent 核心作者；设计 token 与动效 → UI 负责人；覆盖率与可观测性 → 测试/基建 |
| 单项最高收益 | 让 `http_request` 复用 `NetworkAccessPolicy`（改动约 20 行，消除一个 SSRF 面） |

---

## 1. 各成员核心结论

### 🛡️ 安全官（授权边界与 SSRF 专项）

- **核心判断**：安全设计**意图清晰**（审批策略集中、危险级永远确认、`fullAccess` 尊重用户显式选择），但存在**一条真实硬伤**——"敏感网络出口未收敛 + SSRF 校验分散重复"。
- **关键建议**：把 `core_tools.dart` 的私有 `_blockedUrl` 替换为统一的 `NetworkAccessPolicy`；给 MCP 的 HTTP/stdio 两个出口补上策略与用户确认。
- **边界诚实声明**：未做动态测试、未构造 PoC、未验证真机、未审计第三方依赖 CVE。因此下表凡未经 PoC 的均标注为"源码推断"。

### 🎨 设计顾问（UI 与交互动效专项）

- **核心判断**：视觉体系**已完成建设但未形成约束力**——token 体系存在却可被随意绕过，动效规范定义了 5 档却实测出 20 余种取值。
- **关键建议**：把"字号/时长/色值只能取自 token"变成**可机检的 CI 门禁**，否则一致性会持续熵增；优先修"减少动效"失效（无障碍合规问题，非审美问题）。

### 🔧 排障手（代码质量 / 架构 / 性能）

- **状态**：运行 28 分钟未交付，已被终止。三个维度由主理人独立核实补足（见下）。此事实予以明确记录，不掩盖。

---

## 2. 综合审查发现

> 置信度说明：**已核实** = 本次审查中直接读取代码/运行统计确认；**源码推断** = 依据调用链与配置推断，未构造 PoC 或未在真机验证。

> **修复进展（2026-09-17 补记）**：#1、#2、#3 已修复。累计新增 35 项回归测试
> （`test/http_request_ssrf_test.dart` 14 项 + `test/mcp_network_policy_test.dart` 21 项），
> 全量测试 **712 passed / 0 failed**，`flutter analyze` 零告警。
> 另修复了工作区中 3 条 `flutter analyze` 告警（README 宣称"零告警"，实测不成立）。
> 详见文末「修复记录」。

### 🔴 P0 — 发布前必须修（#1、#2、#3 已修复 ✅，#4 待办）

| # | 严重度 | 维度 | 位置 | 问题描述 | 影响 | 修复方向 | 置信度 |
|---|--------|------|------|---------|------|---------|--------|
| 1 | 🔴 ✅已修 | 安全 | `lib/infrastructure/tools/core_tools.dart:139-152` | `http_request` 自带私有 `_blockedUrl` 黑名单，**仅拦 `0.0.0.0`/`169.254.*`/`.internal`/`.local`，漏掉全部 RFC1918 私网段（`10.x`/`172.16-31.x`/`192.168.x`）**。且该文件**完全没有 import `NetworkAccessPolicy`**（已验证 import 列表为空） | 模型可通过 `http_request` 直接访问内网设备/路由器管理页/内网服务。这是全应用最高频的网络出口，却是防护最弱的一个 | 删除私有 `_blockedUrl`，改为调用统一 `NetworkAccessPolicy`；保留 localhost 例外但强制走危险级审批 | 已核实 |
| 2 | 🔴 ✅已修 | 安全 | `lib/infrastructure/tools/core_tools.dart:119`；`lib/infrastructure/plugins/plugin_store.dart:188` | Dio 使用默认 `Options`，**默认 `followRedirects: true`**。攻击者控制的 URL 返回 `302 Location: http://192.168.1.1/...` 即可绕过任何 host 校验 | SSRF 防护被重定向绕过；仅校验"原始 URL 的 host"在设计上不成立 | 显式设 `followRedirects: false`，或在校验时按重定向链逐跳复查；同时在 `onRedirect` 回调中复议目标 | 已核实（Dio 默认行为 + 未显式设置） |
| 3 | 🔴 ✅已修 | 安全 | `lib/infrastructure/mcp/mcp_tool_provider.dart:54,94`（HTTP）、`:97-104`（stdio） | MCP 两个出口**都不经过任何网络/权限策略**：HTTP 型连任意 URL（该文件无任何策略 import）；stdio 型 `StdioClientTransport` 直接 spawn 配置指定的任意命令，且 **`includeParentEnvironment: true`** 把父进程**全部环境变量**（含可能经 env 传入的凭证）继承给子进程 | (a) MCP HTTP 成为绕过 SSRF 政策的第二条通道；(b) stdio 型等价于"配置即可执行任意本地进程"= 配置面即 RCE；(c) 环境变量泄露 | HTTP 出口接入 `NetworkAccessPolicy`；stdio 出口要求用户显式确认并展示将要执行的命令，`includeParentEnvironment` 改 `false` 或按需白名单传参 | 已核实（代码 + 未设置） |
| 4 | 🔴 | 性能/质量 | `lib/infrastructure/terminal/{android_shell_runtime_adapter.dart,builtin_proot_runtime_adapter.dart,termux_runtime_adapter.dart}` | 三个终端运行时适配器（80 + 177 + 222 = 479 行）覆盖率 **0.0% / 7.9% / 17.6%**。其中 `android_shell_runtime_adapter.dart` **整体 0%**；另两个只覆盖到 `inspect`/`run` 的桥接失败路径，核心逻辑（rootfs 校验与安装、shell 转义、detached 协议）全未覆盖。这是全应用**权限最高、最危险**的一批代码（执行任意命令的落地实现） | 改动这批代码无任何回归保护；结合 #1-#3，终端/命令路径是风险集中区却无测试兜底 | 优先补 `android_shell_runtime_adapter`（整体 0%）、PRoot 的 **SHA-256 校验失败必须中止安装**、Termux 的 `_shellQuote` 转义与 detached ack 协议 | 已核实（**2026-09-17 重新生成 lcov 后实测**） |

> **⚠️ 数据修正（2026-09-17）**：本条原写「三个适配器全部 0% 覆盖」，是**基于过期数据得出的错误结论**——
> `coverage/lcov.info` 时间戳为 9-15，而 `test/linux_runtime_test.dart` 创建于 9-16，
> 覆盖率**早于测试文件**。已重新生成（`TOTAL 47.5%`，269 文件），上表为**修正后的真实值**。
> 旧数据保留为 `coverage/lcov.stale-2026-09-15.info`。
> **教训**：任何统计结论都要先确认数据时间戳晚于相关代码/测试的改动时间。

> **#3 修复后的两个附带发现**（本次新增，已一并处理）：
> 1. **自带预设会被自己的策略拒绝**：MCP 页 HTTP 预设原为 `http://127.0.0.1:8000/mcp`，接入策略后必然被拒。
>    说明这条策略**从写下那天起就没在黑名单外的真实场景跑过**——若当时就接上，这个矛盾会立刻暴露。
> 2. **`nexus_page_header.dart` 缺隐藏入口位**：37 个引用文件共享该组件，此前没有任何"无可见入口手势"的复用位，
>    导致隐藏开关只能靠各页面自己 hack。本次新增 `onTitleTap` 可选槽位（默认 null 不占位）。

### 🟠 P1 — 高优先级（下一批次）

| # | 严重度 | 维度 | 位置 | 问题描述 | 影响 | 修复方向 | 置信度 |
|---|--------|------|------|---------|------|---------|--------|
| 5 | 🟠 | 可观测性 | `lib/infrastructure/observability/sentry_service.dart:36-68` + 全库 | Sentry 已初始化（含 `tracesSampleRate = 0.1`），但**全库 `captureException` / `captureMessage` 零调用**。异常上报通道事实上不存在 | 线上崩溃与异常**无任何遥测**。叠加 87 处静默 `catch (_) {}`，"失败"与"成功"在数据上不可区分 | 在全局 `FlutterError.onError` / `PlatformDispatcher.instance.onError` / `runZonedGuarded` 接 Sentry；为静默 catch 处补结构化日志 | 已核实（全库 grep 零命中） |
| 6 | 🟠 | 隐私一致性 | `lib/infrastructure/observability/sentry_service.dart:40` | 类注释声明"守住「无埋点」叙事"，但 `tracesSampleRate = 0.1` 会**采集 10% 性能追踪数据**上报第三方 | 与产品对外的"无埋点"承诺存在内部矛盾，属合规/信任风险 | 若承诺无埋点则设 `tracesSampleRate = 0`；若确需性能数据则修改对外措辞并纳入隐私政策 | 已核实 |
| 7 | 🟠 | 安全/最小权限 | `lib/application/audit_service.dart:17-25` | 审计日志**默认关闭**（`prefs.getBool(...) ?? false`），且 90 天保留期后自动 prune；README 宣称"审批授予记录会写入审计日志，可在审计日志页查看" | 默认状态下**审批留痕不存在**，与对外声明不一致；"删会话联动删审计轨迹"进一步削弱可审计性 | 至少让"审批授予/拒绝"这类安全事件**无条件记录**（可脱敏但不依赖用户开关）；或修正文档措辞 | 已核实 |
| 8 | 🟠 | 安全/脱敏 | `lib/application/audit_service.dart:55-78` | 脱敏为**黑名单模式**（逐 key 检查 `arguments`/`result`/`path` 等固定名单后替换为 `[REDACTED]`） | 黑名单必然遗漏——新增字段名、嵌套结构、或未列入的 key 会原样落库 | 改为**白名单**：只允许已知安全字段落库，其余默认脱敏 | 已核实 |
| 9 | 🟠 | 安全/纵深 | `lib/domain/network_access_policy.dart:56-60` | IPv6 私网判定只检查**地址字面量类型与 `fc00::/7`、`fec0::/10`**，未检查 DNS 解析后的实际连接地址（DNS rebinding），也未覆盖 IPv4-mapped IPv6（`::ffff:192.168.1.1`） | 域名解析到内网 IP 即可绕过；修复不彻底 | 在建立连接前解析并校验实际 peer 地址；补 `::ffff:` 映射段判定 | 已核实（代码级） |
| 10 | 🔴→🟠 | 测试 | `coverage/lcov.info` | 实测**总覆盖率 47.5%**（38,501 LF / 18,290 LH，269 文件），**25 个文件 0% 覆盖**。除 #4 的终端适配器外，`lib/application/scheduled_task_runner.dart` 也仅 26.4%（87 LF，后台调度） | 后台任务与终端是两大危险区，覆盖不足 | 先补这两块关键路径；`flutter test --coverage` 已有数据但 CI **无阈值门禁**，建议加 `lcov` 阈值检查 | 已核实（**2026-09-17 重新生成 lcov 后实测**） |
| 11 | 🟠 | 设计体系 | `lib/presentation` 全量 | 规范规定字号双轨（内容 11/13/15/17、显示 22/28/34），实测 **19 种取值**。**最常用的 `12pt` 出现 114 次，却根本不在规范内**；带小数的 9.5/10.5/11.5/12.5/13.5/14.5/15.5/16.5 共约 66 处，均不可能落在任何轨道 | "字号双轨制"事实上已失效，视觉层级不成立 | 要么把 12/14 纳入规范（承认现实，扩为四档），要么批量迁移到 11/13/15/17。**先决策再改，不要两套并存** | 已核实（分布统计） |
| 12 | 🟠 | 动效一致性 | presentation 层 24 处（如 `chat_page.dart:680,886,948,1789,2046`、`nexus_sheet.dart:28,182`、`model_picker_sheet.dart:249,454`） | 规范定义 5 档时长（90/150/220/300 + exit 150），实测**至少 20 种取值**（12/70/90/100/108/120/150/160/180/200/220/240/250/260/280/300/320/400/500/1000/1200/1800）。**`nexus_sheet.dart` 同一组件内 28 行用 240、182 行用 220** | 同类交互节奏不一致，用户可感知的"不统一" | 把非标时长归位到 5 档；`nexus_sheet` 内部先自统一 | 已核实 |
| 13 | 🟠 | 可访问性 | `chat_page.dart:679,2045`、`floating_capsule_input.dart:586,710`、`message_bubble.dart:726`、`model_picker_sheet.dart:248,453`、`plan_panel.dart:98`、`history_page.dart:216` | **15 处隐式动画中 9 处无"减少动效"守卫**（`MotionPreferences` 全库仅 13 处引用）。缺守卫的位置**恰好包含聊天主界面最高频的互动**（输入胶囊、消息气泡、计划面板） | 用户在系统开启"减少动态效果"后，主界面仍强制播放动画 → **无障碍失效**（非审美问题，属合规） | 这 9 处补 `MotionPreferences` 守卫；更好的做法是把守卫下沉到统一动画封装，让绕过在结构上不可能 | 已核实 |
| 14 | 🟠 | 架构/分层 | `lib/presentation` 共 **78 处** `import '../infrastructure/...'`，其中 **22 处直接依赖 `infrastructure/database/app_database.dart`** | UI 层直接触达数据层（绕过 application 层），分层被击穿 | 数据库 schema 变更会直接波及 UI；UI 难以独立测试 | 在 application 层补 repository/服务门面；`databaseProvider` 只暴露领域模型，不暴露 drift 类型 | 已核实（import 统计） |
| 15 | 🟠 | 架构/一致性 | 全库 **304 处 `setState`** vs **31 处 `ref.watch`**；`chat_page.dart` 单文件 8 处 | Riverpod 与 `setState` **双轨制**。需注意：核心 `ChatController` 是规范的 `Notifier<ChatState>`（`chat_controller.dart:373`），流式也做了 provider 切片——所以**问题不在核心域，而在页面的局部态管理缺乏统一约定** | 状态来源分散，可预测性下降；重构时难以判断某状态该归谁 | 制定明确约定：**跨组件/跨页面状态走 provider，纯 UI 瞬时态才用 setState**；对 `chat_page.dart`(3081 行) 这类大页面优先治理 | 已核实 |
| 16 | 🟠 | 代码质量 | `lib/application/chat_controller.dart`（26 处）、`chat_run_execution.dart`、全库共 **87 处** `catch (_) {}` | 全库 87 处完全静默吞异常。**需公正说明**：其中不少是**刻意的、有注释的**容错设计（如 `chat_controller.dart:1044` 明确写"持久化失败不阻断对话"），这是合理取舍。**真正的问题是失败后没有任何记录**，与 #5 叠加 | 部分持久化失败会表现为"消息没存/Task 没建但对话继续"，用户与开发者都无从发现 | 保留容错策略，但至少 `debugPrint` 或计数上报；建议启用 `avoid_catches_without_on_clauses` lint 逐处审视 | 已核实 |

### 🟡 P2 — 应改但非紧急

| # | 严重度 | 维度 | 位置 | 问题描述 | 建议 | 置信度 |
|---|--------|------|------|---------|------|--------|
| 17 | 🟡 | 样式复用 | `dashboard/widgets/token_usage_hero.dart`(16)、`tasks/task_details_page.dart`(15)、`chat/widgets/tool_approval_sheet.dart`(15)、`markdown/code_block.dart`(14)、`chat/widgets/tool_activity_section.dart`(14) | 调色板外共 **162 处** `Color(0x...)` 硬编码。注意 `code_block.dart` 的语法高亮色属**合理特例**，但 `task_details_page`/`tool_approval_sheet` 里的状态色属**该用语义 token** | 按"特例"与"漂移"分类后，仅收敛后者；把语义色（success/danger/warning）纳入 token 强制引用 | 已核实（统计 + 抽样） |
| 18 | 🟡 | 代码重复 | 30 个文件各自定义 `Future<void> _load`；24 个文件手写 `CircularProgressIndicator` | 三态（loading/empty/error）样板重复 30 次 | **关键**：`widgets/async_state_view.dart`、`widgets/nexus_async_content.dart`、`widgets/empty_state_view.dart` **已存在**（采用率分别为 21/5/65 处）。这是**采用率问题而非能力缺失** → 分批迁移即可，无需新建抽象 | 已核实 |
| 19 | 🟡 | 性能 | `chat_page.dart:2147-2148`、`project_picker_page.dart:83-84`、`model_picker_sheet.dart:311-312` 等 **13 处** `shrinkWrap: true` | `shrinkWrap` 会一次性布局全部子项。其中 `chat_page.dart:2147` 位于消息区（数量随会话增长），风险最高；`model_picker_sheet` 列表通常短，影响有限 | 按数据量级分级处理，只修 `chat_page.dart:2147` 这类大列表 | 已核实 |
| 20 | 🟡 | 性能 | 全库仅 **4 处** `RepaintBoundary`；`lib/presentation/chat/widgets/message_bubble.dart` 无 boundary | 流式输出期间气泡高频重建。项目结论已确认**消息列表与气泡不含玻璃**，因此可安全加 boundary | 在 `message_bubble` 外层加 `RepaintBoundary`。**注意**：计数器/探针不要包在 boundary 内，否则会因缓存而测不准 | 已核实 |
| 21 | 🟡 | 性能/内存 | `lib/infrastructure/database/app_database.dart:1678`（`allKnowledgeDocs()`）、`:1709`（`allKnowledgeChunks()`）；另 `allAgents()`:1114、`allModelProfiles()`:1128 无 limit | 多数批量查询**已有 limit**（`allAuditLogs` 2000、`allRunEvents` 8000 等，做得不错），但**知识库两张表无上限**，随文档量线性增长 | 给 `allKnowledgeChunks` 加分页/上限；全文检索应走 SQL 而非全量载入内存 | 已核实 |
| 22 | 🟡 | 易维护性 | `chat_page.dart`(3081)、`chat_controller.dart`(2728)、`app_database.dart`(2031)、`task_details_page.dart`(1471)、`command_tool.dart`(1409)；超 600 行文件共 **28 个** | 上帝类，单文件职责过载 | `chat_page.dart` 可按"顶栏/消息区/输入区/弹层编排"拆为多个 widget 与 controller；`app_database.dart` 可按领域拆 DAO（`onCreate`/`onUpgrade` 共用 SQL 的做法已很好，需保留） | 已核实 |
| 23 | 🟡 | 命名/一致性 | 全库注释 | 中英文注释混用；`Nexus*` 前缀约定未完全统一 | 统一注释语言（建议中文，与团队一致）；明确 `Nexus*` 为"设计系统组件"保留前缀 | 已核实（抽样） |
| 24 | 🟡 | 工程门禁 | `analysis_options.yaml:32-39` | 自有 lint 仅 5 条（`avoid_print`/`prefer_const_constructors`/`prefer_const_literals_to_create_immutables`/`unawaited_futures`/`use_key_in_widget_constructors`），未启用 `avoid_catches_without_on_clauses`（可拦 #16）、`always_declare_return_types`、`prefer_final_locals` 等 | 把 #16 与设计 token 约束转成 lint/CI 门禁，才能防止熵增 | 已核实 |
| 25 | 🟡 | 响应式 | `main.dart`（`textScaler: TextScaler.linear(systemScale * fontScale)`） | 用户系统字号 × 应用内字号**相乘放大**，超大字号下叠加效应可能溢出（尤其固定高度容器） | 对关键容器改 `IntrinsicHeight`/`Flexible`；补超大字号下的 widget test | 源码推断（未在真机验证溢出） |
| 26 | 🟡 | 可访问性 | presentation 全量：`Semantics` 仅 **34 处**，而 UI 代码 41,423 行 | 语义标签覆盖率偏低。**公正说明**：89 个 `IconButton` 配了 88 个 `tooltip`（近 1:1），图标按钮可访问性做得不错；缺口在**非按钮的可交互元素与图表/数据可视化** | 给纯图标状态指示、图形化数据、自定义手势区域补 `Semantics(label:)` | 已核实（统计） |
| 27 | 🟡 | 架构/扩展性 | `lib/infrastructure/mcp/mcp_tool_provider.dart:106-107`、`orchestration_module.dart`（`_controllers`/`_cancellation` Map） | 连接/控制器缓存于 Map，`dispose()` 存在但需确认 **所有** 退出路径都会调用（ProviderScope 销毁是唯一保证） | 增加泄漏防护：缓存加 LRU 上限；在测试中断言 dispose 后 Map 为空 | 源码推断 |
| 28 | 🟡 | 文档一致性 | `pubspec.yaml`（`0.8.9+93`）vs `README.md`（`0.8.9.2`） | 版本来源不一致（前次审计已指出，**至今未统一**） | 单一版本来源 + 发布校验 | 已核实 |
| 29 | 🟡 | 字体 | `pubspec.yaml:59-64`（仅打包 Inter 400/500）vs 规范要求 w600 | 规范要求字重三档含 600，但只打包了 400/500；中文走系统 fallback，**Windows（Microsoft YaHei）可能被合成伪粗体** | 补 Inter-SemiBold（中文仍需系统字体，需三平台截图验证 600 的实际表现）；或规范改为"中文用 500 代替 600" | 已核实 |
| 30 | 🟡 | 性能/动画 | `plan_panel.dart:98`、`reasoning_block.dart:200`（`AnimatedSize`）；`chat_page.dart:679,2045`（`AnimatedContainer` 改尺寸） | 这些动画触发**布局重算**（非仅重绘）；若位于滚动列表内会放大代价 | 确认是否处于滚动热路径；优先用 `Transform`/`Opacity`（仅合成）替代改尺寸的动画 | 源码推断 |
| 31 | 🟡 | 性能/玻璃 | `lib/presentation/widgets/liquid_glass.dart`、18 处 `BackdropFilter`/`ImageFilter` | 自定义着色器玻璃是已知帧耗时大头。项目已正确把玻璃限制在"浮于滚动内容之上"的层级（顶栏/悬浮输入/Toast/弹层），方向正确 | 补一次中端机帧耗时实测；确认玻璃不落在滚动热路径 | 源码推断（未做性能剖析） |
| 32 | 🟡 | 进程/权限 | `lib/infrastructure/mcp/mcp_tool_provider.dart:101` | `includeParentEnvironment: true`（同 #3 的另一面）：子进程继承父进程全部环境变量 | 见 #3；单独列出以便跟进 | 已核实 |

### 🟢 P3 — 优化建议

| # | 严重度 | 维度 | 位置 | 建议 | 置信度 |
|---|--------|------|------|------|--------|
| 33 | 🟢 | 代码质量 | 全库 21 处 `debugPrint` | 缺少统一日志门面。建议引入可分级、可开关的 logger，为 #5/#16 提供落点 | 已核实 |
| 34 | 🟢 | 架构 | `lib/application/providers.dart` | provider 依赖图建议可视化/文档化，便于新人理解装配关系 | 源码推断 |
| 35 | 🟢 | 性能 | `xterm` 终端输出缓冲 | 终端长输出建议确认有环形缓冲上限（`terminal_sheet.dart:113` 已有 150ms flush 节流，方向正确） | 源码推断 |
| 36 | 🟢 | 可访问性 | 全库 | 补 `Semantics` 的同时，建议加一次真机 TalkBack 走查 | 未验证 |
| 37 | 🟢 | 测试 | `test/` 124 文件 | 补 `integration_test/`（当前**不存在**）覆盖真实安装、审批拒绝、终端、备份恢复链路 | 已核实（目录不存在） |
| 38 | 🟢 | 测试 | `.github/workflows/ci.yml` | CI 已含 analyze + test + debug APK 构建（**做得不错**），建议追加 coverage 阈值与 token/字号 lint 门禁 | 已核实 |
| 39 | 🟢 | 安全 | `flutter_secure_storage` 使用面 | 建议专项确认不存在"密钥落 SharedPreferences/明文文件"的旁路 | 未验证 |
| 40 | 🟢 | 安全 | `cryptography` 保险箱 | 建议复核 KDF 迭代次数、盐随机性、AES 模式（优先 GCM）与 IV 唯一性 | 未验证 |
| 41 | 🟢 | 安全 | 第三方依赖 | 未审计依赖 CVE（`pubspec` 含 mcp_dart/dio/sentry 等 30+ 依赖），建议接入 `dependabot` 或 `osv-scanner` | 未验证 |

---

## ✅ 行动清单

| # | 行动 | 负责方 | 紧急度 | 状态 |
|---|------|--------|--------|------|
| 1 | `http_request` 改用统一 `NetworkAccessPolicy`（删除 `core_tools.dart` 私有 `_blockedUrl`） | Agent 核心 | **P0** | ✅ 已完成 |
| 2 | 对应工具显式设 `followRedirects: false`，或按重定向链逐跳复检目标 | Agent 核心 | **P0** | ✅ 已完成 |
| 3 | MCP HTTP 出口接入网络策略；stdio 出口强制用户确认 + 关闭 `includeParentEnvironment` | MCP/基建 | **P0** | ✅ 已完成 |
| 4 | 为三个终端运行时适配器补单测（当前 0% 覆盖，且是权限最高代码） | 测试 | **P0** | ⬜ 待办 |
| 5 | 接上全局错误钩子（`FlutterError.onError` / `runZonedGuarded` → Sentry），让异常真正上报 | 基建 | P1 | ⬜ 待办 |
| 6 | 决策"无埋点"承诺：`tracesSampleRate` 归 0，或修正对外措辞 | 产品+基建 | P1 | ⬜ 待办 |
| 7 | 安全事件（审批授予/拒绝）改为无条件记录，不依赖用户开关 | 安全 | P1 | ⬜ 待办 |
| 8 | 脱敏从黑名单改白名单 | 安全 | P1 | ⬜ 待办 |
| 9 | 决策字号体系：把 12/14 纳入规范，或批量迁移到 11/13/15/17（**先决策，避免两套并存**） | 设计+UI | P1 | ⬜ 待办 |
| 10 | 9 处缺失"减少动效"守卫的动画补守卫（无障碍合规） | UI | P1 | ⬜ 待办 |
| 11 | 非标动效时长归位到 5 档；`nexus_sheet` 内部先自统一 | UI | P1 | ⬜ 待办 |
| 12 | 给 `presentation → infrastructure` 的 22 处 `app_database` 直连补 application 层门面 | 架构 | P1 | ⬜ 待办 |
| 13 | 统一版本来源（`pubspec` vs README） | 发布 | P2 | ⬜ 待办 |
| 14 | 分批把 30 个手写 `_load` 页面迁移到已有 `AsyncStateView` | UI | P2 | ⬜ 待办 |
| 15 | 把 token 约束与 `avoid_catches_without_on_clauses` 加进 lint/CI 门禁 | 基建 | P2 | ⬜ 待办 |
| 16 | 加 coverage 阈值门禁（当前 **47.5%** 无守护）；补 `integration_test/` | 测试 | P2 | ⬜ 待办 |

---

## ⚠️ 待完善 / 已知局限

1. **排障手（gstack-investigator）超时未交付**：其负责的代码质量/架构/性能三维由主理人以独立统计与代码阅读补足，深度低于专项审查预期。这是本次协作的明确短板，已在成员结论中如实记录。
2. **无真机与性能剖析**：所有性能结论均基于静态分析（列表模式、动画类型、覆盖率、查询上限），**未做帧耗时（`flutter run --profile` + DevTools）实测**。玻璃（#31）与流式重建（#20）的实际开销需实测确认优先级。
3. **安全项均未构造 PoC**：#1-#3、#9 为源码级确认（已验证 import 缺失与 Dio 默认行为），但未实际发起请求验证绕过链。生产环境可利用性需动态验证后定级。
4. **未审计第三方依赖 CVE**：30+ 依赖的已知漏洞未排查。
5. **未覆盖面**：Android 侧 `android:exported` 暴露面、R8 keep 规则、`MANAGE_EXTERNAL_STORAGE` 最小化、导出文件落盘位置（私有 vs 公共）、深链参数注入——因时间与范围限制未展开。
6. **覆盖率数据日期为 2026-09-15**（`coverage/lcov.info`），与当前工作区（含未提交修改）存在时间差，实际覆盖率可能已有变化。
7. **前次审计复核结论**：`docs/PROJECT_AUDIT_2026-09-15.md` 的 10 条 P1/P2 **逐条核实均已修复**，且修复质量良好（备份表清单补齐、审批回调贯通、`thoughtSignature` 保留、APK ZIP 头校验、`requiredSteps` 非空判断、IPv6 私网段、gradlew 路径等）。本报告**不含**对已修项的重复计数。

---

## 🔧 修复记录（2026-09-17 补记）

### 已修复并验证

| 项 | 文件 | 改动 | 验证 |
|---|------|------|------|
| **#1 SSRF 弱黑名单** | `lib/infrastructure/tools/core_tools.dart` | 删除私有 `_blockedUrl`（139-158 行）；改为 import 并调用统一 `NetworkAccessPolicy`；构造函数新增可注入 `NetworkAccessPolicy? policy` 参数（便于测试） | ✅ 新增 14 项回归测试全过 |
| **#2 重定向绕过** | 同上 | `BaseOptions` 显式设 `followRedirects: false`；`execute()` 改为手工逐跳：每跳先 `policy.inspect()` 校验、再请求、读 `Location` 后解析相对路径续跳，上限 5 跳防循环 | ✅ 覆盖 302→私网、307→元数据、链式公网、无限循环 4 类场景 |
| **README「零告警」不成立** | `chat_catalog_drawer.dart:13`、`:587`；`session_metrics_sheet.dart:54` | 删除 1 处未使用 import、2 处未使用局部变量 `surface` | ✅ `flutter analyze` 0 issue |
| **#3a MCP HTTP 出口零校验** | `lib/infrastructure/mcp/mcp_tool_provider.dart` | 新增 `_isAllowed()` 准入闸门，`connectAndListTools` 与 `testConnection` 两条路径都先过 `NetworkAccessPolicy.inspect()`；构造器支持注入 `NetworkAccessPolicy? policy`。拒绝时写 `lastBlockReason` 供页面展示，而不是静默返回空列表 | ✅ 新增 21 项回归测试；红测试验证（禁用闸门后 3 项失败） |
| **#3b MCP stdio 无门禁** | `mcp_server_config.dart`、`mcp_tool_provider.dart` | 新增 `McpStdioAvailability`（唯一权威）：移动端**默认关闭**，需 MCP 页连点标题右侧 5 次解锁并过高危确认；每个 stdio 服务器保存前**再次**确认（列出启动命令与参数）；不再使用时自动回落 | ✅ 门禁判定与持久化均有测试覆盖 |
| **#3c 子进程环境变量泄露** | `mcp_tool_provider.dart:111,151` | 两处 `includeParentEnvironment` 由 `true` 改为 **`false`**，切断 App 进程凭证（Provider API Key 等）向 MCP 子进程的传递 | ✅ 源码级约束测试锁定（防止被改回） |
| **#3d 自带预设会被自己的策略拒绝** | `mcp_servers_page.dart:160,239` | HTTP 预设与输入框 hint 由 `http://127.0.0.1:8000/mcp` 改为 `https://mcp.example.com/mcp`；新增一行提示「仅支持公网地址；本机与内网地址会被安全策略拒绝」 | ✅ 预设地址经策略校验放行 |

**#3 的设计取舍（用户已确认）**
- **STRICT**：MCP HTTP 也走 `NetworkAccessPolicy`，回环地址**不开口子**。理由是本项目已有 HTTP 代理入口承担本地转发，MCP 不需要在策略上开洞；开洞会让"唯一策略"再次分叉，重演 #1 的成因。
- **stdio 保留但加三重门禁**，而不是直接砍掉：它是已上线的一等功能（3 个预设），删除属破坏性变更；但"配置面即 RCE"必须由用户显式承担，故用「隐藏开关 + 两次确认（开开关一次、存配置一次）」把决策成本还给用户。
- `includeParentEnvironment: false` 有**已知代价**：若子进程真的依赖父环境变量会启动失败。考虑到 MCP stdio 服务器按协议用 stdio 通信、不依赖 App 的 env，这个代价可接受。

**验证命令与结果**
```bash
# 专项回归
flutter test --no-pub test/http_request_ssrf_test.dart   # 14 passed
flutter test --no-pub test/mcp_network_policy_test.dart  # 21 passed
# 红测试（证明测试有效，非假绿）
#  - 把 includeParentEnvironment 改回 true → +20 -1（预期失败）
#  - 禁用 _isAllowed 闸门            → +18 -3（预期失败，且尝试真实连内网地址）
# 全量无回归
flutter test --no-pub                                     # 712 passed, 0 failed
# 静态分析
flutter analyze --no-pub                                  # No issues found
```
（本机需 `env -u HTTP_PROXY -u HTTPS_PROXY ... "NO_PROXY=localhost,127.0.0.1"` 包裹 `flutter test`，否则全部用例加载失败——这是本机代理环境问题，与代码无关。）

**修复的关键设计取舍**
- 保留 `NetworkAccessPolicy` 作为**唯一权威**，而非在 `core_tools` 里修修补补——因为"同一策略两处实现、弱的那处被绕过"正是本次缺陷的成因，只补强副本会重演。
- 重定向改为**手工逐跳校验**而非"直接禁止重定向"：后者会让所有依赖 302 的正常场景（短链、CDN 跳转）失效。选择前者是在安全与可用性之间的正确权衡。
- `http_request` 的 `risk` 仍为 `ToolRisk.dangerous`（`core_tools.dart:104`），因此**即便策略放行，仍走用户审批**——这是纵深防御的第二层，未改动。

### 仍待处理

- **#4 三个终端运行时适配器 0% 覆盖**（`android_shell_runtime_adapter.dart` 80 LF / `builtin_proot_runtime_adapter.dart` 167 LF / `termux_runtime_adapter.dart` 200 LF，共 447 行）——**未修**，是下一个 P0。这些文件承担 Android 侧命令执行，无测试意味着终端功能回归无人拦。
- **`lib/presentation/widgets/nexus_page_header.dart`** 本次新增了 `onTitleTap` 隐藏手势槽位（供 MCP 页解锁 stdio 开关）。该组件被 **37 个文件**引用，改动本身向后兼容（默认 null、不占位），但隐藏入口的**可发现性**值得留意：目前没有任何提示告诉用户它存在，属于刻意的设计取舍。
- 其余 P1/P2 见行动清单。

---

## 📚 成员产出索引

- **gstack-security-officer（安全官）**原始产出：SSRF 与授权边界专项报告，含 STRIDE 简表与 4 条 🔴；核心发现即本报告 #1-#3、#8-#9。已通过消息交付主理人。
- **gstack-designer（设计顾问）**原始产出：UI 与交互设计专项报告，覆盖字号分布、token 遵循度、动效一致性、无障碍守卫缺失；核心发现即本报告 #11-#13、#17、#26、#29。
- **gstack-investigator（排障手）**：**未交付**（运行 28m25s 后终止）。代码质量/架构/性能三维改由主理人独立核实，主要量化证据包括：覆盖率解析（首测 46.5%，**2026-09-17 复测修正为 47.5%，25 文件 0%**）、`catch (_) {}` 87 处、`setState` 304 处、`RepaintBoundary` 4 处、`shrinkWrap` 13 处、共享组件采用率、DB 查询 limit 审计。

---

> 本报告由软件工坊 AI 协作生成，关键决策请由工程负责人复核。安全级结论（P0）建议由人工二次验证后再据此修改代码。
