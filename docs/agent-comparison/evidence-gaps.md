# NEXUS 侧机制核实：7 项对照结论

> **本文档的定位**：`evidence-external.md` 只记录外部成熟 agent 的机制。本文档用 `read`/`grep`/`glob` 核实 **NEXUS 自身的当前行为**，逐项给出 `path:line` 证据与"实现 / 部分 / 缺失"判定，便于精确陈述差距。
>
> **方法声明**：只读操作，未修改任何应用代码。所有 `path:line` 均为本次实际读取所得。判定的三个档位：
> - **实现** —— 存在完整机制，且有明确的触发路径与边界处理
> - **部分** —— 有相关代码但覆盖面不全，或需要人工介入才能生效
> - **缺失** —— 完全没有该机制
>
> 对照列引用的 `§x.y` 均指 `evidence-external.md` 的对应小节。

## 结论速览

| # | 机制 | 判定 | 一句话结论 | 外部对照 |
|---|---|---|---|---|
| 1 | 自动压缩 | **部分** | 只有工具结果可压缩，且压缩是**用户手动触发**的；更早的 assistant/user 轮次被**静默丢弃**并插一条告示 | §1.1 / §5.2 / §4.1 |
| 2 | 工具结果截断 | **部分** | 有（16,000 字符，可配置），但是**只留头部**、标记不带体积信息 | §7.4 / §1.2 |
| 3 | 编辑应用策略 | **部分** | 精确串唯一匹配，无模糊/多编辑/补丁格式；但**不做读前写检查** | §3.6 / §1.6 |
| 4 | 读前写约束 & 新鲜度 | **缺失** | 有 baseline 存储与 contentHash 元数据，但**都不作用于编辑前置条件** | §1.6 |
| 5 | 仓库级检索 / repo map | **缺失** | 只有全文搜（glob/grep 式），无符号索引、无 repo map、无 embedding | §3.4 / §6.1 |
| 6 | 验证循环 | **部分** | 验证计划完整且工程质量高，但**默认从不自动执行**（两个调用点都传 `runVerification: false`） | §3.7 |
| 7 | Sub-agent 能力 | **缺失** | 单次串行、返回扁平文本、无并行/隔离/嵌套/并发上限 | §1.4 / §6.4 |

---

## 1. 自动压缩是否存在

**判定：部分**（Lead 的读法**基本确认**，但有一处需要补正）

### 确认的部分

**压缩候选只有工具结果一种类型**，这是硬编码的枚举：

`lib/application/context_compression_planner.dart:7`
```dart
enum ContextCompressionCandidateType { toolResult }
```

枚举只有 `toolResult` 一个值（`:7`），标签映射也只有这一个分支（`:9-13`）。候选筛选逻辑只接受 `MessageRole.tool` 的消息：

`lib/application/context_compression_planner.dart:151-154`
```dart
if (message.role != MessageRole.tool ||
    message.toolCallId?.trim().isNotEmpty != true) {
  continue;
}
```

且有 64 token 的最小候选门槛（`lib/application/context_compression_planner.dart:86` `minCandidateTokens = 64`；`:156` `if (tokens < minCandidateTokens) continue;`）。

**更早的 assistant/user 轮次确实是被"丢弃"而不是"压缩"**。`ContextWindow.apply()` 用**从最新向前的预算游走**决定截断点：

`lib/application/context_window.dart:102-106`
```dart
for (var i = capped.length - 1; i >= 0; i--) {
  if (used + estimates[i] > budget) break;
  used += estimates[i];
  cut = i;
}
```

截断点之后的内容直接 `sublist` 丢弃，前面只插一条**固定文案**的告示：

`lib/application/context_window.dart:124-127`
```dart
return [
  ...system,
  if (!hasNotice) _noticeMessage(),
  ...capped.sublist(cut),
```

告示本身是一段常量字符串，不含任何摘要内容：

`lib/application/context_window.dart:50-51`
```dart
static const compactionNotice = '[上下文提示：更早的 assistant/tool 记录因容量上限'
    '已被压缩，请勿假定其中步骤未执行；需要确认时重新读取文件或重跑检查。]';
```

**关键补正（Lead 读法的偏差）**：这条路径**不是自动执行的**。真正的空间回收靠 `ContextCompressionPlanner`，而它产出的是一个**待用户审核的提案**（数据对象，不改消息），且只在 warning/critical 档位才建议：

`lib/application/context_compression_planner.dart:42-44`
```dart
/// A user-reviewable compression proposal. It is deliberately data-only so a
/// later approval flow can apply it and record an audit event separately.
```

`lib/application/context_compression_planner.dart:69-72`（`shouldSuggest` 的门槛）
```dart
bool get shouldSuggest =>
    candidates.isNotEmpty &&
    (budgetLevel == ContextBudgetLevel.warning ||
        budgetLevel == ContextBudgetLevel.critical);
```

也就是说：**NEXUS 有两条独立的上下文回收路径，两条都不是"自动摘要"**——
1. `ContextWindow.apply()`：**静默 head-drop**（丢掉最早的消息，插常量告示）——这是无条件的、每请求都跑
2. `ContextCompressionPlanner`：**用户审核式**地压缩工具结果——需要用户在指标面板/HUD 入口确认

没有一条是"接近阈值时自动让模型写摘要"。

### 对照

| 维度 | NEXUS | 外部对照 |
|---|---|---|
| 触发方式 | ① head-drop 每请求无条件下跑；② 工具结果压缩需用户审核 | Claude Code：接近窗口**自动**压缩（默认约 967K / 200K 两档，可 `/autocompact 500k` 等四档配置）——§1.1 |
| 压缩对象 | 只 `toolResult`（`context_compression_planner.dart:7`） | OpenHands Condenser：**滚动窗口**保留头 `keep_first`（默认 4）+ 尾，**摘要中间**——§5.2 |
| 是否用模型生成摘要 | **否**（只有常量告示 + 工具结果替换）；`compressedToolResultMark = '[工具结果已压缩]'`（`context_window.dart:55`）是占位标记而非摘要 | Cline Auto Compact：模型生成**保留所有技术细节与决策**的摘要并替换历史——§4.1 |
| 非工具历史如何回收 | **直接丢弃**（`context_window.dart:127` 的 `sublist(cut)`） | Claude Code：压缩产物是**一条结构化摘要**，保留意图/关键概念/文件/错误修复/待办——§1.1 |
| 是否避免重新读文件 | 告示**明确要求模型重新读**："需要确认时重新读取文件或重跑检查"（`context_window.dart:51`） | Claude Code：压缩后**自动重读最近 5 个文件**、重注入 CLAUDE.md / rules / auto memory / plan / 技能正文——§1.1 |

