# 《全量升级落地方案》落地审计（2026-10-19）

审计对象：`docs/mobile-next-major-implementation-2026-10-18.md`（v1.2，全量升级落地方案，基线 0.9.0+95）。
审计方式：逐个 F/W 条目在源码中查同名实现、入口、数据库 schema 与隔离合同报告；只认能指到文件或报告的证据，不把"文档写了"当作"已实现"。

## 结论

**没有全部落地。** 该文档是**实施基线提案**，其开头第 6 行已明确写："本文完成不代表功能已实现或验收通过"。
当前实际状态：

- F01–F22：**0 项**达到方案定义的验收标准；10 项部分落地（有可运行代码与隔离合同），12 项基本未落地。
- W00–W21：**0/22 完成**；主要进度集中在 W04/W05/W09/W10/W11/W12/W13/W15/W16/W17/W18/W19/W21，其余为未开始时点。
- A01–A28 固定验收、S01–S12 专项：**0 项通过**（方案要求真机/ARM64/多厂商/无障碍矩阵，当前只有 x64 模拟器证据）。
- 本文件不改变 `local/temp/major-deepseek-handoff-evidence-20261019.json` 里 `releaseReady:false` 的结论。

## 一、功能规格 F01–F22 落地对照

| 编号 | 方案条目 | 落地状态 | 代码/证据 | 缺口 |
| --- | --- | --- | --- | --- |
| F01 | 首次体验与模型接入 | 部分 | `lib/presentation/onboarding/onboarding_page.dart`；既有模型配置页 | 方案要的"按设备能力推荐模型 + 一键导入"未合并成流程 |
| F02 | 语音助手 | 部分 | `android/.../ForegroundSpeechBridge.kt`（SpeechRecognizer 单句）、`lib/.../speech_capture` UI 合同、TTS 归属隔离 4 条合同（见 `docs/mobile-next-major-deepseek-handoff-2026-10-19.md` §9.1） | 无连续多轮会话、无自动开麦；TTS 全局回调只是"不被误信任"，不能驱动开麦 |
| F03 | 系统助手入口与上下文 | 部分 | `NexusVoiceInteractionService.kt`、`NexusRecognitionService.kt`、`AssistantRoleBridge.kt`、`res/xml/nexus_voice_interaction.xml`、`default_assistant_page.dart`；角色/激活/撤权 UI 合同通过 | 助手入口没有关联个人上下文（依赖 F17，未落地） |
| F04 | 手机动作与跨应用执行 | 部分 | 既有设备控制 + 审批台账；`system_connector_request.dart` 五类 typed 请求（prepare_*） | 连接器只做"打开编辑器/prepare"，不能证明外部任务完成；无动作覆盖矩阵 |
| F05 | 对话、上下文与全量搜索 | 部分 | 全局搜索 12/12（七类分页，`tool/verify_global_search*`）；既有上下文预算 `lib/domain/context_insights.dart` | 方案的统一请求/动作契约（§7.2）未形成单一入口；跨源关联未做 |
| F06 | 任务工作台与恢复 | 部分 | 任务板 14/14、任务运行 20/20；`lib/application/run_controller.dart` | 冷启动/进程被杀后的恢复只覆盖既有 run 事件，方案的"恢复语义"未全量验证 |
| F07 | 成果中心 | 部分 | 成果合同 12/12；`ToolResultTruncation` 大文本 8000 截断 | 成果→交付物→分享链路未做端到端（真机文件系统未验证） |
| F08 | 项目开发完整升级 | 部分 | `development_workflow.dart`、`development_execution_service.dart`（`durablePlanRevision` schema30、`TaskControlRequest`） | 方案要的多模型评审、分支/回滚、任务图未落地 |
| F09 | 个人记忆与知识库 | 部分 | 记忆 12/12 + 作用域 28/28 + 知识作用域 21/21；schema28/29 | 关联召回、使用记录、知识更正闭环未做（页面台账亦如此记） |
| F10 | 提醒、定时执行与主动服务 | 基本未落地 | 已有 `ScheduledTask`/`ScheduledTasksPage`（定时执行 Agent 提示词，属基线） | 无 `Reminder` 模型、无时区/DST、无精确闹钟权限、无通知动作/稍后提醒；主动服务未做 |
| F11 | Agent、技能、MCP 与模板 | 部分 | `lib/domain/provider_template.dart` + `provider_template_import_page.dart`（校验/预览）；既有技能与 MCP | 无二维码导入、无托管决策、无扩展市场/版本签名/权限 diff |
| F12 | 模型推荐、用量与预算 | 部分 | `dashboard_page.dart`、`token_usage_hero.dart`、`context_budget_bar.dart`、`TOKEN_BUDGET_EXHAUSTED` | 只有 token 预算，无费用/货币预算、无推荐模型、无成本硬停 |
| F13 | 远程执行与跨设备连续性 | 未落地 | `remote_execution_probe.dart`（已改为可注入 client，未配置时显式 `StateError`）、`remote_executor_client.dart`、`tool/windows_remote_executor.py` 回环握手 | 无常驻 JobService/配对/同步/租约/断线恢复；`remote_execution_page` 生产路径未接终端用户配置 |
| F14 | 数据、更新与运营 | 部分 | 基线备份/vault（`vault_exporter_io.dart` 含 scheduledTasks） | 方案的数据迁移、增量更新、运营位/公告未做 |
| F15 | 实时多模态会话 | 未落地 | 源码无 `MediaProjection`、无 `RealtimeSession`、无帧/音频会话 | 全部待建 |
| F16 | 具体应用连接与动作覆盖 | 部分 | 连接器合同 12/12：日历/联系人/地图/文件/媒体五类 typed 请求，`system_editors_page.dart` 真接收方/预填/确认前禁用；`requiresSystemConfirmation` | 无 `ConnectorCapability`、无账号/OAuth、无读写动作与撤销；日历完整保存因账号准备未通过 |
| F17 | 关联个人上下文 | 已实现（隔离合同） | `lib/domain/personal_context.dart`、`lib/infrastructure/database/personal_context_store.dart`、`lib/application/personal_context_service.dart`、`lib/presentation/settings/personal_context_page.dart`、`lib/debug/personal_context_checks.dart`；schema 32；22 条合同并入模拟器 228/228；聊天注入在 `lib/application/chat_run_execution.dart` | 无关系可视化图谱；跨设备同步未做；系统助手语音入口尚未注入 |
| F18 | 可复用工作流 | 未落地 | 只有 `desktop_workflows_dialog.dart`、`desktop_workflow_service.dart`、`development_workflow.dart`（桌面/开发模板） | 无 `WorkflowDefinition`/`WorkflowRun`、无移动端确定性流程引擎 |
| F19 | 可核查研究与持续更新 | 未落地 | 无 `Evidence`/`ResearchArtifact` | 全部待建 |
| F20 | 可操作结果卡 | 已实现（隔离合同） | `lib/domain/result_card.dart`、`lib/infrastructure/database/result_action_store.dart`、`lib/application/result_action_service.dart`、`lib/presentation/chat/widgets/result_card_view.dart`、`lib/debug/result_card_checks.dart`；成果中心结果卡区块；17 条合同并入模拟器 228/228 | 六类执行器是注入回调，未接真实 Intent/系统能力；危险动作走页面内限时确认，未接统一 ApprovalBridge |
| F21 | 执行中纠正与人工交接 | 部分 | 计划协议 189/189（`plan_protocol_checks.dart`）、审批作用域、steering guard 12/12、schema30 持久计划修订 | 无结果卡上的内联操作/产出预览；跨恢复后旧回调失效只做到"忽略不可信回调" |
| F22 | 快速开始与自主配置 | 部分 | 模板导入页（无密钥 JSON、大小/版本/字段/协议/端点校验、接收方预览） | 缺二维码、缺设备能力检测、缺本地/远端托管判定 |

