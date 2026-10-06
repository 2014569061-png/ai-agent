# NEXUS × DeepSeek Harness 最终方案 v1

日期：2026-09-30  
基线：分支 `refactor/tool-pipeline`（HEAD `19de275`，1654 测试通过，analyze 0 issues）  
上游参考：deepseek-harness @ `639ed01`（开发者预览）

## 0. 已确认的决策

| 问题 | 你的选择 | 对方案的约束 |
| --- | --- | --- |
| 融入的含义 | 让手机端具备 Harness 式的**架构与使用方式** | 借鉴概念和契约，**不嵌入** Harness 的代码或运行时 |
| 优先级 | **先架构** | 先重构底层，界面只在架构稳定后再改 |
| 连接桌面端 | **以后再说** | 只预留接口（能力接缝），不排进工期 |
| 插件 | **只做内部模块化** | 用 Dart 一方模块，不加载第三方代码，不需要应用商店审核脚本 |
| 会话日志 | 由我推荐 → **并行渐进** | 见 §3 |
| 用户 | **公开发布** | 数据迁移必须可回退，旧会话必须能打开 |
| 人力 | **一个人 + AI** | 每步都要小、能独立合并、测试兜底 |

需要纠正的一点：官方 Harness **没有**一方的手机配对 App。它的桌面端是 Electron 套壳的 Web 应用，Web API 默认只允许本机访问（loopback fence），手机访问都靠社区插件，例如 dsh-pocket、dsh-coding-remote-kit。所以“连桌面”以后要做的话，要么自己写 dsh 插件，要么依赖社区插件，不能指望上游。

---

## 1. 借什么、不借什么

### 借（Harness 的核心架构思想 → NEXUS 的 Dart 版）

| Harness 概念 | 本质 | NEXUS 对应物 |
| --- | --- | --- |
| Cordis：一切皆插件，效果可逆 | 功能通过注册挂到共享上下文，卸载时自动撤销 | `NexusModule` + `ModuleHost`（Riverpod 继续做依赖注入） |
| Profile / Bundle 分层组合 | 同一套模块按场景组合 | `RunProfile`：chat / headless / scheduled / subagent（remote 预留） |
| 追加式 Session 日志，唯一事实源 | 模型历史、分支、恢复、审计都从日志推导 | `SessionEvents` 表 + `deriveMessages()` 投影 |
| “模型可见 = 已记录”不变式 | 每次模型请求都能从日志重建 | 调试/测试期断言：`deriveMessages(log) == 实际请求` |
| 三类事件 | 持久事实 / 运行中拦截 / 能力策略 | SessionEvent / Agent 钩子 / 能力接缝钩子 |
| 瀑布式钩子 `agent/pre-step`、`agent/request`、`tools/*`、`turn-stopping` | 每个阶段可改写、拒绝或包装 | `AgentLoop` 的阶段钩子（工具部分已由 tool_pipeline 做完） |
| 能力接缝 Definition/Provider/Consumer | 换 Provider 等于换执行世界 | `WorkspaceFs`、`ProcessRunner`、`ModelRoute`；**以后接桌面就是换 Provider** |
| ToolDefinition：输出 schema、超时、并发安全、纯函数 presenter | 工具契约完整、界面可回放 | `ToolSpec v2` |
| Preset：稳定 id、快照组合 | 已有会话不受新定义影响 | Agent 预设 + 会话启动时的配置快照事件 |
| 按回合边界 fork、中断封口、不重放副作用 | 可靠分支与恢复 | 基于日志的 fork/resume |
| Session projection 注册表 | 各界面读同一份折叠状态 | 投影：消息、回合边界、作业、待处理、改动摘要 |

### 不借

- Cordis 运行时、TypeScript 插件、热重载（HMR）、用户可编辑的 YAML patch：你选了只做内部模块化，而且手机端公开发布时，动态代码会带来安全和上架风险。
- Web Host / RPC / Electron 生命周期：手机上没有这些概念。Android 的生命周期是界面离开、进程被杀、网络断开。
- 上游代码本身：只借契约。这样上游的破坏性更新**不会影响 NEXUS**（“深度绑定”只在以后接桌面时才相关）。

---

## 2. 现状对照（基于你仓库的实际代码）