**最有借鉴价值的一条**：Claude Code 的"压缩后自动重建"清单（§1.1）正是 NEXUS 这条告示文案所缺失的一半——NEXUS 告诉模型"你自己去重读"，Claude Code 直接替模型重读了。

---

## 2. 工具结果截断的方向性

**判定：部分**（Lead 的读法**完全确认**）

### 确认

`lib/application/context_window.dart:187-202`，`_capToolResult` **只保留头部**：

```dart
ChatMessage _capToolResult(ChatMessage message) {
  if (message.role != MessageRole.tool) return message;
  if (message.parts.length != 1 || message.parts.first.type != 'text') {
    return message;
  }
  final text = message.parts.first.value;
  if (text.length <= maxToolResultChars) return message;
  return ChatMessage(
    role: message.role,
    toolCallId: message.toolCallId,
    parts: [
      MessagePart.text(
          '${text.substring(0, maxToolResultChars)}\n$toolResultTruncatedMark')
    ],
  );
}
```

逐条核实 Lead 的三个断言：

| Lead 的断言 | 结论 | 证据 |
|---|---|---|
| head-only | **确认**：`text.substring(0, maxToolResultChars)` | `context_window.dart:199` |
| 尾部被丢弃 | **确认**：新 `parts` 只含 `substring(0, max)` + 标记，原文 `text` 不再被引用 | `context_window.dart:197-200` |
| 截断标记不含体积信息 | **确认**：标记是常量 `'…[工具结果过长，已截断]'`，**没有**原始字符数、保留字符数、也没有取回方式 | `context_window.dart:54` |

阈值与可配置性：

- 默认 `defaultMaxToolResultChars = 16000`（`lib/application/context_window.dart:32`），注释写明是"单条 tool 结果回灌上限"
- 可通过构造参数覆盖（`context_window.dart:22` `this.maxToolResultChars = defaultMaxToolResultChars`），**但全仓库没有把它接到用户设置**——它是一个纯内部参数
- 按**字符**而非 token 计（`text.length`，`context_window.dart:193`）；同文件另有 `estimateTokens` 做预算折算，两者口径不同

同一方法族里另有两项相关裁剪（都是"保头"或"整条替换"）：
- `_capToolArguments`（`context_window.dart:205-228`）：参数超 `maxToolArgumentChars`（默认 32,000，`:36`）时替换为 `{'_truncated': true, 'originalChars': encoded.length}`——**参数这个路径反而保留了原始长度**（`:221`），与结果路径的不保留形成不对称
- `_capToolCallCount`（`context_window.dart:232-...`）：单条 assistant 消息超 `maxToolCallsPerMessage`（默认 64，`:39`）时截断，并**同步删除对应的孤儿 tool 结果**（注释 `:230-231`："否则'有结果无调用'会被 Provider 直接拒绝"）——这一条是有 Provider 契约意识的正确性处理

### 对照

| 维度 | NEXUS | 外部对照 |
|---|---|---|
| 方向 | **只保头**：`substring(0, max)` | DSH pruner：`headChars=4096` + `tailChars=1024`（**头尾都保**）；`TextRetainer` 支持 `head`/`tail`/`headTail` 三种——§7.4 |
| 阈值 | 16,000 **字符**，内部参数，未接设置 | DSH：`thresholdChars=8192`；Claude Code Bash：成功内联 ~30,000 字符 / 失败内联 ~10,000 字符——§1.2 |
| 是否带体积信息 | **否**，常量文案 | Claude Code：超内联上限时给 **session 目录下的文件路径 + 最多 2,000 字符预览**（即"完整输出仍可取回"）——§1.2 |
| 失败/成功是否分档 | **否**，统一 16,000 | Claude Code：成功 ~30,000 字符走"文件路径 + 预览"，失败 ~10,000 字符走"头+尾摘录、**不给路径**"；exit 1 白名单（`grep`/`rg`/`find`/`diff`/`test`/`git diff`/`git grep` 的 1 算有效结果）决定走哪档——§1.2 |
| 是否落盘可取回 | **否**，尾部永久丢失 | DSH `dsh-spill`：`maxInlineTokens` 触发时把全文落盘并返回 `SpillRef{locator, bytes, retrievalHint}`；且失败降级为"保留原文"（`spill-policy/README.md:65`）——§7.4 |
| 是否按工具分类 | **否**，一刀切 16,000 | DSH：`glob`/`grep`/`web_search` 用 `ItemRetainer`(head)、`bash`/`web_fetch` 用 `TextRetainer`、**`read` 不在此路**（它有自己的 `offset`/`limit` 分页）——§7.4 |

**最有借鉴价值的一条**：NEXUS 的 `read_file` 已有 `offset`/`limit` 分页（§3 同族的 `search_files` 也有 `offset`/`limit`，见 `workspace_tools.dart:577-578`），但**工具结果**这一层却没有分页/取回机制。DSH 的分工（"有自己分页语义的工具不走 retainer"）与 Claude Code 的"落盘 + 指针"是两条可选的补法，其中 Claude Code 那条对 NEXUS 改动面最小——因为它只需要在截断时保留一个可重放的调用描述。

另注：NEXUS 的标记文案已经**意识到了**这个问题的一半——`context_window.dart:51` 的告示建议模型"重新读取文件或重跑检查"，说明设计者知道内容会丢；但截断路径本身没有提供任何"如何取回"的信息。

---

## 3. 编辑应用策略

**判定：部分**（Lead 的读法**完全确认**）

### 确认

`lib/infrastructure/tools/workspace_tools.dart:358` `class EditFileTool with _FileMetadata implements AgentTool`，工具名 `edit_file`（`:364`），参数 `path` / `targetContent` / `replacementContent`（`:370-374`，三个都 required）。

核心匹配逻辑 `lib/infrastructure/tools/workspace_tools.dart:417-434`：