统计（更新于 F17/F20 落地后）：机制已实现并有隔离合同 2 项（F17、F20）；部分落地 10 项（F01–F09、F11、F12、F14、F16、F21、F22 中的多数）；其余 F10、F13、F15、F18、F19 基本未落地。**仍无一项**通过方案 §6 的完整验收条目（需要真机/多设备矩阵，模拟器证据不足以关闭）。

## 二、工作包 W00–W21 状态

以 `docs/mobile-next-major-progress-2026-10-18.md` 台账为准（该文件同样在开头声明"整版状态：未完成，不具备发布资格"）：

- 实施中：W00、W01、W04、W06、W08、W12、W15、W21（另有 W03 待继续复核）。
- 未完成：W02、W05、W07、W09、W10、W11、W13、W14、W16、W17、W18、W19、W20。
- 已完成：**0 项**。台账末尾原话："W00–W21/F01–F22、A01–A28/S01–S12 未完成门禁继续保留。"

## 三、合同证据能证明什么、不能证明什么

能证明（`local/temp/major-*-emulator-contract-20261019.json`，共 371/371；其中计划协议由 189 增至 228，新增 F17 22 项 + F20 17 项）：

| 套件 | 项数 |
| --- | --- |
| 计划协议（含 F17/F20/TTS 等子套件） | 228 |
| 知识作用域 | 21 |
| 记忆作用域 | 28 |
| 记忆 | 12 |
| 任务运行 | 20 |
| steering guard | 12 |
| 成果 | 12 |
| 全局搜索 | 12 |
| 任务板 | 14 |
| 系统连接器 | 12 |