| 模块 | 现状 | 差距 |
| --- | --- | --- |
| Agent 循环 | `AgentExecutor.run()` 单个约 700 行的方法（L43–744），通过 `Stream<AgentEvent>` 对外发出约 20 种事件 | 阶段没有显式化；预算、压缩、重试、推理策略、运行控制都内联在方法里 |
| 工具管线 | ✅ 已完成：run-events → guards → approval → checkpoint → boundary → authorization → file-baseline → execute | 相当于 Harness 的 `tools/*` 瀑布；缺输出 schema、并发、presenter |
| 持久化 | `Messages` 表（role/content/toolCallsJson…）是事实源；`RunRecords` / `RunEvents` 是**脱敏审计** | 没有回合/步骤边界，没有失败尝试记录，也不能证明模型请求可重建 |
| 组合 | `chat_run_execution.dart`（1531 行）和 `headless_executor.dart`（507 行）各自手工接线 | S5 已经暴露：审计、基线、RunRecord 要写两遍 → 这正是 Profile 要解决的问题 |
| 分支 | `conversation_fork_service` 复制锚点前的消息（53 行） | 没有回合边界校验，也没有 fork 来源事件 |
| 插件 | `plugin_store` 只支持声明式 HTTP 工具 + Agent 预设 | 预设没有稳定 id / 快照语义 |
| 执行世界 | 工具直接操作文件 / 终端 | 没有接缝，远端执行只有 `remote_execution_probe` 探针 |
| 界面 | `chat_controller` 2995 行，`chat_page` 3332 行 | 放到架构之后处理（第 7 阶段） |

---

## 3. 会话日志：推荐“并行渐进”

| 方案 | 结论 |
| --- | --- |
| 彻底迁移（一次切换，日志成为唯一事实源） | ❌ 已发布用户的数据一次性迁移，风险高；一个人难以回退 |
| 不改存储 | ❌ 做不到“模型可见 = 已记录”，分支、恢复、审计仍然各说各话 |
| **并行渐进** | ✅ 新表双写 → 影子比对 → 逐个切换读路径 → `Messages` 降级为投影缓存。每一步都能用开关回退 |

**`SessionEvents` 表（schema 25 → 26）**

```
id TEXT PK
conversationId TEXT
seq INTEGER            -- 每个会话内单调递增，UNIQUE(conversationId, seq)
type TEXT              -- 见下表
turnId TEXT? stepId TEXT?
payloadJson TEXT       -- 完整内容（本地、不脱敏）；大块内容存 blobRef
formatVersion INTEGER  -- 事件格式版本，走相邻版本迁移链
createdAt DATETIME
```

**事件词汇（首批）**

`turn/start`、`turn/end{reason: done|cancelled|failed|interrupted}`、`step/start`、`step/end`、`request/header{model, preset快照, 工具集哈希}`、`system/message`、`user/message`、`assistant/message`、`assistant/attempt`（失败或重试的尝试，不进模型历史）、`tool/call`、`tool/result`、`compaction/applied`、`approval/requested|resolved`、`run/control{pause|resume|append}`、`fork/origin{parentId, turnSeq}`、`legacy/imported`。

**两条存储线分开，各司其职**

- `SessionEvents`：完整内容，只在本地，用来重建模型历史。
- `RunEvents` / `AuditLogs`：脱敏摘要，用来展示和诊断，保持现状。**绝不用脱敏摘要去重放模型历史。**

**旧会话怎么办**：切换读路径时，对没有日志的旧会话按需生成 `legacy/imported` 事件（从 Messages 转换），标记为“无回合边界”。这类会话能打开、能继续聊，但分支只允许在消息级别，并在界面上说明。

---

## 4. 目标架构