```dart
final content = await fs.readText(fullPath);
final firstMatch = content.indexOf(target);
if (firstMatch < 0) {
  return ToolResult.failure(
    code: ToolCodes.notFound,
    message: '编辑失败：未在文件中找到指定的 targetContent 匹配块，'
        '请重新读取文件核对内容。',
  );
}

// Detect overlapping matches too (for example 'aa' in 'aaa').
if (content.indexOf(target, firstMatch + 1) >= 0) {
  return ToolResult.failure(
    code: ToolCodes.invalidArguments,
    message: 'targetContent 匹配不唯一，请提供更多上下文后重试',
  );
}
final newContent = content.replaceFirst(target, replacement);
```

逐条核实 Lead 的断言：

| Lead 的断言 | 结论 | 证据 |
|---|---|---|
| 精确串单次匹配 | **确认**：`content.indexOf(target)` 是 Dart 的**字面量子串**查找，无正则、无归一化 | `workspace_tools.dart:418` |
| 0 匹配即拒绝 | **确认**：`firstMatch < 0` → `ToolCodes.notFound` + 要求重读文件 | `workspace_tools.dart:419-425` |
| >1 匹配即拒绝 | **确认**：`:428` 用 `content.indexOf(target, firstMatch + 1) >= 0` 检测**含重叠**的第二处（注释明说 `'aa'` in `'aaa'`）→ `ToolCodes.invalidArguments` | `workspace_tools.dart:427-433` |
| 无模糊/空白容忍匹配 | **确认**：全文件无 trim/whitespace 归一化、无行号定位、无相似度回退 | 整个 `execute`（`:380-458`）无此类分支 |
| 无多编辑批量 | **确认**：schema 是单个 `targetContent`/`replacementContent`（`:370-374`），`replaceFirst` 只改一处（`:434`） | 同上 |
| 无 diff 格式替代 | **确认**：`grep 'apply_patch'` 在 `lib/**.dart` 中**零命中**；无 `unified diff` 作为**模型产出的编辑格式** | 见下 |

**`apply_patch` 检索结果：`lib/**/*.dart` 中 0 命中。**

但需要注意一个容易误判的点——仓库里确实有 `unified_diff` 基础设施，**方向是相反的**（产出 diff 而非消费模型给的 diff）：

- `lib/infrastructure/observability/unified_diff.dart:59-60` 注释："Builds a strict, deterministic unified diff without depending on a native diff executable（the same implementation is used on Android, desktop and web）"——**这是 NEXUS 自己生成 diff 用于审计/回退**
- `unified_diff.dart:96-107` 的 `applyUnifiedDiff(current, diff, reverse: true)` 是**反向应用**，服务于回滚（`lib/application/run_audit_report.dart:221`），不是模型编辑入口
- `unified_diff.dart:100` 注释："edit is never silently overwritten. `null` means the patch is stale"——**这是整个仓库里最接近"新鲜度校验"的逻辑，但它在回滚路径上，不在编辑路径上**

`lib/application/desktop_git_service.dart:361` 有 `applyPatch(String root, String patch, ...)`，由 `lib/presentation/navigation/desktop_review_panel.dart:80` 调用——这是**桌面端把 git 补丁应用到真实仓库**的 UI 功能（stage/unstage/reverse），属于"人在 UI 上操作 git"，与模型编辑策略无关。

### 对照

| 维度 | NEXUS | 外部对照 |
|---|---|---|
| 格式 | 精确串替换（`indexOf` + `replaceFirst`） | Aider：按模型族分 7 种格式（`whole`/`diff`/`diff-fenced`（Gemini）/`udiff`（GPT-4 Turbo，专为减少"偷懒省略"）/`patch`（GPT-4.1）/`udiff-simple`（Gemini 2.5 Pro）/`editor-diff`）——§3.6 |
| 失败恢复 | 拒绝并让模型重读（`workspace_tools.dart:423`）；异常路径让模型 `read_file` 确认（`:453-454`） | Aider：`"Aider makes every effort to get the LLM to conform, and works hard to deal with LLM edits that are 'almost' correctly formatted"`；官方排查建议含"试 `--edit-format whole`"与"试 architect 模式"——§3.6 |
| 围栏/转义冲突 | 未处理（无此概念） | Aider：文件含三反引号时**自动换围栏**（改用 `<source>...</source>`）——§3.6 |
| 读前写约束 | **无**（见第 4 项） | Claude Code：Opus 4.6/Haiku 4.5 及更早**总是**要求先读；新模型可在特定前提下覆盖未读文件；notebook 与 `PARTIAL view` 文件永远要求——§1.6 |
| 编码保护 | `TextFileTooLarge`（`:444`）与 `FormatException`（`:446`）有专门分支；`readText` 隐含 UTF-8 假设 | Claude Code：**明确拒绝**非 UTF-8 文件（Edit/Write 会把整个文件按 UTF-8 写回、用 `U+FFFD` 替换无法解码的字节），错误让模型改用 shell 命令保持原编码——§1.6 |
| 符号链接 | 通过 `WorkspaceSandbox.resolvePath` 做越界检查（`:397-405`），**未检查路径中的 symlink 跳转** | Claude Code：Edit/Write **拒绝透过 symlink 写入**（若 symlink 变了），错误指路去编辑链接目标——§1.6 |
| 批量编辑 | 一次一处 | Codex：官方推荐补丁式工作流（`git diff`/`git apply`）；Aider v0.82.2 还专门 "Update prompts to instruct LLMs to consolidate all edits for a given file into a single block within the patch"——§2.6 / §3.6 |

**一处值得肯定的设计**：`workspace_tools.dart:451-456` 的异常分支区分了"已提交但元数据记录失败"（`effect: applied`）与"编辑中断、可能部分修改"（`effect: unknown` + 让模型先 `read_file` 确认）。这与 DSH 的 `effect` 语义、Codex 的"副作用无法确认"处理是同一类正确性意识。

---

## 4. 读前写约束 & 文件新鲜度校验

**判定：缺失**

Lead 让我查的三样东西都存在，**但没有一样作用于编辑前置条件**：

### (a) `FileBaselineStore` / `FileBaselineInterceptor` —— 是"回滚存储"，不是"新鲜度校验"