只能证明：这些**已写出的纯逻辑/仓储/UI 状态机**在 x64 模拟器 + debug APK 上自洽。
不能证明：真机 ARM64、多厂商 ROM、无障碍（TalkBack/大字/横屏）、安全锁屏、电池/进程被杀、真实账号/OAuth、实时音视频、扩展安装、预算硬停、A01–A28 与 S01–S12 任何一项。

## 四、按方案派生出的下一步（若继续推进）

1. ~~先做 F17 关联上下文与 F20 结果卡~~ **已完成（2026-10-19 17:5x，见第二节末尾"本轮落地"）**；它们被 F03/F21 依赖，建议下一步把 F17 注入系统助手语音入口、把 F20 卡片接入计划面板/执行时间线。
2. F10 提醒需要新模型 + 时区/DST + 精确闹钟权限，非现有 `ScheduledTask` 可复用。
3. F13 远程执行要从"回环握手探针"升级为常驻 JobService + 配对；`remote_execution_page` 需接用户配置入口。
4. F15 实时多模态是独立大块（MediaProjection/帧会话/实时音视频），与现有单句语音不共享实现。
5. A01–A28/S01–S12 门禁要真机与多设备矩阵，当前模拟器证据不足以关闭任何一项。

## 五、审计边界

- 审计本身只做静态核对 + 既有证据复核，没有新增模型调用、没有提交或推送；审计之后按用户指令补做了 F17/F20（记录见第六节）。
- 未逐行比对方案 §5 页面清单中每个候选页的运行时可达性；页面台账见 `docs/mobile-next-major-page-coverage-2026-10-18.md`（原 47 个基线候选仍有未通过项）。

## 六、F17/F20 落地记录（2026-10-19 17:3x–18:0x）

用户指令：先做 F17 关联上下文 + F20 结果卡。两者都由隔离合同覆盖，**仍不等于方案 §6 的完整验收**。

### F17 关联个人上下文

