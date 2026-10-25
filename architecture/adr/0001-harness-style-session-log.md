# ADR 0001：Harness 式会话日志与执行器观察点

- 状态：已采纳（阶段 0–1 已实现）
- 日期：2026-09-30
- 关联：[当前架构概览](../../docs/architecture.md)

## 背景

NEXUS 要借鉴 DeepSeek Harness 的架构，但不引入它的代码。Harness 的核心约定是：会话日志是唯一事实源，模型可见 = 已记录，fork / resume / 审计都从日志推导。

NEXUS 现状：
- `Messages` 表保存的是展示用消息。
- `RunEvents` 保存的是脱敏审计摘要。
- 两者都无法证明“某次模型请求到底发了什么”。

## 阶段 0 的发现（由 `test/agent_loop_characterization_test.dart` 锁定）

1. **请求别名**：`UnifiedRequest.messages` 就是执行器内部的工作列表。本步结束后追加的 assistant/tool 消息会出现在“已发送”的请求对象里，所以事后读取 `request.messages` 不可靠。
2. **执行器内部改写不可见**：system prompt 合并、steering、失败提示、计划确认、暂停提示、上下文裁剪和压缩，都直接改写工作列表，不产生 `AgentEvent`。因此**只订阅 AgentEvent 的旁路记录器无法重建模型输入**。
3. 在完成边界插入 steering 时，被打断那一步的 assistant 文本**不会**进入下一次请求（现状行为，暂不修改）。

## 决策

### D1. 在执行器上加一个观察点，不做旁路订阅

`AgentExecutor.run(onRequest: (step, request) {...})`：
- 每一步发送前回调一次，传入**不可变快照**。
- 重试复用同一请求，不重复回调。
- 回调抛出的异常被吞掉。

这是阶段 2 `agent/request` 钩子的前身。

### D2. 事件词汇（formatVersion = 1）

| type | payload | 说明 |
| --- | --- | --- |
| `turn/start` | `{runId, model}` | 一次 run 开始 |
| `message` | ChatMessageCodec 编码 | 模型可见消息首次出现；`content_key` = 规范化 JSON 的 sha256 |
| `request/sent` | `{step, refs:[seq], model, toolsHash, toolCount, maxTokens, temperature, topP, reasoningEffort}` | 一次模型请求，引用 message 序号 |
| `turn/end` | `{status, refs:[seq], reason?/error?/failureKind?}` | status 取值：completed / paused / cancelled / failed / interrupted；refs 是结束时的完整模型历史 |

- 消息按内容去重，跨步骤、跨运行只存一份，所以存储随消息数线性增长。
- 只编码模型可见字段（role / parts / toolCallId / toolCalls / reasoning）。展示元数据（id、用量、耗时）不进入日志的内容哈希。

### D3. 存储

- `session_events` 裸 SQL 表，主键 `(conversation_id, seq)`，schema 25 → 26。沿用 `artifacts` 的先例，不重新生成 drift 代码。
- seq 在事务里分配（MAX + 1）。
- 随 `deleteConversation` / `clearAllUserData` 一起删除。
- 完整日志只存在本地，不进导出和诊断（诊断继续使用脱敏的 RunEvents）。

### D4. 双写与开关

- `SessionLogSettings.dualWrite`：debug/profile 构建默认开启，release 默认关闭，可用 `--dart-define=NEXUS_SESSION_LOG=` 覆盖。
- 阶段 1 只接入聊天路径。后台 headless 没有会话生命周期，日志会成为孤儿记录，所以放到阶段 3 统一 profile 时再接。
- 记录器永远不影响运行：串行后台队列，错误只计数并交给 `NexusGuard.degradeCaught`。

### D5. 推导

`SessionLogReader`：
- `requestsFor(runId)`：重建每次请求。
- `deriveMessages()`：最近一次 turn/end 时的历史。
- `unsealedRuns`：有 start 没有 end 的运行，阶段 4 用它封口。

## 不变式与测试

- **模型可见 = 已记录**：`test/session_log_test.dart` 在工具循环、steering、预算暂停、取消和失败场景下断言 `requestsFor(run) == Provider 发送时刻的快照`（规范化 JSON 比较）。
- **影子比对**：`test/session_log_chat_wiring_test.dart` 通过真实 ChatController 连发两轮，断言 `deriveMessages()`（去掉 system）与 `Messages` 表一致。
- 特征测试（18 个）在阶段 2 拆分执行器时不得修改。

## 后果与待办

- ~~附件内联~~ 已改为 blobRef（schema 27）：超过 512 字符的附件存 `session_blobs`（按 sha256 去重），
  payload 只留 `blob` 与 `size`；`session_blob_refs` 记录会话引用，删除会话或任务时一并删除。
  启动维护清理无引用的附件以及 30 天未再使用的附件，之后解码为占位文本 `[附件已清理]`。
  `contentKey` 仍按完整内容计算，与拆分前的日志一致。读取须用 `SessionLogReader.load`。
- 事件格式变化时走相邻版本迁移链，不原地改写旧事件。
- release 默认开启双写的前提：在真机上 debug 使用一段时间，确认 `recorder.failures == 0`、影子比对零差异。

## 阶段 4 补充（启动维护、旧数据导入、影子比对）

- **封口**：数据库首次打开后，后台给超过 15 分钟无活动的未封口运行补写
  `turn/end`，`status = interrupted`，`reason = process_ended`，refs 取该运行最后一次
  请求。不能一律封口：WorkManager 的后台 isolate 可能仍在写日志。
- **旧数据导入**（仅在双写开启时）：只存在于 Messages 表的会话导入为一次合成运行，
  `runId = import:<conversationId>`，结束状态是新值 `imported`，refs 为 Messages 表
  逐行转换后的全部消息。通过 `appendAllIfEmpty` 原子写入，会话已有日志时不做任何事，
  所以不会与并发运行交错。每次启动最多导入 20 个会话。
- **影子比对**（仅在双写开启时）：对最近更新的 20 个有日志的会话，比较日志推导历史
  （去掉 system）与 Messages 表（逐条 `sameMessage`：角色、工具调用 ID、工具名必须一致；
  正文只在日志消息为纯文本且非工具结果时比较，因为 Messages 行把附件存成「[图片附件]」
  这类占位标记，敏感工具结果会脱敏）。不一致只写入
  诊断日志，内容只有下标、条数，以及角色、长度、摘要，**不含正文**。
  读路径切换到日志之前，影子比对必须在真机上持续零差异。

## 阶段 4c：在 turn 边界分叉

- 分叉仍以 Messages 表为准：`ConversationForkService` 先在事务里复制到锚点消息；
  调用方传入 `sessionLog`（聊天在双写开启时传入）后，再为分支建立日志。日志失败只上报
  （`chat.forkSessionLog`），不影响分叉。
- `SessionLogForker` 从新到旧查找原日志中历史与已复制行逐条对应的 `turn/end`：
  - 找到时，把当时的模型可见历史（含 system 与附件）写成分支的一次合成运行：
    `runId = fork:<branchId>`，`turn/start` 带 `forked`、`parentConversationId`、
    `parentSeq`、`parentRunId`，`turn/end status = forked`。附件先登记到分支名下，
    原会话删除后分支仍保留附件。
  - 找不到时（锚点在一轮中间，或原会话没有日志），退回旧数据导入（`imported`）。
- 分叉只复制历史，不重放任何工具副作用。