`lib/application/tool_pipeline/file_baseline_interceptor.dart:7-13` 的文档注释把职责写得很清楚：

```dart
/// Saves each file's original content right before a workspace tool mutates
/// it, so a task's change set can restore the exact pre-task state (including
/// deletes, moves, binary files and large edits whose diffs are truncated).
///
/// Sits last in the chain: it only runs for calls that passed approval and
/// are about to execute.
```

它在管线**最后**（`:64-70` 拼在 `defaultToolInterceptors()` 之后），只在写发生**之前**存一份原始字节供回滚。它**不做的三件事**：

1. 不检查"这个文件被读过没有"
2. 不检查"磁盘上的内容是否与模型看到的一致"
3. 不阻止任何调用（`file_baseline_interceptor.dart:47-49`：存储失败只 `onError`，然后 `next(invocation)` 照常执行；注释 `:12-13` 明说 "A failure to save never blocks the tool"）

存储本身是很扎实的：`lib/application/file_baseline_store.dart:76-81` 注释"First write wins: later mutations of the same path within the task never replace the baseline"；`:149` `if (... entries.containsKey(path)) continue;` 落实了这个语义；`:191` 存 sha256；`:86` `maxBytes = 8 * 1024 * 1024` 超限记 `captured: false`。**但这些 hash 只用于回滚时校验，从不用于编辑前置校验。**

### (b) `tool_pipeline/preflight_guards.dart` —— 四个守卫，没有一个和读/写顺序有关

`lib/application/tool_pipeline/preflight_guards.dart:9-14`：

```dart
List<ToolInterceptor> defaultToolPreflightGuards() => const [
      UnknownToolGuard(),
      TruncatedArgumentsGuard(),
      SchemaValidationGuard(),
      PreviewPlanGuard(),
    ];
```

- `UnknownToolGuard`（`:17-33`）：工具未注册即短路
- `TruncatedArgumentsGuard`（`:36-54`）：参数被上下文裁剪截断过就短路（防残缺参数产生副作用）
- `SchemaValidationGuard`（`:57-79`）：按注册项 schema 校验
- `PreviewPlanGuard`（`:83-103`）：设备变更类工具必须有有效预览

完整默认管线见 `lib/application/tool_pipeline/execution_interceptors.dart:14-20`：
```dart
List<ToolInterceptor> defaultToolInterceptors() => [
      ...defaultToolPreflightGuards(),
      const ApprovalInterceptor(),
      const CheckpointInterceptor(),
      const ExecutionBoundary(),
      const AuthorizationInterceptor(),
    ];
```

`CheckpointInterceptor`（`execution_interceptors.dart:68-86`）检查的是**用户取消/暂停**（`context.isCancelled` / `context.isPaused`），与文件状态无关。

### (c) `read_file` 记录的 hash —— 存在，但是**审计元数据**，无人消费

`lib/infrastructure/tools/workspace_tools.dart:117-128`（`recordFile` 的 `read` 分支）确实为读操作记了内容哈希：

```dart
if (operation == 'read') {
  final result = buildUnifiedDiff('', after);
  lastMetadata = {
    'operation': operation,
    'path': path,
    'bytesBefore': 0,
    'bytesAfter': result.bytesAfter,
    'linesAdded': 0,
    'linesRemoved': 0,
    'contentHashAfter': result.contentHashAfter,
  };
  return;
}
```

但这个 `lastMetadata` 是**每次工具调用自己的元数据桶**（`workspace_tools.dart:102-110` 的 mixin，`clearMetadata()` 在每次 `execute` 开头调用）——它进审计事件流（`RunAuditReport`），**不进会话状态**，`edit_file` 也从不读它。所以："文件自被读取后是否变化"这个问题，NEXUS 有计算哈希的能力，但**没有任何机制去问它**。

### (d) 唯一存在的 staleness 检查：`FileCitation` —— 但它只作用于**提示词注入**，且只在 UI 侧

`lib/application/file_citation.dart:18-22` 有 `contentHash` 与 `bool stale`；`lib/application/project_context_service.dart:159-184` 的 `refreshCitations` 会比较哈希并置 `stale`：

```dart
refreshed.add(current.copyWith(
  stale: current.contentHash != citation.contentHash,
  excerpt: current.contentHash == citation.contentHash
      ? citation.excerpt
      : current.excerpt,
));
```

消费点在 `project_context_service.dart:67-71`：

```dart
final stale = citation.stale ? '（文件已变化，旧选区作废）' : '';
buffer.writeln('  · ${citation.displayLabel}$stale');
if (citation.excerpt.isNotEmpty && !citation.stale) {
  buffer.writeln(_clip(citation.excerpt, 800));
}
```

**这是"用户 @ 的文件引用"的过期检测，属于提示词组装层**。它不覆盖"模型自己 `read_file` 之后文件被别人改了"这个场景——因为模型的读取不产生 `FileCitation`。

### 对照

| 维度 | NEXUS | 外部对照 |
|---|---|---|
| 读前写约束 | **无** | Claude Code：按模型能力分档的读前写约束（见 §3 表）——§1.6 |
| 编辑前置新鲜度校验 | **无** | Claude Code 的 `Edit` 要求 `old_string` **逐字出现**（"A single character of whitespace or indentation difference is enough to miss"）——这本身就是一种弱新鲜度检查：文件变了通常就匹配不上了。NEXUS 的精确串匹配**同样**提供了这个弱保证，但错误文案（`workspace_tools.dart:423`"请重新读取文件核对内容"）把它归因为"模型写错了"而非"文件可能变了"——§1.6 |
| 会话级读取记录 | **无**（`lastMetadata` 是单次调用的） | DSH：`FileBaselineInterceptor` 与内容 hash 构成基线；压缩**从不缩 session 前缀**，事件溯源保证可追溯——§7.4 / §7.5 |
| 回滚基线 | **有且扎实**：`FileBaselineStore` 首写优先 + sha256 + 8 MiB 上限 + 目录/超限标注不捕获（`file_baseline_store.dart:171-195`） | Cline shadow git：每次工具使用后提交，**捕获含未被 git 跟踪的文件**——§4.8 |
| 回滚时的哈希校验 | **有**：`run_audit_report.dart:213` 用 `contentHashAfter`、`:226` 用 `contentHashBefore` 校验；`:224` 不匹配则 `'diff 与当前文件不匹配，拒绝覆盖'` | Aider：dirty 文件**先把既存改动提交掉**，"keeps your edits separate from aider's edits"——§3.8 |