- 文件：`lib/domain/personal_context.dart`（实体/别名/关系/来源/确认状态/有效期/遗忘规则模型）、`lib/infrastructure/database/personal_context_store.dart`（裸 SQL 仓储，沿用 artifacts/pending_approvals 先例，不跑 build_runner）、`lib/application/personal_context_service.dart`（读写、消歧、纠正、遗忘、注入块）、`lib/presentation/settings/personal_context_page.dart`（手机页，从 `data_management_page.dart` 进入）、`lib/debug/personal_context_checks.dart`（22 条）。
- schema 升到 32：`app_database.dart:59` `schemaVersion => 32`，onCreate `:101`、onUpgrade `:397` 都调 `ensurePersonalContextTables(this)`；表 `nexus_pctx_entities`、`nexus_pctx_aliases`、`nexus_pctx_relations`、`nexus_pctx_revisions` 及 9 个索引。
- 语义要点：来源三态（用户陈述/授权资料/推测）；推测**永不自动确认**，确认后仍标注推测；未确认与已撤销授权的条目**不进注入**；临时事项按有效期过滤；同名人物必须给限定词、同名文件按项目消歧；歧义引用只返回候选**不自动选**；敏感动作拒绝以推测对象为唯一依据；纠正保留历史并递增 revision，旧 revision 写入被拒；遗忘级联别名与关系并留 tombstone 阻止静默回库；注入按预算截断并在文本里给提示。
- 注入：`lib/application/chat_run_execution.dart` 的动态上下文段新增个人上下文块（在记忆/知识之后，保持"稳定前缀在前、动态内容垫底"）。
- 22 条用例名：`same_name_person_requires_qualifier`、`same_name_file_disambiguated_by_project`、`multi_project_recall_isolation`、`expired_temporary_task_not_recalled`、`expired_entry_excluded_from_injection`、`inferred_entry_never_auto_confirmed`、`confirmed_inference_labeled_as_speculation`、`unconfirmed_entry_excluded_from_injection`、`revoked_authorization_excluded_from_recall`、`forget_cascades_alias_and_relation`、`tombstone_blocks_silent_reentry`、`forgotten_entity_not_recalled_and_scope_reported`、`correction_keeps_history_and_bumps_revision`、`stale_revision_rejected_on_correct`、`ambiguous_reference_never_auto_selected`、`alias_resolves_cross_task_reference`、`sensitive_action_rejects_inferred_object`、`injection_budget_truncates_with_notice`、`empty_store_injection_is_empty_string`、`conflicts_group_duplicate_keys`、`wire_unknown_kind_reports_unsupported`、`normalized_key_ignores_punctuation_and_width`。

### F20 可操作结果卡

- 文件：`lib/domain/result_card.dart`（652 行）、`lib/infrastructure/database/result_action_store.dart`（302）、`lib/application/result_action_service.dart`（597）、`lib/presentation/chat/widgets/result_card_view.dart`（458）、`lib/debug/result_card_checks.dart`（17 条）；`lib/presentation/artifacts/artifact_center_page.dart` 追加结果卡区块与详情（手机/通用分支）。
- 表：`result_cards`、`result_actions`，唯一索引 `idx_result_actions_idempotency`；`ensureResultActionTables(this)` 在 onCreate `:102`、onUpgrade `:398`。
- 注册表 `ResultActionRegistry.all` 共 9 个动作覆盖六类：`reminder.reschedule`、`reminder.cancel`、`calendar.adjust`、`file.preview`、`file.share`、`route.open`、`workflow.trial_run`、`diff.review`、`diff.restore`；按钮只从 `forKind` + `supports()` 生成，模型伪造 actionType 进不了 UI 与 prepare。
- 幂等与并发：默认幂等键 `result-card:<cardId>:<actionType>:v<resourceVersion>`；`execute` 用 `_inFlight` 共享同一 Future；终态再执行返回既有结果（`executed=false`）。
- 失效判定顺序：卡片不存在→stale；卡片 revision 变（含"可能来自其他设备"）→conflict；引用/状态过期→stale 或 conflict；资源缺失→stale；版本不一致→conflict；权限 false→unauthorized。失败绝不写 succeeded。
- 审批：服务只接受 `ResultActionApproval(approvalId, cardId, actionType, grantedAt, expiresAt)` 并校验匹配/过期；成果中心当前用页面内限时确认（`approvalValidity` 5 分钟）生成 approval，未接统一 ApprovalBridge。
- 17 条用例名：未知动作类型在准备阶段被拒绝（unsupported）／模型伪造的命令按钮无法进入执行器／资源被删除后执行返回 stale 并保留失效终态／资源版本不一致时返回 conflict 且不落动作记录／快速重复点击共享同一个执行，执行器只被调用一次／权限撤销后返回 unauthorized 且不调用执行器／危险动作未确认时不得执行／过期审批被拒绝并落失败终态／prepared→pending_confirm→succeeded 全链路／执行器失败时保留失败状态且不伪造成功／执行器抛错被转换为失败而不是成功／六类卡片元数据齐全且组件可构造／准备后跨设备更新触发 conflict 并要求刷新／刷新检测到跨设备资源变化并提升卡片修订号／重试幂等：成功后再次准备/执行返回既有结果／卡片引用真实 resourceId 与版本，缺资源引用时拒绝执行／没有执行器时记录失败而不伪造成功。

