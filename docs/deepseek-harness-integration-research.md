# NEXUS 手机任务工作台：DeepSeek Harness 融合方案

日期：2026-09-29  
用户确认的方向：保留手机端，借鉴桌面工作台能力；本轮先输出方案，不修改应用代码。

> **⚠️ 本文为第一轮静态调研，部分结论已被第二轮实读修正。**
> 第二轮基于 DSH **发行产物**实读（`app.asar/dsh`，289 包）重新核查，请以 [dsh-comparison/00-借鉴清单与路线.md](dsh-comparison/00-借鉴清单与路线.md) 为准。主要修正：
> 1. `docs/subsystems/*.md`、`packages/`、`apps/` 在本机发行物中**不存在**，本文引用的 GitHub 链接与本地发行物**行号不可互换**。
> 2. "Web 用 baseline 和事件序号处理重连恢复"**已证伪**（见下文第 14 行修正说明）。
> 3. 本文"应先处理的回退边界"一节已**大部分过时**：NEXUS 现已具备 v2 change set、字节级基线、人工修改拒绝覆盖。详见 [00 文档 §0.3](dsh-comparison/00-借鉴清单与路线.md)。

## 官方来源核实

上游参考固定为 [639ed015397290b3745d163aafe02ffee4aa3f84](https://github.com/deepseek-ai/deepseek-harness/commit/639ed015397290b3745d163aafe02ffee4aa3f84)。[主 README](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/README.md) 仍将其标记为开发者预览，可能出现破坏性变更。以下“已有”表示官方源码/文档存在相应实现和契约，本次未启动桌面应用验证。

| 核实主题 | 官方事实 | 对 NEXUS 的启发与边界 |
| --- | --- | --- |
| 会话资源工作台 | 每会话资源面板可保存布局，切换会话保留指定页面；聊天文件链接支持预览与行号导航，重复地址复用页面，文档可随源文件变化刷新。[面板契约](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/docs/subsystems/sidebar-right.md)、[聊天预览](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/client/ui-chat/README.md#reference-previews) | 手机以任务内页签/抽屉实现同一上下文导航。未核实上游完整变更集回滚，不据此宣称存在原子审阅/恢复。 |
| 作业统一展示 | 会话头部 jobs 控件汇总状态、耗时与进度；完成项折叠，展开才订阅输出；停止会通知模型。[Jobs UI](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/client/ui-jobs/README.md) | 聚合 NEXUS 已有任务与终端状态。“待我处理”收件箱是本方案的产品推导，不是上游已核实的同名功能。 |
| 分支与重连 | API 在明确稳定的回合边界 fork：`fork(source, boundary?, childSessionId?)`，boundary 为**闭区间** source seq，复制事件日志前缀并以 `session/end-seed{inherited:true}` 标记。[Session API](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/docs/subsystems/session.md#live-session-fork-api) | 提升已有会话 fork 的可发现性和来源导航。分支树是设计建议，不宣称上游已有成品树形界面；重连恢复也不等于文件恢复。 |
| ~~重连恢复（原表此处说法已作废）~~ | **修正（2026-09-29 发行产物实读）**：原表述"Web 用 baseline 和事件序号处理重连恢复"**不成立**。`sequenceNo` 在 DSH 发行树 7,879 个文件中**零命中**。实际机制是 follow 流的 opening `cursor`（`SessionSeqCursor`，空日志为 `-1`）+ journal 的 `replace/prepend/append` 连续性判定 + gap repair 页；投影快照另用 `asOfSeq`。详见 [dsh-comparison/02](dsh-comparison/02-session-runtime.md) 与 [00](dsh-comparison/00-借鉴清单与路线.md) §0.2。 | 不要把 baseline/sequenceNo 当作 DSH 契约对齐到 NEXUS；形状不等价，不可直接映射。 |
| 能力预设 | preset 定义 child plugins 列表并有稳定 id；既有 Agent 组合保持稳定，新定义用于新 Agent；UI 展示用途、示例和只读 YAML，编辑通过 Creator。[预设定义](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/preset/agent-preset/README.md)、[预设 UI](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/client/ui-agent-preset/README.md) | 将 NEXUS 已有配置组成易理解的任务包，并记录启动时配置快照。 |
| 上下文与过程展示 | 有上下文压力测量、自动/手动压缩及工具结果剪枝；聊天过程有不同详细程度，完成过程可折叠，最终答案可见。[压缩](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/docs/subsystems/compaction.md)、[聊天展示](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/client/ui-chat/README.md) | 小屏默认呈现当前进度、关键决策与结果，日志按需展开；复用已有预算和压缩能力。 |
| 生命周期与远端 | Desktop 关窗口会隐藏并保留 Host，真正退出会检查受影响任务；SSH 提供远端文件/进程能力，但不自动重连重放模糊操作，Web workspace 还需额外集成。[桌面生命周期](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/apps/desktop/README.md#closing-the-window-and-quitting)、[SSH](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/docs/subsystems/ssh.md) | 手机应区分界面离开、连接中断和执行进程终止，不能将桌面行为直接解释为 Android 永久后台运行或完整跨设备工作台。 |

架构上，[官方 architecture](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/docs/architecture.md) 说明 Desktop 是 Electron 承载的共享 Web/Host 应用，Cordis 插件组织模型、工具、会话和执行循环。NEXUS 可借鉴明确的能力接口及事件契约，继续使用现有 Flutter、Riverpod、Drift 和执行服务。


## 对 NEXUS 的判断：保留手机端，把现有能力组织成任务工作台

以下是基于本地源码的适配建议，不是 Harness 已承诺的功能，也不是实施完成说明。本次只做静态调研，没有启动 Harness 桌面端或运行 NEXUS 真机验证。

NEXUS 已是具备开发执行能力的 Android 工作台。推荐产品定位：**在手机上交代开发任务、跟进执行、检查改动并拿到可用成果。** 优先降低对话、文件、任务和结果之间的切换成本。

### 现有能力与实际增量

| 优先级 | 借鉴方向 | NEXUS 已有基础 | 建议融合的增量 | 相对工作量 |
| --- | --- | --- | --- | --- |
| P0 | 会话内资源工作台 | 文件树、编辑器、终端、项目主页、任务详情；开发工作台目前主要执行构建验证 | 在当前任务内提供“对话 / 文件 / 结果”切换；运行状态条打开终端与工具明细；按会话保存选中文件、滚动位置和未发草稿 | 中 |
| P0 | 任务收件箱 | 任务列表、运行记录、通知审批、暂停/追加指令、执行租约 | 在会话抽屉顶部集中显示“待我处理 / 运行中 / 已结束”；点击直达具体审批、失败步骤或成果；项目内可筛选 | 中 |
| P0 | 成果与改动审阅 | 任务详情已有 Diff、验证步骤、制品和关联修复；有单次 edit_file 审计回滚 | 将改动文件、验证结果、网页预览/APK 安装集中到“结果”页；完善项目级检查点后再提供整任务回退 | 汇总中；可靠回退高 |
| P1 | 项目与会话分支导航 | 会话关联项目；可从消息创建分支并记录 parent/forkMessage 标签 | 抽屉按项目组织；标出分支来源、父会话及分叉位置，便于比较两种方案 | 中 |
| P1 | 可复用任务配置包 | Agent、Skills、MCP、声明式 HTTP 工具插件、任务模板均有基础 | 将一套角色、技能、MCP 引用、工具范围和验证规则保存为可预览的配置包；支持项目默认配置及兼容性提示 | 中至高 |
| P2 | 上下文与工具加载优化 | Token 构成、上下文历史、工具结果压缩、预算暂停、工具能力目录均已存在 | 将已有指标变成具体操作：定位大工具结果、查看压缩对象、按任务缩小工具目录；以测得的首轮延迟和 schema 占用决定是否继续做按需发现 | 中 |

“相对工作量”为静态阅读后的判断，不是工期承诺。P0 三项可分步交付，不必一次并入。

### 具体代码依据

- 当前应用根入口为对话页：[app_shell.dart](../lib/presentation/navigation/app_shell.dart#L5)。任务、项目、构建工作台目前从更多菜单分别进入：[chat_page.dart](../lib/presentation/chat/chat_page.dart#L1683)。因此首期的主要增量是任务内导航与状态保持。
- 项目主页已有文件、任务与制品内容及预览入口：[project_home_page.dart](../lib/presentation/projects/project_home_page.dart#L222)。任务详情已有流水线、Diff、验证和制品：[task_details_page.dart](../lib/presentation/tasks/task_details_page.dart#L584)。应优先复用这些展示与服务。
- [development_workbench_page.dart](../lib/presentation/workspace/development_workbench_page.dart#L27) 主要负责识别项目、执行分析/测试/构建、检查制品并从失败创建修复任务；它不是当前全部开发能力的统一容器。
- 会话分支通过复制锚点之前的消息实现，不重放工具副作用：[conversation_fork_service.dart](../lib/application/conversation_fork_service.dart#L10)。现有抽屉按时间分组：[chat_catalog_drawer.dart](../lib/presentation/chat/widgets/chat_catalog_drawer.dart#L121)。分支导航是明确增量；“创建对话分支”不能表述为“复制或恢复代码工作区”。
- 会话切换已有解绑可见运行、切回重新绑定的逻辑：[chat_controller.dart](../lib/application/chat_controller.dart#L2664)。暂停、继续和追加指令已有控制器：[run_controller.dart](../lib/application/run_controller.dart#L8)。不应再次把这些列为从零开发。
- [development_execution_service.dart](../lib/application/development_execution_service.dart#L89) 已处理请求去重、工作区租约冲突排队及任务控制；[background_execution_gateway.dart](../lib/application/background_execution_gateway.dart#L15) 为后台执行入口。任务收件箱首先聚合现有运行状态，不能仅凭这些接口假定已有完整的多任务自动调度。
- 终端已有作业列表、日志、取消、持久守护进程记录：[command_tool.dart](../lib/infrastructure/tools/command_tool.dart#L317)。界面离开、网络断开、Android 杀进程是不同生命周期，恢复验收应分别覆盖。
- [database_tables.dart](../lib/infrastructure/database/database_tables.dart#L358) 已有 RunRecords/RunEvents；事件带 runId 和 sequenceNo，可作为统一展示的基础。任务状态、消息历史与事件目前各有存储用途，不应直接宣称已实现 Harness 式完整事件溯源。
- [plugin_store.dart](../lib/infrastructure/plugins/plugin_store.dart#L15) 的范围是 JSON 声明式 HTTP 工具与 Agent 预设；Flutter 不能直接加载 Harness 的 TypeScript/Cordis 插件。建议借鉴包的组合与启停规则，逐步扩展现有格式。
- [context_snapshot_builder.dart](../lib/application/context_snapshot_builder.dart#L5) 已按实际请求消息和工具定义估算上下文构成；[session_configuration_sheet.dart](../lib/presentation/chat/widgets/session_configuration_sheet.dart#L10) 已统一模型、Agent、工作区等配置。无需再做另一套重复仪表盘。
- 仓库的 [dsh-context-source/README.md](../dsh-context-source/README.md) 指向 bowenliang123/dsh-context，是第三方 Harness 上下文插件，不能作为 DeepSeek 官方内置能力的证据。

### 应先处理的回退边界

这不是完整代码审查，但它直接影响“可靠成果审阅”的可交付范围：

1. [ChangeSetService.capture](../lib/application/change_set_service.dart#L105) 当前读取修改后的文件，保存 afterRef/afterHash，beforeHash 为空且不填 beforeRef。
2. [ProjectChangeSetPage._load](../lib/presentation/projects/project_change_set_page.dart#L40) 是进入页面时为最近任务重新 capture，而不是读取执行前后封存的变更集。
3. [ProjectChangeSetPage._rollback](../lib/presentation/projects/project_change_set_page.dart#L77) 将已保存的 afterHash 当作 currentHashes 传入；这不能验证回退前磁盘文件是否又被人工修改。
4. [WorkspaceSnapshotService](../lib/application/workspace_snapshot.dart#L65) 保存的是受大小和数量限制的文件哈希索引，没有修改前内容。
5. 任务详情的单步骤 [AuditRollbackService.rollbackEditFile](../lib/application/run_audit_report.dart#L172) 是另一条实现：支持已确认生效的 edit_file 事件，读取当前文件、检查 hash 并反向应用 Diff。可以继续复用其明确边界，不能把局部回滚能力扩写成整工作区恢复保证。

整任务回退需要持久化修改前内容或可靠的可逆补丁、明确创建/编辑/删除语义、在实际写回前重新校验磁盘状态，并报告部分成功和冲突。终端脚本改动与超限文件需要单独界定覆盖范围。首期先把现有 Diff 和验证结果呈现好。

### 推荐的手机交互

下面是 NEXUS 的设计建议，不是 Harness 界面的复刻。

- 顶部保留项目与当前会话选择，减少配置项常驻占位。
- 内容区提供任务内的“对话 / 文件 / 结果”分段切换，不必新增全应用底部导航。
- 对话显示沟通和计划；文件显示当前项目目录与编辑器；结果显示当前任务的改动、验证和产物。
- 输入框上方保留一条简短运行状态，例如“正在测试 · 2 个文件已修改”；点开后查看工具、终端作业、耗时与取消入口。
- 抽屉顶部展示需要处理的任务，再展示运行中任务和按项目归类的会话。
- 手机竖屏一次聚焦一个内容面；横屏/平板有足够空间时，再考虑对话与资源并排。

以“帮我改网页并验证”为首个完整场景：发出要求 → 查看当前步骤 → 打开改动文件 → 查看验证结果与预览 → 针对失败继续修复。每一页都沿用同一个项目、任务和运行标识。

### 演进顺序与验收

**第一阶段：统一任务工作台。** 接入现有文件、任务详情和制品展示，增加任务内导航、简短状态条及待处理任务入口。首期默认使用既有执行机制。

验收：
- 从当前对话最多两次操作找到本任务的改动和验证结果。
- 切到文件/结果再返回，草稿、选中文件及滚动位置仍保留。
- 查看另一个会话不取消原运行；返回后能看到正确任务状态。
- 多个项目的文件、日志与产物不串任务。
- 待审批、失败、取消、验证未执行均有明确状态，不能统一显示为完成。
- 旧会话和无项目的普通聊天仍可正常打开。

**第二阶段：把恢复与审阅做可靠。** 封存每次任务变更证据，完善项目级回退，增强分支来源导航和中断恢复展示。

验收重点是“人工后续编辑不会被覆盖”“重启不盲目重放已有副作用”“对话分支与文件恢复分开表达”。采用已有数据库与脱敏约束；不要将仅供审计的脱敏摘要当成完整模型历史直接重放。

**第三阶段：可复用配置与扩展。** 先做一个能在新项目重复使用的配置包，例如“小型网页开发”或“Android 小工具构建”，确认导入、依赖检查、缺失模型/MCP 提示和结果验证完整，再扩展其他任务类型。用户密钥仍由现有安全存储提供，配置包只引用凭据。

多 Agent 扩展、完整远端工作台和任意代码插件不进入首期。当前 [remote_execution_probe.dart](../lib/application/remote_execution_probe.dart#L42) 是技术验证接口，默认握手返回 unknown/空工具链；不能当成已完成的远端任务后端。

### 实施范围说明

本次只新增这份研究文档，没有修改应用源码，也没有运行应用测试。工作区原有未提交的 agent_executor/tool_pipeline 等改动保持原样。docs/* 受仓库现有 .gitignore 规则忽略，本报告当前为本地文件，未修改忽略规则或加入暂存区。