**这是 7 项里最清晰的一个"能力已在、位置不对"的案例**：NEXUS 已经会算 `contentHash`（`workspace_tools.dart:126`）、已经会在回滚时拒绝过期补丁（`run_audit_report.dart:224`）、已经会在 UI 引用上标 stale（`project_context_service.dart:174`）——缺的只是把这三块知识接到 `edit_file` 的入口。

---

## 5. 仓库级检索 / repo map

**判定：缺失**

### 确认

`grep` 检索 `repoMap|repomap|symbolIndex|treeSitter|tree_sitter|embeddings|Embedding|vectorSearch`（`lib/**/*.dart`）**只有 1 处命中，且是"预留未实现"**：

`lib/application/knowledge_service.dart:14`
```dart
///   分块时的 embeddingJson 预留，未来接入 provider `/embeddings` 后切余弦 topK。
```

同处注释（`knowledge_service.dart:11-15`）说明了当前实现：
```dart
/// 知识库 / RAG 服务（C4）。
///
/// - 入库：文本分块（~800 字符 + 100 重叠）后写入 KnowledgeChunks。
/// - 检索：默认 BM25 关键词（本地、零网络），保证无 embedding 端点时也可用；
///   分块时的 embeddingJson 预留，未来接入 provider `/embeddings` 后切余弦 topK。
/// - 注入：与记忆同处，在系统提示词前拼接相关片段（限制 1.5KB，仅首轮）。
```

即：**有 BM25 关键词检索的知识库（文档级 RAG），但这是"用户导入的文档"，不是"仓库的符号地图"。**

仓库检索的现状是**全文扫描**：

- 工具面：`search_files`（`lib/infrastructure/tools/workspace_tools.dart:559-582`），参数 `query` / `fileExtension` / `pathPrefix` / `offset` / `limit`（默认 50、上限 100，`:597`），描述"在工作区的所有文本/代码文件中快速全文搜索指定关键字"（`:566`）
- 实现是**递归遍历 + 逐行 `contains`**：`workspace_tools.dart:616-618` 的 `walk` 对每个目录 `fs.list`，命中判定在行级 `contains`
- 有明确的忽略目录集合（`workspace_tools.dart:622-635`：`.git`/`.dart_tool`/`build`/`node_modules`/`dist`/`.idea`/`.vscode`/`.nexus`/`.gradle`/`.venv`/`__pycache__`/`target` 等）
- `pathPrefix` 过滤在 `workspace_tools.dart:576`，另有 `searchSnippets`（`lib/application/project_context_service.dart:219-274`）做**同类的**全文扫描用于提示词注入，且有 `maxFileBytes = 256 * 1024`（`:225`）与逐个文件容错（`:265-268`）

**没有**：符号索引、定义/引用图、tree-sitter 解析、面向模型的分层代码摘要、embeddings 检索。

### 对照

| 维度 | NEXUS | 外部对照 |
|---|---|---|
| 检索手段 | 全文子串匹配（`search_files` + `searchSnippets`） | Cursor Instant Grep：自研搜索引擎，"outperforms `ripgrep` on large codebases"，索引**本机构建与查询**——§6.1 |
| 是否给模型代码结构 | **否**，只给匹配行 | Aider：**tree-sitter 仓库地图**（`aider/queries` 下的 tags 查询）给出每个文件的关键符号与**完整函数签名**，用**图排序算法**（文件为节点、依赖为边）选出能塞进 token 预算的部分——§3.4 |
| 预算控制 | `limit` 默认 50 / 上限 100 条命中（`workspace_tools.dart:597`）；注入侧 `relatedLimit = 6`（`project_context_service.dart:193`）、单块 1.5KB（`knowledge_service.dart:20`） | Aider：`--map-tokens` 默认 **1k**、`--map-multiplier-no-files` 默认 **2**、`--map-refresh` 四档；**无文件时动态扩大地图**——§3.4 |
| 弱模型保护 | 无 | Aider：对弱模型**默认禁用 repo map**，理由是"Weaker models get easily overwhelmed and confused by the content of the repo map"——§3.4 |
| 分页 | `search_files` 有 `offset`/`limit`（`:577-578`）——**这一点比外部对手更细** | Cursor/Aider 的检索工具未见等价的分页参数——§6.1 / §3.4 |

**注**：`search_files` 的 `offset`/`limit` 分页是 NEXUS 在这个维度上**唯一领先**的地方；但因为没有结构信息（只有匹配行），模型要理解"这个仓库怎么组织"仍然只能反复搜索。

---

## 6. 验证循环

**判定：部分**（机制本身质量高，但**默认从不自动执行**）

### 确认

**(a) 验证计划是完整且有工程质量的。** `lib/application/development_verification.dart:274-304` 按 `ProjectKind` 派发：Flutter 项目得到 `flutter analyze`（`:279`）→ `flutter test`（`:284`）→ `flutter build apk --release`（`:290`，超时 20 分钟，`:291`）→ **产物检查**（`:295-302`，`kind: 'artifact'`，校验 `build/app/outputs/flutter-apk/app-release.apk`）。Android Gradle（`:305-329`）、Node（`:330-...`）各有对应步骤。

**(b) 但自动执行在**两个调用点都被关掉**——两处**都传 `runVerification: false`：

`lib/application/chat_run_execution.dart:1510-1517`
```dart
await DevelopmentLoopFinalizer().finalize(
  db: taskDb,
  taskId: taskId,
  runId: runId,
  workspacePath: workspacePath,
  terminal: null,
  runVerification: false,
);
```

`lib/application/chat_controller.dart:1547-1553` 同样传 `runVerification: false`。

而 `lib/application/development_loop_finalizer.dart:104-108` 的门槛是合取：
```dart
final shouldVerify = runVerification &&
    terminal != null &&
    workspacePath.trim().isNotEmpty &&
    implementsChanges &&
    review.files.isNotEmpty;
```

`runVerification` 默认 `false`（`:64`），配合调用点硬编码 `false` + `terminal: null`（`chat_run_execution.dart:1515`），**`shouldVerify` 在聊天路径上恒为 `false`**。