### 本轮验证

- `flutter analyze --no-pub`：No issues found。
- 合同：`lib/debug/plan_protocol_checks.dart` 注册 `runPersonalContextChecks()`（22）与 `runResultCardChecks()`（17），`tool/verify_plan_protocol_emulator.py:45` 计数 189→228；模拟器实跑 **228/228**（`local/temp/major-plan-protocol-emulator-contract-20261019.json`）。
- 首次重建安装：debug APK `sha256 ce8ac684dc3b3e06a559f49e4860db15e2cb2868d80376688944080f23d912bd`（`local/temp/build-apk-f17-f20-20261019.log`），`adb install -r` 成功并重启调试应用。
- 模拟器实看（`local/temp/f17-context-*.png`、`local/temp/f20-*.png`）：F17 管理页可建实体、来源/确认状态/有效期与推测标签可见；F20 成果中心出现「结果卡 1 张可操作结果」，卡片列出 `资源 artifact/… · 版本 v1 · 卡片 r1` 与「预览文件 / 分享文件」按钮。
- 实看中发现并修掉 1 个布局缺陷：`lib/presentation/artifacts/artifact_center_page.dart` 结果卡横向列表的固定高度 168px 在摘要占两行时 `RenderFlex overflowed by 1.0 pixels`；改为 184px 并加注释说明两行标题/两行摘要都不溢出。
- 因该修复涉及源码，重新用工作区签名构建并重装（`adb install -r` 成功），合同复跑 **228/228**。
- 最终同版签收（2026-10-19 18:45）：`build/app/outputs/flutter-apk/app-debug.apk` 与设备已安装 `base.apk` **同为** `sha256 8ebe5948127987652c672c43b3ab611a412fb8f71a9f2ab0977f778c2ac1ddbc`（由 `tool/run-android-preview.ps1` 的 `flutter run` 产出，源码与 `e2bad66a…` 相同、字节不同）；该 APK 上合同 **371/371**、五条最终 UI 驱动 **5/5 通过**（`local/temp/major-final-ui-rerun-after-device-restart-20261019.log`，设备状态已复原）。历史哈希 `ce8ac684…`/`e2bad66a…` 的产物已被覆盖，不再引用。
- F20 失败路径实看：无执行器时点「预览文件」，页面如实显示「没有可用的操作执行器，已停止（不会伪造成成功）」，卡片状态转「失败」、按钮变「重试预览文件」，未伪造成功态——与 17 条合同中的失败保态用例一致。
- 未覆盖（截至 18:45）：非文件类结果卡执行器、主聊天流/计划卡/工具时间线结果卡接入、F17/F20 完整保险箱备份恢复、设置中心子页面全链路导航闭环（上述缺口已在后续第七节全部补齐）。

## 七、UI 页面功能全量闭环与端到端收口（2026-10-19 20:5x–23:5x）

1. **主聊天流 / 计划卡 / 工具时间线结果卡接入（U05）与审批桥接**：
   - `lib/application/conversation_result_projector.dart`、`lib/presentation/chat/widgets/conversation_result_section.dart`、`lib/presentation/chat/widgets/plan_execution_card.dart`、`lib/presentation/chat/widgets/tool_workflow_group.dart`、`lib/presentation/chat/chat_page_Controller_Actions.dart`：完成主对话轮次、计划协议卡与工具时间线的 `ResultCard` 自动投射与动作交互；破坏性动作统一接入 `ResultActionApprovalBridge` / `DeviceActionConfirmSheet`。
   - 合同与 UI 验证：`ext.nexus.conversationResultsContract` **40/40**，UI 场景 **11/11**（`local/temp/u05-conversation-results-contract-20261019.json`、`local/temp/u05-conversation-results-ui-20261019.json`）。
