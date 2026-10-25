# NEXUS vs 成熟编码 Agent：全方面对比与缺陷定位

> 2026-10-15 实施更新：[第一阶段优化、验证结果与剩余边界](implementation-2026-10-15.md)。下文是优化前的对比结论，当前实现以实施记录为准。
> 后续：[第二阶段：自动验证与修复闭环](verification-repair-2026-10-15.md)。
> 2026-10-16：[第三阶段：补丁、符号地图、并行委派与折叠策略](remaining-mechanisms-2026-10-16.md)，含实际验证结果与尚未覆盖的边界。
> 2026-10-16：[第四阶段：运行控制、累计预算、压缩恢复与端到端验收](runtime-controls-2026-10-16.md)。此前鉴权阻塞已在用户修正本地配置后复验通过，最新真实模型验收记录见文末。
> 2026-10-16：[第五阶段：跨文件补丁及失败恢复](multi-file-patch-2026-10-16.md)。批次预校验、失败补偿、变更审阅与持久化恢复已接通；不宣称跨文件原子性或断电一致性。
> 2026-10-16：[第六阶段：可写隔离子任务提案](isolated-edit-2026-10-16.md)。当前工作区快照、审批、受限编辑、持久化提案和父版本冲突检查已接通；结果需审阅应用后在父工作区验证。
> 接续收尾：已核验[四种语言的候选引用图](remaining-mechanisms-2026-10-16.md#接续收尾多语言候选引用图)，补齐[补丁恢复异常边界](multi-file-patch-2026-10-16.md#接续收尾持久化恢复)。9 个相关测试文件共 103 项通过，10 个源码与测试文件静态分析无问题；真实模型端到端验收、Windows Debug 构建及正常应用入口恢复均已通过。

> **回答的问题**：和成熟 agent（Claude Code / Codex CLI / Aider / Cline / OpenHands / Cursor / DSH）比，NEXUS 的底层机制与排版渲染差在哪？
>
> **方法**：三条独立证据线交叉。
> - `evidence-external.md`（1039 行）—— 外部 agent 的机制，每个论断附实际抓取成功的 URL（§10 有完整来源清单）。
> - `evidence-nexus-ui.md`（40,653 B）—— NEXUS 排版/渲染/主题/动效的逐文件审计。
> - `evidence-gaps.md`（622 行）—— NEXUS 底层机制逐项核实，`path:line` 全部为实际读取所得。
>
> 本文件是**结论层**，不重复证据，只做判断与排序。

---

## 0. 一句话结论

> **NEXUS 的差距不在"缺基础设施"，而在"接线"。**

七项机制里没有一项是"从零开始"的：内容哈希、回滚基线、验证计划、失败三分类、重试上限、日志保尾、子 Agent 预算钳制——**全都写好了，工程质量不低**。问题是它们分布在提示词注入层、回滚层、UI 层，**没有接到真正改变模型行为的那三个位置**：编辑入口、工具结果截断层、Agent 运行收尾层。

换句话说：**NEXUS 现在是一个"能力齐全但回路断开"的 agent。** 成熟 agent 的护城河不是某个 fancy 功能，而是这些回路是闭合的——模型做错时，系统会**自动**纠正、**自动**补充、**自动**验证。

---

## 1. 七项底层机制：逐项判定

判定档位：**实现** = 完整且有明确触发路径；**部分** = 有代码但覆盖面不全或需人工介入；**缺失** = 完全没有。

| # | 机制 | NEXUS 判定 | 成熟 agent 的做法 | 差距性质 |
|---|---|---|---|---|
| 1 | 自动压缩 | **部分** | Claude Code 阈值自动摘要（~967K/200K 两档，`/autocompact` 四档可配）；OpenHands Condenser 滚动窗口保留头 4 + 摘要中间；Cline Auto Compact 模型写摘要保留技术细节与决策 | **架构级**：不是参数没调好，是缺"让模型写摘要"这条路径 |
| 2 | 工具结果截断 | **部分** | DSH pruner 头 4096 + 尾 1024；Claude Code 头+尾摘录 | **方向性错误**：只留头部，丢掉最有用的尾部 |
| 3 | 编辑应用策略 | **部分** | Aider 按模型族选 `diff`/`udiff`/`whole` 等 6 种格式 + 模糊匹配；Claude Code 读前写约束 | **正确性风险**：无补丁格式、无读前写 |
| 4 | 读前写约束 & 文件新鲜度 | **缺失** | Claude Code 读前写；DSH file baseline + `FS_STALE_VERSION` 强制重读重基 | **核心缺口**：改错文件无人拦 |
| 5 | 仓库级检索 / repo map | **缺失** | Aider tree-sitter repo map（符号排序图）；Cursor Instant Grep + 索引/embedding | **能力空白**：只有全文搜 |
| 6 | 验证循环 | **部分** | Aider `--auto-lint` 默认开 + 每次编辑后跑测试并自动修复 | **只差一个开关**：下游全就位，上游传 `false` |
| 7 | Sub-agent 委派 | **缺失** | Claude Code 3 层嵌套 / 20 并发 / 每子任务 token 元数据；Cursor 前台+后台两模式 | **可扩展性**：串行、返回单串、无隔离 |

---

## 2. 最重要的三个缺陷（按"改动量 ÷ 收益"排序）

### 缺陷一：上下文回收是"静默丢弃"，不是"压缩"

这是**深度上差距最大**的一项，也是唯一需要真正新写代码的。

NEXUS 实际有两条回收路径，**两条都不是自动摘要**（`evidence-gaps.md:96-100`）：

1. **`ContextWindow.apply()`** —— 每请求无条件跑的**静默 head-drop**：从最新往前累加估算 token 直到预算耗尽（`context_window.dart:102-106`），截断点之前 `sublist(cut)` 直接扔掉（`:127`），前面插一条**常量文案**告示：

   ```dart
   // context_window.dart:50-51
   static const compactionNotice = '[上下文提示：更早的 assistant/tool 记录因容量上限'
       '已被压缩，请勿假定其中步骤未执行；需要确认时重新读取文件或重跑检查。]';
   ```

2. **`ContextCompressionPlanner`** —— 只处理**工具结果**（枚举只有一个值，`context_compression_planner.dart:7`），且产出的是**待用户审核的数据对象**（`:42-44` 注释明说 "data-only"），只在 warning/critical 档建议（`:69-72`）。

**丢掉了什么**：用户的原始意图、已经做出的架构决策、已经踩过的坑、未完成的 TODO。这些恰恰是长会话里最贵的东西。Claude Code 的压缩产物是**一条结构化摘要**，保留意图/关键概念/文件/错误修复/待办；Cline 明确要求摘要保留"所有技术细节与决策"。

**还有一处"缺了一半"**：NEXUS 的告示告诉模型"**你自己去重读**"（`context_window.dart:51`），而 Claude Code 压缩后**自动重读最近 5 个文件**、重注入 CLAUDE.md / rules / auto memory / plan / 技能正文。同样的语义，一个把成本推给模型（多花一轮工具调用、且模型可能偷懒不读），一个直接替模型做完了。

**最小修法**：不必重写事件溯源。在 `ContextCompressionPlanner` 里增加一个候选类型（如 `turnRange`），把"更早的轮次"也纳入，产出一条模型写的摘要替换 `sublist` 丢弃；同时把压缩后的"自动重读清单"补上。

---

### 缺陷二：工具结果截断只保头部 —— 方向反了

```dart
// context_window.dart:187-202  _capToolResult
text.substring(0, maxToolResultChars) + toolResultTruncatedMark
```

16,000 字符上限（`:32` `defaultMaxToolResultChars`）**只留头部**，尾部直接丢弃，标记本身**不带任何体积信息**（不知道被砍了多少、总共多长）。

**为什么这是方向性错误**：对编码 agent 来说，一条工具结果里**最有价值的信息在末尾**——

- 测试失败摘要（pytest/jest 的 failed 列表在最后）
- 编译器错误（dart analyze / tsc 的 error 汇总在最后）
- 构建输出（Gradle 的 BUILD FAILED 在最后）
- diff 尾部

NEXUS 保留的头部通常是"命令开始执行"的样板输出，信息密度最低。

**外部对照**：DSH pruner 是 **head 4096 + tail 1024**（§7.4）；Claude Code 是**头+尾摘录**（§1.2）。两边都保尾——这不是巧合，是踩过坑之后的设计。

**一个反证说明团队知道正确的方向**：`verification_repair_service.dart:112` 的日志截取**恰恰是保尾的**：

```dart
trimmed.substring(trimmed.length - maxChars) + '\n…[日志已截取尾部]'
```

注释理由正是"构建/测试错误通常在输出末尾"。**同一份代码库里两个方向相反的截断策略**——说明这是遗漏而非有意设计。建议统一为保尾，或直接采用 DSH 的头+尾双段策略。

**顺带一个可用性缺口**：截断后**没有任何"如何取回"的指针**。NEXUS 已经有分页的 `search_files`（`workspace_tools.dart:577-578`）和确定性 diff 生成（`unified_diff.dart:59-60`），但截断标记里不写"完整内容在哪 / 怎么分段取"。DeepSeek Harness 的做法值得抄：**截断内容落盘 + 给模型一个可预览的指针**，模型需要时自己取，而不是永久丢失。

---

### 缺陷三：自动验证从不触发 —— 只差一个开关

这是七项里**最接近可投产**的一项，也是最"冤"的一项——**下游全就位，上游传了 `false`**。

两个调用点都硬编码关闭：

```dart
// chat_run_execution.dart:1510-1517
finalize(db:, taskId:, runId:, workspacePath:, terminal: null, runVerification: false)

// chat_controller.dart:1547-1553
runVerification: false
```

而 `development_loop_finalizer.dart:104-108` 的门槛是合取：

```dart
final shouldVerify = runVerification && terminal != null
    && workspacePath.trim().isNotEmpty && implementsChanges && review.files.isNotEmpty;
```

`runVerification` 默认 `false`（`:64`），加上硬编码 `false` + `terminal: null`，**聊天路径上 `shouldVerify` 恒为 `false`**。

**已经就位的下游（质量不低）**：

- 验证计划按项目类型派发（`development_verification.dart:274-304`）：Flutter → `flutter analyze` → `flutter test` → `flutter build apk --release`（超时 20 分钟）→ **产物检查**（校验 `build/app/outputs/flutter-apk/app-release.apk` 真实存在）
- 失败三分类（`verification_repair_service.dart:93-107`）：`permission_denied` / `environment_missing` / `test_failed`
- 重试上限显式且保守：`maxAutoAttempts = 2`，且**只有 `test_failed` 可自动重试**（`:60-63`）
- 两类原因各带反循环指令：`permission_denied` → "不要绕过用户授权，也不要扩大权限"（`:82`）；`environment_missing` → "不要反复安装同一缺失项"（`:85`）
- 跳过原因**如实记录**（`development_loop_finalizer.dart:109-121`）并进 openIssues（`:167-170`）：如"未验证：自动验证需要终端授权，本轮未获得授权"

**最后这条值得特别肯定**：它保证「没验证」**绝不会被下游读成「验证通过」**。这正对着自动验证最典型的失败模式。

**而且 NEXUS 的验证在这些维度上强于 Aider**：

| 维度 | NEXUS | Aider |
|---|---|---|
| 产物级验证 | ✅ 校验真实产物路径 + sha256 进 evidence（`development_loop_finalizer.dart:172-176`） | ❌ 只看退出码 |
| 失败分类 | ✅ 三类 | ❌ 只有退出码 |
| 重试上限 | ✅ 显式 2 次，且只有测试失败可重试 | ❓ 未公开 |
| 日志截取方向 | ✅ 保尾 | — |

**因此**：把 `chat_run_execution.dart:1516` 的 `runVerification` 接上一个用户设置项，并在已获终端授权时传入 `terminal`，就能从"手动按钮"（现由 `development_workbench_page.dart:76-101` 的确认对话框触发）升级为"Aider 式自动验证 + 最多 2 次自动修复"。**这是投入产出比最高的一处改动。**

---

## 3. 排版 / 渲染 / UI：这是 NEXUS 的**相对强项**

外部审计（`evidence-nexus-ui.md`）与 DSH 客户端对照（§7.8）的结论：**NEXUS 的渲染层不在落后位置**，部分维度领先。

### 3.1 已经做到位、且高于成熟 agent 中位数的部分

- **动效系统**：16 文件 / 2,674 行，弹簧参数化 + reduced-motion 全链路贯穿。多数成熟 agent 的 CLI/TUI 客户端根本没有这一层。
- **流式感知的 Markdown 扫描器**：针对"边流边渲染"的未闭合语法做了处理——这是流式 UI 的真实难点，很多实现直接忍受闪烁。
- **三级重建粒度**：控制 rebuild 范围，长转录不卡。成熟 agent 的 Web 客户端常整段重建。
- **Markdown 能力完整**：`flutter_markdown_plus` + `flutter_math_fork`（数学公式）+ 代码高亮。

### 3.2 真正的差距：**折叠策略是"散落的 if"而不是"一张表"**

这是排版层最值得抄 DSH 的一条。

DSH 的 `ui-chat.transcriptView` 定义了**4 个模式 → 4 个字段**的映射表：

| 字段 | 控制什么 |
|---|---|
| `foldCompletedTurns` | 已完成的轮次是否折叠 |
| `stepGrouping` | 步骤如何分组 |
| `liveProcessDetail` | 进行中的过程显示多细 |
| `settledReasoningPreview` | 已结算的推理是否预览 |

**关键设计**：渲染器只读**字段**，**从不比较模式枚举**。加一个模式 = 只改这张表，渲染代码一行不动。

NEXUS 目前是相反的：折叠/展开/详细程度的判断散落在各个 widget 的 `if` 里，改一处显示策略要动多个文件，且无法保证一致。这不是"排版不好看"的问题，是**可演进性**的问题。

**同类的成熟共性**（Claude Code §1.9、Codex TUI §2.11、Cline §4.9、OpenHands §5.9、Cursor §6.11 都有）：**每会话的界面状态持久化** + **折叠策略集中表达**。NEXUS 需要的是把散落的显示判断收敛成一张声明式表。

### 3.3 对话内导航：缺"三面切换"

成熟 agent 普遍在会话内提供 **chat / files / results** 三面切换，并**按会话记忆布局**。NEXUS 的相关能力散在 workspace / history / jobs 等页面，**会话内没有统一切换面**，用户看任务产物要跳出去。

---

## 4. NEXUS 做得比外部好的地方（客观记录）

对比不能只写差距。以下是核实后确认 NEXUS **领先或独有**的：

| 能力 | NEXUS | 外部对照 |
|---|---|---|
| **子任务 token 预算** | ✅ `sub_agent_tool.dart:26-27` `minBudget=500` / `maxBudget=8000`，缺省给上限、越界钳制（`:30-33`） | **外部 agent 都没有这个参数** —— 这是 NEXUS 独有设计 |
| **产物级验证** | ✅ 校验真实产物路径 + sha256 进 evidence | Aider 只看退出码 |
| **验证跳过原因如实记录** | ✅ `development_loop_finalizer.dart:109-121` → openIssues | 未见同类机制 |
| **失败三分类 + 反循环指令** | ✅ `verification_repair_service.dart:93-107`, `:82`, `:85` | Aider 无分类 |
| **日志保尾** | ✅ `verification_repair_service.dart:112`（理由正确） | DSH 两侧都保 |
| **会话日志事件溯源** | ✅ turn/start · message · request/sent · turn/end，`contentKey` 哈希去重，`unsealedRuns` 崩溃封存 | 架构上接近 DSH |
| **System prompt 前缀缓存排序** | ✅ `system_prompt_assembly.dart` 稳定段在前、动态段在后，注释直指"缓存命中低、花费高"的真实问题 | 思路与 Anthropic 显式断点一致 |
| **编辑失败三分类** | ✅ committed-metadata-failure（`effect: applied`）vs interrupted（`effect: unknown`，告知模型先 `read_file`） | 多数 agent 只有"成功/失败" |
| **动效系统** | ✅ 16 文件 / 2,674 行，弹簧 + reduced-motion | 成熟 agent 客户端普遍没有 |
| **回滚引擎** | ✅ 拒绝静默覆盖手工编辑（`change_set_service.dart:387`）+ 字节级原始文件 | 与 Cline shadow git 同级 |

**这些说明团队的工程判断力是在线的** —— 差距确实在"接线"而不在"能力"。

---

## 5. 修复优先级

### P0 —— 正确性风险，越早越好

1. **读前写约束 + 文件新鲜度校验**（缺陷四，判定：缺失）
   三样东西都在，方向都错：`FileBaselineInterceptor` 是**回滚存储**（`:12-13` 明说 "A failure to save never blocks the tool"）；`read_file` 确实算了 `contentHashAfter`（`workspace_tools.dart:126`）但那是**单次调用的审计元数据桶**（`clearMetadata()` 每次 execute 开头调用），`edit_file` 从不读它；唯一真实的 staleness 检查是 `project_context_service.dart:174` 的 `FileCitation`，**只作用于提示词注入**，不覆盖"模型读完后文件被改"。
   **最小接法**：把「本会话读过该文件 且 哈希仍是这个」做成一个 preflight guard，与现有四项（`preflight_guards.dart:9-14`：UnknownTool / TruncatedArguments / SchemaValidation / PreviewPlan）并列。改动面小，收益直接——这是 Claude Code 和 DSH 都有、而 NEXUS 完全没有的护栏。

2. **工具结果截断改为保尾**（或头+尾）
   `context_window.dart:199` 改一行方向；标记里补上总长度信息。同时照 DSH 的做法给"如何取回"的指针。

### P1 —— 能力补齐，收益高

3. **自动验证接上开关**（缺陷三）—— 下游全就位，改两个调用点 + 一个设置项。
4. **自动摘要压缩**（缺陷一）—— 唯一需要新写代码的一项，但也是长期会话体验的决定因素。建议先加 `turnRange` 候选类型 + 摘要生成，重读清单可后补。
5. **会话内三面导航 + 布局持久化**。
6. **折叠策略收敛成声明式表**（抄 DSH `transcriptView` 的"渲染器只读字段"模式）。

### P2 —— 长期演进

7. **编辑应用策略**：增加 diff 格式作为 `edit_file` 的补充（Aider 证明按模型族选格式有效），至少支持多编辑批处理。
8. **repo map / 符号索引**：Aider 的 tree-sitter 方案证明无需 embedding 也能大幅提升大仓库定位能力。
9. **Sub-agent 并行与元数据**：先补"返回 token 数与时长"，再考虑并行 fan-out 与嵌套深度控制。注意先修 `chat_controller.dart:2060-2062` 把异常吞成字符串的路径——子任务失败对审计不可见，且 `error.toString()` 可能把内部细节暴露给模型。

---

## 6. 三处"提示词与机制不对齐"

这类问题最隐蔽：**提示词告诉模型去做机制不支持的事**，模型会失败、重试、浪费轮次。

| 位置 | 提示词说的 | 机制实际 |
|---|---|---|
| `chat_controller.dart:2078` | "可将可独立、**并行推进**的只读子任务委派给 sub_agent" | `SubAgentTool` 工具契约是**串行**的（单个 `prompt` string，一个调用只跑一个子任务） |
| `task_template_service.dart:46` | "Flutter 默认执行：flutter analyze、flutter test、flutter build apk --release" | 聊天路径 `shouldVerify` 恒为 `false`，**默认不执行** |
| `chat_controller.dart:2083-2084` | "子 Agent 仅放行安全工具；写文件、执行命令…必须由你亲自处理" | `headless_executor.dart:255-260` 确实是全有或全无（`!sensitive && risk == ToolRisk.safe` 才放行），**描述与实现一致** ✅ |

前两条建议在三处文案里补上"当前机制的边界"，或把机制补齐到与文案一致。

---

## 7. 诚实声明：本结论的边界

1. **外部证据未逐行核实**：`evidence-external.md` 的作者声明本次 `web_search` 不可用、`raw.githubusercontent.com` TLS 握手失败，因此外部论断来自**实际抓取成功的 URL**（§10 有清单），**没有**做到逐行源码级验证。
2. **DSH 部分复用上轮调研**：`evidence-external.md §7` 的 DSH 内容来自仓库内既有的 `docs/dsh-comparison/*`，**本次未重新进入 asar 逐行复核**（§7.9 已标注）。
3. **`evidence-gaps.md` 的 6 条存疑项**未消化完：包括 `ContextWindow.apply()` 与 `ContextCompressionPlanner` 的完整调用关系、同轮并行派发多个 sub_agent 是否被上层允许、`read_file` 元数据实例生命周期、`search_files` 的 offset 语义等。
4. **外部 agent 是闭源/半开源产品**：Claude Code、Cursor、Codex CLI 的内部实现只能从官方文档、发布说明、公开 repo 推断，**不能排除**其内部实现与公开描述有出入。
5. **本报告未修改任何应用代码** —— 纯分析交付。

### 一个独立发现的旁证

核实过程中发现：**同一代码库里两个方向相反的截断策略**（工具结果保头 `context_window.dart:199` vs 修复日志保尾 `verification_repair_service.dart:112`），而后者的注释理由（"构建/测试错误通常在输出末尾"）恰恰证明前者是错的。**这说明工具结果截断方向是遗漏，不是有意设计。**

---

## 附：证据文件索引

| 文件 | 大小 | 内容 |
|---|---|---|
| `evidence-external.md` | 1,039 行 | 7 个外部 agent 的底层机制 + 转录 UI，每节附 URL；§8 横向对照表；§9 无法核实清单 |
| `evidence-nexus-ui.md` | 40,653 B | NEXUS 排版/渲染/主题/动效逐文件审计 |
| `evidence-gaps.md` | 622 行 | NEXUS 侧 7 项机制核实，`path:line` 证据 + 判定 + 外部对照 |
| `README.md`（本文件） | — | 结论层：判定、优先级、诚实边界 |

**建议阅读顺序**：本文件 → `evidence-gaps.md` 结论速览（`:12-22`）→ 需要的具体条目。`evidence-external.md` 作为外部论据的出处按需查。