**(c) 跳过原因被如实记录**——这是设计上值得肯定的一处。`development_loop_finalizer.dart:109-121`：
```dart
// 跳过自动验证时必须留下原因。这一层是「人在环路」的收口：terminal 只在
// 调用方已经拿到用户授权后才非空，所以此处不是绕过审批，而是把「因为没
// 授权所以没验证」如实记进任务摘要，避免后续把它读成「已验证」。
String? verificationSkipReason;
if (!shouldVerify && review.files.isNotEmpty) {
  verificationSkipReason = !runVerification
      ? '本轮收尾未请求自动验证'
      : terminal == null
          ? '自动验证需要终端授权，本轮未获得授权'
          : workspacePath.trim().isEmpty
              ? '未选择工作区，无法执行验证'
              : '任务类型不产出需要验证的代码变更';
}
```

原因进 `openIssues`（`development_loop_finalizer.dart:167-170`）：
```dart
openIssues: [
  ...failed,
  if (verificationSkipReason != null) '未验证：$verificationSkipReason',
],
```

这条不变量正对着 Aider 的失败模式：**"没验证"绝不能被下游读成"验证通过"。**

**(d) 真正的执行入口是 UI 按钮 + 确认对话框**，且**每个步骤都要用户确认**：

`lib/presentation/workspace/development_workbench_page.dart:76-101`
```dart
Future<void> _run({String? retryStepId}) async {
  final steps = _result?.plan?.steps ?? ...;
  final preview = retryStepId == null
      ? steps.map((step) => step.command.isEmpty ? step.title : step.command)
      : steps.where((step) => step.id == retryStepId)...;
  final approved = await showConfirmAction(
    context,
    title: retryStepId == null ? '确认执行开发工作流' : '确认重试失败步骤',
    message: retryStepId == null
        ? '将依次在工作区执行分析、测试、构建，并检查真实产物：'
        : '只会重新执行失败步骤及其后续校验：',
    ...
  );
  if (approved != true || _running || !mounted) return;
  ...
}
```

**(e) 失败后的修复提示词是拼好的，但需要人触发。** `lib/application/verification_repair_service.dart` 提供完整闭环：

- `fromFailedPlan`（`:35-58`）：从失败步骤构造请求，自动**归类失败原因**（`:93-107`：`permission_denied`（含 `permission`/`eacces`/`denied`）/ `environment_missing`（含 `not found`/`no such file`/`command not found`/`missing`）/ `test_failed`）
- `promptFor`（`:65-91`）：产出结构化修复提示词，含命令、cwd、退出码、原因分类、验收条件、关联文件、`diff`（`:78`，clip 到 1600 字符）、失败日志（`:80`）
- **两类原因有专门的反循环指令**：`permission_denied` → `'不要绕过用户授权，也不要扩大权限。'`（`:82`）；`environment_missing` → `'不要反复安装同一缺失项；说明缺少的工具并停止自动重试。'`（`:85`）
- **重试上限是显式的**：`maxAutoAttempts = 2`（`:33`），`canAutoRetry` 只在 `attempt < maxAttempts` 且 `reason == 'test_failed'` 时为真（`:60-63`）——即**只有测试失败会自动重试，权限/环境类失败不自动重试**；超限时提示词改成 `'自动修复已达 N 次上限，请给出下一步建议而不是继续重跑。'`（`:88`）
- **日志截取方向与工具结果截断相反**：`_clip` 保留**尾部**（`verification_repair_service.dart:112` `trimmed.substring(trimmed.length - maxChars)` + `'\n…[日志已截取尾部]'`）——这是正确的，因为构建/测试错误通常在输出末尾

**(f) 手动验证日志的位置**：`lib/application/development_workflow.dart:48` 里 `flutter analyze` 也是工作流步骤；`lib/application/task_template_service.dart:46` 的模板文本写 "Flutter 默认执行：flutter analyze、flutter test、flutter build apk --release"（**这是提示词层面的期望，不是机制**）。

### 对照

| 维度 | NEXUS | 外部对照 |
|---|---|---|
| 是否自动跑 | **默认不跑**（`runVerification: false` ×2 调用点 + `terminal: null`） | Aider：**`--auto-lint` 默认 True**，对它所编辑的任何文件跑 lint；`--test-cmd` + **`--auto-test`** 每次 AI 编辑后跑测试，**非零退出则尝试修复**——§3.7 |
| 是否有产物级验证 | **有，且比 Aider 强**：`expectedArtifactPath`（`development_verification.dart:292-293`）→ `kind: 'artifact'` 步骤（`:295-302`）→ 产出 `ArtifactInspection`（`:241`）与 sha256 进 `evidence`（`development_loop_finalizer.dart:172-176`） | Aider：只有 lint/测试的退出码，无产物校验——§3.7 |
| 失败分类 | **有**，三分（`permission_denied`/`environment_missing`/`test_failed`） | Aider：只有退出码，无分类——§3.7 |
| 重试上限 | **显式且保守**：`maxAutoAttempts = 2`，且只有 `test_failed` 可自动重试 | Aider：**未公开**上限——§9 第 10 条 |
| 反循环 | **有**：权限类"不要绕过授权"、环境类"不要反复安装同一缺失项并停止自动重试" | Codex：Web search 默认走 OpenAI 维护的索引以**降低提示注入暴露面**（同类安全取向但不同场景）——§2.9 |
| 跳过原因 | **如实记录进 `openIssues`** | 无直接对应；Aider 的 `/run`、`/test` 在非零退出后**自动预填 "Fix that"** 到下一个 prompt（v0.67.0）——§3.7 |
| 日志截取方向 | **保尾**（`verification_repair_service.dart:112`） | DSH pruner 是 head 4096 + tail 1024（两侧都保）——§7.4 |

**这是 7 项里"最接近可投产"的一项**：把 `chat_run_execution.dart:1516` 的 `runVerification` 接上一个用户设置（并在已获终端授权时传 `terminal`），即可从"手动按钮"变成"Aider 式自动验证 + 最多 2 次修复"，而**下游的失败分类、上限、反循环、原因记录全都已经就位**。

---

## 7. Sub-agent 能力

**判定：缺失**（Lead 的读法**完全确认**）

### 确认