2. **全量 9 类 `ResultCard` 动作执行器闭环（`CompositeResultResourceReader` / `CompositeResultActionExecutor`）**：
   - 新增 `lib/application/non_file_result_actions.dart` 并接入 `lib/presentation/artifacts/artifact_center_page.dart`（成果中心与结果卡详情页）：
     - `file.preview` / `file.share`：委托 `ArtifactResultActionExecutor` 打开真实产物预览或调用系统分享面板；
     - `route.open`：校验目标路线（拒绝空目的地或控制字符），通过 `SystemConnectorDispatcher` 调起地图导航预览或打开页面内路线预览详情弹窗；
     - `calendar.adjust`：校验标题/起止时间并调用系统日历连接器预览或回写结果卡负载（`lastAdjustedAt` / `status: adjusted`）并递增 `version`；
     - `reminder.reschedule` / `reminder.cancel`：更新或取消本地 `ScheduledJobs` 定时任务并同步更新结果卡状态與版本；
     - `workflow.trial_run`：解析工作流步骤并创建可追踪的沙盒试跑记录（绝不静默伪造外部副作用）；
     - `diff.review` / `diff.restore`：联动 `ChangeSetService.load` 与 `ChangeSetService.rollback` 执行真实文件变更集审阅与冲突感知回滚。
   - 合同验证：`ext.nexus.artifactActionsContract` **34/34** 通过。
3. **移动端设置中心、扩展与运行时、数据管理全页面导航与搜索闭环**：
   - `lib/presentation/settings/settings_page.dart`：顶部 3 张概览统计卡（模型与密钥、扩展与运行时、数据与治理）支持点击直达对应二级中心；搜索过滤补齐助手角色、提示词模板、运行仪表盘、运行日志、成果中心等全部深层关键词。
   - `lib/presentation/settings/extensions_page.dart`：新增「能力与模板」（助手角色与人设 `AgentsPage`、提示词模板库 `PromptLibraryPage`）与「运行观测与诊断」（运行仪表盘 `DashboardPage`、运行日志与诊断 `LogViewerPage`）两大分组入口。
   - `lib/presentation/settings/data_management_page.dart`：新增「成果与结果卡中心」（`ArtifactCenterPage`）入口，打通从设置中心到成果与结果卡的完整访问路径。
4. **F17 个人上下文与 F20 结果卡加密保险箱（Vault）全量备份与恢复闭环**：
   - 新增 `lib/infrastructure/files/context_result_vault.dart`，并接入 `lib/infrastructure/files/vault_manifest.dart`、`lib/infrastructure/files/vault_snapshot_reader.dart`、`lib/infrastructure/files/vault_exporter_io.dart`：
     - 导出快照时完整打包 `nexus_pctx_entities`、`nexus_pctx_aliases`、`nexus_pctx_relations`、`nexus_pctx_revisions`、`result_cards`、`result_actions` 六张表并写入 `VaultManifest` 计数与校验规则；
     - 从含 `context_and_result_actions.json` 的新保险箱恢复时，完整还原个人上下文与结果卡；对遗留的 `prepared` / `pending_confirm` / `executing` 动作记录自动降级为 `expired` 终态（防止跨备份恢复后自动重放未完成动作）；
     - 从不含该文件的旧版（v1）保险箱恢复时，保留设备本地已有的个人上下文与结果卡，并向用户返回明确的部分覆盖提示。
   - 合同验证：`ext.nexus.personalContextSqlContract` **51/51** 通过（含新增全量保险箱往返恢复与待确认动作降级校验）。
5. **全量页面与弹窗 UI 走查及静态分析**：
   - 50 个移动端页面 × 4 视口/主题（200 项）+ 10 类核心弹窗/底部面板 × 4 视口/主题（40 项）+ 本轮功能升级的 5 个核心页 × 4 视口/主题（20 项）全部 `overflowCount=0`、`uiErrors=0`（`local/temp/ui-page-functions-verification-20261019.json`）。
   - `flutter analyze --no-pub`：**No issues found!**（`local/temp/ui-page-functions-analyze-20261019.log`）。