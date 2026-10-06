# DSH 会话运行时：执行循环 / 工具契约 / 事件持久化 / 上下文压缩

> 调研对象：DeepSeek Harness 桌面版（Electron）解包目录 `D:\DeepSeek\ds\resources\app.asar\dsh`，版本 **0.2.0-rc.2**。
> 本文所有路径均相对该目录的 `node_modules/@deepseek-ai/`，为便于阅读统一写作 `<pkg>/...`。
> 证据格式：`<pkg>/<file>:<行号>` + 一句原文或代码摘要。
> **重要前置事实（影响全篇可核实性）**：该 app.asar 仅发布已编译的 `lib/*.js` 与各包 `README.md`/`README.zh.md`，**不包含** `src/*.ts` 与仓库根 `docs/subsystems/*.md`。因此各 README 中形如 `[src/index.ts](src/index.ts)`、`../../../docs/subsystems/session.md` 的链接在发布物中**不存在**；本文只引用发布物中实际存在的文件与行号。

---

## 0. 结论速览

| 维度 | DSH 的做法 |
|---|---|
| 执行模型 | 事件溯源。`Session` 是 append-only 类型化事件日志，模型历史由日志**派生**（`deriveMessages()`） |
| 一轮 turn | `turn/start` → 循环 [ `agent/pre-step` 决策 → `step/start` → 组装请求 → `request/header` → 流式模型调用 → `assistant/message`/`assistant/attempt` → 工具调用/结果 ] → `step/end` → `turn/end` |
| 持久化 | 内存 Session + 可选 `sessionPersistence` 后端。agent-loop 是生产环境**唯一的写句柄获取点**；默认 JSONL 后端每 session 一个 `.jsonl.zstd` |
| 工具 schema | 作者侧统一 DSL（`defineTool`）编译为**受限 JSON Schema 子集**；wire 上只投影 `name/description/parameters/deferLoading` |
| 权限 | 三层：`tools/pre-execute` 扩展式 allow/deny/ask waterfall → 单调 `guard`（只能否决）→ `approval` 服务（`ask` 走人行；缺失即 deny，fail-closed） |
| 结果裁剪 | 三套并存机制：spill（落盘+预览）、compaction 前置 pruner、per-tool retainer（`dsh-output-retention`） |
| 事件重连 | 客户端 **无全局 sequenceNo**。用 `cursor`（`SessionSeqCursor`，空日志为 `-1`）+ journal 的 `replace/prepend/append` 连续性判定 + gap repair 页 |
| fork | `fork(source, boundary?, childSessionId?)`，`boundary` 为**闭区间** source seq；复制前缀 + `session/end-seed{inherited:true}` 标记 + `forked` 原因的合成收尾事件 |
| 压缩 | `compaction/start`→`compaction/summary`→替换一条 `user/message`→`compaction/end` 的日志锁括号；自动触发在 `agent/pre-step`（压力）与 `agent/request-error`（`CONTEXT_WINDOW_EXCEEDED`） |

---

## 1. 执行循环：一轮 agent turn 的完整阶段

### 1.1 实现位置

| 角色 | 文件 | 证据 |
|---|---|---|
| turn/step 主驱动 | `dsh-agent-loop/lib/index.js` | `agent-loop/lib/index.js:936: async turn()`；`agent-loop/lib/index.js:1041: async step(decision)` |
| 步前决策 | 同上 | `agent-loop/lib/index.js:902: async preStep(target, position)` |
| 请求预备 | 同上 | `agent-loop/lib/index.js:1163: async prepareRequest(turn, step, signal)` |
| 请求构造与冻结 | 同上 | `agent-loop/lib/index.js:1202: buildRequest(config, preparedCall, tools, position, startsRequestSeries, signal)` |
| 工具调用调度 | 同上 | `agent-loop/lib/index.js:506: async function executeToolCalls(ctx, turn, step, toolCalls, signal, acceptContext)`；`agent-loop/lib/index.js:551: async function runGroup(...)` |
| 助手流式累计 | 同上 | `agent-loop/lib/index.js:378: constructor(sessionId, attempt, nextRevision, turn, step, emit)`（`AssistantStreamAttempt`） |
| Agent 句柄/事件表 | `dsh-agent` | `agent/README.md:2: description: "The Agent handle, live registry, process-local initiator scope, and agent/* event vocabulary ..."` |

README 对循环的一句话定义：`agent-loop/README.md:12: "... then drives each turn through model requests, streamed responses, tool execution, and durable session history."`

### 1.2 阶段序列（含行号）

**阶段 0 —— 驱动入口。** `kick()` 反复调用 `turn()`：
```
agent-loop/lib/index.js:887: async kick() {
agent-loop/lib/index.js:889: while (await this.turn());
```

**阶段 1 —— 开启 turn。** 先写 `turn/start`（持久化在模型请求之前）：
```
agent-loop/lib/index.js:941: const turn = phase.turn + 1;
agent-loop/lib/index.js:943: this.session.append("turn/start", { turn });
```

**阶段 2 —— 步前决策 `agent/pre-step`。** 先声明 inbox 中的待处理输入，再组装 system prompt，投影运行时上下文，最后走 waterfall 决策（可 `reject`）：
```
agent-loop/lib/index.js:906: const claimed = this.inbox.claim(target, position.turn);
agent-loop/lib/index.js:907: const assembly = await this.loopCtx.systemPrompt.assemble(assembleContextFor(this, signal));
agent-loop/lib/index.js:911: const decision = await this.dispatch.waterfall("agent/pre-step", {...}, () => Promise.resolve({ kind: "enter", ... }));
agent-loop/lib/index.js:920: if (decision.kind === "reject") return decision;
```
契约说明：`agent/README.md:85: "Acceptance does not commit it: after assembly and `step/start`, `agent/request` and `prepareCall()` resolve the route before the loop commits the system prompt and user batch. Cancellation during either async phase commits neither."`

**阶段 3 —— 写 `step/start`。** 仅在决策被接受且批次非空时开步：
```
agent-loop/lib/index.js:962: if (turnEnds && decision.messages.length === 0) break;
agent-loop/lib/index.js:963: if (phase.step === 0 && decision.messages.length === 0) { turnEnds = { kind: "completed" }; return false; }
agent-loop/lib/index.js:968: this.session.append("step/start", { turn, step });
```

**阶段 4 —— 路由解析。** `agent/request` waterfall 产出 config，再 `ctx.llm.prepareCall()` 绑定适配器；无适配器时保留 `NO_ADAPTER` 语义：
```
agent-loop/lib/index.js:1179: const proposedConfig = await this.dispatch.waterfall("agent/request", {...}, () => Promise.resolve(seedConfig));
agent-loop/lib/index.js:1189: preparedCall = await this.loopCtx.llm.prepareCall(proposedConfig, signal);
agent-loop/lib/index.js:1192: if (!(error instanceof LlmError) || error.code !== "NO_ADAPTER") throw error;
```

**阶段 5 —— 提交 system prompt 与用户消息。** `systemPrompt.project(...)` 产出若干 `system/message` 提交意图；首答才提交 user 批次：
```
agent-loop/lib/index.js:1052: const commits = this.systemPrompt.project(renderedPrompt, { inHistory: ..., startsSeries: ... });
agent-loop/lib/index.js:1056: for (const { message, intent } of commits) this.session.append("system/message", {...}, intent);
agent-loop/lib/index.js:1061: if (firstAttempt) for (const message of decision.messages) this.session.append("user/message", message, { surfaceOp: "append" });
```