工具定义在 `lib/infrastructure/tools/sub_agent_tool.dart`，全文 79 行。逐条核实 Lead 的六个断言：

| Lead 的断言 | 结论 | 证据 |
|---|---|---|
| 只返回扁平文本摘要 | **确认**：`execute` 直接 `return ToolResult.text(summary, extra: {...})`，`summary` 是 `onRun` 返回的 `String`；`extra` 只有 `agentId` 与 `budget` 两个字段键，**无 token 数、无时长、无子会话 id、无工具调用记录** | `sub_agent_tool.dart:70-77` |
| 无并行 fan-out | **确认**：签名是 `final Future<String> Function(String? agentId, String prompt, int? budget) onRun;`——**单次单子任务**；schema 里 `prompt` 是单个 string（`:46`），没有数组参数 | `sub_agent_tool.dart:18-19`、`:39-55` |
| 无 per-child context 隔离 | **确认但其含义需澄清**：子 Agent 走 `RunProfile.subagent`（`chat_controller.dart:2057`），`recordSession: false`（`run_profile.dart:34-35`）——即**子 Agent 不写会话日志**，所以不存在"共享父上下文"的问题；但它是**从零开始的一次独立运行**，父 agent 的历史（已读文件、plan、todo）**不传入**，返回只有最终文本 | `run_profile.dart:33-35`、`chat_controller.dart:2051-2059` |
| 无嵌套深度控制 | **确认**：全仓库无 depth 计数、无"撤掉 Agent 工具"逻辑 | 见下 |
| 无并发上限 | **确认**：全仓库无并发 subagent 计数或信号量 | 见下 |
| HeadlessExecutor 工具限制 | **确认且是关键设计**：子 Agent 内部**只放行 safe 且非 sensitive 的工具** | `headless_executor.dart:255-260` |

HeadlessExecutor 的限制原文（`lib/application/headless_executor.dart:255-260`）：
```dart
// 无 UI 的后台路径（子 Agent/定时任务）没有真人审批，敏感或非 safe 工具一律拒绝。
// 恢复开发闭环时调用方必须传入 approveTool，把写文件/终端交给用户确认。
approveTool: approveTool ??
    (call, risk, sensitive) async => !sensitive && risk == ToolRisk.safe
        ? ToolApproval.allowOnce
        : ToolApproval.reject,
```

`headless_executor.dart:40` 的类文档也重申："危险工具在后台自动拒绝（无用户可审批），只放行 safe 工具。"

**这个限制的实际后果比"能读不能写"更微妙**——它是**全有或全无**的：子 Agent 里 **任何** `requiresConfirmation` 风险的写文件/终端工具都直接 `reject`，错误以工具结果形式回到子 Agent。这带来一个模型层面的风险：子 Agent 收到拒绝后**可能改写方案重试**（而非放弃），而父 Agent 看不到这些中间尝试（只有最终文本）。

**父 Agent 侧的委派策略是提示词而非机制**（`lib/application/chat_controller.dart:2075-2087`）：
```dart
static String _delegationRules(bool autonomous) {
  if (autonomous) {
    return '[自主委派规则]\n'
        '- 可将可独立、并行推进的只读子任务委派给 sub_agent 执行以加快处理。\n'
        '- 通过 maxTokens 为每个子任务分配受限预算（上限 ${SubAgentTool.maxBudget}），不要超预算。\n'
        '- 子 Agent 仅放行安全工具；写文件、执行命令、提交、联网发布等危险操作必须由你亲自处理并走审批，不得委派。\n'
        '- 委派只是优化手段，你仍对最终结果负责，应核实并汇总子 Agent 返回。';
  }
  ...
}
```

注意 `'可将可独立、并行推进的只读子任务委派给 sub_agent'`（`:2078`）——**提示词里说了"并行推进"，但工具契约是串行的**（一个 `sub_agent` 调用一次只跑一个子任务，返回一个字符串；模型要"并行"只能在一轮里发多个 `sub_agent` 调用，是否有并行取决于上层工具调度，`SubAgentTool` 自身无此能力）。**这是一处提示词与机制不对齐的地方**，建议核对上层是否真的允许同轮并行派发。

**预算是显式钳制的**：`minBudget = 500` / `maxBudget = 8000`（`sub_agent_tool.dart:26-27`），`clampBudget` 缺省返回上限、越界收敛（`:30-33`）；schema 也把它们写成 `minimum`/`maximum`（`:49-50`）。**这是 NEXUS 特有的一个好设计——外部 agent 都没有"给子任务分配 token 预算"的参数。**

### 对照

| 维度 | NEXUS | 外部对照 |
|---|---|---|
| 返回内容 | **仅最终文本**（`sub_agent_tool.dart:71-77`） | Claude Code：最终文本 + **一小段元数据**（token 数与时长）；官方量化例：子 Agent 读了 6,100 tokens 的文件，主上下文只拿到 **420 tokens** 结果——§1.4 |
| 上下文 | 全新（父历史不传入），且**不写会话日志**（`run_profile.dart:34-35`） | Claude Code：非 fork `subagent` **新隔离上下文**（看不到历史/已读文件）；`/subtask` 的 **fork 继承整段对话**且首个请求命中父缓存——§1.4 |
| 并行 | **工具契约串行**（单个 `prompt` string） | Cursor：前台/后台两种模式；**后台立即返回独立工作**；50 个并行 subagent 约为单 agent 的 5 倍 token 开销——§6.4 |
| 嵌套深度 | **无控制** | Claude Code：**默认 3 层**，到达上限时**从所有 subagent 的工具列表里撤掉 `Agent` 工具**（fork 保留但调用报错）；Cursor：**2 层**（主 agent 与其直接 subagent 可派生，subagent 的 subagent 不能再派生）——§1.4 / §6.4 |
| 并发上限 | **无** | Claude Code：**默认 20**，超限时 Agent 工具以 `Concurrent subagent limit reached` 失败并**告诉模型不要重试**；Codex：`agents.max_concurrent_threads_per_session`——§1.4 / §2.4 |
| 工具权限 | **全有或全无**：只放行 safe 且非 sensitive，其余一律 reject（`headless_executor.dart:255-260`） | Cline：**批准 `spawn_agent` 即批准 subagent 内的一切**——其内部工具调用不再询问，**审批设置不作用于 subagent 内部**（另一种粗粒度取舍）——§4.4 |
| 元数据/可恢复 | **不可恢复、无 id 概念**（`extra['agentId']` 只是回显请求里的参数） | Claude Code：每次执行返回 **agent ID**，`SendMessage` 可恢复并**保留完整历史**；transcript 存 `~/.claude/projects/{project}/{sessionId}/subagents/agent-{agentId}.jsonl`，**主会话压缩不影响它们**；Cursor：输出写到 `~/.cursor/subagents/`，父 agent 读文件看进度——§1.4 / §6.4 |
| 失败处理 | 异常被吞成字符串：`'子任务执行失败：$error'`（`chat_controller.dart:2060-2062`） | Cursor：子 Agent 返回 **error status** 给父 agent，父可 retry / resume with additional context / 其它处理——§6.4 |
| 预算参数 | **有**（500–8000 tokens，`sub_agent_tool.dart:26-33`）——**外部对照中未见等价设计** | — |
| 描述质量对上下文的影响 | 无（只有一个内建工具） | Claude Code：所有自定义 subagent 的 description **合计超过 15,000 tokens** 时启动告警——§1.4 |