```
┌──────────── RunProfile (chat | headless | scheduled | subagent | remote*) ────────────┐
│  ModuleHost：按 profile 装配 NexusModule，按依赖顺序启动，结束时按相反顺序撤销          │
│                                                                                       │
│   AgentLoop（显式阶段）                                                               │
│     preStep ─► request ─► stream ─► tools(已有 pipeline) ─► stepEnd ─► turnStopping    │
│       ▲瀑布      ▲瀑布      ▲瀑布       ▲拦截器链                        ▲串行            │
│   模块挂载：预算/运行控制  推理策略/压缩  重试/用量  守卫/审批/基线   验证/变更集/收尾  │
│                                                                                       │
│   SessionLog（追加，唯一事实源） ──► Projections（messages / turnBoundary / jobs /     │
│                                        inbox / changeSummary）──► UI / fork / resume   │
│                                                                                       │
│   能力接缝：WorkspaceFs · ProcessRunner · ModelRoute · ApprovalPolicy · Credentials    │
│             Local 实现（现在）   Remote 实现（以后：桌面 Harness / SSH）*               │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

**`NexusModule` 契约（示意）**

```dart
abstract class NexusModule {
  String get id;                       // 稳定 id，写入 request/header 快照
  Set<String> get dependsOn;
  Future<void> install(ModuleContext ctx); // 通过 ctx 注册：钩子、工具、prompt 段、投影、接缝实现
}
// ctx 上的每次 register* 都返回 Disposable，由 ModuleHost 统一回收 → 对应 Cordis 的“可逆效果”
```

**钩子语义**（照搬 Harness 的规则）：

- 瀑布式钩子必须调用 `next()`，可以改写、拒绝或包装后续流程。
- `turnStopping` 串行执行，没有 `next`。
- 取消发生在 `request` 阶段时，不提交任何事件。

---

## 5. 分阶段路线（一个人 + AI；每阶段都能单独合并）

> 工期是按一个人加 AI 估计的相对量，不是承诺。每个阶段结束时都要满足：全量测试通过、analyze 0 issues、功能开关默认安全。

### 阶段 0：准备（约 1 周）

- 合并 `refactor/tool-pipeline`。
- 为 `AgentExecutor` 写**特征测试**：录下现有行为，包括事件序列、工具调用、预算暂停、重试、取消。它们是后续重构的安全网。
- ADR 文档：事件词汇、钩子语义、模块契约。
- **验收**：特征测试覆盖 `run()` 的主要分支，并且全部通过。

### 阶段 1：会话日志双写（2–3 周）

- `SessionEvents` 表 + schema 26 迁移。
- `SessionLog` 服务：`append`、按会话串行、`seq` 单调递增。
- 写入由订阅 `AgentEvent` 的**旁路模块**完成，不改 `run()` 的逻辑。
- `deriveMessages(log)`：在调试和测试中与 `Messages` 以及实际请求做**影子比对**，出现不一致就计数并上报。
- **验收**：
  - 所有特征测试场景下，比对零差异。
  - 关闭开关后行为与现在完全一致。
  - 事件写入不增加首 token 延迟（有测量）。

### 阶段 2：拆 AgentLoop 的阶段钩子（约 3 周）

- 把 `run()` 拆成 `preStep / request / stream / tools / stepEnd / turnStopping`。
- 按以下顺序把内联逻辑**逐个**迁移到钩子监听器，每迁一个就合并一次：
  1. 运行控制（暂停 / 追加）
  2. 预算
  3. 推理策略
  4. 上下文压缩
  5. 重试
  6. 验证和收尾（`development_loop_finalizer`、变更集捕获）
- 事件由 loop 在阶段边界**直接写入**日志，取代阶段 1 的旁路写入。
- **验收**：特征测试不改一行就通过；`run()` 本体降到 200 行以内；每个钩子都有单测。

### 阶段 3：ModuleHost + RunProfile（约 2 周）

- `NexusModule` / `ModuleHost`（依赖排序、失败回滚、可逆注册）。
- 把 chat 和 headless 改成两个 profile，**消除 `chat_run_execution` 与 `headless_executor` 之间的重复接线**（审计、基线、RunRecord 只保留一份）。
- 配置分层：模块默认 → profile → 全局设置 → 项目设置 → 本次运行。
- `request/header` 记录本次的模块 id 列表、预设和工具集哈希，也就是“启动快照”。
- **验收**：
  - headless 自动获得 chat 的全部审计能力，不用单独写代码。
  - 顺带补上 headless 没有 taskId 时不落记录的问题。
  - 新增一个 profile 只需要一份模块列表。

### 阶段 4：读路径切换到日志（约 2 周）

- 历史加载、分页、上下文构建改为从投影读取；`Messages` 降级为缓存（保留写入，方便回退）。
- 旧会话按需导入 `legacy/imported`。
- **fork**：只允许在稳定的回合边界发生，写 `fork/origin`，不重放副作用。
- **resume**：启动时扫描没有 `turn/end` 的回合，补写 `turn/end{interrupted}` 封口，界面显示“已中断”，不自动重跑。
- **验收**：
  - 旧会话能打开、能继续。
  - 进程被杀后重启不会重复执行工具。
  - 分支来源可追溯。
  - 开关可以一键切回 `Messages`。

### 阶段 5：能力接缝（2–3 周）

- `WorkspaceFs` / `ProcessRunner` / `ModelRoute` 的接口和 Local 实现；工具全部通过接缝访问文件和进程。
- `FileBaselineInterceptor` 改挂到 `WorkspaceFs` 写入钩子。这样 MCP 工具和其他写入方式也能自动保存原件（**终端脚本的改动仍然无法覆盖**，要明确告知用户）。
- **预留** `RemoteWorkspaceFs` / `RemoteProcessRunner` 接口和一个空的 `remote` profile，**不实现**。
- **验收**：没有任何工具绕过接缝（用静态检查或测试保证）；换一个 fake provider 就能跑完整个工具测试集。

### 阶段 6：ToolSpec v2（约 2 周）

- 输出 schema 校验、`timeoutMs`、`isConcurrencySafe`（只读工具可以并行）、纯函数 `presentCall` / `presentResult`（替换 `tool_humanizer`，界面可以从日志回放）。
- **验收**：并行只读调用的结果顺序稳定；从日志回放出的工具卡片和实时显示一致。

### 阶段 7：体验层（架构完成后，大约 4–6 周，分批）

从 GPT 文档的 P0/P1 里挑，但现在它们都只是**投影 + 界面**，不需要再改底层：

1. 拆分 `chat_page`（先出计划，再动手）。
2. 会话内“对话 / 文件 / 结果”页签 + 运行状态条。
3. 作业列表：终端作业、后台运行、子 Agent 统一成 Job 投影。
4. 待处理收件箱：审批、失败、中断。
5. 分支树导航。
6. 预设包：稳定 id + 快照 + 兼容性提示。

### 以后：连接桌面 Harness（不排期，只记录路线）

- **桌面侧**：写一个 dsh 插件（TypeScript），在独立端口上提供**白名单 RPC**，并做 QR/PIN 配对 + 端到端加密。可以参考社区的 dsh-coding-remote-kit 的“双平面”设计：管理接口只在本机，手机数据走独立端口。
- **手机侧**：实现阶段 5 预留的 Remote Provider，或者一个 `remote` profile（Agent 在电脑上跑，手机只订阅日志投影）。
- 因为 NEXUS 的日志和投影已经与 Harness 同构，映射成本低。

---

## 6. 风险与对策

| 风险 | 对策 |
| --- | --- |
| 已发布用户的数据迁移 | schema 迁移只**新增**表；读路径切换有开关；`Messages` 保留到 v+2 版本后再考虑移除 |
| 日志体积（手机存储） | 大块工具输出存 blobRef，与 changeset 共用清理策略（30 天 / 50 任务）；payload 可选压缩 |
| 隐私 | 完整日志只存在本地、不同步；导出和诊断只用脱敏的 RunEvents；敏感工具参数沿用现有脱敏规则 |
| 重构引入回归 | 阶段 0 的特征测试 + 每步小合并 + 全量测试门禁 |
| 一个人精力 | 每阶段都能单独发布；阶段 1–3 做完就已拿到大部分架构收益，后面的阶段可以按需暂停 |
| Android 被杀 | 靠封口语义（interrupted），不做“永久后台”承诺 |

## 7. 做完后用户能感受到什么

- 后台任务、定时任务、子 Agent 与聊天拥有**同样的**审计、回滚和记录能力。
- App 被杀或重启后，任务显示“已中断”，**不会**重复执行危险操作。
- 分支能看到来源，恢复可信。
- 工具卡片、作业和待处理项在任何页面看到的都是同一份状态。
- 以后接电脑上的 Harness 时，不需要推倒重来。