**阶段 6 —— 构造并冻结请求。** 写 `request/header`（仅当首个、变更或新序列），必要时写 `request/context` 与工具增删的 `developer/message`：
```
agent-loop/lib/index.js:1214: headerSeq = this.session.append("request/header", { header, reason: baseline === void 0 ? "initial" : "resume", ... }).seq;
agent-loop/lib/index.js:1220: } else if (baseline === void 0 || !headerEquals(baseline, header)) headerSeq = this.session.append("request/header", { header, reason: "change", ... }).seq;
agent-loop/lib/index.js:1225: else if (startsSeries) this.session.append("request/header", { header, reason: "series" });
agent-loop/lib/index.js:1240: if (additions.length > 0 || removals.length > 0) session.append("developer/message", {...});
agent-loop/lib/index.js:1259: if (previousContext?.provider !== ... ) session.append("request/context", requestContext);
agent-loop/lib/index.js:1262: const boundaryMessages = session.deriveMessages();
```
请求对象组成（**注意：请求体不含 `system` 字段，系统提示是 surface 节点**）：
```
agent-loop/lib/index.js:1269: return markAgentLoopRequest(Object.freeze({ ...header.config, messages: boundaryMessages, toolHistory: session.toolHistory(), ...header.tools !== void 0 ? { tools: header.tools } : {}, sessionId: this.session.id, signal }));
```
佐证：`agent-loop/README.md:119`"The request is `header.config`, `deriveMessages()`, and `header.tools`; it carries no `system` field."

**阶段 7 —— 流式模型调用与助手锚点。** 每次尝试启动 `live.start()`，逐 chunk 推送；正常结束写 `assistant/message`（`surfaceOp: 'append'`），取消则写 `interrupted: true` 的锚点，失败/中止写 `assistant/attempt`：
```
agent-loop/lib/index.js:1072: const stream = preparedCall?.stream(request) ?? this.loopCtx.llm.stream(request);
agent-loop/lib/index.js:1074: live.start();
agent-loop/lib/index.js:1076: for await (const chunk of stream) { signal.throwIfAborted(); live.push(chunk); }
agent-loop/lib/index.js:1086: if (signal.aborted) { ... this.session.append("assistant/message", {... interrupted: true ...}, { surfaceOp: "append" }) }
agent-loop/lib/index.js:1101: else live.settle("assistant/attempt", () => this.session.append("assistant/attempt", {...}).seq);
agent-loop/lib/index.js:1144: live.settle("assistant/message", () => this.session.append("assistant/message", {...}, { surfaceOp: "append" }).seq);
```

**阶段 8 —— 工具执行。** 无 tool-call 即结束；有则交给调度器：
```
agent-loop/lib/index.js:1152: const toolCalls = message.content.filter((block) => block.type === "tool-call");
agent-loop/lib/index.js:1153: if (toolCalls.length === 0) return { kind: "completed" };
agent-loop/lib/index.js:1154: const { concluded } = await executeToolCalls(this.loopCtx, turn, step, toolCalls, signal, (context) => this.inbox.splice("next-step", this.inbox.nextStep.length, 0, [context]));
```
每个工具条目先写 `tool/call`，结果写 `tool/result` 并以 `sourceEventSeqs` 指回 call：
```
agent-loop/lib/index.js:682: return session.append("tool/call", { turn, step, callId: block.id, name: block.name, arguments: block.arguments }).seq;
agent-loop/lib/index.js:697: session.append("tool/result", { turn, step, message, ...result.error?.info ? { error: result.error.info } : {}, ...result.meta !== void 0 ? { meta: result.meta } : {} }, { surfaceOp: "append", sourceEventSeqs: [callSeq] });
```
调度模型：`executionMode()` 决定独占或并行；独占调用组成屏障，并行调用使用有界滚动池，**结果按模型顺序提交**：
```
agent-loop/lib/index.js:523: const mode = ctx.tools.executionMode(first.exec).kind;
agent-loop/lib/index.js:524: const outcome = await runGroup(ctx, turn, step, mode === "parallel" ? planned.slice(next) : [first], mode, signal, acceptContext);
agent-loop/lib/index.js:553: const maxParallelToolCalls = ctx.agentLoop.config.maxParallelToolCalls.get();
agent-loop/lib/index.js:619: while (!aborted && nextToStart < group.length && inFlight.size < maxParallelToolCalls) {
agent-loop/lib/index.js:621: if (nextToStart > 0 && mode === "parallel" && ctx.tools.executionMode(nextCall.exec).kind !== "parallel") break;
```
取消时，未派发的调用写合成 `tool/call` + `ABORTED_BEFORE_DISPATCH` 结果对：
```
agent-loop/lib/index.js:663: function appendSkippedToolCall(session, turn, step, block) {
agent-loop/lib/index.js:668: text: "Error: tool call aborted before dispatch"
agent-loop/lib/index.js:675: code: TOOL_ABORTED_BEFORE_DISPATCH
```

**阶段 9 —— 收尾 `step/end` / `turn/end`。** `step/end` 在 finally 中无条件写；`turn/end` 携带 `reason`（`completed` / `max-tokens` / `blocked` / `aborted` / `error`）：
```
agent-loop/lib/index.js:992: this.session.append("step/end", { turn, step });
agent-loop/lib/index.js:1027: this.session.append("turn/end", { turn, reason: turnEnds });
agent-loop/lib/index.js:999: await this.dispatch.serial("agent/turn-stopping", { turn, signal });
```
步失败时的工具结果恢复（同一 turn 内）：
```
agent-loop/lib/index.js:982: for (const event of toolRecovery.results()) this.session.append("tool/result", event.data, { surfaceOp: "append", ... });
```
README 佐证：`agent-loop/README.md:75`"Each step sends the session's derived history — with the latest non-empty `system/message` node as the effective prompt ... every accepted fact is appended to the session log before the next step derives from it."

### 1.3 状态持久化方式

- **模型**：事件溯源。`session/README.md:88: "The package is built on event sourcing: a `Session` is an append-only log of typed `SessionEvent`s, and everything else — model history, transcripts, telemetry, titles, persistence — derives from that stream."`
- **追加即持久化边界**：`session/lib/index.js:1455: seq: SessionSeq(this.log.length)`（seq 恒等于日志长度）；`session/lib/index.js:1441: append(type, data, ...opts)`。
- **持久化后端接入点是 agent-loop**：`agent-loop/README.md:115`"The loop is the production acquisition point for session write handles. When `ctx.sessionPersistence` is mounted, `create`/`createAgent` call `persistence.create(header)` ... and `resume` calls `persistence.open(id, 'write')` first ... and appends `interruptedTurnClosers` for a log crashed mid-turn as an ordinary batch."
- **默认后端落盘形态**：每 session 一个 append-only 日志，默认 Zstandard 压缩帧：
  `session-persistence-jsonl/README.md:48: | `compression` | `'zstd'` | Physical encoding: `'zstd'` checksummed frames, or `'none'` newline-delimited UTF-8 text |`
  `session-persistence-jsonl/README.md:76: A session is materialized lazily: `create(header)` writes nothing and returns the owned write handle ...`
- **崩溃恢复语义**：保留中断的最后一个 turn，由 resume 路径补合成收尾事件。证据同上 `agent-loop/README.md:115` 与 `session-persistence-jsonl/README.md:76` 同段。
- **`session/end-seed`**：会话生命周期标记，用于区分“继承的 fork 历史”与“本进程新产生的事件”。`session/lib/index.js:1351: if (seed !== void 0 && mode === "snapshot" && this.header.isSeeded && !markedSeed) this.append("session/end-seed", { inherited: true });`

### 1.4 与“一轮 turn”相伴的可配置项