**一个明确的正确性缺口**：`chat_controller.dart:2060-2062` 把子任务异常吞成一句给模型看的字符串：
```dart
} catch (error) {
  return '子任务执行失败：$error';
}
```
这有两个后果：① 子任务的失败**对审计/统计不可见**（不进 `ToolResult.failure`，无 error code）；② `error.toString()` 可能把内部异常细节暴露给模型，而 Claude Code 官方明确"从不删除或改写 subagent 输出"，同时它会**扫描**子 Agent 输出并在模仿 harness 标签时前置告警（§1.4）——NEXUS 这条路径既没做脱敏也没做审计留痕。

---

## 附：三项"能力已在、位置不对"的案例（供优先级排序参考）

这三条是我在核实过程中反复注意到的、**改动面最小而收益最直接**的地方：

| 现象 | 已有能力 | 缺的接入 | 外部对照 |
|---|---|---|---|
| 编辑不做新鲜度校验 | `read_file` 已算 `contentHashAfter`（`workspace_tools.dart:126`）；回滚已会用 `contentHashBefore/After` 拒绝过期补丁（`run_audit_report.dart:213-231`）；UI 引用已会标 `stale`（`project_context_service.dart:174`） | 把"本会话读过该文件、且哈希仍是这个"接成 `edit_file` 的前置条件（可做成一个 preflight guard，与 `preflight_guards.dart:9-14` 的现有四项并列） | Claude Code 的读前写约束（§1.6） |
| 工具结果截断后无法取回 | 已有 `offset`/`limit` 分页的 `search_files`（`workspace_tools.dart:577-578`）；已有确定性 `unified_diff` 生成（`unified_diff.dart:59-60`） | 截断时保留"如何取回"的指针（Claude Code 的落盘+预览），或按工具分档（DSH 的 retainer 分工） | §1.2 / §7.4 |
| 自动验证从不触发 | 验证计划（`development_verification.dart:274-304`）、失败三分类（`verification_repair_service.dart:93-107`）、重试上限 2（`:33`）、反循环指令（`:82`/`:85`）、跳过原因记录（`development_loop_finalizer.dart:109-121`）**全部就位** | 把 `chat_run_execution.dart:1516` / `chat_controller.dart:1553` 的 `runVerification: false` 接上一个设置项，并在已获终端授权时传 `terminal` | Aider `--auto-lint`/`--auto-test`（§3.7） |

---

## 未核实 / 存疑项（诚实清单）

1. **`ContextWindow.apply()` 与 `ContextCompressionPlanner` 的调用关系**：我核实了各自的触发条件与产物形态，但**没有逐一追踪**上层是否在某些路径上自动应用 planner 的提案（planner 注释说"a later approval flow can apply it"，暗示有审批流；`lib/application/context_compression_applier.dart` 存在，本次只看了它的文件头注释（`:24-25` 提到 stale index/tool id 会被忽略而非应用），**未读完整实现**）。
2. **同轮并行派发多个 `sub_agent` 是否被上层允许**：`chat_controller.dart:2078` 的提示词鼓励"并行推进"，但 `SubAgentTool` 自身串行。上层工具调度（`maxParallelToolCalls` 之类的概念）本次**未核实**——建议向负责运行时的同事确认。
3. **`read_file` 是否真的对同一个文件多次调用时复用 `lastMetadata`**：`clearMetadata()` 在每次 `execute` 开头调用（如 `workspace_tools.dart:586`），所以每次调用独立。**但 mixin 是实例级的**（`workspace_tools.dart:102-110`），若注册表复用同一工具实例，`lastMetadata` 会被下一次调用覆盖——本次未核实注册表的实例生命周期。
4. **`search_files` 的 `offset` 语义**：`workspace_tools.dart:597` 读 `offset`，但本次只读到 `walk` 的过滤逻辑开头（`:616-635`），**未完整读完计数与跳过部分**，因此"offset 是跳过命中数还是文件数"未确认。
5. **`file_citation` 的 `stale` 是否有编辑前置的消费者**：本次核实的是 `project_context_service.dart:67-71` 的提示词注入消费点，**未穷尽搜索**该字段的其它读取者。
6. **DSH 侧的对照细节**：第 1、2、4、7 项引用的 DSH 机制（`spill`/`pruner`/`FileBaselineInterceptor`/`subagent` 事件）来自 `evidence-external.md §7`，而 §7 本身标注为"复用上一轮 in-repo 调研、本次未重新进入 asar 逐行复核"。如需把与 DSH 的对照写进对外文档，建议先复核该节。

---

## 一句话结论

**NEXUS 的差距不在"缺少基础设施"，而在"连接"**：内容哈希（`workspace_tools.dart:126`）、回滚基线（`file_baseline_store.dart`）、失败三分类 + 重试上限（`verification_repair_service.dart:33`/`:93-107`）、验证计划与产物校验（`development_verification.dart:274-304`）都已存在且工程质量不低，但它们在**提示词注入层、回滚层、UI 层**各自为政，而没有接到 **编辑入口、工具结果截断层、Agent 运行收尾层**这三个真正会改变模型行为的位置上。
