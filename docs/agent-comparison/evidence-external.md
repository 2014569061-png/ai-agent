# 外部成熟编码 Agent 的底层机制与转录/UI 设计：证据汇编

> 范围：Claude Code、OpenAI Codex CLI、Aider、Cline、Roo Code、OpenHands、Cursor、DeepSeek Harness（DSH，本地发行物）。
> 本文**不审计 NEXUS 代码库**（由另一名 teammate 负责）。
>
> **置信度标记约定**
> - `[verified: read source]` —— 我实际读了源码/官方仓库中的源文件（含本地 DSH 发行物内的 `lib/*.js`，以及上一轮 in-repo 调研文档中带 `path:line` 的既有证据）
> - `[verified: official docs]` —— 我实际抓取了官方文档页面（URL 见链接）
> - `[inferred]` —— 由多条证据推断，无单一直接出处
>
> **本次调研的工具限制（影响覆盖度，必须声明）**
> - `web_search` 在本会话中不可用（每次都返回 "DeepSeek returned no web_search_tool_result blocks"）。**所有外部结论均来自我实际抓取的 URL，没有任何一条来自搜索摘要。**
> - `raw.githubusercontent.com` 在本网络下不可达（TLS 握手失败），因此外部仓库的源码级引用只能通过 GitHub 的 HTML 页面或官方文档站获得，**未做逐行源码核对**。
> - Claude Code 与 OpenAI 的文档站支持在 URL 后追加 `.md` 返回原始 Markdown；本报告对其引用均以该形式抓取。
> - DSH 部分复用 `docs/dsh-comparison/` 既有调研（带 `path:line`），这些路径相对于 app.asar 内的 `dsh/`；本次我重新阅读了该文档的原文段落，未重新进入 asar 逐行复核。

---

## 0. 横向速览（先给结论）

| 维度 | 最值得注意的差异 |
|---|---|
| 上下文压缩 | Claude Code、Codex、OpenHands、Cline 都会**自动摘要**；Aider **完全不做自动压缩**，靠 `--max-chat-history-tokens` 软阈值 + 用户 `/clear`；DSH 是"阈值压力 + provider 溢出恢复"双触发，且压缩是**面（surface）区间替换**而非重写历史。 |
| 工具结果截断 | 只有 Claude Code、Codex、DSH 把它做成了**系统级**多档机制；Aider/Cline/OpenHands 基本把输出原样塞回上下文。 |
| 编辑应用策略 | Aider 是唯一**为不同模型族分别设计编辑格式**的；Claude Code 是 search/replace 块 + 读前写约束；DSH 把 schema 子集校验放在 body 之前。 |
| 回退 | Claude Code（快照，100 个）、Cline（shadow git，每工具一次提交）、Cursor（快照）三者都是**独立于 git 的快照**；Aider 直接用**真 git 提交**；Codex 建议用 worktree + `codex apply`；DSH **没有会话级文件回退**，只有会话 fork。 |
| 转录 UI | Claude Code 有 fullscreen/classic 双渲染器 + 只渲染可见消息；Codex 是 TUI + alt-screen 可选；Cursor 是 GUI 时间线；DSH 是"详细度四档 + 过程折叠"的**策略表驱动**设计——这一点比大多数外部 agent 更结构化。 |
| 中断语义 | 明确区分"中断当前 turn"与"排队下一条"的只有 Claude Code、Codex、Cursor；DSH 的取消会为未派发调用合成 `tool/call`+`ABORTED_BEFORE_DISPATCH` 结果对，保证 tool 配对不破。 |

---

## 1. Claude Code（Anthropic）

主要来源：`https://code.claude.com/docs/en/*.md`（均可直接抓取原始 Markdown）。

### 1.1 上下文管理