| 配置 | 默认 | 出处 |
|---|---|---|
| `agents[].maxParallelToolCalls` | `10` | `agent-loop/README.md:12` 同段（Summary 区）；常量 `agent-loop/lib/index.js:1285: const DEFAULT_MAX_PARALLEL_TOOL_CALLS = 10;`；schema `agent-loop/lib/index.js:1534: maxParallelToolCalls: z.number().step(1).min(1).default(10).volatile(),` |
| `agents[].provider` / `model` | 必填（缺一即 `agent/request` 阶段报错） | `agent-loop/lib/index.js:1185: if (!proposedConfig.provider || !proposedConfig.model) throw new Error(...)` |
| `agents[].sessionId` / `resumeSessionId` | — | `agent-loop/README.md:12` 同段及 README 配置表 |
| `agents[].id` | 必填；新会话铸造 `${id}-session-<uuid>` | `agent-loop/README.md:12` 同段配置表 |

> **未核实**：`agents[].reasoningEffort` / `maxTokens` 在 `lib/index.js` 中的 schema 行号未逐一定位（仅在 `agent-loop/lib/index.js:1172-1177` 见到读取逻辑）。

---

## 2. 工具定义契约

### 2.1 schema 形式

**双轨**：作者侧统一 DSL，wire 侧受限 JSON Schema 子集。

- 作者 DSL 支持的类型集合：`tools/README.md:60: "The unified schema DSL supports `string`, `number`, `integer`, `boolean`, `null`, `array`, `object`, author-only `json`, and exact-one `oneOf`; `InferValue` preserves exact types through 16 container levels before widening to `JsonValue`."`
- 原始 JSON Schema 是 wire 级对等物，与 subagent / workflow / MCP 共用：
  `tools/README.md:60` 同段后句 "A raw JSON Schema (`JsonSchemaNode`) is the wire-level counterpart shared with subagents, workflows, and MCP."
- **被强制执行的子集**（实现，非文档）：
  ```
  tools/lib/index.js:206: violations.push(`${path}.${key} is not a supported keyword (subset: type/oneOf/properties/required/additionalProperties/items/enum/const + annotations)`);
  tools/lib/index.js:212: if (hasType && hasOneOf) { violations.push(`${path} cannot declare both type and oneOf`); continue; }
  tools/lib/index.js:227: if (!isPlainJsonArray(oneOf) || oneOf.length < 2) violations.push(`${path}.oneOf must be an array of at least two schemas`);
  tools/lib/index.js:237: violations.push(Array.isArray(type) ? `${path}.type must be a single type string (type arrays are not supported)` : ...);
  tools/lib/index.js:468: for (const key of Object.keys(frame.value)) if (!Object.hasOwn(properties, key)) tailViolations.push(...);
  ```
  即：**不支持 `type: [...]` 联合类型、不支持 `oneOf` 与 `type` 并存、`oneOf` 至少 2 个分支、`oneOf` 旁不允许兄弟关键字、`additionalProperties: false` 会被真正检查**。
- 唯一允许的注解键：
  ```
  tools/lib/index.js:537: const ANNOTATION_KEYS = ["description", "title", "default", "examples"];
  ```
- **投影到 wire 的字段白名单**（execute / finalizeContent / timeoutMs / present* 均不外泄）：
  ```
  tools/lib/index.js:3023: schemas(scope) { return [...this.view(scope).visible.values()].map((definition) => this.schemaOf(definition, true)); }
  tools/lib/index.js:3039: schemaOf(definition, detachParameters) { const { name, description, parameters, deferLoading } = definition; ... return { name, description, parameters: detached, ...deferLoading === true ? { deferLoading } : {} }; }
  ```
  佐证：`tools/README.md:103`（“Design concept”）"... `output`, `execute`, `finalizeContent`, `timeoutMs`, and presentation callbacks never leak onto the wire."
- **参数校验发生在 body 之前**：非法输入变成普通错误结果而不是异常终止 turn：
  ```
  tools/lib/index.js:866: async execute(args, exec) {
  tools/lib/index.js:867: const violations = validate(args);
  tools/lib/index.js:868: if (violations.length > 0) throw new ToolArgsError(violations);
  tools/lib/index.js:869: return userExecute(args, exec);
  ```
- **演示模式** `mode: native | ptc | both`（`tools/README.md:64`），子调用并发上限 `maxParallelSubCalls` 默认 10（`tools/README.md:75`，实现 `tools/lib/index.js:2655-2657`）。

### 2.2 执行流水线（固定顺序）

原文顺序：`tools/README.md:105: "Every call runs a fixed pipeline: `tools/pre-execute` (extensible allow/deny/ask) → registered monotonic guards → `tools/execute` (around-dispatch wrappers) → `tools/post-execute` (inspect/replace, attach context) → definition-owned `finalizeContent` → the observe-only `tools/result` event."`

实现侧对应：
```
tools/lib/index.js:3225: const gate = await this.ctx.waterfall(carrier, "tools/pre-execute", exec, () => Promise.resolve({ kind: "allow" }));
tools/lib/index.js:3226: const askResolution = gate.kind === "ask" ? await this.serviceAsk(exec, gate) : { decision: gate, approvalCancelled: false };
tools/lib/index.js:3241: const denialReason = decision.kind === "allow" ? this.guardReason(exec) : decision.reason;
tools/lib/index.js:3243: if (denialReason !== void 0) return await next({ kind: "post-result", exec, result: ... });
tools/lib/index.js:3331: const result = await this.ctx.waterfall(carrier, "tools/execute", mutableExec, () => this.dispatchToolBody(mutableExec));
tools/lib/index.js:3504: const decision = await this.ctx.waterfall(scopeTarget(this, exec.agent), "tools/post-execute", exec, result, () => Promise.resolve({ kind: "accept" }));
tools/lib/index.js:3409-3420: notifyResult(exec, result) { Object.freeze(exec); ... this.ctx.events.dispatch("emit", [scopeTarget(this, exec.agent), "tools/result", exec, result]);
```

### 2.3 allow / ask / deny 如何表达与执行

- **表达**：`tools/pre-execute` waterfall 返回判别式联合 `{ kind: 'allow' | 'deny' | 'ask' | 'cancel' }`；默认 `{ kind: "allow" }`（`tools/lib/index.js:3225` 的 fallback）。
- **deny 的落地文本**：统一渲染为 `Error: <reason>`，并携带结构化 `error.info`（供 UI/PTC 投影，不进模型正文）：
  ```
  tools/lib/index.js:3247: content: [{ type: "text", text: `Error: ${denialReason}` }],
  tools/lib/index.js:3251: isError: true,
  tools/lib/index.js:3252: error: { message: denialReason, ...denialInfo === void 0 ? {} : { info: denialInfo } }
  ```
  佐证：`tools/README.md:123: "A pre-execute denial may attach `ToolErrorInfo` beside its model-facing reason ... without adding that detail to model content."`
- **cancel 的落地**：`ABORTED_BEFORE_DISPATCH`（未进入 body）：
  ```
  tools/lib/index.js:3236: if (decision.kind === "cancel") return await next({ kind: "post-result", exec, result: toolAbortedBeforeDispatchResult() });
  ```
- **guard（单调、只能否决）**：晚注册的 listener 无法把 deny 翻回允许：
  ```
  tools/lib/index.js:2646: guardReason(exec) { for (const guard of this.guards.values()) { const reason = guard(exec); ... } }
  tools/lib/index.js:2921: guard(guard) { return this.layers.effect(this.ctx, (layer) => layer.guards.append(guard), { label: "tools.guard()" }); }
  ```
  佐证：`tools/README.md:85: "`ctx.tools.guard(guard)` registers a monotonic synchronous guard after the extensible `tools/pre-execute` waterfall: a returned reason denies the call, and no later listener can turn that denial back into permission."`
- **ask → approval 服务**：`serviceAsk()` 是唯一的 ask 出口；`allowed-once` 才放行，其余三种（`rejected` / `cancelled` / `unavailable`）**全部 fail-closed 为 deny**，且各自给出可区分的理由文本：
  ```
  tools/lib/index.js:3440: const approval = this.ctx.get("approval");
  tools/lib/index.js:3441: if (approval === void 0) return { decision: { kind: "deny", reason: ask.reason ?? `tool "${exec.name}" requires approval (not yet supported)` }, approvalCancelled: false };
  tools/lib/index.js:3448: if (exec.agent === void 0) return { decision: { kind: "deny", reason: `tool "${exec.name}" requires approval, but the call has no agent to route it through` }, ... };
  tools/lib/index.js:3464: case "allowed-once": return { decision: { kind: "allow" }, approvalCancelled: false };
  tools/lib/index.js:3468: case "rejected": return { decision: { kind: "deny", reason: `the user rejected tool "${exec.name}"` }, ... };
  tools/lib/index.js:3475: case "cancelled": return { decision: { kind: "deny", reason: `approval for tool "${exec.name}" was cancelled` }, approvalCancelled: true };
  tools/lib/index.js:3482: case "unavailable": return { decision: { kind: "deny", reason: `tool "${exec.name}" requires approval, but no approval channel is available` }, ... };
  ```
  approval 侧契约：`user-approval/README.md:2: "... a one-shot decision before a sensitive tool action proceeds. The `ask` policy sends each request to the deployment's human or machine answerers; `never` rejects it without prompting. Missing or failed answerers return `unavailable`, so the action fails closed, and an approval applies only to that request."`
  会话级策略只有 `ask` / `never` 两档，且 `never` 在服务内部先于 waterfall 判定，无法被 prepend 的 listener 绕过：`user-approval/README.md:78` "The `never` policy is enforced inside the service before waterfall dispatch, so a listener registered later with `prepend` cannot bypass the deterministic rejection."`
  审计落盘为成对事件：`user-approval/README.md:86` "`request()` appends `approval/asked` with the request identity and tool, then `approval/decided` with the closed outcome ... Both are log-only."
- **权限预设把 sandbox 模式与 approval 策略打包**（`permission-presets/README.md:84-86`“Write path”）：`set()` 解析预设 → 仅当有效预设变化时 append `permission/preset` → 通过 `setSandboxMode` / `setApprovalPolicy` 写各个 knob；净零选择不写事件。
- **ask 的模型可见文案**（与本次会话实际收到的系统上下文一致）：
  `user-approval/README.md:116``Approval policy: ask. Operations that require approval may ask through the configured answerers; without an available answerer, the request fails closed.`
  `user-approval/README.md:122``Approval prompts are disabled in this session: actions that require approval are rejected automatically — do not request sandbox escalation (do not set `sandbox_permissions`).`

### 2.4 工具结果如何裁剪

DSH 在此处有**三套并存机制**，触发点各不相同：

**(a) spill（工具作者/策略驱动，落盘 + 预览）** —— `dsh-spill` 提供 `ctx.spillStore.saveText()` 返回 `SpillRef = { locator, bytes, retrievalHint }`；`dsh-spill-policy` 挂 `tools/post-execute` 监听器决定何时替换：
```
spill-policy/lib/index.js:127: const Config = z.object({ maxInlineTokens: z.number() });
spill-policy/lib/index.js:144: if (!Number.isSafeInteger(cap) || cap < 0) throw new Error(`spill-policy: maxInlineTokens must be a non-negative integer (got ${cap})`);
spill-policy/lib/index.js:187: const spillStore = ctx.get("spillStore");
spill-policy/lib/index.js:189: const ref = await spillStore.saveText({ ... });
spill-policy/lib/index.js:237: ctx.on("tools/post-execute", async (exec, result, next) => {
spill-policy/lib/index.js:256: ctx.on("tools/ptc-dispatch-log", async (dispatch, next) => {
```
配置项只有 `maxInlineTokens`（省略 = 关闭）：`spill-policy/README.md:43: | `maxInlineTokens` | omitted | Estimated token cap for retained text, images, image descriptions, and notices; omission disables retention |`。
提示文案（模型可见）由 `formatSpillNotice` 生成，本地后端形态为：
```
spill-policy/lib/types/notice.js:20: return `${OPEN}${describeOmitted(omitted, 'bytes')}${imageNotice}${LOCATION}${ref.locator}${GUIDANCE_SEPARATOR}${ref.retrievalHint}${CLOSE}`;
```
失败降级为 best-effort（保留原文并告警），不会把成功调用变成错误：`spill-policy/README.md:65`"A missing owner or spill backend, failed storage, missing route image pricing, or unavailable execution-world image path logs a warning and keeps the original content."`

**(b) compaction 前置 pruner（token 压力驱动，头+尾截断）** —— 仅在压缩触发后、选择压缩区间前运行：
```
compaction-tool-result-pruner/README.md:52: | `thresholdChars` | `8192` | Trim when combined text exceeds this many Unicode code points. |
compaction-tool-result-pruner/README.md:53: | `headChars` | `4096` | Leading Unicode code points retained. |
compaction-tool-result-pruner/README.md:54: | `tailChars` | `1024` | Trailing Unicode code points retained. |
```
替换事件以 `sourceEventSeqs` 指回原事件，并**紧邻前置**一条 `compaction/prune` 影子计价事件：
`compaction-tool-result-pruner/README.md:78`"`compaction/prune` immediately precedes its replacement, pricing the exact replaced range through the injected token meter ..."

**(c) per-tool retainer（工具自身预算驱动）** —— `dsh-output-retention` 提供 `ItemRetainer` / `TextRetainer` / `formatRetentionNotice` / `truncateWithoutSplittingSurrogatePair`。
- `TextRetainer` 按**字节**计数（head / tail / headTail），`finish()` 会裁掉切点上的半个码点：
  `output-retention/README.md:56`"`head`, `tail`, and `headTail` count bytes, not characters or lines ... `finish()` trims a partial codepoint at each cut."
- `truncated` 的语义被明确限定为“预算事实”，不表示上游不完整：
  `output-retention/README.md:83: "`truncated` is a budget fact: the retainer omitted otherwise-available content because of a cap. It never means the upstream was incomplete ..."`
- 已使用该库的工具及各自仍自有的职责（`output-retention/README.md:85`“How the current tools use it”；`read` 的排除理由见 `output-retention/README.md:95`）：`glob`/`grep`/`web_search` 用 `ItemRetainer`(head)，`bash` 用 `TextRetainer`，`web_fetch` 用 `TextRetainer`；**`read` 不在其中**，因其 `offset`/`limit` 分页是文件专用渲染器。

**(d) 超时裁剪** —— `timeoutMs` 本身在 registry 中**只是声明式**，不强制：
`tools/README.md:232: "`timeoutMs` on a definition is declarative only — the registry never enforces deadlines; enforcement requires the `@deepseek-ai/dsh-tool-call-timeout-policy` wrapper."
该 wrapper 是**协作式**的：只 abort `exec.signal`，等下游结算后才把结果替换为 `Error: tool call timed out after <ms>ms` + `{ name: 'ToolTimeoutError', code: 'TOOL_TIMEOUT' }`；忽略信号的工具有多慢就等多久。
`tool-call-timeout-policy/README.md:122: - **Cooperative, never a hard kill** — the deadline only notifies via `exec.signal` ...`
`tool-call-timeout-policy/README.md:62: - **Enforcement home, not a library.** `dsh-timeout` owns timing and classification ...`

> **未核实**：`dsh-tool-*` 各具体工具（read/write/edit/bash/glob/grep/web_fetch）在自己的 `lib/index.js` 中声明的 byte/char 预算常量行号，本次未逐一核对；上表 (c) 的角色分工来自 `dsh-output-retention` README。

---

## 3. 事件与会话持久化

### 3.1 事件类型

DSH 的 `SessionEventMap` 是 **declaration-merging 可扩展** 的；发布物中保存了本 build 认识的完整事件名白名单（生成物）：

`session/lib/types/known-event-types.js:21: export const KNOWN_SESSION_EVENT_TYPES = new Set([ ... ]);`（共 56 项，行 22–81）

按用途归类（每一项均为文件内字面量，行号即该字符串所在行）：

| 类别 | 事件 | 行号 |
|---|---|---|
| 会话生命周期 | `session/end-seed`, `session/title` | 54, 55 |
| turn/step | `turn/start`, `turn/end`, `step/start`, `step/end` | 76, 77, 57, 58 |
| 模型请求 | `request/header`, `request/context`, `llm/retry`, `llm/retry-started` | 50, 49, 44, 45 |
| surface（模型可见） | `system/message`, `developer/message`, `user/message`, `assistant/message`, `tool/result` | 62, 36, 78, 28, 75 |
| assistant 尝试 | `assistant/attempt` | 27 |
| 工具调用 | `tool/call`, `tool/ptc-dispatch`, `tool/ptc-dispatch-start` | 72, 73, 74 |
| inbox | `agent/inbox/spliced` | 23 |
| 审批 | `approval/asked`, `approval/decided`, `approval/policy` | 24, 25, 26 |
| 压缩 | `compaction/start`, `compaction/summary`, `compaction/end`, `compaction/prune` | 33, 34, 31, 32 |
| 目标/计划/待办 | `goal/change`, `plan/mode`, `todo/write` | 40, 48, 67 |
| 权限/沙箱 | `permission/preset`, `sandbox/mode` | 47, 51 |
| 子代理/团队/workflow | `subagent/*`, `team/*`, `tool-workflow/*` | 59–66, 68–71 |
| 其它 | `command/run`, `command/done`, `hook/invoked`, `hook/result`, `image/offload`, `model/selection`, `workspace/changes` 等 | 29, 30, 41, 42, 43, 46, 80 |

**只有一条消息投影事件**（需要显式纯解释器）：
`session/lib/types/known-event-types.js:83: export const MESSAGE_PROJECTION_EVENT_TYPES = new Set(['image/offload']);`

**事件信封**的精确字段白名单（wire 侧校验，多余字段直接报错）：
```
api-session-controller/lib/types/client/session-wire-event.js:16-28: case 'type' / 'seq' / 'time' / 'data' / 'ignorable' / 'surfaceOp' / 'sourceEventSeqs'; default: throw new Error(`${subject} has unexpected field ${key}`);
api-session-controller/lib/types/client/session-wire-event.js:31-37: seq 必须为非负安全整数且非 -0；time 必须为安全整数；必须自有 data；ignorable 若存在必须恰为 true
```
未知事件类型的兼容机制是信封上的 `ignorable` 标记，而不是事件名注册：
`session/lib/types/known-event-types.js:10-13: "The persistence read path refuses to interpret a log containing a type outside this set unless the event carries the envelope's `ignorable` marker ..."`

**surface 事件的额外元数据契约**（模型可见性的唯一开关）：
`session/README.md:50: "Surface events (`system/message`, `developer/message`, `user/message`, `assistant/message`, `tool/result`) require `surfaceOp` in both typed events and append input. A replacement uses exactly `{ op: 'replace', startSeq, endSeq }`, with inclusive `SessionSeq` endpoints in current surface order. An Assistant message embeds its exact compact provider stream and forbids `sourceEventSeqs`. Known log-only events forbid both metadata fields and never produce a message."`
实现侧校验：`session/lib/index.js:299: if (raw.surfaceOp !== void 0) throw new Error(`session event "${event.type}" is not surface-eligible and cannot carry surfaceOp`);`、`session/lib/index.js:304: if (op === void 0) throw new Error(`session event "${event.type}" is surface-eligible and requires a surfaceOp marker`);`

### 3.2 序号

- **每个事件有一个全局连续 seq，无 per-turn 序号**：
  ```
  session/lib/index.js:1455: seq: SessionSeq(this.log.length),
  session/lib/index.js:1400: /** The next event's sequence number — always the log length (the `seq = log.length` contiguity contract). */
  session/lib/index.js:423: if (event.seq !== expectedSeq) throw new Error(`session event seq ${event.seq} is not contiguous; expected ${expectedSeq}`);
  ```
- **两种数值类型**（同一底层数字，语义不同）：
  `session/README.md:62` 同节 "Session log positions use two numeric types. `SessionSeq` identifies an existing event or inclusive event watermark; `SessionLogOffset` identifies a gap, prefix length, or read boundary and may equal the event count. `SessionSeqCursor` adds the `-1` "no event yet" value, while `OptionalSessionSeq` uses `null` when absence is data."
  实现：`session/lib/index.js:22: `SessionSeq must be a non-negative safe integer, got ${String(value)}``。
- **“重连基线”不是 sequenceNo**：DSH 的客户端重连用 **follow 流的 opening cursor + 页连续性**，不是 `{sequenceNo, baseline}` 对：
  `api-gateway/lib/types/client/journal-stream.js:8-13: "Owns snapshot-first opening, ordered live delivery, pagination, and repair. The domain retains its published window during reconnection. A replacement is published only after the opening page reaches the generation's cursor. Notifications never change a cursor and wait behind an in-flight gap repair."`
  `api-gateway/lib/types/client/journal-stream.js:157-165: opening(item, resumed) { ... if (resumed && this.lastCursor !== undefined && this.options.compare(cursor, this.lastCursor) < 0) throw protocolViolation(`${this.options.name} resumed at a cursor behind the last applied entry`); ... }`
- **投影快照的一致性切点**用 `asOfSeq`（每个返回值反映的最后一个事件 seq）：
  `session-projection/README.md:58`"`snapshot(session)` — `{ asOfSeq, values }`, where `asOfSeq` is the seq of the last event every value reflects"；类型声明 `api-session-controller/lib/typert.host.js:2205: "export interface SessionProjectionBaseline { readonly asOfSeq: number; readonly values: SessionProjectionValues; }"`（`-1` 表示空日志，见 `api-session-controller/lib/client.js:1549: asOfSeq: value.asOfSeq === -1 ? -1 : SessionSeq(value.asOfSeq)`）。

> **未核实**：未在发布物任何文件中找到 `sequenceNo` 这一标识符（已对 `dsh` 下 3091 个非二进制文件做过一次全文包含性搜索，结果为空）。DSH 中与“重连基线”最接近的概念是 follow 流的 opening `cursor` 加 `replace/prepend/append` 变体语义，**与 `{baseline, sequenceNo}` 这一形状不同名也不同形**。

### 3.3 重连恢复（客户端 follow 协议）

**打开顺序：先 follow，再取首页。** 客户端适配器 `SessionEventStream` 只发布连续的四种变更：
`api-session-controller/README.md:48: "The Client adapter exposes `SessionEventStream`, a Gateway `RemoteJournalStream` bound to one ordinary or direct-subagent address. It opens follow before the initial page, publishes only contiguous `replace`, `prepend`, `append`, and `settle-assistant` changes, and repairs reconnect or sequence gaps through a tail page."`

**追平（follow）语义**（`api-gateway/lib/types/client/journal-stream.js`）：
```
:189: if (this.options.compare(cursor, last) <= 0) return;                              // 重复帧丢弃
:191: if (this.options.compare(first, last) <= 0) throw protocolViolation(`... emitted a partially overlapping entry`);  // 部分重叠 = 协议违规
:194: if (!this.options.follows(last, first)) { const request = this.repairPageRequest(); const superseded = await this.replaceThrough(request, cursor, ...); }  // 断层 → 修复页
:206: this.options.publish({ type: 'append', entry });
```
**修复页必须走到 opening cursor**，否则协议违规：
```
:213: this.assertPageThrough(page, requiredCursor);
:226: throw protocolViolation(`${this.options.name} page did not reach its opening cursor`);
:233: this.options.publish({ type: 'replace', page, entries, hasMore: this.options.hasMore(page) });
```
**历史向前分页**（`prepend`）同样校验连续性：
```
:92: const tail = accepted.at(-1);
:93: if (tail !== undefined && before !== undefined && !this.options.follows(this.options.last(tail), before)) { this.options.publish({ type: 'prepend', page, entries: [], hasMore: false }); throw protocolViolation(`${this.options.name} history page is discontinuous`); }
```
**物理 carrier 重试白名单**：只有 `RemoteStreamCarrierError` 才触发自动重连；其它异常是终态失败：
```
api-gateway/lib/types/client/remote-stream.js:113: if (!(error instanceof RemoteStreamCarrierError)) throw terminalStreamFailure(error);
api-gateway/lib/types/client/remote-stream.js:120: await waitForRemoteStreamRetry(this.connection, error, attempt, signal);
api-gateway/lib/types/client/remote-stream.js:149: if (connection.generation.getSnapshot() !== undefined) { if (attempt === 1) return; throw error; }
```
README 的业务层结论：`api-session-controller/README.md:48` 同段 "A business, persistence, or unresolved continuity failure terminates the stream, while only physical carrier loss selects automatic resumption."

**分页预算**（可核实的具体数值，`api-session-controller/README.md:63`）：初始 follow / 重连 opening / `loadOlder()` 至少请求 **50** 条 append 源 `user/message` 与 `assistant/message`，且至少跨 **2** 个 `turn/start`；Host 在同时满足两个下限的第一个 Turn start 停止，或到 **500** 条计数消息或历史耗尽为止。`loadThrough()` 每页最少 **200** 条消息。

**投影流（控制流）与 journal 流是两套**：`SessionControlStream` 是 `RemoteSnapshotStream`，**每一代 opening 都是完整进程内基线**，重连即整体替换，而不是当作 durably 事件处理：
`api-session-controller/README.md:48: "`SessionControlStream` is a Gateway `RemoteSnapshotStream`; every generation opens with a complete process-local baseline, so reconnect replaces projection state instead of treating transient values as durable events."`

### 3.4 fork API 的确切语义与边界

**签名**：`ctx.sessions.fork(source, boundary?, childSessionId?)`（`session/README.md:68`）。

**语义（高置信，有实现级证据）**：
```
session/lib/index.js:1887: fork(source, boundary, childSessionId) {
session/lib/index.js:1888: if (childSessionId !== void 0 && this.get(childSessionId) !== void 0) throw new SessionForkError(`session "${childSessionId}" already exists`, "SESSION_ALREADY_EXISTS");
session/lib/index.js:1890: const events = liveSource.snapshotEvents();
session/lib/index.js:1891: const resolved = this._forkBoundary(liveSource.id, events, boundary);
session/lib/index.js:1892: const seed = resolved === void 0 ? [] : buildForkSeed(events, resolved);
session/lib/index.js:1895: inheritedEventCount: SessionLogOffset(resolved === void 0 ? 0 : resolved + 1),
session/lib/index.js:1898: parentSession: liveSource.id, isSeeded: true
```
- **闭区间**：`boundary` 是“子会话继承到的（含）源事件 seq”。
  `session/lib/types/fork.js:19: const prefix = events.slice(0, boundary + 1);`（`boundary + 1` 证明闭区间）
- **继承标记**：紧接前缀追加 `session/end-seed{ inherited: true }`：
  `session/lib/types/fork.js:20-25: prefix.push({ type: 'session/end-seed', seq: SessionSeq(boundary + 1), time: events[boundary].time, data: { inherited: true } });`
- **只修复“开着的尾巴”**：用 `forked` 原因补合成收尾（未应答工具结果 + step/end + turn/end），**已关闭的 step/turn 保持不变**：
  `session/lib/types/fork.js:26: return prefix.concat(openTurnClosers(prefix, { kind: 'forked' }));`
  `session/lib/types/fork.js:8-9: "Copy an inclusive event prefix, mark its inherited cut, and close its open tail with forked results and step/turn endings. Closed steps and turns are preserved unchanged."`
- **`inheritedEventCount` 只计被复制的前缀**，不计合成收尾：
  `session/lib/types/fork.js:15-16: "@returns a new array retaining the source event objects, followed by synthetic closers outside the inherited prefix counted by `inheritedEventCount`."`
- **边界校验（拒绝条件）**：
  ```
  session/lib/index.js:1911: if (!Number.isSafeInteger(boundary) || boundary < 0) throw new SessionForkError(`fork boundary for session "${sessionId}" must be a non-negative safe integer, got ${String(boundary)}`, "INVALID_BOUNDARY");
  session/lib/index.js:1912-1914: if (boundary >= events.length) { ... throw new SessionForkError(`fork boundary ${boundary} does not exist in session "${sessionId}" (last seq: ${lastSeq ?? "none"})`, "INVALID_BOUNDARY"); }
  session/lib/index.js:1917: if (boundaryEvent === void 0 || boundaryEvent.seq !== boundary) throw new SessionForkError(`fork boundary ${boundary} does not match a contiguous event seq in session "${sessionId}"`, "INVALID_BOUNDARY");
  ```
- **省略边界**：取最后一个事件；**空源会话 fork 出空子会话**（`resolved === undefined` → `seed = []`，`inheritedEventCount = 0`）：
  `session/lib/index.js:1908: if (lastEvent === void 0) return void 0;` 与 `session/lib/index.js:1909: boundary = lastEvent.seq;`
- **源必须是本进程 live 实例**（否则 `SESSION_NOT_LIVE` / `SESSION_NOT_FOUND`）：
  ```
  session/lib/index.js:1923: if (session === void 0) throw new SessionForkError(`session "${source}" not found`, "SESSION_NOT_FOUND");
  session/lib/index.js:1928: if (live !== source) throw new SessionForkError(`session "${source.id}" is not the live store instance`, "SESSION_NOT_LIVE");
  ```
- **子会话保留父会话的 `cwd`**：`session/lib/index.js:1897: ...liveSource.header.cwd !== void 0 ? { cwd: liveSource.header.cwd } : {},`
- **`isSeeded` 的构造不变量**（子会话必须有显式 seed 与继承计数）：
  `session/lib/index.js:1340: if (this.header.isSeeded && seed === void 0) throw new Error("seeded session requires an explicit constructor seed");`
  `session/lib/index.js:1341: if (this.header.isSeeded && suppliedInheritedEventCount === void 0) throw new Error("seeded session requires an inherited event count");`

**上层 API（桌面/网关）的默认边界与 README 的措辞不同，需要区分**：
`api-session-controller/README.md:57: "Fork copies the exact inclusive event prefix selected by `atSeq`, including a cut inside an open turn. The child records its inherited marker before synthetic fork results and closing events. Omitting `atSeq` selects the latest completed turn and its standalone tail, stopping before the next turn or queued input; a nonexistent event is rejected. The chat action selects a completed turn."`
即：**core `sessions.fork` 省略边界 = 最后一个事件（可切在 open turn 中间）**；**API/UI 层省略 `atSeq` = 最近一个已完成 turn + 其独立尾巴**。二者不是同一默认值。

**已知边界（README 自陈）**：
- `session/README.md:191: "Fork closes only the open tail and does not repair missing results in previously closed steps."
- 同上 "**No session tree beyond fork** — a pi-style entry tree over branched sessions is deferred unless a consumer needs more than boundary-based forking."
- fork 生成的恢复文案与 live/crash 恢复文案不同（前者描述“前缀里没有/有开始记录”），见 `session/README.md:160` 整段。

### 3.5 服务端持久化接口

```
session-persistence/README.md:36-42: "const handle = await ctx.sessionPersistence.create(header)     // store a new session, take write ownership
const handle = await ctx.sessionPersistence.open(id, 'write')  // claim single-writer ownership of an existing session
const reader = await ctx.sessionPersistence.open(id, 'read')   // observe without ownership
const snap = await ctx.sessionPersistence.stat(id)             // header + revision (+ eventCount / sizeBytes) without a log read
const all = await ctx.sessionPersistence.list()                // one snapshot per visible stored session
await ctx.sessionPersistence.flush()                           // backend-wide durability barrier over every active write handle
```
- **单写者不变量**：第二个写打开 → `SessionAlreadyOwnedError`；已占用 id 的 `create` → `SessionAlreadyExistsError`；对 read 句柄写入 → `SessionReadOnlyError`；关闭后任何操作 → `SessionHandleClosedError`；写句柄丢失所有权 → `SessionOwnershipLostError`（均见 `session-persistence/README.md:53`“Ownership and visibility”）。
- **durability barrier**：只有已 resolve 的 `flush` 承诺能扛住崩溃；`append` 的 resolve 只表示被接受、排序、对本后端实例可见（`session-persistence/README.md:53` 同段）。
- **物理布局**：`<root>/--<normalized-cwd>--/<encoded-id>/session.v3.jsonl.zstd`（当前格式 v3）；运行时选择数值最高的 canonical generation（`session-persistence-jsonl/README.md:72`“On-disk layout”）。
- **撕裂尾恢复**：不完整的最后一行丢弃；撕裂的最后一个 zstd 帧只贡献其完整解码出的 JSONL 记录，写句柄会截断撕裂字节并在首个新批次前把这些记录重新持久化（`session-persistence-jsonl/README.md:78`）。

---

## 4. 上下文压缩

### 4.1 三包分工

| 包 | 角色 |
|---|---|
| `dsh-compaction` | 抽象契约 `CompactionEngine`（三个操作）+ `ctx.compaction` 服务 + 事件类型。**自身不做任何压缩** |
| `dsh-compaction-basic` | 出货后端：自动（压力/溢出）+ 手动 + 显式区间的 LLM 摘要 |
| `dsh-compaction-tool-result-pruner` | 可选前置：先裁剪超大工具输出，可能直接免掉摘要调用 |

`compaction/README.md:73: "- **The log-recorded bracket is the lock.** `compaction/start` is appended before summarization yields and `compaction/end` releases; every failure makes exactly one close attempt, and a failed close leaves the unmatched start as the intentional busy signal."`

### 4.2 触发时机

**（1）自动压力触发** —— 序列化的 `agent/pre-step` 监听器，在请求派生**之前**检查压力：
`compaction-basic/README.md:113: "With `auto: true`, a serial `agent/pre-step` listener checks pressure before request derivation: it prices the latest durable routed request envelope through `ctx.tokenMeter`, and when pressure crosses the routed model's threshold it prunes, then summarizes the oldest balanced span while keeping a priced recent tail."`
实现：
```
compaction-basic/lib/index.js:839: ctx.on("agent/pre-step", async ({ agent, signal }, next) => {
compaction-basic/lib/index.js:841: const result = await this.compactIfNeeded(agent, "pressure", signal);
```
**（2）上下文溢出恢复** —— `agent/request-error` 仅在 provider 确认 `CONTEXT_WINDOW_EXCEEDED` 时绕过正常阈值与保留策略，做一次最大化的均衡头部削减，且**只有 surface 的 `replaceGeneration` 前进后才授权 retry**：
```
compaction-basic/lib/index.js:861: ctx.on("agent/request-error", async ({ agent, failure, signal }, next) => {
compaction-basic/lib/index.js:862: if (failure.code !== CONTEXT_WINDOW_EXCEEDED_CODE || signal.aborted) return next();
compaction-basic/lib/index.js:868: if (retries >= policy.maxOverflowRetries) return next();
compaction-basic/lib/index.js:869: const generation = agent.session.surface.replaceGeneration;
compaction-basic/lib/index.js:872: result = await this.compactIfNeeded(agent, "context-overflow", signal);
compaction-basic/lib/index.js:883: if (signal.aborted || agent.session.surface.replaceGeneration <= generation) return next();
compaction-basic/lib/index.js:886: return { kind: "retry" };
```
重试预算在 agent 回到 idle 或产生新的 `assistant/message` 时清零：
```
compaction-basic/lib/index.js:853: ctx.on("agent/status", ({ agent, status }) => { if (status === "idle") this.overflowRetries.delete(agent); });
compaction-basic/lib/index.js:856: ctx.on("session/event", (session, event) => { if (event.type !== "assistant/message") return; ... this.overflowRetries.delete(agent); });
```
**（3）手动触发** —— `/compact` 命令（`dsh-command-compact`）；无后端时命令失败。手动路径**不需要** open turn，bracket 记 `turn: null`（`compaction/README.md:78`“Service API”："Automatic and explicit-region brackets recover their numeric owner from the open turn; manual brackets require no open turn and stamp `turn: null`."）
**（4）显式区间** —— `compactRegion(start, end, ...)`（程序化）。

三个操作的确切签名（README 级）：`compaction/README.md:78: "`compactIfNeeded` for automatic `pressure` or `context-overflow` triggers, `compactNow` for one explicit on-demand reduction, and `compactRegion` for a caller-selected surface range."

### 4.3 压缩对象与保留

- **对象是 surface 区间，起点永远不是 `system/message`**：
  `compaction-basic/README.md:113` 同段 "Every selected range starts at the first surface node that is not a `system/message`, so a system prompt at surface node 0 is never shadowed; a later `system/message` appended by an in-history prompt update is ordinary history that the range may shadow ..."
- **压缩产物是**一条带 `surfaceOp: { op: 'replace', startSeq, endSeq }` 的 `user/message`：
  `compaction/README.md:95` "it appends `compaction/start` (log-only) to acquire the lock, summarizes the range, appends the log-only `compaction/summary` record, replaces the selected span with one `user/message` carrying the summary — the only surface mutation — and appends `compaction/end` (log-only) to release the lock."
- **摘要必须能缩小才被接受**：`compaction-basic/README.md:125`"rejects a summary that does not shrink its source"
- **模型可见的包装标签**：`<compacted-summary>`；原始摘要文本保留在 `compaction/summary` 事件上（`compaction-basic/README.md:119`“Summarization mechanics”）。
- **摘要调用复用 provider 热前缀**：重放 surface node 0 的 system prompt + 上一次路由请求的 tools + 被遮蔽区间的消息，逐字节一致，只把压缩指令作为最后一条 user 消息追加（`compaction-basic/README.md:119` 同段）。仅返回的文本进入 checkpoint，**排除 reasoning 与 tool calls**。

### 4.4 剪枝策略

**(a) 压缩前的工具结果裁剪（可选）** —— 见 §2.4(b)。仅在压缩触发成立后运行；below-pressure 会话完全不碰。
**(b) 压缩边界必须均衡工具对** —— `toolPairingBalancedBefore(session, seq)` / `toolPairingBalancedAfter(session, seq)`：
`compaction/README.md:91: "A safe edge has no unanswered assistant tool call crossing it."
显式区间路径的实际报错：
```
compaction-basic/lib/index.js:557: if (!toolPairingBalancedBefore(session, nodes[startIdx])) throw new Error(`compactRegion: start seq ${start} is not a balanced boundary (would split a step's tool-call/result pair)...`);
compaction-basic/lib/index.js:558: if (!toolPairingBalancedAfter(session, nodes[endIdx])) throw new Error(`compactRegion: end seq ${end} is not a balanced boundary (would split a step, or the step is still open)`);
```
**(c) 区间选择**（保留最近若干 token 逐字）：
```
compaction-basic/lib/index.js:410: function selectCompactableRange(session, measurement, retainTokens) {
compaction-basic/lib/index.js:421: if (accumulated >= retainTokens) break;
```

### 4.5 可配置项（`dsh-compaction-basic`）

配置键白名单（实现）：
```
compaction-basic/lib/index.js:19-29: const POLICY_CONFIG_KEYS = ["thresholdRatio","headroomTokens","retainRatio","retainTokens","summarizationProvider","summarizationModel","maxTokens","compactionRetries","maxOverflowRetries"];
compaction-basic/lib/index.js:31-35: const BASIC_COMPACT_CONFIG_KEYS = new Set([...POLICY_CONFIG_KEYS, "modelPolicies", "auto"]);
compaction-basic/lib/index.js:37-41: const MODEL_POLICY_KEYS = new Set(["provider", "model", ...POLICY_CONFIG_KEYS]);
```

| 字段 | 默认 | 含义与出处 |
|---|---|---|
| `thresholdRatio` | `0.8` | `compaction-basic/README.md:66`；常量 `compaction-basic/lib/index.js:15: const DEFAULT_THRESHOLD_RATIO = .8;` |
| `headroomTokens` | `65536` | `compaction-basic/lib/index.js:63: const headroomTokens = config.headroomTokens ?? 65536;` |
| `retainRatio` | `0.16` | `compaction-basic/README.md:68`；常量 `compaction-basic/lib/index.js:17: const DEFAULT_RETAIN_RATIO = .16;` |
| `retainTokens` | — （与 `retainRatio` 互斥） | `compaction-basic/lib/index.js:192: if (retainRatio !== void 0 && retainTokens !== void 0) throw new Error(...retainRatio and retainTokens are mutually exclusive`);` |
| `maxTokens` | `headroomTokens`（65536） | `compaction-basic/lib/index.js:64: const maxTokens = config.maxTokens ?? headroomTokens;` |
| `compactionRetries` | `1` | `compaction-basic/lib/index.js:82: compactionRetries: config.compactionRetries ?? 1,` |
| `maxOverflowRetries` | `1` | `compaction-basic/lib/index.js:83: maxOverflowRetries: config.maxOverflowRetries ?? 1,` |
| `auto` | `true` | `compaction-basic/README.md:62`“Tuning when condensation starts”表 |
| `modelPolicies` | `[]` | 精确 `{provider, model, ...partialPolicy}` 覆盖；重复即拒绝加载（`compaction-basic/README.md:62` 同表） |
| `summarizationProvider` / `summarizationModel` | `''` | 成对设置；空对则用最新路由请求目标，再退回 `AgentOptions`（`compaction-basic/README.md:62` 同表） |

**触发阈值公式**（README 原文，行 62）：`floor(min(W × 0.8, W − O − B))`，其 `B = 65,536`；保留最近 `W − O` 的 16% 逐字。
实现：
```
compaction-basic/lib/index.js:130: const pressureBudgetTokens = messageBudgetTokens - policy.headroomTokens;
compaction-basic/lib/index.js:131: if (pressureBudgetTokens <= 0) throw new TargetPressureConfigError(targetKey, ...);
compaction-basic/lib/index.js:132: const thresholdTokens = Math.floor(Math.min(contextWindow * policy.thresholdRatio, pressureBudgetTokens));
compaction-basic/lib/index.js:133: const retainTokens = policy.retainTokens === void 0 ? Math.floor(messageBudgetTokens * policy.retainRatio) : policy.retainTokens;
compaction-basic/lib/index.js:134: if (retainTokens >= thresholdTokens) throw new TargetPressureConfigError(...);
```
**加载期快速失败**：未知键、重复 per-model 覆盖、非法 token 数、两种保留形式同给、`retainRatio >= thresholdRatio` 都会在加载时拒插件（`compaction-basic/lib/index.js:155-156` 与 `compaction-basic/README.md:78`“Tuning”）。

**pruner 配置**：`thresholdChars=8192` / `headChars=4096` / `tailChars=1024`（`compaction-tool-result-pruner/README.md:52-54`），且三个值的和必须落在 threshold 之内，未知键直接拒插件。

### 4.6 压缩的边界（README 自陈）

`compaction/README.md:160-162`“Known Limitations”三段：
- **压缩只能由人命令或自动压力触发，没有面向模型的压缩工具**："Human command, not a model tool — condensation is triggered by the `/compact` command and by automatic pressure; no model-facing compaction tool is registered."
- **不可分割单元溢出不在契约内**："balanced summary compaction cannot split one indivisible unit. The optional pruning companion can still repair a closed tool pair when text-bearing tool-result bulk is removable; a large non-tool node or a tool unit whose non-prunable remainder is oversized cannot be compacted."
- **压缩只缩小派生历史，从不缩 system prompt / tools / session 前缀**："An envelope that alone approaches the window is not surface-compaction work — compaction shrinks derived history, never the system prompt, tools, or session prefix."

---

## 5. 关键数据结构与文件索引（便于后续核对）

| 文件（相对 `dsh/node_modules/@deepseek-ai/`） | 行数 | 作用 |
|---|---|---|
| `dsh-agent-loop/lib/index.js` | 1982 | turn/step 驱动、inbox、工具调度、请求构造 |
| `dsh-session/lib/index.js` | 1934 | Session、surface 投影、fork、append 校验 |
| `dsh-session/lib/types/fork.js` | 28 | `buildForkSeed` |
| `dsh-session/lib/types/known-event-types.js` | 86 | 事件名白名单 + 消息投影白名单 |
| `dsh-session/lib/types/repair.js` | — | `interruptedTurnClosers` / `ToolCallRecovery` |
| `dsh-tools/lib/index.js` | 3715 | schema 子集校验、DSL 编译、注册表、执行流水线、ask 解析、PTC |
| `dsh-compaction/lib/index.js` | 176 | 抽象 `CompactionEngine` 契约 |
| `dsh-compaction-basic/lib/index.js` | 1028 | 自动/手动压缩后端、配置解析、区间选择 |
| `dsh-spill-policy/lib/index.js` | — | `tools/post-execute` 结果保留策略 |
| `dsh-spill-policy/lib/types/notice.js` | 59 | spill 提示文案格式化与识别 |
| `dsh-api-gateway/lib/types/client/journal-stream.js` | — | follow cursor / 分页 / 修复语义 |
| `dsh-api-gateway/lib/types/client/remote-stream.js` | 206 | 物理 carrier 代际重连 |
| `dsh-api-session-controller/lib/types/client/session-wire-event.js` | 43 | wire 事件信封校验 |

---

## 6. 未核实项汇总

以下内容本次**未取得发布物中的行号级证据**，不做断言：

1. `sequenceNo`：发布物 3091 个非二进制文件中不存在该标识符。DSH 的重连协议是 `cursor`（`SessionSeqCursor`，空日志 `-1`）+ `replace/prepend/append` 连续性，**不是** `{baseline, sequenceNo}` 形状。若确需该形状，属于 DSH 未实现能力，本文不给出等价映射。
2. 各包 `README.md` 中链接的 `src/*.ts` 与 `docs/subsystems/*.md` 在发布物中不存在（app.asar 只含 `lib/*.js`）。因此**所有**“设计意图”类描述只能引用 README 文本，无法与 TypeScript 源交叉验证。
3. `dsh-agent-loop` 中 `agents[].reasoningEffort` / `agents[].maxTokens` 的 zod schema 行号未定位。
4. 各具体工具（`dsh-tool-fs` / `dsh-tool-bash` / `dsh-tool-pwsh` / `dsh-tool-web` 等）内部的字符/字节预算常量行号未逐一定位；§2.4(c) 的角色分工依据 `dsh-output-retention` README 的汇总表。
5. 渲染/客户端一层的消息锚点重放细节（`assistant/live-chunk` 的 `startedAfterSeq` / `nextIndex` 语义）只引用了 `api-session-controller/README.md:48` 的整段描述，未逐行核对 `dsh-client-ui-conversation` 的实现。
6. `dsh-ptc-runtime` 各语言 SDK 渲染器与执行器崩溃（executor collapse）契约未展开。