- **自动压缩窗口可配置**，且是"模型上下文的一定比例"而非固定值。默认：未知模型 ID 时按 Claude Code 假设的窗口；原生 1M 窗口的模型（Fable 系、Sonnet 5+、Haiku 5.5、Opus 4.7+）默认在约 **967K tokens** 时压缩；`CLAUDE_CODE_DISABLE_1M_CONTEXT=1` 时把原生 1M 模型也当作 200K 处理，压缩点退回 200K。窗口可用 `/autocompact 500k`、`autoCompactWindow` 设置、`--autocompact`  flag、`CLAUDE_CODE_AUTO_COMPACT_WINDOW` 环境变量四档设置，接受 100K–1M。[verified: official docs]（[model-config](https://code.claude.com/docs/en/model-config.md)）
- **压缩的产物是"一条结构化摘要"替换整段会话**，摘要保留：用户请求与意图、关键技术概念、检查/修改过的文件与重要代码片段、错误及修复方式、待办任务、当前工作。**完整工具输出与中间推理丢失。**[verified: official docs]（[context-window](https://code.claude.com/docs/en/context-window.md)）
- **压缩后自动重建的内容**（这是"如何避免重新读文件"的答案）：[verified: official docs]（[context-window](https://code.claude.com/docs/en/context-window.md)）
  - 项目根 `CLAUDE.md` 与无 `paths:` 的规则 —— 从磁盘重新注入
  - 自动记忆（auto memory）—— 从磁盘重新注入
  - git status 快照 —— 重新读取
  - **plan mode 里写的计划 —— 从磁盘重新注入**
  - 会话中读/改过的文件 —— **重新读取最多 5 个，按最近修改优先**；超过 5,000 tokens 的文件只回一个路径引用（显示为 `Referenced file` 而不是 `Read`）
  - 被调用的技能正文 —— 重新注入，**每个技能上限 5,000 tokens、总计 25,000 tokens，超预算先丢最旧的**；截断保留文件开头
  - 后台命令与后台 subagent —— 继续运行，并提醒 Claude 它们还在跑，避免重复启动
  - 技能**描述列表不重新注入**（只有你实际调用过的技能正文会被恢复）
- **压缩使用独立请求**：与你的对话相同的 system prompt、tools、history，再加一条摘要指令作为最后的 user 消息。缓存热时该请求从缓存读前缀，所以中期 `/compact` 的成本远低于上下文体量所暗示的；**缓存冷时（如恢复久未活动的会话）该请求以未缓存输入重算整个历史**——这是 `/compact` 最贵的场景。[verified: official docs]（[prompt-caching](https://code.claude.com/docs/en/prompt-caching.md)）
- **空闲压缩**：在 1 小时 TTL 下长时间空闲的对话，会在缓存过期前不久自动压缩；用 `idleCompaction: false` 关闭（v2.1.290+）。[verified: official docs]（[prompt-caching](https://code.claude.com/docs/en/prompt-caching.md)）
- **subagent 有独立的自动压缩**：随 subagent 自己的上下文窗口填满触发；`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` 对 subagent 也生效；per-subagent 可用 frontmatter `autoCompactWindow` 设为 100000–1000000 之间的整数提前压缩（注意 frontmatter 里写 `200k` 会被读成 `200`，必须写 `200000`）。压缩事件落盘为 `{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"auto","preTokens":167189}}`。[verified: official docs]（[sub-agents](https://code.claude.com/docs/en/sub-agents.md)）

### 1.2 工具结果截断

这是被文档化得最细的一家。Bash 工具：[verified: official docs]（[tools-reference](https://code.claude.com/docs/en/tools-reference.md)）

- 命令输出边跑边写入一个 working file；输出超过 **5 GB 的命令被 kill**。
- **成功结果**：默认内联约 **30,000 字符**；超出后给"session 目录下的文件路径 + 最多前 2,000 字符预览"，文件截断在 64 MiB 之外。
- **失败结果**：内联约 **10,000 字符**；超出则从 read-back window 里切一段**头+尾**摘录（约 10,000 字符），**不给文件路径**。
- `BASH_MAX_OUTPUT_LENGTH` 控制从 working file 读回的字符数（默认 30,000，硬上限 150,000）——它扩大的是 read-back window（也是失败摘录的取材窗口），**不抬高内联上限**。
- `bashOutputMaxChars` 设置（v2.1.261+，上限 128,000）同时调整内联上限与 read-back window，设置后 `BASH_MAX_OUTPUT_LENGTH` 被忽略。
- 退出码语义被白名单化：只有 `grep`/`rg`/`egrep`/`fgrep`/`find`/`diff`/`test`/`[` 以及 `git diff`/`git grep` 的 exit 1 算"有效结果"，其它命令 exit 1 一律算失败——这直接决定了走 30K 档还是 10K 档。

其它工具的裁剪：[verified: official docs]（[tools-reference](https://code.claude.com/docs/en/tools-reference.md)）

- `Read`：单次调用默认最多返回 **25,000 tokens**（`CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS` 可调），并**拒绝整文件超过 256 KB**；超限时返回第一页并带 `PARTIAL view` 标记说明如何用 `offset`/`limit` 续读。v2.1.296+ 支持 `allow_large: true` 一次性读完（按剩余上下文空间计量）。图片在超过 500KB 时会被重新编码为低质量 JPEG。
- `WebFetch`：每次调用最多读 **100,000 字符**（v2.1.290+ 会告知还有多少未读）；响应默认缓存 15 分钟；**跨主机重定向不自动跟随**，而是返回一段文本告知原 URL 与目标 URL，由模型再发一次 fetch。
- `Glob`：结果按修改时间排序并**截断在 100 个文件**，截断时结果里带 truncation flag。
- Hook 输出：`additionalContext` / `systemMessage` / `initialUserMessage` 各自上限 **10,000 字符**；超出则写入 session 目录文件并把路径 + 最多 2,000 字符预览交给 Claude，**这个上限没有设置项或环境变量可调**。[verified: official docs]（[hooks](https://code.claude.com/docs/en/hooks.md)）

### 1.3 System prompt 结构

- **三层前缀，按"变化频率"排序**（这是 prompt caching 的核心设计）：[verified: official docs]（[prompt-caching](https://code.claude.com/docs/en/prompt-caching.md)）

  | 层 | 内容 | 何时变化 |
  |---|---|---|
  | System prompt | 核心指令、**工具定义** | 已加载工具定义集合变化时 |
  | Project context | CLAUDE.md、auto memory、无 `paths` 的规则 | 会话开始，或 `/clear`、`/compact` 之后 |
  | Conversation | 你的消息、Claude 回复、工具结果 | 每一轮 |

  前缀匹配是精确匹配，"没有按文件或按段的缓存"。改 system prompt 会让后面全部失效。
- **`CLAUDE.md 不是 system prompt 的一部分`**：官方文档明确写 "CLAUDE.md content is delivered as a user message after the system prompt, not as part of the system prompt itself. Claude reads it and tries to follow it, but there's no guarantee of strict compliance." 需要真正进 system prompt 的内容要用 `--append-system-prompt`。[verified: official docs]（[memory](https://code.claude.com/docs/en/memory.md)）
- **启动内容的具体 token 量被官方可视化给出**（200K 窗口的模拟）：System prompt ≈ 4,200、Auto memory `MEMORY.md` ≈ 680、Environment info ≈ 280、MCP 工具（延迟加载）≈ 120、技能描述 ≈ 450、`~/.claude/CLAUDE.md` ≈ 320、项目 CLAUDE.md ≈ 1,800。[verified: official docs]（[context-window](https://code.claude.com/docs/en/context-window.md)）
- **MCP 工具 schema 默认延迟加载**：只把工具名放进上下文，模型按需通过 tool search 加载具体 schema。`ENABLE_TOOL_SEARCH=auto` 时在能塞进上下文窗口 10% 的前提下预加载；`=false` 时全量加载。[verified: official docs]（[context-window](https://code.claude.com/docs/en/context-window.md)）
- **哪些操作会破坏缓存**（官方给了清单，这是很有价值的一份"提示词工程约束"）：切换模型、改 effort level、开 fast mode、增删 MCP server（当 tool search 未生效时）、启用/停用插件、把某个工具**整体** deny 掉（如裸 `Bash`，会从下一请求移除工具定义）、压缩会话、累积大量图片、升级 Claude Code。**不会破坏缓存**的：改仓库文件、改 CLAUDE.md、换 permission mode、换 output style、调用技能/命令、`/recap`、`/rewind`、spawn subagent。[verified: official docs]（[prompt-caching](https://code.claude.com/docs/en/prompt-caching.md)）
- **TTL 分两个桶**：主对话一个 TTL（Claude 订阅内默认 1 小时；用 usage credits / API key / 云厂商时默认 5 分钟），其它一切（subagent、workflow、in-process teammate、fork、压缩、会话标题）默认 5 分钟。可用 `promptCacheTtl`/`subagentPromptCacheTtl` 或对应环境变量覆盖，取值只有 `5m` 和 `1h`。[verified: official docs]（[prompt-caching](https://code.claude.com/docs/en/prompt-caching.md)）
- **一个反直觉的交互**：`plan mode` 和技能加载是**把指令作为 conversation 消息 append** 的，所以缓存前缀保持完好——这是刻意设计。[verified: official docs]（[prompt-caching](https://code.claude.com/docs/en/prompt-caching.md)）

### 1.4 Subagent / 任务委派

[verified: official docs]（[sub-agents](https://code.claude.com/docs/en/sub-agents.md)）

- **非 fork 的 subagent 拿到全新隔离上下文**：看不到对话历史、已调用的技能、已读的文件。启动内容是：自己的 system prompt（agent 自己的 prompt + 环境细节，**不是** Claude Code 的 system prompt）、任务消息、**CLAUDE.md 各层级**、**git status 快照**、预加载技能正文、兄弟 roster（仅当该 subagent 有 `SendMessage` 工具且存在≥1 个具名 agent，且是启动时的快照）。
- **不传给 subagent 的**：output style、主会话的 auto memory（fork 会继承）、上下文窗口尺寸（由 subagent 自己的模型决定）。
- 内置 `Explore` / `Plan` 跳过 CLAUDE.md 与 git status 以换取速度和成本；自定义 agent 可用 frontmatter `omitClaudeMd: true` 做到（此时只加载 managed policy 文件）。
- **结果返回**：非 fork subagent 只把最终文本 + 一小段元数据（token 数与时长）返回主上下文。官方给的量化例子：subagent 读了 6,100 tokens 的文件，主上下文只拿到 **420 tokens** 的结果。
- **可恢复**：每次 subagent 调用创建新实例；`SendMessage` 用 agent ID 或名字恢复，恢复后的运行**保留完整历史**（含之前所有工具调用、结果、推理），并且**可以继续读原运行暖起来的 prompt cache**。built-in Explore/Plan 是一次性的，不返回 agent ID。transcript 存在 `~/.claude/projects/{project}/{sessionId}/subagents/agent-{agentId}.jsonl`，**主会话压缩不影响它们**。
- **嵌套深度默认 3 层**（`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`）。到达深度上限时，Claude Code 会**从所有 subagent 的工具列表里撤掉 `Agent` 工具**（fork 除外——fork 保留但调用会报错）。
- **并发上限默认 20**（`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`），超限时 Agent 工具以 `Concurrent subagent limit reached` 失败并告诉模型不要重试。`/subtask` 启动的 in-session fork 占槽但不被上限阻塞；恢复一个已完成的 subagent 不检查上限，因此可以把运行数推过上限。
- **输出扫描（安全机制，很独特）**：Claude Code 在 Claude 读到 subagent 的最终报告前会扫描它。它**从不删除或改写内容**，只做两种改动：在模仿 Claude Code 自身输出的文本（如 `<system-reminder>` 标签、以 `Human:`/`Assistant:` 开头的行）里**插入反斜杠**；当报告模仿标签或提到 `bypassPermissions`、`--dangerously-skip-permissions` 等权限设置时，**前置一行** `[harness: subagent output matched instruction-shaped pattern(s):`。报告还带一个头，声明报告里的指令或"已获批准"的说法都是 subagent 自己的话、不具用户权威。[verified: official docs]（[sub-agents](https://code.claude.com/docs/en/sub-agents.md)）
- **subagent 描述占上下文**：所有自定义 subagent 的 description 合计超过 **15,000 tokens** 时启动告警。[verified: official docs]（[sub-agents](https://code.claude.com/docs/en/sub-agents.md)）
- **Fork**：`/subtask` 启动的 fork **继承整段对话**（同 system prompt、tools、model、消息历史），但它的工具调用不进主对话，只把最终结果带回来。fork 首个请求会命中父会话的缓存。[verified: official docs]（[sub-agents](https://code.claude.com/docs/en/sub-agents.md)、[prompt-caching](https://code.claude.com/docs/en/prompt-caching.md)）

### 1.5 记忆 / 项目指令

[verified: official docs]（[memory](https://code.claude.com/docs/en/memory.md)）

- **加载顺序（由宽到具体）**：Managed policy（`/Library/Application Support/ClaudeCode/CLAUDE.md`、`/etc/claude-code/CLAUDE.md`、`C:\Program Files\ClaudeCode\CLAUDE.md`）→ User（`~/.claude/CLAUDE.md`）→ Project（`./CLAUDE.md` 或 `./.claude/CLAUDE.md`）→ Local（`./CLAUDE.local.md`）。
- **发现规则**：工作目录及其**所有上级目录**的 `CLAUDE.md`/`CLAUDE.local.md` 在启动时加载；**子目录里的文件按需加载**——当 Claude 读/写/编辑该子目录下的另一个文件时加载。同目录内 `CLAUDE.local.md` 追加在 `CLAUDE.md` 之后。**所有发现的文件是拼接（concatenate）而不是互相覆盖**；目录树方向上从根到工作目录，越靠近启动位置的越晚读到。
- **导入**：`@path/to/import` 语法，相对路径**相对于包含该导入的文件**而非工作目录；可递归，**最多 4 跳**；导入文件在启动时展开加载。**导入不降低上下文成本**（它们也在启动时加载）。在项目级记忆文件里指向工作目录之外的导入会被视为 external，首次出现时弹审批框。`@` 出现在 Markdown 代码段/围栏里会被跳过。
- **块级 HTML 注释在注入前被剥离**（`<!-- maintainer notes -->`），代码块内的注释保留。
- `.claude/rules/*.md` 递归发现，无 `paths` 的与 `.claude/CLAUDE.md` 同优先级；有 `paths` 的只在 Claude 对匹配文件使用 Read/Write/Edit 时加载。整个 `paths` 列表共享 **1,000 条展开模式与 4 MiB** 的预算（无花括号的模式不计数）。规则文件只有 `paths` 一个字段被读取，其它字段静默忽略。
- **单文件尺寸**：建议 < 200 行；**超过 4 MiB 的 CLAUDE.md 会被跳过**。`MEMORY.md` 只加载**前 200 行或 25KB（先到者为准）**，超出部分在下次加载时被丢弃——写成功后若超限，Claude Code 会返回一个错误要求 Claude 重写索引。
- **AGENTS.md 兼容**：默认只有当工作目录及以上**不存在** `CLAUDE.md` / `.claude/CLAUDE.md` / `CLAUDE.local.md` 时才读 `AGENTS.md`。`/config` 的 **Project instructions** 可设为 `claude-md-or-agents-md`（默认）/ `claude-md-and-agents-md` / `claude-md` / `managed-only`。`AGENTS.local.md`、`AGENTS.override.md` 和 `.agents/` 目录**都不读**。[verified: official docs]（[memory](https://code.claude.com/docs/en/memory.md)）
- **auto memory**：Claude 自己写的笔记，存在 `~/.claude/projects/<project>/memory/`，含一个 `MEMORY.md` 索引 + 每个记忆一个主题文件。四类：`user` / `feedback` / `project` / `reference`（写在 frontmatter 的 `type`）。**主会话的 auto memory 不加载进 subagent**；subagent 可用 `memory` 字段启用自己独立的一份。
- **指令加载有专门 hook**：`InstructionsLoaded` 的 matcher 取值是加载原因——`session_start`、`nested_traversal`、`path_glob_match`、`include`、`compact`。[verified: official docs]（[hooks](https://code.claude.com/docs/en/hooks.md)）

### 1.6 编辑 / 应用策略

- `Edit` 工具做**靶向编辑**，要求 `old_string` **逐字出现**："A single character of whitespace or indentation difference is enough to miss."[verified: official docs]（[tools-reference](https://code.claude.com/docs/en/tools-reference.md)）
- **读前写约束**：Opus 4.6 / Haiku 4.5 及更早的模型**总是**要求先读才能覆盖已有文件；更新的模型可以在"读它也不会触发权限提示且 Read 工具可用"的前提下覆盖未读文件。Jupyter notebook 与只被 `PARTIAL view` 读过的文件在所有模型上都需要先读。用 Bash 查看文件也算满足（`cat`/`head` 单个文件）。**[inferred] 这是一种"按模型能力放宽安全护栏"的设计**——不是硬约束而是能力协商。
- **非 UTF-8 文件被拒绝**：Edit/Write 工具会把整个文件按 UTF-8 写回，会用 `U+FFFD` 替换无法解码的字节，所以它们直接拒绝，错误信息让 Claude 改用 shell 命令保持原编码，或先问用户是否转 UTF-8。Write 可以替换这类文件，除非新内容含 `U+FFFD`（防止把读到的乱码写回去）——写成功则原编码丢失。
- **符号链接防护**：Edit/Write 拒绝透过 symlink 写入（若 symlink 变了），错误会指路去编辑链接目标。
- **除 Edit/Write 之外还有 `NotebookEdit`、`MultiEdit` 式的批量能力**（本报告未逐一核实 MultiEdit 的当前状态）。**[未核实]**

### 1.7 验证循环

- **没有"自动跑测试"的强制机制**。官方把它作为**使用建议**而非机制存在：在 prompt 里给验证目标（测试用例、截图、期望输出），"When Claude can verify its own work, it catches issues before you need to request fixes"；"Test incrementally: Write one file, test it, then continue."[verified: official docs]（[costs](https://code.claude.com/docs/en/costs.md)）
- 真正**机制化**的是 hook 层：`PostToolUse`（工具成功后）、`PostToolUseFailure`、`PostToolBatch`（一批并行工具调用全部结算后、下一次模型调用前）。`PostToolUse` 可以用 `updatedToolOutput` **替换工具结果**；`PreToolUse` 可以用 `updatedInput` 改写工具参数；`PreToolUse` 还能返回 `permissionDecision: allow|deny|ask|defer`。[verified: official docs]（[hooks](https://code.claude.com/docs/en/hooks.md)）
- 官方给了"用 PreToolUse hook 把 `npm test` 改写成只显示失败行"的完整示例脚本——**这是把验证输出压缩进上下文的推荐做法**。[verified: official docs]（[costs](https://code.claude.com/docs/en/costs.md)）
- **没有文档化的重试次数上限**。**[未核实]**

### 1.8 检查点 / 回退

[verified: official docs]（[checkpointing](https://code.claude.com/docs/en/checkpointing.md)）

- **在你发送的每个"开启一轮"的 prompt 时打一个 checkpoint**，快照由 Claude 的文件编辑工具产生的改动构成。
- **保留最近 100 个 checkpoint 的文件快照**在一个会话内；丢弃旧 checkpoint 时删除不再被引用的快照文件，**但每个文件的第一个快照会保留**（VS Code 扩展把它当作会话 diff 的基线）。
- checkpoint **随会话一起保存**，所以 `--resume` 后仍可 `/rewind`。默认保留约 **30 天**（`cleanupPeriodDays`）；过期后回退可能报 `No files were restored`。
- `/rewind` 菜单的 6 个动作：Restore code and conversation / Restore conversation / Restore code / **Summarize from here** / **Summarize up to here** / Never mind。后两个是**部分压缩**——这是 `/compact` 之外的定向上下文回收手段。
- **明确的限制（很值得抄进对照表）**：
  - **不追踪 Bash 命令改的文件**（`rm`/`mv`/`cp` 的效果无法 rewind）
  - **subagent 的编辑通常不被捕获**（例外：`context: fork` 且前台运行的技能）
  - **不追踪会话外的手动改动或其它并发会话的改动**
  - **turn 中途（Claude 还在工作时）你发的消息没有自己的 checkpoint**，在菜单里标成 `No code restore`
  - **不恢复符号链接与硬链接路径**：跳过并提示 `Restored the code, but skipped N files`
- 明确声明"不是版本控制的替代品"。

### 1.9 转录 UI

[verified: official docs]（[fullscreen](https://code.claude.com/docs/en/fullscreen.md)）

- **两条渲染路径**：classic（对话留在终端原生 scrollback，`Cmd+f`、tmux copy mode 可用）与 **fullscreen**（research preview，画在终端 alternate screen buffer，像 vim/htop）。
- **fullscreen 只渲染当前可见的消息，所以内存在长会话里保持恒定**——这是"长聊天虚拟化"的官方答案，也是比"渲染全部"更高的门槛（classic 渲染器据文档是问题所在："eliminates flicker, keeps memory usage flat in long conversations"）。
- 只发送帧间变化的单元格（incremental cell diff），Windows Terminal/ConPTY 会错误合并定位写入导致残影，可用 `CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT=1` 改成每帧全量重绘。
- fullscreen 下 `/diff` 打开一个**独立面板**（需要 ≥110 列；≥144 列时在 Claude 开始编辑文件时自动打开；打开过一次后后续会话会自动打开）。面板列出改动文件与增删行数，每个文件下方给 diff；**可点 `ask` 把该文件的 diff 附到下一条 prompt**；有 `source` 选择器在 `Current` 与逐轮视图 `T1`/`T2`… 之间切换；面板默认**跳过测试文件与生成文件**，并把本次会话之前的改动折叠成底部一行。
- **折叠 & 展开**：`Ctrl+O` 切换 transcript viewer，显示详细工具使用与执行、每条 assistant 消息的时间戳与所用模型，并**展开默认折叠的行**——例如 MCP 调用折叠为一行 `Called slack 3 times`，跨会话消息折叠为一行 `Message from @<sender>` 预览。在 fullscreen 里点击折叠的工具结果可展开（工具调用与其结果一起展开），只有"还有内容可显示"的消息可点。
- **有 `/focus` 静默视图**："only your last prompt, a one-line summary of tool calls with edit diffstats, and the final response"，设置跨会话保持。**[inferred] 这与 DSH 的"详细度分级"是同一类需求的两种实现：Claude Code 用开关式静默视图，DSH 用四档持久化枚举 + 策略表。**
- **transcript 模式有 `less` 风格导航与搜索**：`/` 搜索、`n`/`N` 跳转、`j`/`k`/`g`/`G`、`{`/`}` 按 prompt 跳转、`Ctrl+u`/`Ctrl+d` 半页、`Ctrl+b`/`Ctrl+f`/空格/`b` 整页。
- **把内容交回终端**：`[` 把完整对话（**所有工具输出展开**）写入终端原生 scrollback，之后 `Cmd+f`、tmux copy mode 可用；`v` 写入临时文件并用 `$VISUAL`/`$EDITOR` 打开。
- **滚动即暂停自动跟随**：向上滚动暂停 auto-follow，底部浮出 `Jump to bottom` 按钮并显示 `3 new messages` 计数；`Ctrl+End` 或滚到底恢复。可在 `/config` 关掉 auto-scroll。
- **鼠标支持**：点击定位输入光标、点击展开折叠工具结果、`Cmd`/`Ctrl`+点击打开 URL 或文件路径（文件路径在工具输出里如 Edit/Write 后打印的），拖拽选择文本（双击选词、三击选行），**选中即复制**（可在 `/config` 关掉 Copy on select）。`CLAUDE_CODE_DISABLE_MOUSE=1` 完全退出鼠标捕获但保留无闪烁渲染与恒定内存；`CLAUDE_CODE_DISABLE_MOUSE_CLICKS=1` 只关点击。
- **TMUX 兼容性边界写得很细**：需要 `set -g mouse on`；与 iTerm2 的 `tmux -CC` 集成模式**不兼容**（alternate screen 与鼠标跟踪在那里不工作）；tmux ≤3.6 不实现 synchronized output 所以重绘更闪。
- **渲染器的失败降级**：一次启动失败后下次仍尝试 fullscreen；两次失败后停在 classic 直到升级 Claude Code 或手动 `/tui fullscreen`。失败计数按版本计、成功启动会重置。
- **`/btw` 侧问题**：不进对话历史，答案只从已有上下文回答、**没有工具访问**；可 `f` 把它 fork 成一个继承父对话 + 该问答的 subagent。终端里以可关闭的 overlay 形式出现，"Claude Code replays the newest 20 exchanges with each ask"。
- **`/diff` 的 turn 视图来自 Claude 的文件编辑而非 git**，所以 Claude 通过 shell 命令做的改动只出现在 `Current` 视图下。**[inferred] 这是一次刻意的数据源二选一：turn 视图要"我改了什么"，工作树视图要"现在和 git 差什么"。**

### 1.10 中断语义

[verified: official docs]（[interactive-mode](https://code.claude.com/docs/en/interactive-mode.md)）

- `Esc`：**中途停止当前响应或工具调用**，让你可以改向。**"Claude keeps the work done so far"**。若你有排队消息，Claude Code 接下来会发它们。
- `Ctrl+C`：中断运行中的操作；没有东西在跑时第一次清空输入、第二次退出。
- **排队机制**：`Up` 从第一行可以"取回"已排队的消息；`Ctrl+Enter` 或 `Ctrl+X Ctrl+S` 立即发送排队消息与草稿。
- `Ctrl+X Ctrl+K`：停掉本会话所有后台 subagent，并关掉 artifact 自动回复（3 秒内按两次确认）；**在后台 subagent 的权限提示开着时也能按**。
- **中断后不会重新读取的形式化保证**：[inferred] 由 `Esc` 的 "Claude keeps the work done so far" + checkpoint 语义共同给出。
- **`/btw` 可以在 Claude 工作时运行且不打断主 turn**，它看到对话至今的一切、除了 Claude 正在写的那条回复。[verified: official docs]（[interactive-mode](https://code.claude.com/docs/en/interactive-mode.md)）

---

## 2. OpenAI Codex CLI

主要来源：`https://learn.chatgpt.com/docs/*.md`（原 `developers.openai.com/codex/*`，现已 302 到 learn.chatgpt.com）。**注意：本次未能访问 codex 仓库源码**（raw.githubusercontent.com 不可达），所以本节全部是官方文档级证据。

### 2.1 上下文管理

- **自动压缩阈值可配**：`model_auto_compact_token_limit`（token 阈值，未设置则用模型默认值）；`model_auto_compact_token_limit_scope` 取值 `total`（默认，计整个活动上下文）或 `body_after_prefix`（只计"携带的压缩窗口前缀之后的增长"）。[verified: official docs]（[config-reference](https://learn.chatgpt.com/docs/config-file/config-reference.md)）
- `model_context_window` 可显式声明上下文窗口大小。[verified: official docs]（[config-reference](https://learn.chatgpt.com/docs/config-file/config-reference.md)）
- **有 `remote` 与 `local` 两种压缩类型**（遥测计数器 `task.compact` 的 `type` 字段就是 `remote` 或 `local`，含手动与自动）。**[inferred] 这说明 OpenAI 侧存在服务端压缩路径**，但官方文档没有展开其行为差异。
- **手动 `/compact`**：把较早的 turn 替换为一段简洁摘要，"freeing context while keeping critical details"。文档还专门区分 `/compact`（释放上下文）与 `/recap`（生成一段会话摘要但**不**释放空间）。[verified: official docs]（[developer-commands](https://learn.chatgpt.com/docs/developer-commands.md)）
- **压缩是模型可见的且有专门配置**：`hide_agent_reasoning`（抑制 reasoning 输出，例如 CI 日志）、`show_raw_agent_reasoning`（显示原始 reasoning）。[verified: official docs]（[config-advanced](https://learn.chatgpt.com/docs/config-file/config-advanced.md)）

### 2.2 工具结果截断

**[未核实] 本次没有在官方文档中找到 Codex 对工具输出做 token/字符截断的阈值或分页策略。** 这是与 Claude Code、DSH 相比明显的文档缺口。会话历史落盘有 `history.max_bytes`（默认设置下 `~/.codex/history.jsonl`，超过上限时丢弃最旧条目并压缩文件），但那是**会话文件**而非工具结果。[verified: official docs]（[config-advanced](https://learn.chatgpt.com/docs/config-file/config-advanced.md)）

### 2.3 System prompt 结构

- 有 `model_instructions_file` 键（旧名 `experimental_instructions_file`，已弃用）可整体替换指令文件；相对路径相对于所在 `.codex/` 目录解析。[verified: official docs]（[config-reference](https://learn.chatgpt.com/docs/config-file/config-reference.md)）
- **`AGENTS.md` 的注入方式有明确的上限与合并规则**：Codex 启动时（每次运行一次，TUI 里约等于每次启动会话）构建"指令链"，把文件**从根向下用空行拼接**，"Files closer to your current directory override earlier guidance because they appear later in the combined prompt"。**合并后总大小达到 `project_doc_max_bytes`（默认 32 KiB）就停止继续加入文件**。[verified: official docs]（[agents-md](https://learn.chatgpt.com/docs/agent-configuration/agents-md.md)）
- `additional_developer_instructions` 是 managed requirement 里的一个**独立 developer 消息**，超过 10,000 estimated tokens 会被 Codex 拒绝。[verified: official docs]（[config-reference](https://learn.chatgpt.com/docs/config-file/config-reference.md)）
- 会话级别的配置层有**明确优先级**：`profiles` 文件（`~/.codex/<profile>.config.toml`）覆盖 `config.toml`，项目 `.codex/config.toml` 覆盖用户配置，`--config`/`-c` CLI 覆盖一切。`/debug-config` 打印配置层顺序（最低优先级在前）、on/off 状态与 policy 来源。[verified: official docs]（[config-advanced](https://learn.chatgpt.com/docs/config-file/config-advanced.md)）

### 2.4 Subagent / 任务委派

[verified: official docs]（[subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents.md)）

- **本地 Codex 默认启用 subagent workflow**；CLI 用 `/subagents` 在各 agent thread 之间切换与检视；主线程把 subagent 结果汇总进最终回复。
- **agent thread 是一等概念**：每个 subagent 有可打开的 thread。CLI 中"approval requests can surface from inactive agent threads even while you are looking at the main thread；approval overlay 显示来源 thread label，按 `o` 可以先打开那个 thread 再批准/拒绝/回答"。
- **非交互或无法弹出新审批时，"需要新审批的动作失败"并把错误冒泡回父 workflow**——这是一个 fail-closed 的明确表述。
- **权限继承是单向的**："Subagents inherit the parent turn's current sandbox and approval settings, including changes made with `/permissions` or `--yolo`. A custom agent file can't replace those settings."
- **自定义 agent 文件**在 `~/.codex/agents/`（个人）或 `.codex/agents/`（项目），每个文件一个 agent，必填 `name`、`description`、`developer_instructions`。可选 `model`、`model_reasoning_effort`、`model_reasoning_summary`、`model_verbosity`。
  - **模型解析顺序**：显式 spawn 值 → `[agents]` 默认 → 父 agent 的值。"If an explicit spawn request or an `[agents]` default selects a model and neither supplies a reasoning effort, Codex uses that model's default effort."
  - **能力可通过把 feature 键设为 `false` 来削减**：`features.shell_tool`、`features.apps`、`features.plugins`、`features.memories`、`features.request_permissions_tool`；技能可用 `skills.config` 或 `skills.bundled.enabled = false` 关。
  - **不能覆盖的**：`sandbox_mode`、`approval_policy`、`model_provider`、`mcp_servers`。
- **内置 agent**：`default`（通用回退）、`worker`（实现与修复）、`explorer`（读密集探索）。自定义 agent 名与内置冲突时自定义优先。
- **并发上限**：`agents.max_concurrent_threads_per_session`（不设则由 Codex 决定，旧键 `agents.max_threads` 作别名）；`agents.enabled` 默认 `true`。
- **中断消息**：`agents.interrupt_message` 默认 `true`——"Record a model-visible message when an agent turn is interrupted"。这是**中断语义的一个显式配置点**，很多其它 agent 没有。
- 官方给出的动机是**上下文污染 / context rot**，并引了 Chroma 的 context rot 研究。"每 5 个并行 subagent 大致消耗 5 倍 token"。

### 2.5 记忆 / 项目指令

- **发现顺序（三级）**：[verified: official docs]（[agents-md](https://learn.chatgpt.com/docs/agent-configuration/agents-md.md)）
  1. **Global**：`$CODEX_HOME`（默认 `~/.codex`）下先 `AGENTS.override.md`，否则 `AGENTS.md`，**只取第一个非空文件**
  2. **Project**：从项目根（通常是 git root）**向下**走到当前工作目录；每层依次检查 `AGENTS.override.md`、`AGENTS.md`、以及 `project_doc_fallback_filenames` 里的名字；**每层至多一个文件**。找不到项目根时只看当前目录。
  3. **合并**：从根向下用空行拼接；越靠近当前目录的越晚出现（因而"覆盖"更早的）。
- **项目根如何判定**：默认含 `.git` 的目录；可用 `project_root_markers = [".git", ".hg", ".sl"]` 自定义，设为 `[]` 则跳过父目录搜索、把 cwd 当根。[verified: official docs]（[config-advanced](https://learn.chatgpt.com/docs/config-file/config-advanced.md)）
- **空文件被跳过**；达到 `project_doc_max_bytes`（默认 32 KiB）就停止追加。[verified: official docs]（[agents-md](https://learn.chatgpt.com/docs/agent-configuration/agents-md.md)）
- 另有 `/memories` 命令配置聊天是否使用或生成 memories；遥测里有 `memory.phase1` / `memory.phase2` / `memories.usage` 计数器，说明存在**两阶段记忆管线**。[verified: official docs]（[config-advanced](https://learn.chatgpt.com/docs/config-file/config-advanced.md)）
- **项目级配置的安全门**：只有当项目被信任时才加载 `.codex/` 层（含 `.codex/config.toml`、项目级 hooks、项目级 rules）。且项目配置**不能**覆盖一批键（`openai_base_url`、`chatgpt_base_url`、`model_provider`、`model_providers`、`notify`、`profile`、`profiles`、`otel` 等），遇到时忽略并打启动警告。[verified: official docs]（[config-advanced](https://learn.chatgpt.com/docs/config-file/config-advanced.md)）

### 2.6 编辑 / 应用策略

- **`codex apply`**：把最近一次 Codex cloud 聊天的 diff 应用到本地仓库，**打印被打补丁的文件，`git apply` 失败（如冲突）时以非零退出**。[verified: official docs]（[developer-commands](https://learn.chatgpt.com/docs/developer-commands.md)）
- 官方明确推荐**补丁式工作流**："Prefer patch-based workflows (for example, `git diff`/`git apply`) over editing tracked files directly. Commit frequently so you can roll back in small increments."[verified: official docs]（[agent-approvals-security](https://learn.chatgpt.com/docs/agent-approvals-security.md)）
- **`--worktree`** 让 `codex exec` 创建受管 git worktree（`codex exec --worktree "..."`），不能与 `resume`、`review`、`--ephemeral`、`--ignore-user-config` 同用。`codex fork <SESSION_ID> --worktree` 同理，且需要显式 session ID、不支持 `--last` 或选择器。[verified: official docs]（[developer-commands](https://learn.chatgpt.com/docs/developer-commands.md)）
- TUI 里 `Escape` 按两次（composer 为空）**编辑上一条 user 消息并从该点 fork 会话**。[verified: official docs]（[developer-commands](https://learn.chatgpt.com/docs/developer-commands.md)）
- 有 `task.undo` 遥测计数器（undo 动作次数），但**[未核实]** undo 的具体实现（是否基于补丁栈）。

### 2.7 验证循环

- **`/review`**：对未提交改动、某个 commit 或 base branch 做专门审查，"reports prioritized findings without modifying your working tree"；`review_model` 可单独指定 review 用的模型。[verified: official docs]（[cli](https://learn.chatgpt.com/docs/codex/cli.md)、[config-advanced](https://learn.chatgpt.com/docs/config-file/config-advanced.md)）
- **没有自动跑测试的机制化描述**。有的只是**自动审批审查**（下节）——它审查的是"要不要批准一个动作"，不是"代码是否正确"。
- **[未核实]** 重试上限：文档只提到 `request_max_retries`、`stream_max_retries`、`stream_idle_timeout_ms` 是 per-provider 的网络层参数，与验证循环无关。

### 2.8 检查点 / 回退

- **Codex 没有内置会话级文件快照**。回退手段是：managed git worktree、`--worktree`、`git apply`/`git diff` 的补丁工作流，以及会话级的 `codex archive`/`unarchive`/`delete`/`fork`。[verified: official docs]（[developer-commands](https://learn.chatgpt.com/docs/developer-commands.md)）
- `codex exec fork <SESSION_ID> [PROMPT]` 把已保存会话**复制**成新会话，原 transcript 不动。[verified: official docs]（[developer-commands](https://learn.chatgpt.com/docs/developer-commands.md)）
- **worktree 命令可直接在 TUI 里用**：`/worktree` 在本地 git 仓库创建受管 worktree 并选择"新 chat 还是把当前对话带过去"；`Browse worktrees` 可看已有 worktree 及其所属 chat。**任务运行中不可用。**[verified: official docs]（[developer-commands](https://learn.chatgpt.com/docs/developer-commands.md)）

### 2.9 沙箱与审批（Codex 最强的一块）

[verified: official docs]（[agent-approvals-security](https://learn.chatgpt.com/docs/agent-approvals-security.md)、[sandboxing](https://learn.chatgpt.com/docs/sandboxing.md)）

- **两层正交控制**：`sandbox_mode`（技术边界：能写哪里、能否联网）与 `approval_policy`（何时必须问你）。
- **三个沙箱模式**：`read-only` / `workspace-write` / `danger-full-access`。默认启动时探测：**受版本控制的目录 → `Auto`（workspace-write + on-request）**；**非版本控制的目录 → `read-only`**。
- **OS 级实现**：
  - macOS：**Seatbelt**，通过 `sandbox-exec -p <profile>` 运行；当限制读访问启用平台默认时会追加一份**精选的 macOS platform policy**（而不是宽泛允许 `/System`）以保持常见工具兼容。
  - Linux：默认 **`bwrap` + `seccomp`**；`bwrap` 缺失时回退到内置 helper（需要非特权 user namespace），并打启动警告。WSL1 在 `0.115` 起不再支持。
  - Windows：支持 **MXC**，`elevated`/`unelevated` 作为 legacy 回退；WSL2 走 Linux 实现。`features.prefer_mxc = true` 可优先 MXC 并在不支持时回退。
- **可写根内的受保护路径**（`workspace-write` 下仍只读，且递归）：`<writable_root>/.git`（若是 `gitdir: ...` 指针文件，**解析后的 git 目录路径也被保护**）、`.agents`、`.codex`、`.aws`。**[inferred] 这是"agent 不能改自己的策略文件"的显式实现。**
- **审批策略**：`on-request`（沙箱内自主、越界问）、`never`、以及 `granular` 表（逐类控制 `sandbox_approval`、`rules`、`mcp_elicitations`、`request_permissions`、`skill_approval` 是否允许弹出——其余自动拒绝）。`untrusted` **已退役**，项目级更严格的审批改为在用户配置里写 `[projects."/path"].trust_level = "untrusted"`。
- **自动审批审查（auto_review）**：`approvals_reviewer = "auto_review"` 时，**只对本来就"需要审批"的动作**走 reviewer agent（沙箱内动作不额外审查）。reviewer policy 检查数据外泄、凭据探测、持续削弱安全、破坏性动作；低/中风险在策略允许下可放行，**critical 拒绝**，high 需要足够的用户授权且无匹配 deny 规则。**prompt 构造、审查会话、解析失败一律 fail closed；超时单独上报但动作仍不执行。**默认策略在开源仓库的 `codex-rs/core/src/guardian/policy.md`。
- **网络默认关闭**，`[sandbox_workspace_write] network_access = true` 打开。`features.network_proxy` 是**强制层而非授权层**：三种组合被文档化——"Net off + proxy on: network stays off, and the feature does nothing" / "Net on + proxy off: 直接无限制出站" / "Net on + proxy on: 按配置的 domain 策略约束出站"。
- **域规则是 allowlist 优先**：精确主机只匹配自己；`*.example.com` 匹配子域但不匹配 apex；`**.example.com` 两者都匹配；全局 `*` 允许规则匹配任何未 deny 的公网主机；**`deny` 总是胜过 `allow`，且 `*` 只能用于 allow**。
- **本地/私网默认被阻断**（`allow_local_binding = false` 阻断 loopback、link-local、私网）：通配符规则**不算**显式本地例外；解析到本地/私网 IP 的主机名即使匹配 allowlist 也仍被阻断。
- **DNS 重绑定防护**是 best-effort：查不到/超时即阻断；解析到非公网地址即阻断；文档自陈"reduces DNS rebinding risk, but it does not eliminate it"。
- **Web search 默认走 OpenAI 维护的索引（`cached`）**，而不是实时抓页面，动机是**降低提示注入暴露面**；`--yolo`/full-access 下默认变 `live`。四个取值：`disabled` / `cached` / `indexed` / `live`。
- **`shell_environment_policy`** 控制传给子进程的环境变量：`inherit = "none" | "core"`、`set = {...}`、`filters`（大小写不敏感、支持 `*`/`?`，值为 `exclude`/`include`）、`ignore_default_excludes` 默认 `true`（即**默认不会**自动移除含 `KEY`/`SECRET`/`TOKEN` 的变量）。应用顺序：自动排除 → 自定义排除 → `set` 的值 → include 白名单。

### 2.10 中断语义

[verified: official docs]（[developer-commands](https://learn.chatgpt.com/docs/developer-commands.md)）

- **`Tab`（Codex 工作时）**：把后续 prompt、slash command 或 shell command **排队到下一轮**。
- **`Enter`（Codex 工作时）**：**把新指令注入当前 turn**。
- **`Escape` 两次（composer 为空）**：编辑上一条 user 消息并从该点 fork。
- `Ctrl+C` 或 `/exit` 关闭会话；`Ctrl+O` 或 `/copy` 复制最近一次已完成的输出（"If a turn is still running, `/copy` uses the latest completed output instead of the in-progress response"）。
- **`/archive` 在 turn 运行时确认会先停掉该 turn**；`/delete` 在 chat 运行时不可用。
- `agents.interrupt_message`（默认 `true`）决定中断时是否给模型留一条可见消息。

### 2.11 转录 UI / TUI

[verified: official docs]（[config-advanced](https://learn.chatgpt.com/docs/config-file/config-advanced.md)、[cli-customization](https://learn.chatgpt.com/docs/cli-customization.md)）

- `[tui]` 配置组：`notifications`、`notification_method`（`auto`/`osc9`/`bel`）、`notification_condition`（`unfocused`/`always`）、`animations`、**`alternate_screen`（设为 `never` 以保留终端 scrollback）**、`show_tooltips`。
- `/tui` 在 scrollback 与 fullscreen 之间切换，需要重启生效；`--no-alt-screen` 是单次启动的覆盖。
- **语法高亮**：TUI 对围栏 Markdown 代码块与文件 diff 做高亮；`/theme` 打开主题选择器并把选择存进 `tui.theme`；自定义主题放 `$CODEX_HOME/themes` 下的 `.tmTheme` 文件。
- **`file_opener`** 把引用变成可点击链接，取值 `vscode` / `cursor` / `windsurf` / `vscode-insiders` / `none`，例如把 `/home/user/project/main.py:42` 改写成 `vscode://file/...:42`。**[inferred] 这是一个很轻的"文件引用可导航"实现，与 DSH 的 `dsh-resource://file/...` 地址体系形成对比：Codex 交给外部编辑器，DSH 自带预览面板并支持 `params.line`。**
- **`/ps`**：列出后台终端及其状态，显示每条命令加**最多三行最近的非空输出**；`/stop`（别名 `/clean`）停掉当前会话所有后台终端。后台终端来自 `unified_exec`。
- **`/statusline`** 与 **`/title`** 都是可配置项列表：status line 有 model、model+reasoning、context stats、rate limits、git branch、token counters、session id、cwd/project root、Codex 版本；title 有 app name、project、spinner、status、thread、git branch、model、task progress。
- **`/export`** 把完整对话导出为 Markdown（复制到剪贴板或存文件，`/export session.md` 直接写文件，turn 运行中需等结束）。
- **`/recap`** 生成会话摘要但**不释放上下文**（与 `/compact` 对比明确）。
- **`/raw`（或 `Alt+R`，或 `tui.raw_output_mode = true`）**：切到原生 scrollback 模式，使终端选择与复制更直接。**[inferred] 这是 alt-screen 带来的"失去原生选择"问题的官方补丁**，与 Claude Code 的 `[` 写入 scrollback 属于同一类需求。
- **`/keymap`** 可重映射快捷键（绑定名如 `ctrl-a`、`shift-enter`、`page-down`），写入 `tui.keymap`；上下文特定绑定覆盖 `tui.keymap.global`；**空绑定列表即解绑**。
- **`/pets`** 是个轻量氛围元素（内置或自定义 pet）。
- **`codex app-server`** 支持 JSONL-over-stdio、WebSocket、Unix socket 三种传输，`--remote` 让 TUI 连到远端；**这是"TUI 与运行时解耦"的架构证据**——CLI 只是 app-server 的一个客户端。[verified: official docs]（[developer-commands](https://learn.chatgpt.com/docs/developer-commands.md)）

### 2.12 遥测 / 可观测性（作为"机制透明度"的证据）

Codex 的 OTel 事件与指标清单本身就暴露了大量内部机制。[verified: official docs]（[config-advanced](https://learn.chatgpt.com/docs/config-file/config-advanced.md)）

- `turn.e2e_duration_ms`、`turn.ttft.duration_ms`（time to first token）、`turn.ttfm.duration_ms`（time to first model output item）、`turn.tool.call`、`turn.token_usage`（按 `total`/`input`/`cached_input`/`output`/`reasoning_output` 分）。
- `approval.requested` 的 `approved` 字段取值：`approved` / `approved_with_amendment` / `approved_for_session` / `denied` / `abort`——**"with amendment"与"for session"是两种独立结果**。
- `thread.fork`、`thread.side`、`thread.rename`、`conversation.turn.count`。
- `thread.skills.enabled_total`、`thread.skills.kept_total`、**`thread.skills.truncated`**——说明技能列表渲染会截断。
- `task.compact`（`type` = `remote`|`local`）、`task.review`、`task.undo`、`task.user_shell`。
- `shell_snapshot` / `shell_snapshot.duration_ms`——启动时抓 shell 快照。
- `multi_agent.spawn`（`role`）、`multi_agent.resume`、`multi_agent.nickname_pool_reset`——**agent 有 nickname pool**。
- `memory.phase1` / `memory.phase2` / `memories.usage`（`kind`、`tool`、`success`）——**两阶段记忆管线**。
- `hooks.run` / `hooks.run.duration_ms`（`hook_name`、`source`、`status`）。

---

## 3. Aider

主要来源：`https://aider.chat/docs/**`。Aider 的文档是**唯一把"为什么这样设计"写成博客文章**的一家，因此本节证据链最完整。

### 3.1 上下文管理

**Aider 没有自动摘要压缩。**这是它与其余所有 agent 的最显著差异。证据：[verified: official docs]

- 唯一的自动机制是 **`--max-chat-history-tokens`**："Soft limit on tokens for chat history, after which summarization begins. If unspecified, defaults to the model's `max_chat_history_tokens`."（[options](https://aider.chat/docs/config/options.html)）
- 历史默认值是 8k：v0.71.0 release notes 写 "Increased max chat history tokens limit from 4k to 8k"。[verified: official docs]（[HISTORY](https://aider.chat/HISTORY.html)）
- **aider 从不强制 token 上限，只报告 provider 报的错**："Aider never _enforces_ token limits, it only _reports_ token limit errors from the API provider. The token counts that aider reports are _estimates_."（[token-limits](https://aider.chat/docs/troubleshooting/token-limits.html)）
- 超限时的官方建议是**人工操作**：`/tokens` 看用量、`/drop` 移出不需要的文件、`/clear` 清空历史、把代码拆成更小的源文件。[verified: official docs]（[token-limits](https://aider.chat/docs/troubleshooting/token-limits.html)）
- **输出 token 上限的应对是预填充续写（"infinite output"）**，这是一个很有辨识度的机制：当收集模型的代码编辑时命中输出上限，aider **用已部分生成的响应作为 prefill 再发起一次请求**，让模型从断点继续；可重复，从而支持很长的输出。"Joining the text across these output limit boundaries requires some heuristics, but is typically fairly reliable." 仅对支持 prefill 的模型可用（文档列了极长的一份白名单，含 Anthropic 全系、DeepSeek、Mistral、OpenRouter 等）。[verified: official docs]（[infinite-output](https://aider.chat/docs/more/infinite-output.html)）
- **上下文填充的官方立场是"越少越好"**："Above about 25k tokens of context, most models start to become distracted and become less likely to conform to their system prompt."[verified: official docs]（[edit-errors](https://aider.chat/docs/troubleshooting/edit-errors.html)）

### 3.2 工具结果截断

**[未核实] 没有文档化的工具结果截断机制。** Aider 的"工具"本质是 shell 命令与 lint/test 命令，输出直接进上下文。唯一相关的是 `/run` 与 `/test` 会**询问**是否把输出加入 chat（"Add the output to the chat? y"），以及 `/copy-context` 会显示 token 数（FAQ 例子里是 "Add 6.9k tokens of command output to the chat?"）。[verified: official docs]（[lint-test](https://aider.chat/docs/usage/lint-test.html)、[faq](https://aider.chat/docs/faq.html)）

**[inferred] 结论：这是 Aider 的一个明确短板——没有把"工具输出是上下文的主要消耗方"这件事机制化，只有人工确认。**

### 3.3 System prompt 结构 & 缓存

[verified: official docs]（[caching](https://aider.chat/docs/usage/caching.html)）

- **prompt caching 需要显式开启**（`--cache-prompts`，默认 False）。开启后 aider 组织聊天历史以缓存四件事，顺序为：
  1. system prompt
  2. `--read` / `/read-only` 加入的只读文件
  3. **仓库地图（repo map）**
  4. 加入 chat 的可编辑文件
- 缓存 TTL 5 分钟（Anthropic 侧），aider 提供 **`--cache-keepalive-pings N`**：每次你发消息后，在 `N*5` 分钟内每 5 分钟 ping 一次保持缓存热。
- **streaming 与缓存统计互斥**：provider API 的限制导致流式响应时拿不到缓存统计与成本，"To turn off streaming, use `--no-stream`"。[verified: official docs]（[caching](https://aider.chat/docs/usage/caching.html)）
- **system prompt 是模块化可替换的**：`aider/coders/` 下每个 edit format 有自己的 coder 与 prompts 文件（`wholefile_coder.py`/`wholefile_prompts.py`、`editblock_coder.py`/`editblock_prompts.py`、`udiff_coder.py`/`udiff_prompts.py`）。[verified: official docs]（[faq](https://aider.chat/docs/faq.html)）
- **有 model-specific system prompt 前缀机制**：release notes 提到 "Ensured model-specific system prompt prefixes are placed on a new line before the main system prompt"（v0.83.0）。[verified: official docs]（[HISTORY](https://aider.chat/HISTORY.html)）
- **有 `weak_model` 与 `editor_model` 的角色分离**：`--weak-model` 用于 commit message 生成与聊天历史摘要；`--editor-model` 用于 architect 模式的编辑器角色。[verified: official docs]（[options](https://aider.chat/docs/config/options.html)）

### 3.4 仓库地图（Aider 的核心机制）

[verified: official docs]（[repomap](https://aider.chat/docs/repomap.html)、[blog](https://aider.chat/2023/10/22/repomap.html)）

- **目标**：把整个 git 仓库的一张**精简地图**随每次变更请求发给 LLM，含每个文件里定义的关键符号及其**关键代码行**（含完整函数调用签名，因为 tree-sitter 能从源码直接取）。
- **tree-sitter 而非 ctags**：改用 tree-sitter 的三个理由被明确写出——地图更丰富（完整签名）、通过 `py-tree-sitter-languages` 获得多语言二进制 wheel（随 `pip install -U aider-chat` 自动装）、不再要求用户手动装 `universal-ctags`。地图标签定义在 `aider/queries` 下（对上游 tree-sitter 语言实现做了修改）。
- **优化算法**：完整 repo map 对大树也可能过大，aider 用**图排序算法**在"每个源文件是节点、文件间依赖是边"的图上计算，选出能塞进 token 预算的最重要部分。
- **token 预算 `--map-tokens` 默认 1k**；aider **动态调整**地图大小——通常保持在该值附近，但当 chat 里还没加任何文件时会**显著扩大**。`--map-multiplier-no-files` 默认 **2**（无文件时地图 token 的乘数）。`--map-refresh` 取值 `auto`（默认）/`always`/`files`/`manual`。
- **ranking 的两个具体增强**（写在 release notes 里）：v0.80.0 "Boost repomap ranking for files whose path components match identifiers mentioned in the chat"；v0.85.0 "Improved kebab-case identifier recognition in repository maps"；v0.71.1 修过 repomap 计算的整数索引 bug。
- **地图可能默认被禁用**：对弱模型会 "Repo-map: disabled"，官方解释是"Weaker models get easily overwhelmed and confused by the content of the repo map. They sometimes mistakenly try to edit the code in the repo map."，要强制开启用 `--map-tokens 1024`。[verified: official docs]（[faq](https://aider.chat/docs/faq.html)）
- **地图可导出**：`aider --show-repo-map > map.md`。[verified: official docs]（[faq](https://aider.chat/docs/faq.html)）
- **忽略/scope 机制**：`.aiderignore`（`.gitignore` 语法，`--aiderignore <filename>` 可指定不同文件）、`--subtree-only`（忽略启动目录之外的仓库）、`--add-gitignore-files`（把 `.gitignore` 里的文件纳入编辑范围，默认 False）。[verified: official docs]（[faq](https://aider.chat/docs/faq.html)、[options](https://aider.chat/docs/config/options.html)）
- **project conventions 文件**：aider 没有自动发现的项目指令文件；官方做法是写一个 Markdown（如 `CONVENTIONS.md`）并用 `/read CONVENTIONS.md` 或 `aider --read CONVENTIONS.md` 加入，或写进 `.aider.conf.yml` 的 `read:` 字段。选 `/read`（只读）而非 `/add` 的理由是明确的：**"This way it is marked as read-only, and cached if prompt caching is enabled."**[verified: official docs]（[conventions](https://aider.chat/docs/usage/conventions.html)）

### 3.5 Subagent / 任务委派

**Aider 没有 subagent。** [verified: official docs] 全站文档与本报告已抓取的 8 个页面中均无 subagent / agent 派生机制。它的对应机制是**多模型分工**：

- `--weak-model`（commit message、历史摘要）
- `--editor-model`（architect 模式的编辑执行）
- `--architect` 模式：主模型作为 architect 提议方案，editor model 把方案翻译成具体文件编辑指令。[verified: official docs]（[modes](https://aider.chat/docs/usage/modes.html)）

**[inferred] 这是"用模型特化替代上下文隔离"的路线**——Aider 不分叉上下文，而是分叉角色。代价是没有并行探索能力。

### 3.6 编辑 / 应用策略（Aider 的第二个核心机制）

[verified: official docs]（[edit-formats](https://aider.chat/docs/more/edit-formats.html)）

Aider 为不同模型族分别设计了编辑格式，且**每种格式都有明确的问题指向**：

| 格式 | 语法 | 设计理由 |
|---|---|---|
| `whole` | 文件路径 + 围栏里整个文件 | 最简单；慢且贵，因为即使只改几行也要返回整个文件 |
| `diff` | `<path>` + 围栏内 `<<<<<<< SEARCH` / `=======` / `>>>>>>> REPLACE` | 高效，只返回改动部分。语法类似 git 冲突标记 |
| `diff-fenced` | 文件路径**放在围栏内** | **专为 Gemini 族**设计，因为它们常无法遵循格式里把路径放在围栏外的写法 |
| `udiff` | 围栏 `diff` + `--- a` / `+++ b` / `@@ ... @@`（对标准 unified diff 做了修改与简化） | **专为 GPT-4 Turbo 族**，因为能减少它们的"偷懒"倾向——用其它格式时 GPT-4 Turbo 会把大段代码省略成 `# ... original code here ...` |
| `editor-diff` / `editor-whole` | 与 diff / whole 语法相同，但用**更简单的 prompt**，只聚焦"编辑文件"而非"解决编码任务" | 供 `--editor-edit-format` 在 architect 模式下使用 |
| `patch` | 未在 edit-formats 页详述 | release notes v0.82.0 提到 "Added new `patch` edit format for OpenAI's GPT-4.1 model"。[verified: official docs]（[HISTORY](https://aider.chat/HISTORY.html)） |
| `udiff-simple` | 同上 | release notes v0.82.3 提到 "Add new `udiff-simple` edit format, for Gemini 2.5 Pro" |

- **失败恢复策略**（[edit-errors](https://aider.chat/docs/troubleshooting/edit-errors.html)）："Aider makes every effort to get the LLM to conform, and works hard to deal with LLM edits that are 'almost' correctly formatted." 官方给的用户侧排查清单是：别加太多文件（>`/drop`）、换更强的模型、注意本地模型的 context window 与量化、**试 `--edit-format whole`**、**试 architect 模式**（"This two-step process often produces more reliable edits, especially with models that have trouble following edit format instructions"）。
- **围栏冲突处理（很细的一个点）**：如果 chat 里的文件含三反引号，aider 会告诉 LLM 改用别的围栏（如 `<source>...</source>`），否则 LLM 无法安全地把你的反引号放进它的代码块里。副作用是输出代码可能不再高亮。[verified: official docs]（[faq](https://aider.chat/docs/faq.html)）
- **"需要新文件"的重提交语义**：如果 aider 提示你加一个新文件而你说 yes，它会**重新提交原请求**——理由是 LLM 的回复表明它本应能看到/编辑该文件，"Often LLMs will hallucinate content for the files they needed but didn't have."[verified: official docs]（[faq](https://aider.chat/docs/faq.html)）
- **文件总是最新读取**："Aider always reads the latest copy of files from the file system when you send each message." 并在等待回复期间建议不要编辑已加入 chat 的文件。[verified: official docs]（[faq](https://aider.chat/docs/faq.html)）
- release notes 里还有两条编辑健壮性的具体修补：v0.82.3 "Improved robustness of edit block parsing when filenames start with backticks or fences" / "Fix parsing of diffs for newly created files (`--- /dev/null`)"；v0.82.2 "Improve robustness of patch application by allowing multiple update/delete actions for the same file within a single response" 与 "Update prompts to instruct LLMs to consolidate all edits for a given file into a single block within the patch"。[verified: official docs]（[HISTORY](https://aider.chat/HISTORY.html)）

### 3.7 验证循环

aider 是**唯一默认自动跑 lint 的**。[verified: official docs]（[lint-test](https://aider.chat/docs/usage/lint-test.html)）

- **`--auto-lint` 默认 True**：aider 自带多数主流语言的 linter，**默认对它所编辑的任何文件跑 lint**，用 `--no-auto-lint` 关闭。
- 自定义 linter：`--lint-cmd <cmd>`，命令接收要 lint 的文件名，**如果有 lint 错误应在 stdout/stderr 打印并以非零退出**。可按语言指定：`--lint "language: cmd"`。
- **formatter 作为 linter 的陷阱被明确写出**：很多 formatter 在改动文件后返回非零退出码，会让 aider 误以为有真实 lint 错误——官方给了"跑两次"的 wrapper 脚本。
- **测试**：`/test <test-command>` 手动跑；`--test-cmd <test-command>` + **`--auto-test`** 让 aider 在**每次 AI 编辑代码后**跑测试套件。**非零退出码时 aider 会尝试修复**。
- **非零退出后自动预填下一条 prompt**：v0.67.0 "When `/run` or `/test` have non-zero exit codes, pre-fill 'Fix that' into the next message prompt."（[HISTORY](https://aider.chat/HISTORY.html)）
- **编译语言**：官方建议用 `--lint-cmd` 编译单文件、`--test-cmd "dotnet build && dotnet test"` 编译整个项目。
- **重试上限**：**[未核实]** 文档未给出固定次数；`max_reflections` 类似的机制未在官方文档中出现。

### 3.8 检查点 / 回退（git-native）

[verified: official docs]（[git](https://aider.chat/docs/git.html)）

- **直接用真 git，不用 shadow repo**：
  - 在非 git 目录启动时会**询问是否创建 git repo**
  - **每当 aider 编辑文件，就用一条描述性的 commit message 提交这些改动**——这让 `/undo` 与"回看 aider 改了什么"变得简单
  - **对已有未提交改动（dirty）的文件，aider 会先把既存改动提交掉**，"This keeps your edits separate from aider's edits, and makes sure you never lose your work if aider makes an inappropriate change"
- **in-chat 命令**：`/diff`（显示自上次消息以来的所有文件改动）、`/undo`（撤销并丢弃最后一次改动）、`/commit`（以合理的 message 提交所有 dirty 改动）、`/git`（跑原始 git 命令）。
- **commit message 由 weak model 生成**：aider 把 diff 与聊天历史的副本发给 `--weak-model` 让它产出 message，**默认遵循 Conventional Commits**；可用 `--commit-prompt` 自定义。
- **署名机制很细**：aider 区分"创作了改动"与"仅提交了改动"——创作的 commit 在 **git author 与 committer 名**后追加 `(aider)`；仅提交的只在 **committer 名**后追加 `(aider)`。另有 `--attribute-commit-message-author`（只在创作的 message 前加 `aider: ` 前缀）、`--attribute-commit-message-committer`（所有 message 都加）、`--attribute-co-authored-by`（追加 `Co-authored-by` trailer，**默认 True**，且优先于默认的 author/committer 行为，除非显式把后两者设为 True）。
- **默认跳过 pre-commit hook**：使用 `--no-verify`（`--git-commit-verify=False` 是默认）。要跑 hook 用 `--git-commit-verify`。
- **可完全关闭**：`--no-auto-commits`、`--no-dirty-commits`、`--no-git`（不推荐）。
- **`--dry-run`** 可在不改文件的情况下跑一遍。
- **"aider 写了 xx% 代码"是 git blame 算出来的**：`scripts/blame.py`，"Only lines in source code files are counted, not documentation or prompt files."；官方自陈 aider 通常写了每个 release 新增代码的 70–80%。[verified: official docs]（[faq](https://aider.chat/docs/faq.html)、[HISTORY](https://aider.chat/HISTORY.html)）

### 3.9 转录 UI

- **配色是显式主题化的**：`--user-input-color`（默认 `#00cc00`）、`--tool-output-color`、`--tool-error-color`（`#FF2222`）、`--tool-warning-color`（`#FFA500`）、`--assistant-output-color`（`#0088ff`）、`--completion-menu-*` 四项、`--code-theme`（default/monokai/solarized-dark/solarized-light 或任意 Pygments 内置风格）、`--dark-mode`/`--light-mode`。[verified: official docs]（[options](https://aider.chat/docs/config/options.html)）
- **`--pretty` 默认 True** 做彩色输出；v0.71.0 "Pretty output remains enabled even when editing files with triple-backtick fences"。[verified: official docs]（[HISTORY](https://aider.chat/HISTORY.html)）
- **流式渲染优化有明确记录**：v0.71.0 "Streaming pretty LLM responses is smoother and faster for long replies"；v0.80.0 "Streaming automatically turns off for models that don't support it"；v0.83.0 加了"等待 LLM 开始流式响应时的 spinner 动画"（Knight Rider 风格），v0.84.0 扩展 spinner 也用于非流式响应，并做了 **console width clipping、cursor hiding、"更连续的外观"**。[verified: official docs]（[HISTORY](https://aider.chat/HISTORY.html)）
- **有 chat transcript 的分享路径**：把 `.aider.chat.history.md` 的内容做成 GitHub gist，然后拼到 `https://aider.chat/share/?mdurl=<gist-url>`，会渲染成终端风格的聊天记录。[verified: official docs]（[faq](https://aider.chat/docs/faq.html)）
- **历史文件三分**：`.aider.input.history`（输入）、`.aider.chat.history.md`（聊天，Markdown）、可选的 `--llm-history-file`（完整 LLM 往返日志，配合 `--verbose --no-pretty` 调试用）。[verified: official docs]（[options](https://aider.chat/docs/config/options.html)）
- **多行输入**：`--multiline` 使 Enter 变成软换行、META-ENTER 发送；可用 `/multiline-mode` 切换。**vi 编辑模式**（`--vim`）可用，且 v0.78.0 加了"在 multiline 模式下 vi normal 模式按 enter 时的 vi 式行为"。[verified: official docs]（[options](https://aider.chat/docs/config/options.html)、[HISTORY](https://aider.chat/HISTORY.html)）
- **通知**：`--notifications` + `--notifications-command`。"Aider will notify you when it's completed the last request and needs your input"（v0.76.0）。[verified: official docs]（[HISTORY](https://aider.chat/HISTORY.html)）
- **无 GUI 之外的 TUI 框架**：aider 用 Rich 做终端渲染（`--code-theme` 走 Pygments、release notes 提到 "Improved inline code rendering in Rich markdown output"、"Improved code block rendering in markdown output with better padding using NoInsetMarkdown"、"Left-align markdown headings in the terminal output"）。**[inferred] 没有虚拟化/alternate-screen 这类长会话渲染性能机制——它是线性打印终端风格。**
- 还有 `--gui`/`--browser` 的 Streamlit GUI 与 `--copy-paste` 模式（与 LLM web UI 协作）。

### 3.10 中断语义

**[未核实] Aider 的官方文档没有描述"用户中断正在进行的 LLM 请求"的语义。** 可确认的相关项：`Ctrl-Z` 进程挂起（v0.67.0）、`Ctrl-D` 正确退出（v0.68.0）、`Ctrl-C` 在多行模式与确认提示下的行为（v0.74.0 "multi-line mode persists through ^C at confirmation prompts"）、v0.72.3/v0.72.2 "Enforce user/assistant turn order to avoid R1 errors" / "Harden against user/assistant turn order problems which cause R1 errors"。**[inferred] Aider 是请求-响应式的（不是长驻 agent loop），"中断"的语义问题在它这里不成比例地小——这是一个设计上的优势。**

---

## 4. Cline / Roo Code

**重要事实核查**：`docs.roocode.com` 现在 302 到 `roocodeinc.github.io`（不存在），`roocode.com` 302 到 `roomote.dev`。Roo Code 的文档站已下线，产品线演进为 **Roomote**（"By the creators of Roo Code"）。因此本节的 Roo Code 部分**只能引用其后继产品的官方文档**，并明确标注这一替代关系。[verified: official docs]

### 4.1 Context management

**Cline — Auto Compact（自动摘要）**[verified: official docs]（[auto-compact](https://docs.cline.bot/features/auto-compact.md)）

- Cline 监控会话中的 token 用量，接近模型窗口上限时：生成一份全面摘要（保留所有技术细节、代码改动与决策）→ **用摘要替换对话历史** → 从断点继续。
- 触发时你会在对话里**看到一次摘要工具调用**，其成本像任何其它 API 调用一样显示。
- **成本论证**："Summarization leverages your existing prompt cache from the conversation, so it costs about the same as any other tool call. Since most input tokens are already cached, you're primarily paying for summary generation (output tokens)."——与 Claude Code 的 `/compact` 缓存论证一致。
- **关键降级路径**："With other models, Cline falls back to standard rule-based context truncation, even if Auto Compact is enabled."——**不是所有模型都有摘要，其它模型退回规则式截断。**
- 文档明确对比了旧行为："Previously, Cline would truncate older messages when hitting context limits, losing important context."
- **与 checkpoints 的配合**：可以用 checkpoint 恢复到摘要之前的任务状态，"You never truly lose context since you can always roll back"。编辑摘要工具调用之前的消息也等效。

**Cline — Memory Bank（跨会话，非上下文内）**[verified: official docs]（[memory-bank](https://docs.cline.best-practices/memory-bank.md)、实际 URL `https://docs.cline.bot/best-practices/memory-bank.md`）

- 这是**方法论而非内建机制**：一组约定俗成的 Markdown 文件放在 `memory-bank/`：`projectbrief.md`、`productContext.md`、`activeContext.md`、`systemPatterns.md`、`techContext.md`、`progress.md`。通过在 `.clinerules/memory-bank.md` 里写一段 custom instructions 来启用。
- **处理上下文窗口的官方流程是手动的**：①让 Cline "update memory bank" 记录当前状态 → ②开新对话 → ③让 Cline "follow your custom instructions"。
- 文档推荐用 `/newtask` 与 `/smol` 两个 slash command 做上下文窗口管理。

**Roo Code → Roomote**：Roomote 的记忆是**部署级共享语料**（"one deployment, one memory, shared by everyone"），不是每用户或每任务。[verified: official docs]（[memory](https://docs.roomote.dev/memory.md)）

- 来源：完成的任务（含发起请求 + agent 自己写的简短记忆：决定了什么、为什么、还开着什么）、PR、**公共** Slack 频道、公共 Discord 频道与活跃公共 thread、GitHub issues、显式共享给集成的 Notion 页面、Granola 会议纪要、Rippling 员工目录与汇报结构、人物身份。
- **私密 Slack 频道与 DM 永不读取**；Discord 只收 `@everyone` 角色可见、且 bot 有 View Channel + Read Message History 的频道；Notion 只返回显式共享给集成的页面。
- **检索是 hybrid（向量 + 关键词融合），没有 cross-encoder reranker**——理由是"keeps search latency flat and provider requirements minimal"。
- **agent 以只读 MCP server 的形式访问记忆**：能 search、recall、browse、要一段带引用的合成答案，**不能直接写**。写入走 Roomote 平台侧（"the platform places that text under a slug it controls, after scrubbing credential-shaped strings"）。
- **agent 记忆是 bounded 的**：请求有界、只记录真人发起的任务（不记录自动生成的工作如 review）；PR 记忆含描述与 labels、改动文件与主要代码区域、行数、review 结果，**描述被当作 source evidence 而非 agent instructions**，大文件列表用 count + truncation marker 汇总。
- **有"judgment model"做回合后的主动捕获**：每个 settled turn 后检查是否出现"陈述的偏好/决策/纠正、明确的记住请求、或花了真实调查的发现"；任务侧检查报告的决策/发现/死路/未决项。**凭据形状的字符串、邮箱、电话、卡号与证件号在任一模型看到之前就被擦除**；"Only a confident yes leads to a save"；**看起来敏感的 turn、试图植入审批或绕过规则、重复已保存内容的 turn 被跳过**；private session 与 private task 永不检查。
- **嵌入模型的维度在第一启动时确定向量存储宽度，之后无法原位调整**；换模型要整体重嵌入。这是一个**在生产上很实际的设计约束**，值得作为对照。

### 4.2 工具结果截断

**[未核实] Cline 与 Roomote 的公开文档都没有描述工具结果截断/分页阈值。** Roomote 只提到记忆页里的**大文件列表**会被 "summarized with a count and truncation marker"。[verified: official docs]（[memory](https://docs.roomote.dev/memory.md)）

### 4.3 System prompt 结构

- Cline 的 `editor` vs `apply_patch` 工具选择是**按模型路由**的："By default, Act mode offers `apply_patch` to GPT and Codex models and to every model on the OpenAI (`openai-native`) provider, and `editor` to other models"。**一个会话只提供其中一个，从不两个都给**；Plan mode 两个都不给。SDK 调用者可用 `toolRoutingRules` 替换这些默认。[verified: official docs]（[tools](https://docs.cline.bot/tools-reference/all-cline-tools.md)）
- Cline 有 **legacy 工具名的迁移说明**：旧文档里的 `read_file`、`replace_in_file`、`execute_command`、`use_skill` 等 XML 风格名字对应现在的 `read_files`、`apply_patch`、`run_commands`、`skills`。[verified: official docs]（[tools](https://docs.cline.bot/tools-reference/all-cline-tools.md)）
- **Roo Code 的 role 拆分是产品级一等概念**（Roomote）：Helper（读懂请求并路由到正确的 repo/环境）→ Explorer（找到真正相关的文件）→ Advisor（在编码前规划方案，并在 Coder 卡住时接管）→ Coder（按计划与你的指导做改动并跑工具）→ **Reviewer（冷读最终 diff，端到端检查 coder 因过于熟悉而看不见的 bug）**；另有 Vision 模型为你输入的图片/视频做描述。**每个 role 的模型可独立配置，可逐任务切换、也可任务中途切换。**[verified: official docs]（[agent-roles](https://roomote.dev/product/agent-roles)）

### 4.4 Subagent / 任务委派

**Cline**[verified: official docs]（[subagents](https://docs.cline.bot/features/subagents.md)）

- **只在 Cline CLI 与 Cline Desktop 可用；VS Code 与 JetBrains 扩展不用它们**（这是一个重要的可用性边界）。
- `spawn_agent` 工具启动 subagent；每个 subagent：拿到自己的指令与任务、跑在**独立上下文窗口**、**拥有当前模式下的 Cline 内建工具**（Act 模式能读/改文件与跑命令；Plan 模式没有编辑文件的工具，且 Cline **拒绝**那些通常会改动文件的 shell 命令如 `rm`、`git commit`——但其它命令仍然跑，"some of them, such as `python -c`, can write files"）、**可以再启动自己的 subagent**、**拿不到 MCP 工具**、把最终回复返回主 agent。
- **审批是一个粗粒度的授权**："Approving the `spawn_agent` call approves everything the subagent then does: its own tool calls don't ask for approval. Approval settings don't apply inside a subagent, so read the subagent's task before you approve it." **[inferred] 这是与 Claude Code / Codex 的"逐工具审批穿透到 subagent"截然不同的取舍：Cline 用一次批准换 subagent 内部零打断，代价是审批粒度变粗。**
- 主 agent 等待其 subagent，然后继续；**它们的 token 用量与成本计入会话总量**。
- 可在 `/settings` 的 Tools 标签关掉 `spawn_agent`；设置对新会话生效。
- 官方建议："Asking for research only, and working in Plan mode, make subagents less likely to change files, but **neither stops every change**."

**Roo Code → Roomote**：role 拆分如上；Roomote 的 task 在隔离沙箱里跑，并把 transcript、日志、diffs、previews、artifacts 与执行元数据都暴露出来。[verified: official docs]（[how-roomote-works](https://docs.roomote.dev/how-roomote-works.md)）

### 4.5 记忆 / 项目指令

- Cline 的 rules 与 memory bank 都是**文件式**的（`.clinerules/`）；memory bank 是约定而非内建发现机制。[verified: official docs]（[memory-bank](https://docs.cline.bot/best-practices/memory-bank.md)）
- Roo Code 的 `.clinerules` 在 Claude Code 的 `/init` 迁移清单里被列为可导入项之一："With `CLAUDE_CODE_NEW_INIT=1` set: `AGENTS.md`, `.devin/rules/`, `.windsurf/rules/` or `.windsurfrules`, and `.clinerules`"。[verified: official docs]（[memory](https://code.claude.com/docs/en/memory.md)）

### 4.6 编辑 / 应用策略

- Cline 的核心编辑工具就叫 **`apply_patch`**（"Apply patch/diff edits"），与 `editor` 互斥二选一。[verified: official docs]（[tools](https://docs.cline.bot/tools-reference/all-cline-tools.md)）
- Cline 的 Act/Plan 模式划分是**能力级**的：Plan 模式不能改文件、不能跑命令；Act 模式可以。**切换模式时对话历史会带过去**："The conversation history carries over when you switch modes."[verified: official docs]（[plan-and-act](https://docs.cline.bot/core-workflows/plan-and-act.md)）
- **Plan / Act 可各配一个模型**（"Use different models for Plan and Act"），切换模式时自动切换模型，切回时保留你的选择。官方给的示例配置：成本优化 = GLM 4.6（Plan）+ Grok Code Fast（Act）；最高质量 = Claude Opus（Plan）+ Claude Sonnet（Act）。[verified: official docs]（[plan-and-act](https://docs.cline.bot/core-workflows/plan-and-act.md)）
- `/deep-planning` 是**扩展规划会话**：系统性探索代码库 → 识别所有受影响文件与依赖 → 生成详细实施计划 → 在继续前提出澄清问题。**"The deep planning prompt is optimized for each model family"**。[verified: official docs]（[plan-and-act](https://docs.cline.bot/core-workflows/plan-and-act.md)）

### 4.7 验证循环

**[未核实] Cline / Roo 文档中没有自动跑测试并回灌结果的内建机制描述。** Roo Code 的一等公民是 **Reviewer role**（独立模型冷读 diff），而非测试执行。[verified: official docs]（[agent-roles](https://roomote.dev/product/agent-roles)）

### 4.8 检查点 / 回退（Cline 的 shadow git）

[verified: official docs]（[checkpoints](https://docs.cline.bot/core-workflows/checkpoints.md)）

- **Cline 维护一个独立于项目真实 git 历史的 shadow Git 仓库**。"After each tool use (file edits, commands, etc.), Cline commits the current state of your files to this shadow repo. Your main Git repository stays untouched."
- 因此：你的 git 历史保持干净且由你掌控；**checkpoint 捕获一切，包括未被 git 跟踪的文件**；可以在任务中恢复到任意点而不影响你已做的 commit；**checkpoint 跨编辑器会话持久**。
- 每个 checkpoint 捕获该时刻**完整的文件状态**。"If Cline edits three files in sequence, you get three checkpoints and can restore to any of them independently."
- **三个恢复选项**（这是一个比"回退"更细的语义分解，很值得对照）：
  | 选项 | 做什么 |
  |---|---|
  | **Restore Files** | 把项目文件恢复到该 checkpoints 的快照（保留对话） |
  | **Restore Task Only** | 删除该点之后的消息，不动文件（换 prompt 但保留当前代码） |
  | **Restore Files & Task** | 两者都回退 |
- **Compare** 用编辑器自己的 diff viewer 打开，看所有受影响文件的增删改。
- **与 auto-approve 的耦合被明确论述**："Checkpoints make auto-approve practical. Without checkpoints, auto-approve feels risky because Cline can make many changes before you notice a problem." 典型流程：开 auto-approve 给文件编辑与命令 → 让 Cline 快速做完整任务 → 看最终结果 → 错了就恢复到最后一个好的 checkpoint → 给更具体的指导。
- **消息编辑与 checkpoint 集成**：编辑之前的消息并选 "Restore All" 时，Cline 先把文件恢复到该点的 checkpoint 再重新提交编辑后的消息。
- **成本自陈**："For very large repositories, checkpoints may use significant storage and slow down Cline as it commits file snapshots after each tool use. Consider disabling them if you notice performance issues."

### 4.9 转录 UI

**[未核实] 本次没有抓到 Cline 转录渲染的机制级文档**（工具调用折叠、diff 侧对比 vs 统一、thinking 展示、流式渲染性能）。已知的只有 checkpoint 指示器的形态：**"a bookmark icon labeled 'Checkpoint' with a dotted line connecting to Compare and Restore buttons"** 出现在对话里。[verified: official docs]（[checkpoints](https://docs.cline.bot/core-workflows/checkpoints.md)）

Roomote 侧的 UI 描述是产品级而非机制级：session 持有对话与报告，每个 task 视图暴露 transcript、日志、diffs、previews、artifacts 与执行元数据；支持 **live previews**（跑起真实应用并给 reviewer 一个 URL）。[verified: official docs]（[how-roomote-works](https://docs.roomote.dev/how-roomote-works.md)、[roomote.dev](https://roomote.dev/)）

### 4.10 中断语义

**[未核实] Cline / Roo / Roomote 的公开文档没有描述中断进行中的 agent loop 的语义。**

---

## 5. OpenHands（原 OpenDevin）

主要来源：`https://docs.openhands.dev/**`（原 `docs.all-hands.dev`，302 到 `docs.openhands.dev`）。

### 5.1 事件流架构（OpenHands 最核心的设计）

[verified: official docs]（[conversation](https://docs.openhands.dev/sdk/arch/conversation.md)、[events](https://docs.openhands.dev/sdk/arch/events.md)）

- **不可变、类型安全的事件框架**，事件构成 append-only log，同时充当 **agent 的记忆**与**辅助服务的集成点**。
- **明确的两类事件**：
  - `LLMConvertibleEvent`（模型可见）：`MessageEvent`（user/assistant 文本）、`ActionEvent`（工具调用）、`ObservationEvent`（工具结果）、`UserRejectObservation`、`AgentErrorEvent`、`SystemPromptEvent`、`CondensationSummaryEvent`。
  - 内部事件（**模型不可见**）：`ConversationStateUpdateEvent`、`CondensationRequest`、`Condensation`、`PauseEvent`。
- **`Event.source` 与 LLM `role` 被刻意解耦**，文档明确警告不要从一个推断另一个：
  - Observation 通常是 `source="environment"` 但以 `role="tool"` 呈现
  - SDK 可能注入合成的框架消息（如来自 hooks 的反馈）为 `source="environment"` 但用 `role="user"`，让 agent 当作用户指令来读
  - **"Do not infer event origin from LLM role."**
- **并行工具调用的特殊处理**：当多个 `ActionEvent` 共享同一个 `llm_response_id` 时，按该 ID 分组 → 合并成**单个**带多个 `tool_calls` 的 Message → **只保留第一个事件的 `thought`、`reasoning_content`、`thinking_blocks`**，同批后续事件的这些字段为空。
- **两种错误事件被区分**：
  - `AgentErrorEvent`：`ObservationBaseEvent`，作用域是**某次工具调用**（有 `tool_name` 与 `tool_call_id`），`source="agent"`，**以 tool 消息发给模型让模型自我恢复**，对话继续，不是终态。
  - `ConversationErrorEvent`：非 LLM-convertible，作用域是**对话级运行时失败**，通常 `source="environment"`，**不发给模型**，run loop 进入 ERROR 且 `run()` 抛 `ConversationRunError`。
- **状态更新的双路径 + FIFO 锁**：State-Only 更新（status、stats、metadata）vs Event-Based 更新（消息、action、observation）。"FIFO Lock ensures ordered, atomic updates"；**回调在成功 commit 之后触发**；**读操作从不阻塞写**。
- **辅助服务只读事件日志、从不直接改状态**："Services read from the event log but never mutate state directly." 清单：Event Log（append-only 不可变存储）、Persistence（debounced writes + 增量事件）、**Stuck Detection（滑动窗口模式匹配做循环防护）**、Visualization（事件流 → 执行图）、Secret Registry（仅内存 + 打码日志）。

### 5.2 上下文管理：Condenser

[verified: official docs]（[condenser](https://docs.openhands.dev/sdk/arch/condenser.md)）

- **抽象契约** `CondenserBase`；具体实现 `NoOpCondenser`（不压缩）、`LLMSummarizingCondenser`（LLM 摘要）、`PipelineCondenser`（多级串联）、`RollingCondenser`（阈值触发的滚动窗口基类）。
- **`LLMSummarizingCondenser` 的配置项与默认值（这是本报告中最完整的一组具体数字）**：
  - `max_size`：触发压缩的**事件计数**阈值，**默认 120**
  - `keep_first`：**逐字**保留的初始事件数，**默认 4**（通常是 system prompt）
  - `llm`：做摘要的 LLM 实例，**"often cheaper model than reasoning LLM"**
- **滚动窗口策略**：保留头 `keep_first` 个 → 保留尾 `target_size - keep_first - 1` 个 → **摘要中间**。压缩后视图达到 `max_size // 2` 个事件（默认 **60**）。
- **两种触发**：
  1. **自动**：每次 `step()` 调 `condenser.condense()`，`should_condense()` 判断阈值（如事件数 > `max_size`）
  2. **手动**：`CondensationRequest` 事件被加入历史（由 agent 在**遇到 LLM 上下文窗口错误时**加入，或由应用代码加入），下一次 step 的 `condense()` 检测到 `view.unhandled_condensation_request`
- **压缩不是原地改写，而是产出新事件**：condenser **返回 `Condensation`（不是 `View`）** → agent 把它追加到事件日志并**提前结束这一步** → **下一步** `View.from_events()` 过滤掉 `forgotten_event_ids` 并在 `summary_offset` 处插入摘要。这是一个**两步（step）协议**，不是同步重写。
- `Condensation` 事件的字段：`forgotten_event_ids`、`summary`、`summary_offset`，外加继承自 `Event` 的 `id`/`timestamp`/`source`。
- `View` 的组成：`events`（被 Condensation 过滤后的 `LLMConvertibleEvent` 列表）、`unhandled_condensation_request`、`condensations`（已处理的所有 Condensation 事件）。

### 5.3 Agent 推理-行动循环

[verified: official docs]（[agent](https://docs.openhands.dev/sdk/arch/agent.md)）

- **单步执行模型**，每次 `step()` 处理一个推理周期。文档给出的 step 内流程（这是伪代码级的确切顺序）：
  1. **Pending actions**：如果存在等待确认的动作，执行它们并返回
  2. **Condensation**：若有 condenser → 用当前事件视图调 `condense()`：
     - 返回 `View` → 用压缩后的事件做 LLM 查询，**在同一步内继续**
     - 返回 `Condensation` → 发出事件并返回（下一步再处理）
  3. **LLM Query**：若有上下文窗口超限错误 → 发出 `CondensationRequest` 并返回
  4. **Response Parsing**：工具调用 → 创建 `ActionEvent`(s)；文本消息 → 创建 `MessageEvent` 并返回
  5. **Confirmation Check**：若动作需要用户批准 → 置会话状态为 `WAITING_FOR_CONFIRMATION` 并返回
  6. **Action Execution**：执行工具并创建 `ObservationEvent`(s)
- **关键特性被明确列出：Stateless（step 之间 agent 不持有可变状态）、Event-Driven、Interruptible（"Each step is atomic and can be paused/resumed"）。**
- **工具前有安全检查器**：`SecurityAnalyzer` 在**执行前**评估每个动作的风险；低风险立即执行、中风险记警告并监控执行、**高风险阻断并要求用户确认**。
- **两种执行模式**：Direct（立即执行，用于开发/可信环境）vs Confirmation（存为 pending，等用户批准，用于高风险动作/生产）。
- **`AgentContext` 含两类技能**：`repo`（始终激活）与 `knowledge`（触发词/模式激活）。
- **关键的不变量**："Each step sends the session's derived history — with the latest non-empty `system/message` node as the effective prompt ... every accepted fact is appended to the session log before the next step derives from it."（这句在 DSH 的调研文档里也被引作 DSH 的契约；两者一致。）**[inferred] 这是事件溯源式 agent 的通例。**

### 5.4 Skill 系统（OpenHands 的"记忆/指令"机制）

[verified: official docs]（[skill](https://docs.openhands.dev/sdk/arch/skill.md)）

- **四类技能，各有独立的注入点**：
  | 类型 | 触发 | 注入点 |
  |---|---|---|
  | Repository Skill | `trigger: None`（**始终激活**） | system prompt |
  | Knowledge Skill | `KeywordTrigger`（对用户消息做正则/字符串匹配） | system prompt |
  | Task Skill | `TaskTrigger`（**与 KeywordTrigger 相同的匹配逻辑**，语义区分：带结构化的 `inputs`） | system prompt |
  | **Path Rule** | `PathTrigger`（gitignore 风格 `paths` glob，匹配 agent 触碰的**工作区相对 POSIX 路径**） | **工具的 `ObservationEvent.extended_content` 里的 `<EXTRA_INFO>` 块——不是用户消息** |
- **Path Rule 的几个精确定义（很值得对照）**：
  - 在 agent **读、编辑或创建**匹配 glob 的文件时触发（`create` 也触发）
  - **基线成本为零**：被排除在 `<available_skills>` 和 `<REPO_CONTEXT>` 之外；且 **`disable_model_invocation` 被强制**，所以规则永不可被模型调用
  - **去重**：每条规则每个对话**只注入一次**（用 `ConversationState.activated_path_rules` 追踪）
  - **互斥**："A skill is either path-triggered or model-invocable, not both — if a file declares both `paths:` and `triggers:`, `paths:` wins"
  - **边界**："Path-rule injection applies to local conversations; **ACP-backed conversations do not inject rules because the ACP server owns tool execution**"
- **Repository Skill 的推荐载体是 `AGENTS.md`**（"put these permanent instructions in `AGENTS.md` (and optionally `GEMINI.md` / `CLAUDE.md`) at the repo root"）；也支持 `.agents/skills/*.md`、`.cursorrules`、`agents.md`/`agent.md`。
- **动态内容渲染**：技能正文里的 `` !`cmd` `` 模式会在渲染时**执行子进程并把 stdout 替换进去**；反引号围栏与行内代码块永不执行；未闭合的围栏块延伸到 EOF（保护尾部内容）；失败的命令替换为 `[Error: ...]` 标记；**每个命令输出截断在 50KB**。
- **Repository Skill 可携带 MCP 服务器配置**（`mcp_tools`，FastMCP 格式），启动 MCP client 并把工具注册进 agent 的 tool registry。

### 5.5 运行时沙箱（OpenHands 的第二核心机制）

[verified: official docs]（[runtime](https://docs.openhands.dev/openhands/usage/architecture/runtime.md)）

- **Docker 客户端-服务端架构**：用户在提供的 base image 上，OpenHands 构建一个 "OH runtime image"（含 OpenHands 特有代码，主要是 "runtime client"）→ 启动容器 → 容器内 action execution server 初始化 `ActionExecutor`（bash shell + plugins）。
- **通信走 RESTful API**：backend（`openhands/runtime/impl/action_execution/action_execution_client.py`）向容器内的 action execution server 发 action、收 observation。runtime 实现有 `docker_runtime.py`、`local_runtime.py`、`remote_runtime.py`。
- **runtime client 的职责被明确列出**：充当 backend 与沙箱之间的中介；在容器内安全执行各类 action（shell 命令、文件操作、Python 代码等）；**管理沙箱状态，包括当前工作目录与已加载的插件**；以一致接口格式化并返回 observation。
- **镜像三标签系统**（一个很值得借鉴的构建缓存设计）：
  - **Versioned Tag**：`oh_v{version}_{base_image}`（最泛）
  - **Lock Tag**：`oh_v{version}_{16位lock_hash}`，hash 来自 base image 名 + 镜像内 `pyproject.toml` 内容 + `poetry.lock` 内容——**这是依赖的 hash，与源码无关**
  - **Source Tag**：`oh_v{version}_{16位lock_hash}_{16位source_hash}`（最具体），source hash 是 openhands 源码目录哈希的 MD5 前 16 位
  - 构建时的四级回退：**No re-build**（存在相同 source tag 的镜像就直接用）→ **Fastest re-build**（存在 lock tag 就基于它构建，跳过除复制源码外的所有安装步骤）→ **Ok-ish re-build**（基于 versioned tag 构建）→ **Slowest re-build**（从 base image 全新构建）
- **卷挂载**支持 bind mount（`/abs/host/path:/container/path[:mode]`）与 Docker named volume（`volume:<name>:/container/path`）；**overlay（copy-on-write）** 通过在 mode 后追加 `:overlay` 支持，需把 `SANDBOX_VOLUME_OVERLAYS` 指向一个可写宿主目录（未设置则 overlay 挂载被跳过）。
- **插件系统**：Python 类继承 base `Plugin`，在 `openhands/runtime/plugins/__init__.py` 的 `ALL_PLUGINS` 注册；通过 `Agent.sandbox_plugins: list[PluginRequirement]` 关联；**在 runtime 启动时异步初始化**。已知插件：Jupyter（Kernel Gateway）、VS Code（暴露带 token 的 URL）、Agent Skills（`openhands/runtime/plugins/agent_skills/`）。
- **端口分配用文件锁定的区间**（"file-locked ranges for stability and concurrency"）：主 runtime 端口、VS Code 端口（`SandboxConfig.sandbox.vscode_port` 或 `VSCODE_PORT_RANGE` 内找）、两个 app 端口区间。VS Code URL 形如 `http://localhost:{port}/?tkn={token}&folder={workspace_mount_path_in_sandbox}`（Docker/Local）或 `scheme://vscode-{host}/?tkn={token}&folder=...`（Remote），token 来自 action execution server 的 `/vscode/connection_token`。

### 5.6 后端系统总览

[verified: official docs]（[backend](https://docs.openhands.dev/openhands/usage/architecture/backend.md)）

- **前端（SPA）→ HTTP/WS → OpenHands Backend**；backend 持有 EventStream、Storage、Runtime Interface、LLM Providers。
- Runtime Interface 有三实现：Docker Runtime、Local Runtime、Remote Runtime，**都收敛到同一个 ActionExecutionServer**，后者再驱动 BashSession、JupyterPlugin、BrowserEnv。
- 类图给出的抽象链：`Agent`（抽象，带 `sandbox_plugins`）← `CodeActAgent`（带 `tools`）；`Runtime` ← `ActionExecutionClient` ← {DockerRuntime, LocalRuntime, RemoteRuntime}；`ActionExecutionServer` 暴露 `/execute_action` 与 `/alive`。
- **`Action --> Observation`** 的关系被画在事件流上，确认 action-observation 是核心配对。
- 文档自己给出「更新此图时需对照的代码」清单——这是可核查性的好实践：`action_execution_client.py`、`docker_runtime.py`、`local_runtime.py`、`action_execution_server.py`、`plugins/*`。

### 5.7 Conversation 抽象（Local vs Remote 同 API）

[verified: official docs]（[conversation](https://docs.openhands.dev/sdk/arch/conversation.md)）

- `Conversation(agent, workspace)` 是一个**工厂**：workspace 是字符串或 `LocalWorkspace` → `LocalConversation`（进程内执行）；`RemoteWorkspace` → `RemoteConversation`（经 agent-server 走 HTTP/WebSocket）。
- 四项主要职责：agent 生命周期管理（初始化/运行/暂停/终止）、状态编排（对话历史、事件、执行状态）、workspace 协调、运行时服务（持久化、监控、安全、可视化）。
- 对比表：Local 是直接函数调用、状态立即同步、用于开发与 CLI；Remote 是 HTTP + WebSocket、状态网络序列化、用于生产与 web app；隔离级别分别是**进程级**与**容器级**。
- **"Key Insight: Same API surface means switching between local and remote requires only changing workspace type—no code changes."**

### 5.8 中断语义

[verified: official docs]（[events](https://docs.openhands.dev/sdk/arch/events.md)）

- **`PauseEvent` 是一等事件类型**（`source` 为 `user`，表示用户请求暂停 agent 执行）——**它是内部事件，不发给模型**。
- 加上 `Agent` 的 Interruptible 特性（"Each step is atomic and can be paused/resumed"）与 `Conversation` 的 pause/terminate 职责，OpenHands 有明确的会话级暂停语义。
- **中断/暂停是模型不可见的**——这（与 Codex 的 `agents.interrupt_message = true` 默认相反）是一个有意思的取舍。

### 5.9 转录 UI / 可视化

[verified: official docs]（[conversation](https://docs.openhands.dev/sdk/arch/conversation.md)）

- **Visualization 被列为 aux service**："Execution diagrams | Event stream → visual representation"。
- 前端是 SPA，经 HTTP/WS 与 backend 通信；`RemoteConversation` 用 WebSocket 做事件流。
- **[未核实] 本次没有抓到 OpenHands 前端的转录渲染机制文档**（虚拟化、工具调用折叠、diff 渲染模式、thinking 展示、流式渲染性能）。

---

## 6. Cursor

主要来源：`https://cursor.com/docs/**`（`.md` 后缀可拿到干净 Markdown）。

### 6.1 代码库索引 / 检索

- **关键事实：Cursor 现在不存代码库的 embeddings 用于搜索。** Instant Grep 是"a custom search engine that outperforms `ripgrep` on large codebases"，**索引在你的机器上构建与查询**："Cursor does not upload file paths or code to build a search index, and **it does not store embeddings of your codebase for search**."（当 Agent 打开某个匹配文件时，那个文件内容当然仍可能进入模型请求。）[verified: official docs]（[search](https://cursor.com/docs/agent/tools/search.md)）
- Instant Grep 支持完整正则与词边界匹配，运行无需配置。**[inferred] 这与"Cursor 用 embeddings 做语义检索"的普遍印象不符——至少在当前版本的官方文档里，被明确否定的是"为搜索而存 embeddings"。**
- **Explore subagent 承担检索的上下文隔离**：它跑在自己的上下文窗口里、用更快的模型、执行大量并行搜索、只返回相关发现。可自动触发，也可显式请求（"use a subagent to find all the places we validate user input"）。[verified: official docs]（[search](https://cursor.com/docs/agent/tools/search.md)）

### 6.2 上下文管理

- **Cursor 的官方文档没有描述自动压缩/摘要机制。** 它走的是**委托隔离**路线：把上下文密集的操作交给 subagent。[verified: official docs]（[subagents](https://cursor.com/docs/subagents.md)）
- **两个内建 subagent 的引入动机被明确写成"基于对 agent 对话的分析"**："These subagents were designed based on analysis of agent conversations where context window limits were hit." 表格给出的理由：
  - **Explore**：代码库探索产生大量中间输出，会撑爆主上下文；用更快的模型跑大量并行搜索
  - **Browser**：浏览器交互产生**嘈杂的 DOM 快照与截图**；subagent 把它过滤成相关结果
- **四条共同特征**被列出：产生嘈杂的中间输出、受益于专门的 prompt 与工具、能消耗大量上下文、以及**成本效率**（"Faster models cost less. Isolating token-heavy work in subagents with appropriate model choices reduces overall cost."）。

### 6.3 System prompt 结构

- **三层组件**：1. **Instructions**（system prompt + rules）2. **Tools** 3. **Model**。[verified: official docs]（[agent/overview](https://cursor.com/docs/agent/overview.md)）
- **"Cursor's agent orchestrates these components for each model we support, tuning instructions and tools specifically for every frontier model."** —— **每个前沿模型有各自的 instructions 与 tools 调优**。[verified: official docs]（[agent/overview](https://cursor.com/docs/agent/overview.md)）
- **`Rules` 有四种作用域与四种应用模式**，且**底层是三个 frontmatter 字段的交互**（这是一个很干净的"何时进上下文"决策表）：[verified: official docs]（[rules](https://cursor.com/docs/rules.md)）

  | `alwaysApply` | `description` | `globs` | 行为 |
  |---|---|---|---|
  | `true` | — | — | **总是**包含（globs 与 description 被忽略） |
  | `false` | — | 有 | 上下文中出现匹配文件时自动附加 |
  | `false` | 有 | 无 | Agent 读 description 并在相关时拉入 |
  | `false` | 无 | 无 | **仅在你 `@`-mention 时**包含 |

- **项目规则必须是 `.cursor/rules/` 下的 `.mdc` 文件**；纯 `.md` 会被忽略（"because it has no frontmatter to specify `description`, `globs`, and `alwaysApply`"）。要纯 Markdown 就用 `AGENTS.md`。[verified: official docs]（[rules](https://cursor.com/docs/rules.md)）
- **规则内容按原文到达 agent；`@file` 引用不会被内联**："The file's contents are not inlined into the prompt... Put anything that must always be in context directly in the rule body."[verified: official docs]（[rules](https://cursor.com/docs/rules.md)）
- **优先级**："Team Rules → Project Rules → User Rules. All applicable rules are merged; earlier sources take precedence when guidance conflicts." 团队规则可标为"enforced"（成员无法在 Customize 关掉）。[verified: official docs]（[rules](https://cursor.com/docs/rules.md)）
- **`AGENTS.md` 支持嵌套**：项目根与任意子目录；"Instructions from nested `AGENTS.md` files are combined with parent directories, with more specific instructions taking precedence."[verified: official docs]（[rules](https://cursor.com/docs/rules.md)）

### 6.4 Subagent / 任务委派

[verified: official docs]（[subagents](https://cursor.com/docs/subagents.md)）

- **每个 subagent 独立上下文窗口**；"Subagents start with a clean context. The parent agent includes relevant information in the prompt since subagents don't have access to prior conversation history."
- **前台 vs 后台**：前台阻塞直到完成并立即返回结果；后台立即返回、独立工作。
- **自定义 subagent 在 `.cursor/agents/`（项目）/ `~/.cursor/agents/`（用户）**，**并兼容 `.claude/agents/` 与 `.codex/agents/`**；同名冲突时 `.cursor/` 优先。frontmatter 字段：`name`、`description`、`model`（默认 `inherit`）、**`readonly`**（为 `true` 时限制写权限：不能编辑文件、不能跑会改状态的 shell 命令）、**`is_background`**。
- **模型参数可内联指定**：`composer-2.5[fast=false]`、`claude-opus-5[effort=high]`、`claude-opus-5[context=300k]`、`claude-opus-5[effort=high,context=300k]`。
- **模型回退的三种触发条件**：团队管理员封禁该模型、legacy request-based 计划下需要 Max Mode 但未启用、该模型不在你的计划内。
- **嵌套上限**：自 Cursor 2.5 起 subagent 可以启动子 subagent 形成协作树，但**"the main agent and its direct subagents can launch subagents, but a subagent launched by another subagent can't launch further ones"**（即两层）。
- **隔离级别可分档**：默认共享父 agent 的 checkout；显式请求隔离时**每个 subagent 得到自己的环境与分支——本机上是一个隔离的 git worktree（独立工作目录），云端上是自己的 VM 与仓库克隆**。改动留在各自分支直到父 agent 合并。
- **可恢复**：每次执行返回 agent ID，用它恢复并保留完整上下文。后台 subagent 边跑边写状态；输出写到 `~/.cursor/subagents/`，父 agent 可以读这些文件看进度（**[inferred] 这是一个"用文件系统当 IPC"的务实做法**）。
- **失败处理**："The subagent returns an error status to the parent agent. The parent can retry, resume with additional context, or handle the failure differently."
- **成本论述诚实**：50 个并行 subagent 的 token 开销约为单 agent 的 5 倍；"The benefit is context isolation, not speed. A subagent doing a simple task may be slower than the main agent because it starts fresh."
- **官方明确反对反模式**："Having 50+ subagents with vague instructions like 'helps with coding' is ineffective."；"A 2,000-word prompt doesn't make a subagent smarter. It makes it slower and harder to maintain."；"Start with 2-3 focused subagents."
- **验证 agent 模式被官方推为首选范式**（verifier：怀疑地验证被声明完成的工作确实能跑）；另有 orchestrator 模式（Planner → Implementer → Verifier，**每次交接带结构化输出**）。

### 6.5 记忆 / 项目指令

见 6.3。要点：`.cursor/rules/*.mdc` + `AGENTS.md`（支持嵌套）+ User Rules（全局，**不作用于 Inline Edit**，只被 Agent (Chat) 使用）+ Team Rules（dashboard 管理）。[verified: official docs]（[rules](https://cursor.com/docs/rules.md)）

### 6.6 编辑 / 应用策略

**[未核实] Cursor 的官方文档没有描述编辑的应用算法**（search/replace 块还是 unified diff），只说 "Suggest edits to files and apply them automatically"。[verified: official docs]（[agent/overview](https://cursor.com/docs/agent/overview.md)）

### 6.7 验证循环

- **没有自动跑测试的内建描述**。可确认的相关机制：[verified: official docs]（[subagents](https://cursor.com/docs/subagents.md)、[agent/overview](https://cursor.com/docs/agent/overview.md)）
  - **Verifier subagent 模式**（官方作为 common pattern 给出，含完整 prompt 模板）
  - **Browser tool**："Control a browser to take screenshots, test applications, and verify visual changes. Agent can navigate pages, interact with elements, and capture the current state for analysis."
  - **`Agent Review`** 与 **Bugbot / Security Agents** 是独立产品文档（本次未抓取）。
- **`Ask questions` 的一个非阻塞设计**：等待你回答时 agent **继续**读文件、做编辑、跑命令，"Your answer is incorporated as soon as it arrives"。[verified: official docs]（[agent/overview](https://cursor.com/docs/agent/overview.md)）

### 6.8 检查点 / 回退

[verified: official docs]（[agent/overview](https://cursor.com/docs/agent/overview.md)）

- **快照式，与 git 分离**："Checkpoints save snapshots of your codebase during an Agent session. Agent automatically creates them before making significant changes, capturing the state of all modified files."
- **是自动的，不是在每个 prompt 上**——"before making significant changes"（与 Claude Code 的"每个开启一轮的 prompt 打一个"不同）。
- 可以在 chat timeline 点任意 checkpoint **预览**那时的文件，再 restore 回退所有文件；也可从先前请求的 `Restore Checkpoint` 按钮或悬停在消息上的 `+` 按钮恢复。
- **"Restoring a checkpoint reverts files only; it does not remove messages from the conversation."** —— 对照 Cline 的三选项（Files / Task Only / Files & Task），Cursor 只提供 Files。
- 存储是**本地、与 Git 分离**；"Only use them for undoing Agent changes; use Git for permanent version control."

### 6.9 权限 / 沙箱（Cursor 最强的一块）

[verified: official docs]（[run-modes](https://cursor.com/docs/agent/security/run-modes.md)）

- **三种 Run Mode**：
  | 模式 | 免批准执行 | 沙箱 | 分类器 |
  |---|---|---|---|
  | **Auto-review**（推荐默认） | 白名单调用立即执行；其它 shell 命令尽量走沙箱；不用沙箱的调用交给 Auto-review 分类器 | 是（shell 命令） | 是 |
  | **Allowlist** | 白名单内的动作 | 可选（shell 命令） | 否 |
  | **Run Everything** | 每个工具调用 | 否 | 否 |
- **Auto-review 的检查顺序**（很具体的生命周期）：本机上白名单内的 shell / Fetch / MCP 调用**在沙箱外**执行 → 其它 shell 命令**尽量在沙箱内**执行 → **无法用沙箱的 shell 命令、沙箱执行失败的命令、以及其它调用**交给 **Cursor 后端上的 LLM 分类器** → 分类器**可以在你机器上做只读的 `ReadFile`、`Grep`、`Glob`、`ListDir`**（例如读命令要执行的脚本）→ 允许的调用在沙箱外执行 → 被阻断的调用让 agent 换方案或弹审批。
- **分类器模型**：当前用 **Gemini 3.5 Flash Lite**，回退 **Claude 4.5 Haiku**；团队封禁 Claude 4.5 Haiku 会**导致 Auto-review 不可用**并把成员退回 Allowlist。
- **明确自我否定**："Auto-review is not a security boundary. The classifier can make mistakes."
- **`permissions.json` 用自然语言写策略**：`~/.cursor/permissions.json`（全项目）与 `<project>/.cursor/permissions.json`（单项目，会合并），也可由团队在 dashboard 配全局策略（优先于本地）。schema 是 `autoRun.allow_instructions` / `autoRun.block_instructions`，每条是**纯英文句子**，例如 `"Every AWS CLI command should go through approval first."`。**Agent 可以直接帮你改这个文件**——"Tell it something like 'I want every AWS CLI command to go through approval first,' and it edits your `permissions.json` for you."
- **沙箱的 OS 实现**：
  - macOS：**Seatbelt**，通过 `sandbox-exec`，"A generated sandbox profile limits file access, network access, and other process behavior **for the full subprocess tree**"（需要 Cursor v2.0+）
  - Linux：**Landlock + seccomp**（Landlock 管文件系统、seccomp 挡不安全 syscall）；要求**内核 6.2+ 且 Landlock v3**（`CONFIG_SECURITY_LANDLOCK=y`）与非特权 user namespace；**不满足内核要求时回退为"跑命令前询问批准"**
  - **Linux 沙箱内 UID 被重映射为 0**：`id -u` 和 `$UID` 返回 0；需要真实 UID 时读 **`CURSOR_ORIG_UID` / `CURSOR_ORIG_GID`**（在沙箱施加 namespace/identity 变更之前捕获）。另外注入 `CURSOR_SANDBOX`（macOS 为 `"seatbelt"`，Linux 为 `"native"`）与 `CURSOR_SANDBOX_LANDLOCK_STATUS`（`fully_enforced` = Landlock，`bubblewrap` = 回退）。
- **受保护路径**：`.git/config`、`.git/hooks`、`.vscode`、`.cursorignore` 以及敏感的 Cursor 配置文件；每项目还有 `.cursorignore` 隐藏文件。默认沙箱行为：工作区内可读写；**网络默认阻断**；`/tmp` 与平台临时目录可写（可在 `sandbox.json` 关掉）。
- **网络三档**：`sandbox.json Only`（只用你的允许列表）/ **`sandbox.json + Defaults`（默认；你的列表 + Cursor 对常见包管理器与语言工具的内建默认）** / `Allow All`。文档**完整列出了默认允许域名**（一份近百条的清单：`registry.npmjs.org`、`pypi.org`、`proxy.golang.org`、`crates.io`、`maven.org`、`docker.io`、`ghcr.io`、`github.com`、`apt.llvm.org`、`pub.dev`、`rubygems.org`、`nuget.org`、`playwright.azureedge.net` 等）。**[inferred] 这份清单本身就是"agent 需要什么网络"的数据集。**
- **`permissions.json` 与 `sandbox.json` 职责分离**被明确写出：前者决定 Auto-review 自动跑还是审查，后者控制沙箱内能被什么访问（域名、额外可读写路径、临时目录写入、共享构建缓存）。
- **Read Access 三档**（Cursor 3.23+，最新特性）：`System`（默认，可无批准读工作区外文件）/ `Workspace`（工作区内自由读，工作区外需批准，除非在 **Read Allowlist** 内）。Workspace 模式下：搜索保持在工作区边界内、沙箱命令只能读工作区 + Read Allowlist + 常见工具需要的系统路径（系统库、工具链、证书存储），**命令得到项目私有的临时目录而不是宿主临时目录**。Read Allowlist 支持文件夹、glob（`~/notes/*.md`；**沙箱命令不能匹配 glob，会退化为读该 pattern 的父目录**）、`~` 展开。可用 `sandbox.json` 的 `readBoundary` 与 `additionalReadPaths` 配置。**Run Everything 模式下 Read Access 不适用（设置项被隐藏）。**
- **另有三个独立保护层**（即使模式本该自动跑也仍需批准）：Browser Protection（阻止自动运行 Browser 工具）、File-Deletion Protection（阻止自动删文件，含 `rm`）、External-File Protection（阻止在工作区外自动创建/修改/删除文件）。
- **团队控制优先于个人与项目配置**；可覆盖可用模式、配网络规则、设团队读策略。**Cloud Agents 不用 Run Modes**——"Cloud Agents run inside their own dedicated machine, so the agent never asks you to approve an action."

### 6.10 中断语义

[verified: official docs]（[agent/overview](https://cursor.com/docs/agent/overview.md)）

- **排队（Queue）**：Agent 工作时按 Enter 把消息加入队列，等当前任务完成后**顺序**处理；**可拖拽重排**队列。
- **立即发送（Cmd+Enter）**："your message is appended to the most recent user message in the chat and processed right away without waiting in the queue. Your message attaches to tool results and sends immediately."
- **Steer a running agent**（更新的机制）：发 follow-up 并点 **Send now** 或**按两次 Enter**，**消息在 agent 的下一个工具调用处送达，而不是中途切断动作**——"which preserves in-flight work and keeps the agent on task"。按 Tab 则改为排队到 turn 之后。
- **CLI 的语义与 GUI 不同且被明确区分**："In the CLI, pressing Enter while the agent works **steers the active run at a safe boundary**, and pressing Enter again **interrupts the turn**."
- **`/goal` 的长久目标语义**：Agent 把每条消息读作一个新 job，`/goal` 给它一个长期目标；"In the CLI, Ctrl+C pauses the goal."
- **Side chat**：`/side` 或 `/btw` 开一个不打断主对话的旁路对话；"It uses the parent thread as hidden reference context and keeps its own transcript. @-mention the side chat in the main thread to pull that context back." —— **旁路对话是一个持久的 agent 对话，有自己的 transcript，且可被主线程按名引用**。[verified: official docs]（[agent/overview](https://cursor.com/docs/agent/overview.md)）

### 6.11 转录 UI

[verified: official docs]（[agent/overview](https://cursor.com/docs/agent/overview.md)）

- **对话检索**：在 Agents Window 里按 `Cmd+K` / `Ctrl+K` 打开 command palette 搜索**历史 agent transcript**；"Cursor builds a local search index."。在当前对话内查找文本用 `Cmd+F` / `Ctrl+F`。
- **Checkpoint 时间线可点**：点任意 checkpoint **预览**文件状态，再 restore。
- **`/goal` + `/loop`**：内置技能 `/loop` 可按固定或可变间隔跑一个 prompt/skill；不指定固定间隔时 **agent 自己决定何时唤醒**。
- **[未核实] 本次没有抓到 Cursor 转录渲染的机制级文档**（长聊虚拟化、工具调用折叠策略、diff 侧对比 vs 统一、thinking 展示、流式渲染性能）。

---

## 7. DeepSeek Harness（DSH，本地发行物）

来源：`D:\DeepSeek\ds\resources\app.asar` 内的 `dsh/` 树，以及本仓库既有调研 `docs/dsh-comparison/01-architecture-plugins.md`、`02-session-runtime.md`、`03-client-ui.md`。以下路径均**相对于 asar 内的 `dsh/`**。本次我重新阅读了这些调研文档的原文段落，**未重新进入 asar 逐行复核**——因此 DSH 部分的标记为 `[verified: read source]`（指上一轮确读过源码）或 `[verified: in-repo prior research]`。

**发行形态约束（影响一切）**：asar 根只有 `desktop-runtime.json`、`node_modules/`、`package.json`；`node_modules/@deepseek-ai/` 有 289 个条目；共 3664 个文件、**0 个 `.d.ts`**；只有带 YAML frontmatter 的 README 是可依赖的契约；**`lib/*.js` 是真正的代码**，`src/*.ts` 只存在于 cordis 系列。版本：`dsh/package.json:4` `"version": "0.2.0-rc.2"`，Cordis `4.0.4`，`"type": "module"`。[verified: in-repo prior research]

### 7.1 架构与插件系统

- **插件契约三种形态**（`cordis/src/registry.ts:91-95`）：`export type Plugin<T = any> = Plugin.Function<T> | Plugin.Constructor<T> | Plugin.Object<T>`；函数形态 `(ctx, config)`（`:120-123`）、类形态 `new (ctx, config)`（`:125-128`）、对象形态 `apply(ctx, config)`（`:130-133`）。元数据基类字段 `name`/`Config`/`inject`/`provide`/`intercept`（`:100-111`）。错误：`invalid plugin, expect function or object with an "apply" method`（`:319`）。[verified: in-repo prior research]
- **生命周期状态机**（`cordis/src/fiber.ts:139-154`）：PENDING / LOADING / ACTIVE / FAILED / UNLOADING / DISPOSED；`_refresh()` `:611-623`、`_reload()` `:646-673`、`_unload()` `:675-696`、`await()` `:704-710`、`restart()` `:718-723`、`update(config, noSave)` `:736-753`（先跑 `internal/update` waterfall，让 HMR 可以否决或替换重启）。[verified: in-repo prior research]
- **服务注入**：`Inject<M> = (keyof M)[] | { [K in keyof M]?: M[K] }`（`registry.ts:19`）；`ctx.inject(deps, callback)` 等价于 `ctx.plugin({ inject, apply: callback, name: callback.name })`（`:176-177`、`:300-302`），JSDoc 说明**任一所需服务变化时回调会被卸载并重跑**；Proxy traps 在未声明 inject 时抛 `cannot get property "<prop>" without inject`（`reflect.ts:144`），在非活动上下文抛 `cannot get required service "<prop>" in inactive context`（`reflect.ts:160`）。[verified: in-repo prior research]
- **profile / bundle / patch 组合**（`dsh-app-boot/lib/index.js`）：profile 是 `$DSH_HOME/profiles/<name>` 下的目录，含 `package.json`（`dsh.profile.bundles` 有序）与 `cordis.patch.yml`（`:465-475`）；组合顺序 `:472-475` = 按 `dsh.profile.bundles` 顺序把每个 bundle 的 patch 叠到**一个空条目列表**上，然后是 profile 自己的 patch，最后是 launcher 层（`--patch` 与 flag 派生的 patch）。[verified: read source]
- **CRITICAL：patch 的 `config` 是整体替换而非深合并**——JSON Schema 描述 `index.js:2760`："Other patches replace supplied fields; config is replaced wholesale, not deep-merged." patch 语义 `:61-105`：无 id 的 `insert` 追加到顶层；带 id 的 `insert` 要求目标 `group: true` 且追加进它的 `config` 列表（警告文案 `patch insert: entry %C not found` / `is not a group`）；既无 insert 又无 id → 警告 `patch: id is required for non-insert patches`；id 覆盖在目标缺失时警告、名字不匹配时 `name mismatch ... skipping`，否则替换字段。[verified: read source]
- **启动审计**（`index.js:4010-4019`）：收集未激活条目；缺少必需 id 则抛 `StartupError`，否则警告。必需全局 id 见 `dsh-app-boot/README.md:43`：`agent-loop`、`webserver`、`modules`、`connection`、`headless-runner`、`acp`、`sdk-jsonrpc-server`。[verified: read source]
- **本机真实 profile**（`C:\Users\HJIE\.dsh\profiles\`）：`default`、`desktop`、`headless`、`smoother-deepseek-harness`、`web`；`web\package.json` = `{"name":"dsh-profile-web","private":true,"dependencies":{},"dsh":{"profile":{"bundles":["@deepseek-ai/dsh-base","@deepseek-ai/dsh-web-app"]}}}`。[verified: read source]

### 7.2 执行循环（turn / step）

[verified: read source]（`docs/dsh-comparison/02-session-runtime.md` §1）

实现主驱动在 `dsh-agent-loop/lib/index.js`：`turn()` `:936`、`step(decision)` `:1041`、`preStep(target, position)` `:902`、`prepareRequest(turn, step, signal)` `:1163`、`buildRequest(...)` `:1202`。README 定义：*"... then drives each turn through model requests, streamed responses, tool execution, and durable session history."*（`agent-loop/README.md:12`）

阶段序列（含行号）：

0. `kick()` 反复调 `turn()`：`agent-loop/lib/index.js:887: async kick()` / `:889: while (await this.turn());`
1. **开启 turn**：先写 `turn/start`（**持久化在模型请求之前**）——`:941: const turn = phase.turn + 1;`、`:943: this.session.append("turn/start", { turn });`
2. **步前决策 `agent/pre-step`**：先声明 inbox 待处理输入（`:906` `this.inbox.claim(...)`），再组装 system prompt（`:907` `this.loopCtx.systemPrompt.assemble(...)`），投影运行时上下文，最后走 waterfall 决策（`:911`），可 `reject`（`:920`）
3. **写 `step/start`**：仅在决策被接受且批次非空时开步——`:962`、`:963`、`:968`
4. **路由解析**：`agent/request` waterfall（`:1179`）产出 config，再 `ctx.llm.prepareCall()`（`:1189`）绑定适配器；无适配器时保留 `NO_ADAPTER` 语义（`:1192`）
5. **提交 system prompt 与用户消息**：`systemPrompt.project(...)`（`:1052`）产出若干 `system/message` 提交意图；**首答才提交 user 批次**（`:1061`）
6. **构造并冻结请求**：`request/header` 仅在首个/变更/新序列时写（`:1214`/`:1220`/`:1225`），工具增删写 `developer/message`（`:1240`），必要时写 `request/context`（`:1259`）；**请求对象不含 `system` 字段**（`:1269` 的 `Object.freeze`，`agent-loop/README.md:119`："it carries no `system` field"）
7. **流式模型调用与助手锚点**：每次尝试 `live.start()`（`:1074`），逐 chunk `live.push(chunk)`（`:1076`）；正常结束写 `assistant/message`（`surfaceOp: 'append'`，`:1144`），**取消则写 `interrupted: true` 的锚点（`:1086`）**，失败/中止写 `assistant/attempt`（`:1101`）
8. **工具执行**：无 tool-call 即完成（`:1153`）；有则 `executeToolCalls(...)`（`:1154`）。每个工具条目先写 `tool/call`（`:682`），结果写 `tool/result` 并以 `sourceEventSeqs: [callSeq]` 指回（`:697`）。调度由 `executionMode()` 决定独占或并行（`:523`）；独占调用组成**屏障**，并行调用用**有界滚动池**（上限 `maxParallelToolCalls`，`:553`、`:619`），**结果按模型顺序提交**
9. **收尾 `step/end` / `turn/end`**：`step/end` 在 finally 中无条件写（`:992`）；`turn/end` 携带 `reason`（`completed` / `max-tokens` / `blocked` / `aborted` / `error`，`:1027`）

**可选配置**：`agents[].maxParallelToolCalls` 默认 **10**（`agent-loop/lib/index.js:1285: const DEFAULT_MAX_PARALLEL_TOOL_CALLS = 10;`，schema `:1534`）；`provider`/`model` 必填（缺一在 `agent/request` 阶段报错，`:1185`）。

**状态持久化**：事件溯源——`session/README.md:88`："The package is built on event sourcing: a `Session` is an append-only log of typed `SessionEvent`s, and everything else ... derives from that stream."；**seq 恒等于日志长度**（`session/lib/index.js:1455: seq: SessionSeq(this.log.length)`，`:1400` 注释）；持久化后端接入点在 agent-loop（`agent-loop/README.md:115`）；默认后端每 session 一个 append-only 日志、**默认 Zstandard 压缩帧**（`session-persistence-jsonl/README.md:48`）；崩溃恢复保留中断的最后一个 turn，由 resume 路径补合成收尾事件。

### 7.3 工具定义契约与执行流水线

[verified: read source]（`docs/dsh-comparison/02-session-runtime.md` §2）

- **双轨 schema**：作者侧统一 DSL（支持 `string`/`number`/`integer`/`boolean`/`null`/`array`/`object`/author-only `json`/exact-one `oneOf`），wire 侧受限 JSON Schema 子集（与 subagent / workflow / MCP 共用）。`tools/README.md:60`
- **被强制执行的子集**（实现级）：`tools/lib/index.js:206` 不支持的关键字直接记违规（subset: `type`/`oneOf`/`properties`/`required`/`additionalProperties`/`items`/`enum`/`const` + annotations）；**不支持 `type: [...]` 联合类型**（`:237`）；**不支持 `oneOf` 与 `type` 并存**（`:212`）；`oneOf` 至少 2 个分支（`:227`）；`oneOf` 旁不允许兄弟关键字；**`additionalProperties: false` 会被真正检查**（`:468`）。唯一允许的注解键是 `["description", "title", "default", "examples"]`（`:537`）。
- **投影到 wire 的字段白名单**：只有 `{ name, description, parameters, ...(deferLoading ? { deferLoading } : {}) }`（`:3039`）；`output`、`execute`、`finalizeContent`、`timeoutMs`、presentation 回调**都不外泄**（`tools/README.md:103`）。
- **参数校验在 body 之前**（`:866-869`）：违规抛 `ToolArgsError`，变成普通错误结果而不是异常终止 turn。
- **固定执行流水线**（`tools/README.md:105`）：`tools/pre-execute`（可扩展的 allow/deny/ask）→ 注册的**单调 guard** → `tools/execute`（around-dispatch wrapper）→ `tools/post-execute`（inspect/replace，可附加上下文）→ 定义自有的 `finalizeContent` → 只读的 `tools/result` 事件。实现行：`:3225`、`:3226`、`:3243`、`:3331`、`:3504`、`:3409-3420`。
- **guard 是单调的、只能否决**（`tools/README.md:85`）："a returned reason denies the call, and **no later listener can turn that denial back into permission**"（实现 `:2646` `guardReason`、`:2921` `guard()`）。
- **ask 的 fail-closed 四态**（`:3464`–`:3482`）：只有 `allowed-once` 放行；`rejected`（`the user rejected tool "..."`）、`cancelled`（`approval for tool "..." was cancelled`）、`unavailable`（`tool "..." requires approval, but no approval channel is available`）**全部映射为 deny**。会话级策略只有 `ask` / `never` 两档，且 **`never` 在服务内部先于 waterfall 判定**，`prepend` 注册的 listener 无法绕过（`user-approval/README.md:78`）。审批落盘为 **成对事件** `approval/asked` + `approval/decided`（`user-approval/README.md:86`）。
- **deny 的落地文本**统一为 `Error: <reason>`，并携带结构化 `error.info`（供 UI/PTC 投影，**不进模型正文**）（`:3247`/`:3251`/`:3252`；`tools/README.md:123`）。

### 7.4 工具结果裁剪（三套并存 + 超时）

[verified: read source]（`docs/dsh-comparison/02-session-runtime.md` §2.4）

**(a) spill（落盘 + 预览）**——`dsh-spill` 提供 `ctx.spillStore.saveText()` 返回 `SpillRef = { locator, bytes, retrievalHint }`；`dsh-spill-policy` 挂 `tools/post-execute` 监听器决定何时替换。配置只有一个 `maxInlineTokens`（省略 = 关闭）。提示文案由 `formatSpillNotice` 生成（`spill-policy/lib/types/notice.js:20`）。**失败降级为 best-effort**："A missing owner or spill backend, failed storage, missing route image pricing, or unavailable execution-world image path logs a warning and **keeps the original content**."（`spill-policy/README.md:65`）

**(b) compaction 前置 pruner（头+尾截断）**——仅在压缩触发后、选择压缩区间前运行：`thresholdChars=8192`、`headChars=4096`、`tailChars=1024`（`compaction-tool-result-pruner/README.md:52-54`）。替换事件用 `sourceEventSeqs` 指回原事件，并**紧邻前置**一条 `compaction/prune` 影子计价事件。

**(c) per-tool retainer**——`dsh-output-retention` 提供 `ItemRetainer` / `TextRetainer` / `formatRetentionNotice` / `truncateWithoutSplittingSurrogatePair`。`TextRetainer` **按字节**计数（`head`/`tail`/`headTail`），`finish()` **会裁掉切点上的半个码点**。`truncated` 的语义被严格限定为"预算事实"：*"`truncated` is a budget fact: the retainer omitted otherwise-available content because of a cap. It never means the upstream was incomplete."*（`output-retention/README.md:83`）用户：`glob`/`grep`/`web_search` 用 `ItemRetainer`(head)、`bash` 用 `TextRetainer`、`web_fetch` 用 `TextRetainer`；**`read` 不在其中**，因为它的 `offset`/`limit` 分页是文件专用渲染器。

**(d) 超时是协作式的**——`tools/README.md:232`：*"`timeoutMs` on a definition is declarative only — the registry never enforces deadlines; enforcement requires the `@deepseek-ai/dsh-tool-call-timeout-policy` wrapper."* 该 wrapper 只 abort `exec.signal`，等下游结算后才把结果替换为 `Error: tool call timed out after <ms>ms` + `{ name: 'ToolTimeoutError', code: 'TOOL_TIMEOUT' }`；**忽略信号的工具有多慢就等多久**（`tool-call-timeout-policy/README.md:122`："**Cooperative, never a hard kill**"）。

### 7.5 上下文压缩

[verified: read source]（`docs/dsh-comparison/02-session-runtime.md` §4）

- **三包分工**：`dsh-compaction`（抽象契约 `CompactionEngine` + `ctx.compaction` 服务 + 事件类型，**自身不做任何压缩**）、`dsh-compaction-basic`（出货后端：自动压力/溢出 + 手动 + 显式区间的 LLM 摘要）、`dsh-compaction-tool-result-pruner`（可选前置）。
- **bracket 即锁**：`compaction/README.md:73`：*"**The log-recorded bracket is the lock.** `compaction/start` is appended before summarization yields and `compaction/end` releases; every failure makes exactly one close attempt, and a failed close leaves the unmatched start as the intentional busy signal."*
- **四个触发路径**：
  1. **自动压力**：序列化的 `agent/pre-step` 监听器，在**请求派生之前**检查压力（`compaction-basic/README.md:113`；实现 `compaction-basic/lib/index.js:839`、`:841`）
  2. **上下文溢出恢复**：`agent/request-error` **仅在 provider 确认 `CONTEXT_WINDOW_EXCEEDED`** 时绕过正常阈值与保留策略，做一次最大化的均衡头部削减，且**只有 surface 的 `replaceGeneration` 前进后才授权 retry**（`:861`、`:862`、`:868`、`:869`、`:872`、`:883`、`:886`）。重试预算在 agent 回到 idle 或产生新的 `assistant/message` 时清零（`:853`、`:856`）
  3. **手动**：`/compact` 命令（`dsh-command-compact`）；手动路径**不需要** open turn，bracket 记 `turn: null`（`compaction/README.md:78`）
  4. **显式区间**：`compactRegion(start, end, ...)`
  三个操作签名：`compactIfNeeded`（自动 `pressure` / `context-overflow`）、`compactNow`（一次显式的按需缩减）、`compactRegion`（调用者选定的 surface 区间）。
- **压缩对象是 surface 区间，起点永远不是 `system/message`**（`compaction-basic/README.md:113`）——"a system prompt at surface node 0 is never shadowed"。
- **产物是一条带 `surfaceOp: { op: 'replace', startSeq, endSeq }` 的 `user/message`**（`compaction/README.md:95`）——**这是唯一的 surface 变更**，其余 `compaction/start`、`compaction/summary`、`compaction/end` 都是 log-only。
- **摘要必须能缩小才被接受**："rejects a summary that does not shrink its source"（`compaction-basic/README.md:125`）。模型可见的包装标签是 `<compacted-summary>`；原始摘要文本保留在 `compaction/summary` 事件上。
- **摘要调用逐字节复用 provider 热前缀**：重放 surface node 0 的 system prompt + 上一次路由请求的 tools + 被遮蔽区间的消息，只把压缩指令作为最后一条 user 消息追加；**仅返回的文本进入 checkpoint，排除 reasoning 与 tool calls**（`compaction-basic/README.md:119`）。
- **剪枝必须均衡工具对**：`toolPairingBalancedBefore(session, seq)` / `toolPairingBalancedAfter(session, seq)`；"A safe edge has no unanswered assistant tool call crossing it."（`compaction/README.md:91`）。显式区间越界时报 `compactRegion: start seq ... is not a balanced boundary (would split a step's tool-call/result pair)`（`:557`）与 `... end seq ... is not a balanced boundary (would split a step, or the step is still open)`（`:558`）。
- **配置项与默认值**（这是最可对照的一组数字）：
  | 字段 | 默认 | 出处 |
  |---|---|---|
  | `thresholdRatio` | **0.8** | `DEFAULT_THRESHOLD_RATIO = .8`（`compaction-basic/lib/index.js:15`） |
  | `headroomTokens` | **65536** | `:63` |
  | `retainRatio` | **0.16** | `DEFAULT_RETAIN_RATIO = .16`（`:17`） |
  | `retainTokens` | —（与 `retainRatio` **互斥**） | `:192` 抛错 |
  | `maxTokens` | = `headroomTokens`（65536） | `:64` |
  | `compactionRetries` | **1** | `:82` |
  | `maxOverflowRetries` | **1** | `:83` |
  | `auto` | `true` | `compaction-basic/README.md:62` |
  | `modelPolicies` | `[]`（精确 `{provider, model, ...partialPolicy}` 覆盖；**重复即拒绝加载**） | 同上 |
  | `summarizationProvider` / `summarizationModel` | `''`（成对设置；空对则用最新路由请求目标，再退回 `AgentOptions`） | 同上 |
- **触发阈值公式**：`floor(min(W × 0.8, W − O − B))`，其中 `B = 65,536`；保留最近 `W − O` 的 **16%** 逐字（实现 `:130`–`:134`）。
- **加载期快速失败**：未知键、重复 per-model 覆盖、非法 token 数、两种保留形式同给、`retainRatio >= thresholdRatio` 都会在**加载时拒插件**（`:155-156`、`compaction-basic/README.md:78`）。
- **README 自陈的边界**（`compaction/README.md:160-162`）：
  - **"Human command, not a model tool — condensation is triggered by the `/compact` command and by automatic pressure; no model-facing compaction tool is registered."**
  - **不可分割单元溢出不在契约内**：均衡摘要压缩不能切分一个不可分割单元；大非工具节点、或非可裁剪剩余部分过大的工具单元无法压缩。
  - **"compaction shrinks derived history, never the system prompt, tools, or session prefix."**

### 7.6 事件与会话持久化

[verified: read source]（`docs/dsh-comparison/02-session-runtime.md` §3）

- **`SessionEventMap` 是 declaration-merging 可扩展的**；发布物保存了本 build 认识的事件名白名单：`session/lib/types/known-event-types.js:21: export const KNOWN_SESSION_EVENT_TYPES = new Set([...])`（**共 56 项**，行 22–81）。分类（行号即字符串所在行）：会话生命周期（`session/end-seed` 54、`session/title` 55）、turn/step（`turn/start` 76、`turn/end` 77、`step/start` 57、`step/end` 58）、模型请求（`request/header` 50、`request/context` 49、`llm/retry` 44、`llm/retry-started` 45）、**surface（模型可见）**（`system/message` 62、`developer/message` 36、`user/message` 78、`assistant/message` 28、`tool/result` 75）、assistant 尝试（`assistant/attempt` 27）、工具调用（`tool/call` 72、`tool/ptc-dispatch` 73、`tool/ptc-dispatch-start` 74）、inbox（`agent/inbox/spliced` 23）、审批（`approval/asked` 24、`approval/decided` 25、`approval/policy` 26）、**压缩**（`compaction/start` 33、`compaction/summary` 34、`compaction/end` 31、`compaction/prune` 32）、目标/计划/待办（`goal/change` 40、`plan/mode` 48、`todo/write` 67）、权限/沙箱（`permission/preset` 47、`sandbox/mode` 51）、子代理/团队/workflow（`subagent/*` 59–66、`team/*` 68–71）、其它（`command/run` 29、`command/done` 30、`hook/invoked` 41、`hook/result` 42、`image/offload` 43、`model/selection` 46、`workspace/changes` 80）。
- **只有一条消息投影事件**：`known-event-types.js:83: export const MESSAGE_PROJECTION_EVENT_TYPES = new Set(['image/offload']);`
- **事件信封是字段白名单**（wire 侧校验，多余字段直接报错）：`api-session-controller/lib/types/client/session-wire-event.js:16-28` 只认 `type`/`seq`/`time`/`data`/`ignorable`/`surfaceOp`/`sourceEventSeqs`，其它抛 `has unexpected field ${key}`；`:31-37` 约束 seq 为非负安全整数且非 `-0`、time 为安全整数、必须自有 `data`、`ignorable` 若存在必须恰为 `true`。
- **未知事件类型的兼容机制是信封上的 `ignorable` 标记，而不是事件名注册**（`known-event-types.js:10-13`）。
- **surface 事件的元数据契约是模型可见性的唯一开关**（`session/README.md:50`）：surface 事件**必须**在两处都带 `surfaceOp`；替换使用**恰好** `{ op: 'replace', startSeq, endSeq }`（闭区间、按当前 surface 顺序）；**Assistant message 嵌入其精确的压缩 provider 流，且禁止 `sourceEventSeqs`**；已知的 log-only 事件**禁止**这两个字段且永不产生消息。实现校验：`session/lib/index.js:299`（非 surface 事件不允许带 `surfaceOp`）、`:304`（surface 事件必须带 `surfaceOp`）。
- **序号契约**：每个事件一个**全局连续 seq，无 per-turn 序号**；`seq = log.length`（`:1455`、`:1400`）；不连续即抛错（`:423` `session event seq N is not contiguous; expected M`）。两种数值类型：`SessionSeq`（标识已存在事件或闭区间水位）vs `SessionLogOffset`（标识间隙、前缀长度或读边界，可等于事件数）；`SessionSeqCursor` 额外允许 `-1`（"no event yet"），`OptionalSessionSeq` 用 `null`（`session/README.md:62`）。
- **重连恢复用 follow 流的 opening cursor + 页连续性，不是 `{sequenceNo, baseline}` 对**（[未核实]：对 `dsh` 下 3091 个非二进制文件做过全文包含性搜索，`sequenceNo` 标识符结果为**空**）。打开顺序是**先 follow，再取首页**；只发布连续的四种变更：`replace` / `prepend` / `append` / `settle-assistant`（`api-session-controller/README.md:48`）。追平规则（`api-gateway/lib/types/client/journal-stream.js`）：重复帧丢弃（`:189`）、部分重叠即协议违规（`:191`）、断层触发修复页（`:194`）、修复页必须走到 opening cursor（`:213`、`:226`、`:233`）。**物理 carrier 重试白名单**：只有 `RemoteStreamCarrierError` 触发自动重连，其它异常是终态失败（`remote-stream.js:113`、`:120`、`:149`）。
- **分页预算（具体数值）**：初始 follow / 重连 opening / `loadOlder()` 至少请求 **50** 条 append 源 `user/message` 与 `assistant/message`，且至少跨 **2** 个 `turn/start`；Host 在同时满足两个下限的第一个 Turn start 停止，或到 **500** 条计数消息或历史耗尽为止；`loadThrough()` 每页最少 **200** 条消息（`api-session-controller/README.md:63`）。
- **投影流与控制流是两套**：`SessionControlStream` 是 `RemoteSnapshotStream`，**每一代 opening 都是完整的进程内基线**，重连即整体替换（`api-session-controller/README.md:48`）。投影快照用 `asOfSeq` 表示一致性切点（`session-projection/README.md:58`；`-1` 表示空日志）。
- **fork API**：签名 `ctx.sessions.fork(source, boundary?, childSessionId?)`（`session/README.md:68`）。**boundary 是闭区间**（`session/lib/types/fork.js:19` 的 `events.slice(0, boundary + 1)` 证明）；紧接前缀追加 `session/end-seed{ inherited: true }`（`:20-25`）；**只修复"开着的尾巴"**——用 `forked` 原因补合成收尾（未应答工具结果 + `step/end` + `turn/end`），**已关闭的 step/turn 保持不变**（`:26`、`:8-9`）；`inheritedEventCount` **只计被复制的前缀**，不计合成收尾（`:15-16`）。边界校验拒绝非安全整数/负数（`session/lib/index.js:1911`）、越界（`:1912-1914`）、不匹配连续 seq（`:1917`）；合法子会话 ID 冲突抛 `SESSION_ALREADY_EXISTS`（`:1888`）。

### 7.7 System prompt 与模型可见性

- **请求体不含 `system` 字段**——系统提示是 surface 上的一个**节点**（`agent-loop/README.md:119`）。[verified: read source]
- 每步构造请求时，**取最新的非空 `system/message` 节点作为有效提示**（`agent-loop/README.md:75`）。[verified: read source]
- system prompt 由 `ctx.systemPrompt.assemble(...)` 组装（`agent-loop/lib/index.js:907`），再由 `project(renderedPrompt, { inHistory, startsSeries })` 产出**若干** `system/message` 提交意图（`:1052`、`:1056`）。**[inferred] `inHistory` 与 `startsSeries` 两个参数说明 system prompt 可以进历史、也可以开启新序列——这是 prompt caching 的序列边界概念。**
- **审批的两条模型可见文案**（与本会话实际收到的系统上下文一致）：`user-approval/README.md:116` 的 `Approval policy: ask. Operations that require approval may ask through the configured answerers; without an available answerer, the request fails closed.`；`:122` 的 `Approval prompts are disabled in this session: actions that require approval are rejected automatically — do not request sandbox escalation (do not set sandbox_permissions).`。[verified: read source]

### 7.8 客户端 UI（转录渲染）

[verified: read source]（`docs/dsh-comparison/03-client-ui.md` §3）包 `@deepseek-ai/dsh-client-ui-chat`（`lib/client.js` 约 56.5 万字节）

- **四个详细度档位是持久化枚举**：`const TRANSCRIPT_VIEW_MODES = ["compact", "standard", "detailed", "verbose"];`（`:11915-11920`）。设置命名空间 `"ui-chat"`（`:11911`）、字段 `transcriptView`（`:11913`）。两个历史值 `"normal"`（`:11925`）与 `"expanded"`（`:11927`）**被读作 `detailed` 但不再提供、不再回写**（读取映射 `:12089`）。非桌面 Web 默认 `detailed`（`:11934-11935`），桌面端默认 `standard`（`dshDesktop in globalThis ? "standard" : DEFAULT_TRANSCRIPT_VIEW_MODE`，`:12357`）。
- **档位到行为的映射是一张表，渲染器从不比较枚举本身**（`POLICIES` `:12100-12129`）：
  | 档位 | `foldCompletedTurns` | `stepGrouping` | `liveProcessDetail` | `settledReasoningPreview` |
  |---|---|---|---|---|
  | compact | true | collapsed | false | false |
  | standard | true | collapsed | true | true |
  | detailed | true | **history** | true | true |
  | verbose | **false** | **none** | false | true |
  设计理由的注释写得很清楚（`:12095-12099`）：*"Renderers and seats select single fields of this policy; **none of them compares the mode enum**, so adding a mode changes only the table below."* **[inferred] 这是本报告中最好的一个"可扩展详细度分级"设计范例，直接对应 NEXUS 的 P1 详细度分级需求。**
- **README 层面的折叠语义**（`README.md:83`）：*"Work-details modes control process-group display and reasoning previews. Compact, Standard, and Detailed **fold eligible completed Turns without hiding the final answer**; Verbose retains the duration/status header without a collapse action and shows historical process rows directly."* 补：`README.md:13`、`README.md:104`（每个分组持有自己的本地 `useDisclosure` 状态，模式切换时保留）、`:106`（外层 Turn 真的隐藏了过程成员时，座位重置这些 disclosure 但**不替换组件 key、不更换 Hook 引用**）、`:108`（过程行在所有 work-details 模式下共用一套文字与图标颜色：静止 tertiary、hover secondary，错误与警告保留语义色）。
- **另一条独立的详细度轴**：性能与用量。`PERFORMANCE_USAGE_MODES = ["compact", "detailed"]`（`:11937`），默认 `detailed`（`:11938`），设置项 `performanceUsage`（`:11943`），行组件 `PerformanceUsageRow`（`:12183-12199`）。compact 只在输入框下显示可用输出速度与缓存命中率、**不提供交互式统计对话框与逐 Turn 用量**（`README.md:61`）。
- **文件引用体系**：前缀常量 `const FILE_ADDRESS_PREFIX = "dsh-resource://file/";`（`:43`）；`encodeSegment` 保留冒号字面量（盘符）`encodeURIComponent(segment).replace(/%3A/gi, ":")`（`:45-47`）；`sessionFileAddress` 产出 `dsh-resource://file/session/<sessionId>/<path>`，反斜杠归一为正斜杠、去掉前导 `./`（`:58-61`）；`fileAddressFor(sessionId, cwd, path)` 决定相对/工作区内绝对路径走 session 作用域、工作区外绝对路径保留绝对路径（`:100-107`）。
- **行号导航契约**（documentpreview `README.md:124`）：`ctx.sidebarRight.openResource(address, { params: { line } })` 传的是 **1-based 源码行**；text-pages 模式下 owner 顺序加载页直到该行或 EOF；**纯文本与代码渲染器暴露源码行锚点，Markdown 不暴露**；选定渲染器没有锚点时导航保持 pending，用户切到纯文本或代码后才执行；**字节模式渲染器不消费源码行导航**；每次完成的导航 revision 只被应答一次。
- **重复地址复用两个层次**：Sidebar 层"a resource tab already showing the same (kind, contentId) is focused wherever it sits unless `revealIfOpened: false`"（`sidebar-right/README.md:93`）；Chat 层用户可见效果是 `#L24` 与 `#L24-L30` 跳到首个指定行并复用已有文件 tab（`ui-chat/README.md:36`）。**导航参数不进布局状态**（`sidebar-right/README.md:74`、`:93`）。
- **随源刷新**：预览主体持有 session 作用域、按 tab id 分桶的共享加载与视图状态，含累计页或完整字节、已读与已观测版本、待处理 Resource 变更、自动刷新状态、加载与失败状态、渲染器选择、滚动偏移、换行、已应答的导航 revision（`README.md:33`）。自动刷新默认开启；其独立开关被隐藏但状态/标签/样式/逻辑保留（`README.md:32`）。同一完整地址的元数据在所有 UI 间共享（`README.md:42`）。
- **滚动**：滚动位置由 Chat 自己用**模块级 Map** 存（`const chatScrollPositions = new Map();` `:12327`；`chatScroll.save`/`chatScroll.read` `:12444-12450`）。语义锚点恢复跨历史 prepend 与渲染器重挂载（`README.md:115`）。**轨道显示阈值按可用宽度而非视口宽度**（"hides when the transcript's available width, excluding its horizontal padding, is at most **900px**"，`README.md:117`）。滚动被拆成六个 hook：`useScrollFollow` / `useProcessScroll` / `useChatViewport` / `useChatReading` / `useChatNavigation` / `useChatScroll`（`README.md:139-143`）。
- **Chat 视角节点通过 keyed slot 注入**：`conversation.view`（id `chat`，order 0）下挂 `conversation.chat.node`（kind **keyed**、scope session、inject `CHAT_NODE_INJECT`）与 `conversation.message.images`（kind single、scope session），store 为 `chatStore`（`lib/client.js:12391-12407`）；分组渲染走 `uiConversation.groups`，React 通过稳定的 Group 与 Node 座位渲染混合的 node/group 根序列（`README.md:90`）。
- **Jobs 控件**（同包 `lib/client.js`）：状态聚合模型、折叠策略三处、订阅输出的两条独立时机、**停止任务的两段式 + 通知账本**（`03-client-ui.md` §2.5）。**[inferred] "停止任务如何通知模型"被设计成两段式，是一个与"中断语义"直接相关的机制，值得在 NEXUS 侧对照实现。**

### 7.9 DSH 的边界与未核实项（诚实声明）

[verified: in-repo prior research]（`02-session-runtime.md` §6、`03-client-ui.md` §5）

- **未核实**：`dsh-tool-*` 各具体工具（read/write/edit/bash/glob/grep/web_fetch）在自己 `lib/index.js` 中声明的 byte/char 预算常量行号未逐一核对；§7.4(c) 的角色分工来自 `dsh-output-retention` README 而非各工具源码。
- **未核实**：`agents[].reasoningEffort` / `maxTokens` 在 `lib/index.js` 中的 schema 行号未定位（只在 `agent-loop/lib/index.js:1172-1177` 见到读取逻辑）。
- **未核实**：完全找不到 `sequenceNo` 标识符（已对 3091 个非二进制文件做过全文包含性搜索）。
- **DSH 没有会话级文件回退/checkpoint 机制**（对照：Claude Code / Cline / Cursor 都有）。DSH 提供的是**会话 fork**（事件前缀复制 + 开放尾巴修复）。

---

## 8. 横向机制对照表

> 单元格格式：**具体做法**；括注来源 agent 的关键数值或术语。空表示公开证据不足（`未公开`）。

| 机制 | Claude Code | Codex CLI | Aider | Cline | OpenHands | Cursor | DSH |
|---|---|---|---|---|---|---|---|
| **上下文压缩触发** | 自动：接近模型窗口（原生 1M 模型默认 ~967K，禁用 1M 时 200K）；`/autocompact 500k`、`autoCompactWindow`、`--autocompact`、`CLAUDE_CODE_AUTO_COMPACT_WINDOW`，范围 100K–1M；另有**空闲压缩** | 自动：`model_auto_compact_token_limit`（未设则用模型默认），`model_auto_compact_token_limit_scope` = `total` \| `body_after_prefix`；手动 `/compact`；类型有 `remote`/`local` | **无自动压缩**；只有 `--max-chat-history-tokens` 软阈值（默认 8k）触发历史摘要；超限靠人工 `/drop`、`/clear` | Auto Compact：接近窗口时自动摘要；**非支持模型退回规则式截断**；官方手法是手动 "update memory bank" → 新对话 | Condenser：`max_size` **事件计数**阈值（默认 **120**）；自动（每 step 调 `condense()`）+ 手动（`CondensationRequest` 事件，agent 遇上下文溢出时注入） | **未公开**（走 subagent 隔离路线，无自动压缩描述） | `agent/pre-step` 压力检查（在请求派生**之前**）；公式 `floor(min(W×0.8, W−O−65536))`；另有 `agent/request-error` 的 `CONTEXT_WINDOW_EXCEEDED` 溢出恢复（绕过阈值，`maxOverflowRetries=1`） |
| **压缩保留什么** | 摘要含：请求与意图、关键技术概念、检查/修改过的文件与重要代码片段、错误及修复、待办、当前工作。**重读最近 5 个文件**；重注入项目 CLAUDE.md/规则/auto memory/plan/git status；技能正文按 **5,000/技能、25,000 总计**重注入；**技能描述列表不重注入** | **未公开**细节（只有 `/compact` "keeping critical details"） | 摘要由 `weak_model` 生成（`--weak-model`）；无保留清单 | 摘要保留"所有技术细节、代码改动与决策"，替换历史 | 滚动窗口：**逐字保留头 `keep_first`（默认 4，通常是 system prompt）** + 尾 `target_size − keep_first − 1`，**摘要中间**；压缩后达 `max_size // 2`（默认 60 事件） | **未公开** | 压缩区间**起点永远不是 `system/message`**（node 0 的 system prompt 永不被遮蔽）；产物是**一条带 `surfaceOp:{op:'replace',startSeq,endSeq}` 的 `user/message`**（唯一 surface 变更）；**摘要必须能缩小才被接受**；reasoning 与 tool calls **不进** checkpoint；压缩**从不缩 system prompt / tools / session 前缀** |
| **压缩的实现形态** | 独立请求：同 system prompt+tools+history + 摘要指令作最后一条 user 消息；**缓存热时便宜、冷时等于全量重算** | 替换较早 turn 为摘要 | 摘要历史（`weak_model`） | 摘要**以一次工具调用**的形式出现（成本可见） | **两步协议**：condenser 返回 `Condensation`（不是 View）→ agent 追加事件并提前结束本步 → **下一步** `View.from_events()` 过滤 `forgotten_event_ids` 并插入摘要 | — | **bracket 即锁**：`compaction/start` 在摘要 yield 前 append、`compaction/end` 释放；每次失败只做一次关闭尝试 | 
| **工具结果截断** | **三档 + 分支**：Bash 成功内联 ~30,000 字符、失败内联 ~10,000 字符（头+尾摘录）；超内联给文件路径 + 2,000 字符预览（文件截 64 MiB）；`BASH_MAX_OUTPUT_LENGTH` 默认 30,000/硬顶 150,000（只调 read-back window）；`bashOutputMaxChars` 上限 128,000（两者都调）；**exit 1 白名单**决定走哪档；Read 默认 25,000 tokens/次、拒 >256KB；WebFetch 100,000 字符/次；Glob 100 文件；hook 输出 10,000 字符（不可调） | **未公开**（只有会话文件 `history.max_bytes`） | **无机制化截断**；`/run`、`/test` 问是否加入 chat 并显示 token 数 | **未公开** | **未公开** | **未公开** | **四套并存**：① spill（`maxInlineTokens`，落盘 `SpillRef{locator,bytes,retrievalHint}` + 预览，失败则保留原文）② compaction 前置 pruner（`thresholdChars=8192`/`headChars=4096`/`tailChars=1024`，仅在压缩触发后跑）③ per-tool retainer（`TextRetainer` **按字节**，`finish()` 裁半个码点；`truncated` 明确是"预算事实"不表示上游不完整；`read` 用 `offset`/`limit` 分页不经此路）④ 超时**协作式**（只 abort `exec.signal`，不硬杀） |
| **System prompt 组装** | **三层按变化频率排序**（System prompt+工具定义 → Project context → Conversation）；CLAUDE.md **不是** system prompt 的一层，而是 system prompt 之后的 user 消息；MCP 工具 schema 默认延迟加载 | `model_instructions_file` 可整体替换；`AGENTS.md` 从根向下**空行拼接**，总大小到 `project_doc_max_bytes`（默认 32 KiB）**停止追加**；managed 的 `additional_developer_instructions` 是独立 developer 消息，>10,000 estimated tokens 被拒 | 每个 edit format 有独立 coder + prompts 文件（`wholefile_*` / `editblock_*` / `udiff_*`）；有 model-specific system prompt 前缀机制；weak/editor 两个角色模型 | 按模型路由 `editor` vs `apply_patch`（**一个会话只给其中一个**）：GPT/Codex 模型与 `openai-native` provider 给 `apply_patch`，其它给 `editor`；Plan 模式两个都不给 | `AgentContext` 含 `repo`（始终）与 `knowledge`（触发词）两类技能；system prompt 是 `SystemPromptEvent`，也是事件流的一部分 | "Instructions = system prompt + rules"；**对每个前沿模型分别调优 instructions 与 tools**；rules 由 `alwaysApply`/`description`/`globs` 三字段交互决定何时进上下文（4 种组合） | 请求体**不含 `system` 字段**——系统提示是 surface 上的一个**节点**；每一步取**最新的非空 `system/message` 节点**作为有效提示；由 `systemPrompt.assemble()` 组装、`project(rendered, {inHistory, startsSeries})` 产出多个提交意图 |
| **Prompt 缓存策略** | 内建自动；层序即为缓存边界；**明确列出**哪些操作会/不会破坏缓存；TTL 分两桶（主对话默认 1h 订阅内 / 5m 付费与其它一切），可 `promptCacheTtl` 覆盖；`/usage` 显示 `Prompt cache (main)` 行（命中率、miss、是否 warm、**上次 miss 的可能原因**） | **未公开**（遥测有 `cached_input` token 类型） | **需显式 `--cache-prompts`**（默认 False）；按 system prompt → 只读文件 → repo map → 可编辑文件 的顺序组织以命中缓存；`--cache-keepalive-pings N` 每 5 分钟 ping 保活；**streaming 与缓存统计互斥**（`--no-stream`） | Auto Compact 论证依赖已有 prompt cache | **未公开**（CondensationSummaryEvent 未提缓存） | **未公开** | `systemPrompt.project` 的 `startsSeries` 参数说明有"序列边界"概念；摘要调用**逐字节**重放热前缀（node 0 system prompt + 上次路由请求的 tools + 被遮蔽区间消息），只追加压缩指令；`request/header` 仅在首个/变更/新序列时写（`reason: initial`/`change`/`series`） |
| **Subagent：是否派生 / 上下文** | 是。非 fork subagent **全新隔离上下文**（看不到历史/已读文件）；有 fork 继承整段对话 | 是，本地默认启用；每个 subagent 有可打开的 **agent thread**；权限从父 turn 继承且**自定义 agent 文件不能覆盖** | **无 subagent**；改为多模型角色分工（weak model / editor model / architect） | 有 `spawn_agent`（**仅 CLI 与 Desktop**，VS Code/JetBrains 扩展不用）；独立上下文；**拿不到 MCP 工具**；**可再派生** | 有 Conversation 的 Local/Remote 双实现，但**无 subagent 派生** | 是。每个 subagent 独立上下文、**从干净上下文开始**（父必须把信息写进 prompt）；内建 Explore / Browser | 有 `subagent/*` 与 `team/*` 事件类型（`:59-71`）；具体派生语义未在本次范围内核实 |
| **Subagent：结果返回** | 只把**最终文本 + 一小段元数据**（token 数与时长）返回主上下文（官方例：6,100 tokens 的文件读取 → 420 tokens 结果） | 主线程汇总；CLI 用 `/subagents` 在各 thread 间切换 | — | 把**最终回复**返回主 agent；主 agent 等待后继续；token 与成本计入会话总量 | — | 返回**最终消息**；后台 subagent **把状态写到 `~/.cursor/subagents/`**，父 agent 读文件看进度；失败返回 error status（父可 retry/resume/其它处理） | — |
| **Subagent：上限** | **嵌套默认 3 层**（到达上限时**撤掉 `Agent` 工具**；fork 保留但报错）；**并发默认 20**（`Concurrent subagent limit reached`，告诉模型不要重试）；描述合计 >15,000 tokens 告警 | `agents.max_concurrent_threads_per_session`（旧键 `max_threads`） | — | 未公开 | — | **两层**（主 agent 与其直接 subagent 可派生；subagent 的 subagent 不能再派生） | 未核实 |
| **Subagent：审批/沙箱** | 继承父权限规则；前台 prompt 直通、后台 prompt 在主会话浮出并标明来源；`Ctrl+X Ctrl+K` 可停掉所有后台 subagent（**权限提示开着时也能按**） | **继承父 turn 的 sandbox 与 approval**，`/permissions`、`--yolo` 的改动也继承；自定义 agent 文件**不能**替换；**非交互下需要新审批的动作失败**并把错误冒泡回父 workflow；CLI 中 approval 可从**非活动 thread** 浮出，按 `o` 先打开该 thread | — | **批准 `spawn_agent` 即批准 subagent 内的一切**——其内部工具调用不再询问，**审批设置不作用于 subagent 内部** | — | subagent 继承父的全部工具（含 MCP）；**cloud subagent 例外**：用团队在 cursor.com/agents 配置的 MCP | 未核实 |
| **记忆 / 项目指令（形式）** | 文件式 + 自动记忆。CLAUDE.md 层级：managed → user → project → local；**向上遍历 + 子目录按需加载**；`@path` 导入（**最多 4 跳**，相对包含文件解析）；`.claude/rules/` 可按 `paths` 惰性加载 | 文件式 `AGENTS.md`。**三级**：global（`AGENTS.override.md` 否则 `AGENTS.md`，只取第一个非空）→ project（从项目根**向下**走，每层取一文件）→ 从根向下空行拼接（越近越晚、"覆盖"更早）；项目根默认含 `.git` | 文件式但**无自动发现**：写一个 Markdown（如 `CONVENTIONS.md`）用 `/read` 或 `.aider.conf.yml` 的 `read:` 加入；选 `/read` 的理由是**只读且可被 prompt caching 缓存** | 文件式但**无自动发现**：Memory Bank 是约定（`memory-bank/*.md` 六个文件）+ `.clinerules/` 里的 custom instructions 启用 | 文件式 + 技能系统：Repository Skill 的推荐载体就是 **`AGENTS.md`**（也支持 `GEMINI.md`/`CLAUDE.md`/`.cursorrules`/`.agents/skills/*.md`） | 文件式四种：`.cursor/rules/*.mdc`（**必须 `.mdc`，纯 `.md` 被忽略**）、`AGENTS.md`（**支持嵌套，子目录与父目录合并、更具体者优先**）、User Rules、Team Rules（dashboard，可"enforce"） | 事件溯源 + 插件系统。profile/bundle/patch 三层组合：`$DSH_HOME/profiles/<name>` 的 `package.json`（`dsh.profile.bundles` 有序）+ `cordis.patch.yml`；bundle 用 `dsh.bundle.patch` 声明 patch；**patch 的 `config` 整体替换不深合并** |
| **记忆：动态加载 / 分级** | `MEMORY.md` 只加载**前 200 行或 25KB**；CLAUDE.md 建议 <200 行、**>4 MiB 直接跳过**；`.claude/rules/` 的 `paths` 共享 **1,000 条展开模式 / 4 MiB** 预算；`InstructionsLoaded` hook 的 matcher 是加载原因（`session_start`/`nested_traversal`/`path_glob_match`/`include`/`compact`） | 空文件被跳过；总大小到 32 KiB 停止追加；`project_doc_fallback_filenames` 可加备用文件名（如 `TEAM_GUIDE.md`） | repo map 承担"自动补充其余代码上下文"的角色（见下行） | Memory Bank 的 `activeContext.md` 更新最频繁；`progress.md` 记里程碑 | **Path Rule** 是分级加载的机制版：glob 匹配 agent 触碰的文件时，注入进 `ObservationEvent.extended_content` 的 `<EXTRA_INFO>` 块（**不是** user 消息）；**基线成本为零**（排除在 `<available_skills>`/`<REPO_CONTEXT>` 之外）；`disable_model_invocation` 被强制；**每对话只注入一次**；`paths:` 优先于 `triggers:`；**ACP 会话不注入**（因为 ACP server 拥有工具执行） | rules 的三字段交互本身就是分级策略；项目规则可 `@`-mention 手动附加；**规则里的 `@file` 引用不会被内联**（必须放正文才能保证在上下文里） | 事件名白名单 **56 项**（`KNOWN_SESSION_EVENT_TYPES`），**只有 `image/offload` 是消息投影事件**；未知类型靠信封 `ignorable` 标记兼容；surface 事件必须带 `surfaceOp`（唯一模型可见性开关） |
| **Repo map / 检索** | 无 repo map；用 Glob/Grep/Read + 可选 LSP 代码智能插件 + 子代理探索 | 无 repo map；`@` 语法搜索工作区文件 | **tree-sitter 仓库地图**（`aider/queries` 下的 tags 查询）：全仓符号 + 关键代码行（含完整签名）；**图排序算法**（文件为节点、依赖为边）选出能塞进 token 预算的部分；`--map-tokens` 默认 **1k**、`--map-multiplier-no-files` 默认 **2**、`--map-refresh` = auto/always/files/manual；对弱模型默认禁用；`--show-repo-map` 可导出 | `search_codebase` 工具 | Repository Skill 可携带 MCP 服务器配置；无内建 repo map | **Instant Grep**（自研搜索引擎，"outperforms ripgrep"），**索引在本机构建与查询**，"does not store embeddings of your codebase for search"；Explore subagent 做并行检索 | 工具集自身的 `glob`/`grep`/`read`；无 repo map |
| **编辑/应用策略** | `Edit` 靶向编辑（`old_string` **逐字**匹配，"a single character of whitespace or indentation difference is enough to miss"）；**读前写约束按模型能力放宽**（Opus 4.6/Haiku 4.5 及更早总是要求；新模型可在特定前提下覆盖未读文件；notebook 与 `PARTIAL view` 文件永远要求）；**拒绝非 UTF-8 文件**（会写坏编码），错误让改用 shell；Write 可替换但新内容含 `U+FFFD` 时拒绝；拒绝透过 symlink 写入 | 明确推荐**补丁式工作流**（`git diff`/`git apply`，而非直接改被跟踪文件），频繁提交以便小步回退；`codex apply` 把 cloud diff 应用到本地，`git apply` 失败即非零退出；`--worktree` / `/worktree` 创建受管 git worktree | **按模型族分别设计编辑格式**：`whole`（整文件）/ `diff`（SEARCH/REPLACE 块）/ `diff-fenced`（**专为 Gemini 族**，路径放围栏内）/ `udiff`（**专为 GPT-4 Turbo**，减少"偷懒省略"）/ `patch`（GPT-4.1）/ `udiff-simple`（Gemini 2.5 Pro）/ `editor-diff`/`editor-whole`（architect 模式用更简单的 prompt）；**围栏冲突自动换围栏**（文件含三反引号时改用 `<source>`）；**"需要新文件"时重提交原请求**（因为 LLM 本应能看到该文件，否则会编造内容）；文件总是最新读取 | `apply_patch`（"Apply patch/diff edits"）与 `editor` **互斥二选一**，按模型路由；Plan/Act 模式是能力级区分（Plan 不能改文件/跑命令） | Action→Observation 严格配对；工具调用前经 `SecurityAnalyzer` 评风险（低=立即、中=警告+监控、高=阻断+要确认） | **未公开**编辑应用算法（只说 "Suggest edits to files and apply them automatically"） | **schema 子集在 body 之前校验**（违规抛 `ToolArgsError` → 普通错误结果，不终止 turn）；固定流水线 `tools/pre-execute` → 单调 guard → `tools/execute` → `tools/post-execute`（可 replace）→ `finalizeContent` → `tools/result`；**guard 只能否决、无法被后续 listener 翻回**；deny 统一为 `Error: <reason>` + 结构化 `error.info`（不进模型正文） |
| **验证循环** | **无强制机制**；官方作为建议（"give verification targets"、"test incrementally"）；机制化的是 hooks：`PostToolUse`（可用 `updatedToolOutput` 替换结果）、`PostToolUseFailure`、`PostToolBatch`；官方示例用 `PreToolUse` hook 把测试输出过滤成只留失败行 | `/review`（对未提交/某 commit/base branch 做专门审查，**不改工作树**）；`review_model` 可单独指定；无关自动跑测试的机制化描述 | **唯一默认自动 lint**（`--auto-lint` 默认 True，自带多数主流语言 linter）；`--lint-cmd` 自定义（错误须打印并以非零退出）；**formatter 用作 linter 的陷阱**有官方 wrapper 解法；`--test-cmd` + **`--auto-test`** 每次编辑后跑测试，**非零退出则尝试修复**；`/run`、`/test` 非零退出后**自动预填 "Fix that"** 到下一个 prompt | **未公开**（Roo Code 侧一等公民是 Reviewer role，而非测试执行） | 工具执行前后有事件；`Stuck Detection` 用**滑动窗口模式匹配**做循环防护 | Verifier subagent 模式（官方推荐的完整 prompt 模板）；Browser tool 可截图/测试/验证视觉改动；`Ask questions` **非阻塞**（等待回答时 agent 继续读文件/编辑/跑命令） | 无可配置的验证循环；`checkpoint` 重试预算 `compactionRetries=1`、`maxOverflowRetries=1`（仅针对压缩） |
| **检查点 / 回退（基础机制）** | **快照**，与 git 分离；**每个开启一轮的 prompt 打一个**；保留**最近 100 个**checkpoint 的文件快照（每个文件的第一个快照永留）；随会话保存（`--resume` 后仍可 `/rewind`）；默认约 30 天后被清理 | **无内建文件快照**；靠 git worktree + `git apply`/`git diff` + `codex archive`/`unarchive`/`delete`/`fork` | **真 git 提交**（不是 shadow repo）：每次编辑后**用描述性 message 提交**；对 dirty 文件会**先把既存改动提交掉**（"keeps your edits separate from aider's edits"，防止丢工作）；`/undo`、`/diff`、`/commit`、`/git`；commit message 由 `weak_model` 生成，默认 Conventional Commits；**署名区分"创作"与"仅提交"**（author+committer vs 仅 committer）；默认跳过 pre-commit hook | **shadow git repo**（独立于项目真实 git）；**每次工具使用后**提交当前文件状态；捕获**含未被 git 跟踪的文件**；跨编辑器会话持久；**每个 checkpoint 是完整文件状态** | 无文件 checkpoint（未在本次抓取的文档中出现） | **快照**，本地存储、与 Git 分离；**"before making significant changes"**（非每 prompt）；可**预览**再回退；**恢复只回退文件，不删消息** | **无会话级文件回退**；只有**会话 fork**（复制闭区间事件前缀 + `session/end-seed{inherited:true}` + 只修复开着的尾巴） |
| **检查点：恢复粒度** | 6 个动作：Restore code and conversation / Restore conversation / Restore code / **Summarize from here** / **Summarize up to here** / Never mind（后两个是**部分压缩**而非回退，可带 focus 指令） | `codex fork` 复制会话；TUI 里 `Escape`×2 编辑上一条 user 消息并从该点 fork | `/undo` 撤销并丢弃最后一次改动（git 层面） | **3 个选项**：Restore Files / **Restore Task Only**（删该点之后的消息、不动文件）/ Restore Files & Task；**Compare** 用编辑器自带 diff viewer | — | 只回退文件（消息保留） | `fork(source, boundary?, childSessionId?)`；boundary 是**闭区间**；`inheritedEventCount` 只计被复制前缀；已关闭 step/turn 原样保留 |
| **检查点：已知边界** | **不追踪 Bash 命令改的文件**；**subagent 的编辑通常不捕获**（例外：`context: fork` 且前台）；**不追踪会话外/并发会话的改动**；**turn 中途发的消息没有自己的 checkpoint**（标 `No code restore`）；**不恢复 symlink 与硬链接**（警告 `Restored the code, but skipped N files`） | — | 需要 git；可用 `--no-auto-commits`/`--no-dirty-commits`/`--no-git` 关闭（不推荐） | **大仓库会显著占用存储并拖慢 Cline**（每次工具使用都提交快照），可关闭 | — | 明确声明"不是版本控制替代品" | — |
| **沙箱 / 权限** | 权限模式循环 `default`(Manual) / `acceptEdits` / `plan` / `bypassPermissions` / `auto`；规则格式 `ToolName(specifier)`（`Bash(npm run *)`、`Read(~/secrets/**)`、`Edit(/src/**)`、`WebFetch(domain:x)`）；`Edit(...)` allow 同时授读；`Read(...)` deny 同时阻断 Edit/Write；hook 可返回 `permissionDecision: allow/deny/ask/defer`；`auto` 模式有 classifier | **两层正交**：`sandbox_mode`（`read-only`/`workspace-write`/`danger-full-access`）× `approval_policy`（`on-request`/`never`/`granular`）；启动时按"目录是否受版本控制"选默认（受控→Auto，不受控→read-only）；**受保护路径**（递归只读）：`.git`（含 gitdir 指针解析后的目录）、`.agents`、`.codex`、`.aws`；**网络默认关闭**；`network_proxy` 是强制层非授权层；domain 规则 allowlist 优先、`deny` 恒胜、`*` 只能用于 allow；**本地/私网默认阻断**（`allow_local_binding=false`，通配符不算显式例外）；DNS 重绑定 best-effort 防护；**`approvals_reviewer=auto_review`** 走 reviewer agent（低/中可放行、critical 拒绝、high 需足够授权；**prompt 构造/审查会话/解析失败一律 fail closed**；超时不上报但也不执行） | **无沙箱**（本机直接跑）。`--git-commit-verify` 默认 False 即跳过 pre-commit hook；`--dry-run` | 审批可 auto-approve；`spawn_agent` 审批是粗粒度一次性授权 | Runtime 侧容器隔离（见下行） | **Run Modes**：Auto-review（推荐默认）/ Allowlist / Run Everything；Auto-review 检查顺序 = 白名单沙箱外 → 其它 shell 尽量沙箱内 → 不能用沙箱的/沙箱失败的/其它调用 → **Cursor 后端 LLM 分类器**（可在本机做只读 ReadFile/Grep/Glob/ListDir）；分类器用 Gemini 3.5 Flash Lite，回退 Claude 4.5 Haiku；**明确自陈"不是安全边界"**；`permissions.json` 用**自然语言句子**（`allow_instructions`/`block_instructions`）；另有 Browser / File-Deletion / External-File 三个独立保护；**Read Access** 三档（System/Workspace + Read Allowlist） | `tools/pre-execute` waterfall 返回 `{kind:'allow'|'deny'|'ask'|'cancel'}`；**单调 guard 只能否决**；ask 的四种结果中**只有 `allowed-once` 放行**，`rejected`/`cancelled`/`unavailable` **全部 fail-closed 为 deny**；会话级策略只有 `ask`/`never`，且 **`never` 在服务内部先于 waterfall 判定**（`prepend` 无法绕过）；审批落盘为 `approval/asked` + `approval/decided` **成对事件**；权限预设把 sandbox 模式与 approval 策略打包 |
| **沙箱：OS 实现** | （文档未展开；有 `sandbox.enabled` managed setting） | macOS **Seatbelt**（`sandbox-exec -p <profile>`，限制读访问时追加精选 macOS platform policy 而非宽泛允许 `/System`）；Linux **`bwrap` + `seccomp`**（`bwrap` 缺失回退内置 helper，需非特权 user namespace，打启动警告）；Windows **MXC**（`elevated`/`unelevated` 为 legacy 回退）；WSL2 走 Linux 实现（WSL1 自 0.115 起不支持） | — | — | **Docker 容器**：用户 base image → 构建 OH runtime image（含 runtime client）→ 启动容器 → action execution server 初始化 `ActionExecutor`（bash shell + plugins）；backend 经 RESTful API 通信。**镜像三标签**（versioned `oh_v{ver}_{base_image}` / lock `oh_v{ver}_{lock_hash}`（hash = base image 名 + `pyproject.toml` + `poetry.lock`）/ source `..._{source_hash}`（源码目录 MD5 前 16 位））配**四级构建回退**（无重建 → 最快重建（基于 lock，跳过安装）→ 尚可重建（基于 versioned）→ 最慢（全新））；支持 bind mount / named volume / **`:overlay` COW**（需 `SANDBOX_VOLUME_OVERLAYS`） | macOS **Seatbelt**（`sandbox-exec`，限制"整个子进程树"的文件/网络/进程行为）；Linux **Landlock + seccomp**（要求**内核 6.2+ 且 Landlock v3** + 非特权 user namespace；不满足则**回退为跑命令前询问批准**）；**Linux 沙箱内 UID 被重映射为 0**，需真实 UID 时读 `CURSOR_ORIG_UID`/`CURSOR_ORIG_GID`；注入 `CURSOR_SANDBOX`、`CURSOR_SANDBOX_LANDLOCK_STATUS` | （本次未核实 DSH 自身的 sandbox 后端实现；事件类型有 `sandbox/mode`，权限预设会调 `setSandboxMode`） |
| **转录 UI：长会话渲染** | **两条渲染路径**。fullscreen（alternate screen buffer，像 vim/htop）**只渲染当前可见的消息，所以内存恒定**；只发送帧间变化的单元格（incremental cell diff，Windows Terminal/ConPTY 需 `CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT=1`）；classic 保留终端原生 scrollback（`Cmd+f`/tmux copy mode 可用） | TUI；`tui.alternate_screen` 可设 `never` 以保留终端 scrollback；`/tui` 在 scrollback 与 fullscreen 间切换（需重启）；`/raw`（或 `Alt+R`）切到原生 scrollback 使选择复制更直接；**`codex app-server` 与 TUI 解耦**（stdin JSONL / WebSocket / Unix socket 三传输，`--remote` 连远端） | Rich 线性打印终端；**无虚拟化/alternate-screen 机制**；流式渲染有专门优化记录（spinner 从等待首个 token 到非流式响应、console width clipping、cursor hiding）；`--pretty` 默认 True | **未公开** | **未公开**（有 Visualization 服务：事件流 → 执行图） | **未公开** | 客户端插件化 chat（`lib/client.js` 约 56.5 万字节）；滚动被拆成 6 个 hook（`useScrollFollow`/`useProcessScroll`/`useChatViewport`/`useChatReading`/`useChatNavigation`/`useChatScroll`）；**语义锚点恢复**跨历史 prepend 与渲染器重挂载；轨道显隐阈值按**可用宽度 ≤900px**（非视口宽度）；滚动位置用**模块级 Map** 按 session 存 |
| **转录 UI：过程折叠 / 详细度** | `Ctrl+O` transcript viewer 展开默认折叠行（如 MCP 调用折叠为一行 `Called slack 3 times`）；**`/focus`** 静默视图（只留最后 prompt + 工具调用一行摘要含 edit diffstats + 最终回复，跨会话保持）；fullscreen 里点击折叠的工具结果可展开（工具调用与结果一起展开） | 配置项 `hide_agent_reasoning` / `show_raw_agent_reasoning`（抑制或显示原始 reasoning）；`/ps` 显示每个后台终端的命令 + **最多 3 行最近非空输出** | **未公开**（无折叠概念） | checkpoint 指示器形态：书签图标 + 虚线连到 Compare 与 Restore | **未公开** | **未公开** | **四档持久化枚举** `compact`/`standard`/`detailed`/`verbose`（设置命名空间 `ui-chat.transcriptView`，桌面默认 `standard`、非桌面 Web 默认 `detailed`）；档位到行为的映射是**一张策略表**（`foldCompletedTurns` / `stepGrouping` = collapsed\|history\|none / `liveProcessDetail` / `settledReasoningPreview`）；**渲染器从不比较枚举本身**（"none of them compares the mode enum, so adding a mode changes only the table"）；**每个分组持有自己的本地 `useDisclosure` 状态，模式切换时保留**；另有**第二条独立轴** `ui-chat.performanceUsage`（compact/detailed） |
| **转录 UI：diff 渲染** | `/diff` 在 fullscreen 下是**独立面板**（≥110 列，≥144 列自动打开）；列文件与增删行数、每文件下方给 diff；可点 `ask` 把该文件 diff 附到下条 prompt；`source` 选择器在 `Current` 与逐轮视图 `T1`/`T2`… 间切换；默认**跳过测试文件与生成文件**，把本会话之前的改动折叠成一行；**turn 视图来自 Claude 的文件编辑而非 git** | `/diff` 显示 git diff（含未被 git 跟踪的文件）；TUI **对文件 diff 做语法高亮**；`file_opener` 把 `/path/file:42` 变成可点击的 `vscode://file/...:42` | `/diff` 调 `git diff`（用你自己的 diff 工具） | **Compare** 用**编辑器自带的 diff viewer** | **未公开** | **未公开** | 会话内右侧资源面板 + 文档预览包（`dsh-client-ui-sidebar-documentpreview`）；**行号导航**经 `openResource(address, { params: { line } })` 传 1-based 行；纯文本与代码渲染器暴露源码行锚点、**Markdown 不暴露**；字节模式渲染器不消费行导航；**重复地址复用**（同 `(kind, contentId)` 的 tab 会被聚焦；`#L24`/`#L24-L30` 复用已有 tab）；**自动刷新**默认开启；同地址元数据在所有 UI 间共享 |
| **转录 UI：可搜索性 / 导出** | transcript 模式有 `less` 风格 `/` 搜索、`n`/`N`、`{`/`}` 按 prompt 跳转；**`[` 把完整对话（工具输出全展开）写入终端原生 scrollback**；`v` 写入临时文件并用 `$VISUAL`/`$EDITOR` 打开 | **`/export`** 导出完整对话为 Markdown（复制到剪贴板 / 存文件 / `/export session.md`）；`Ctrl+O` 或 `/copy` 复制最近完成的输出 | `.aider.chat.history.md`（Markdown）；可做成 gist 拼到 `https://aider.chat/share/?mdurl=<gist>` 渲染成终端风格记录；`--llm-history-file` 记录完整 LLM 往返 | **未公开** | **未公开** | Agents Window 里 `Cmd+K` 搜历史 transcript（**本地建立搜索索引**）；当前对话内 `Cmd+F` | 未核实（本次未覆盖导出/检索路径） |
| **中断语义** | `Esc` **中途停止当前响应或工具调用**，**"Claude keeps the work done so far"**；排队消息随后发送；`Up` 可取回排队消息；`Ctrl+Enter`/`Ctrl+X Ctrl+S` 立即发送；`Ctrl+C` 中断运行中的操作（无对象时两次清空/退出）；`Ctrl+X Ctrl+K` 停掉所有后台 subagent（3 秒内两次确认，**权限提示开着时也能按**）；`/btw` 可在工作时运行且不打断主 turn | **`Tab` = 排队到下轮；`Enter` = 注入当前 turn**；`Escape`×2（空 composer）= 编辑上一条并 fork；`/archive` 确认会先停掉运行中的 turn；`/delete` 运行时不可用；`agents.interrupt_message`（默认 `true`）决定中断是否给模型留可见消息 | **未核实**（官方文档未描述中断进行中 LLM 请求的语义）。相关：`Ctrl-Z` 挂起、`Ctrl-D` 退出、`Ctrl-C` 在多行与确认提示下的行为、**强制 user/assistant 轮次顺序**以规避 R1 错误 | **未核实** | **`PauseEvent` 是一等事件类型**（`source=user`，**是内部事件、模型不可见**）；step 之间 agent 无状态、**"Each step is atomic and can be paused/resumed"** | **Queue**（Enter，顺序处理、**可拖拽重排**）vs **Send now / Enter×2**（**在下一次工具调用处送达，不切断进行中的动作**——"preserves in-flight work"）；**CLI 语义不同**：Enter **在安全边界 steer**，再按 Enter **中断 turn**；`Ctrl+C` 暂停 `/goal`；`/side`/`/btw` 开不打断主对话的旁路对话（**持久、有自己 transcript、可被主线程 `@` 引用**） | 取消时**未派发的工具调用写合成 `tool/call` + `ABORTED_BEFORE_DISPATCH` 结果对**（保证 tool 配对不破）；`assistant/message` 写 `interrupted: true` 锚点；`turn/end` 的 `reason` 含 `aborted`；`kick()` 用 `while (await this.turn())` 驱动，`turn()` 返回 false 即停 |
| **状态持久化模型** | 会话 JSONL（`~/.claude/projects/...`）+ 独立 checkpoint 快照；`cleanupPeriodDays` 默认 30 天 | `~/.codex/history.jsonl`（`history.persistence`、`history.max_bytes`）+ SQLite 支撑的运行时状态（`sqlite_home`）；session 可用 `codex archive`/`unarchive`/`delete`/`resume`/`fork` 管理 | `.aider.chat.history.md`、`.aider.input.history`、可选 `.aider.llm.history`；改动以**真 git 提交**持久化 | shadow git repo + 对话历史 | **事件溯源**：`EventLog` 是不可变 append-only store（带索引）；`Persistence` 用 **debounced writes + 增量事件**；`ConversationState` 是 Pydantic 模型（带校验与序列化）；**FIFO 锁保证有序原子更新，回调在成功 commit 后触发，读从不阻塞写** | 本地 checkpoint 快照 + 本地 transcript 搜索索引 | **事件溯源**：`Session` 是 typed `SessionEvent` 的 append-only log，**seq 恒等于 log.length**；不连续即抛错；默认后端每 session 一个 append-only 日志（**默认 Zstandard 压缩帧**）；崩溃恢复保留中断的最后 turn 并由 resume 补合成收尾事件；**事件信封是字段白名单**（多余字段报错）；只有 `image/offload` 是消息投影事件 |
| **客户端/服务端形态** | 单一 CLI 进程（另有 IDE 扩展 / Desktop / cloud）；fullscreen 切换靠**重启进程**并把会话状态带过去 | **TUI 是 app-server 的客户端**（stdio JSONL / WebSocket / Unix socket；`--remote`、`--remote-auth-token-env`）；`codex app-server` 明确标注"primarily for development and debugging" | 单一 Python 进程；另有 Streamlit GUI 与 `--copy-paste` web-UI 协作模式 | VS Code / JetBrains 扩展 + CLI + Desktop 三种宿主（**subagent 只在 CLI/Desktop**） | **前端 SPA ── HTTP/WS ── backend**；backend 持 EventStream / Storage / Runtime Interface / LLM Providers；`LocalConversation`（进程内）与 `RemoteConversation`（HTTP+WebSocket）**同 API**，切换只需换 workspace 类型 | GUI 应用 + CLI + Cloud Agents；**Cloud Agents 不用 Run Modes**（在自己的专用机器上跑，从不请求批准） | **Cordis 插件化运行时**：profile / bundle / patch 三层组合；必需全局插件 id 由启动审计强制（`agent-loop`、`webserver`、`modules`、`connection`、`headless-runner`、`acp`、`sdk-jsonrpc-server`）；客户端是插件（slot 机制），与服务端经事件流 + follow/快照流通信 |

---

## 9. 明确无法核实的项（诚实清单）

1. **Codex CLI 的工具结果截断策略**：官方文档未给出任何 token/字符阈值或分页方式。Codex 仓库源码本次不可达（raw.githubusercontent.com TLS 失败）。
2. **Cline 的转录渲染机制**：虚拟化、工具调用折叠策略、diff 侧对比 vs 统一、thinking 展示、流式渲染性能，均无公开机制级文档。
3. **OpenHands 前端的转录渲染机制**：同上。
4. **Cursor 的转录渲染机制**（虚拟化、折叠、diff 样式）与**编辑应用算法**：官方文档未描述。
5. **Cursor 的上下文压缩**：无任何自动压缩/摘要的描述；只能确认它走 subagent 隔离路线。
6. **Aider 的中断语义**：官方文档未描述"中断进行中的 LLM 请求"。
7. **Aider 的工具结果截断**：无机制化截断。
8. **Cline / Roo / Roomote 的中断语义**：无公开描述。
9. **Roo Code 的当前官方文档**：`docs.roocode.com` → `roocodeinc.github.io`（404），`roocode.com` → `roomote.dev`。本文的 Roo Code 相关内容只能引用其**后继产品 Roomote** 的官方文档，无法确认 Roomote 的机制与已下线的 Roo Code 逐项等价。
10. **各家的重试次数上限**：除 DSH（`compactionRetries=1`、`maxOverflowRetries=1`）与 Codex（网络层 `request_max_retries`/`stream_max_retries`）外，均未在官方文档中给出明确数字。
11. **Claude Code 的隐藏机制**：tool result 的 per-tool token 上限在官方文档中是以"字符"给出的（Bash 30,000 / Read 25,000 tokens），但**哪些内部常量决定这些值、是否有更多未文档化的工具**（如 `MultiEdit`）本次未核实。
12. **DSH 的 sandbox 后端实现**：本次未核实（既有调研文档的事件表里有 `sandbox/mode` 与 `permission/preset`，但后端机制未在已读范围内）。

---

## 10. 参考来源清单（全部为实际抓取成功的 URL）

**Claude Code**（`https://code.claude.com/docs/en/` 下均以 `.md` 后缀抓取原文）
- `interactive-mode.md`、`hooks.md`、`memory.md`、`context-window.md`、`prompt-caching.md`、`checkpointing.md`、`fullscreen.md`、`costs.md`、`model-config.md`、`tools-reference.md`、`sub-agents.md`

**OpenAI Codex**（`https://learn.chatgpt.com/docs/`，原 `developers.openai.com/codex/*` 已 302）
- `codex/cli.md`、`agent-approvals-security.md`、`sandboxing.md`、`config-file/config-advanced.md`、`config-file/config-reference.md`、`developer-commands.md`、`agent-configuration/agents-md.md`、`agent-configuration/subagents.md`、`cli-customization.md`

**Aider**
- `https://aider.chat/docs/repomap.html`、`more/edit-formats.html`、`usage/caching.html`、`troubleshooting/token-limits.html`、`usage/lint-test.html`、`git.html`、`faq.html`、`more/infinite-output.html`、`usage/modes.html`、`usage/conventions.html`、`config/options.html`、`troubleshooting/edit-errors.html`、`https://aider.chat/HISTORY.html`、`https://aider.chat/2023/10/22/repomap.html`

**Cline**
- `https://docs.cline.bot/features/subagents.md`、`core-workflows/checkpoints.md`、`best-practices/memory-bank.md`、`features/auto-compact.md`、`tools-reference/all-cline-tools.md`、`core-workflows/plan-and-act.md`

**Roo Code → Roomote**
- `https://roomote.dev/`、`https://roomote.dev/product/agent-roles`、`https://docs.roomote.dev/how-roomote-works.md`、`https://docs.roomote.dev/memory.md`
- （Roo Code 自身文档站已下线：`https://docs.roocode.com/` → 302；`https://roocodeinc.github.io/features/boomerang-tasks` → 404）

**OpenHands**
- `https://docs.openhands.dev/openhands/usage/architecture/runtime.md`、`backend.md`、`https://docs.openhands.dev/sdk/arch/conversation.md`、`events.md`、`condenser.md`、`agent.md`、`skill.md`

**Cursor**
- `https://cursor.com/docs/agent/overview.md`、`agent/tools/search.md`、`agent/tools/terminal.md`、`agent/security/run-modes.md`、`agent/plan-mode.md`、`rules.md`、`subagents.md`

**DSH**
- 本地发行物 `D:\DeepSeek\ds\resources\app.asar` 内的 `dsh/`（经本仓库既有调研文档引用的 `path:line`）
- 本仓库：`docs/dsh-comparison/01-architecture-plugins.md`、`02-session-runtime.md`、`03-client-ui.md`
