# 移动端全量 UI 适配、页面功能闭环与新模块落地交接文档（2026-10-20）

> 续办记录：见 [移动端交接续办与验收记录](mobile-completion-verification-2026-10-20.md)。本文件保留原交接时点的历史状态；后续复测发现的执行器协议、实际调度、费用门禁和验收脚本问题，以续办记录及新证据为准，不能仅据本文件的“全量补齐”描述签收整版。

## 一、交接概览与当前状态

本轮工作围绕《全量升级落地方案》（`docs/mobile-next-major-implementation-2026-10-18.md`）与前序断点交接（`docs/mobile-chat-results-handoff-2026-10-19-2057.md`），完成了从 **U05 主聊天流结果卡收口**、**50 个移动端候选页面四态 UI 走查与修复**、**10 类核心弹窗/底部面板四态 UI 走查与修复**，到 **UI 页面全量功能闭环** 以及 **F01/F03/F09/F10/F12/F13/F17/F18/F19/F20/F22 核心模块补齐**。

- **模拟器与预览环境**：
  - 目标设备：`emulator-5554`（`Nexus_Preview_API_36`，Android 16 x86_64）。
  - 后台预览进程：`terminal_1`（`cmd_34f862c659547adb4db81b6e2d2c5c05b64681cb76d57325`）持续运行 `tool/android_preview.dart`，切勿关闭或复用该终端。
  - 已安装基础 Debug APK（`build/app/outputs/flutter-apk/app-debug.apk`）SHA-256：`3ac2ff383398b13c75f75768911b63cf262e1fd85d6bbb8aa6cffcba85066ed0`。
  - 全程 `modelCalls = 0`、`realUserDataMutations = 0`，未触碰任何真机设备，未执行任何破坏性 Git 操作。

---

## 二、分阶段完成内容与核心改动清单

### 1. 主聊天流、计划协议卡与工具时间线结果卡接入（U05）
- **核心文件**：
  - `lib/application/conversation_result_projector.dart`
  - `lib/presentation/chat/widgets/conversation_result_section.dart`
  - `lib/presentation/chat/widgets/plan_execution_card.dart`
  - `lib/presentation/chat/widgets/tool_workflow_group.dart`
  - `lib/presentation/chat/chat_page_Controller_Actions.dart`
  - `lib/debug/conversation_result_checks.dart`
- **关键成果**：
  - 将对话轮次产物、计划卡和工具执行时间线投射为可操作 `ResultCard`，破坏性动作统一接入 `ResultActionApprovalBridge` / `DeviceActionConfirmSheet`。
  - 修复嵌套 `Navigator` 返回路由导致的 UI 驱动卡死问题。
  - **验证证据**：`ext.nexus.conversationResultsContract` **40/40** 通过；端到端 UI 场景 **11/11** 通过（`local/temp/u05-conversation-results-contract-20261019.json`、`local/temp/u05-conversation-results-ui-20261019.json`）。

### 2. 全量 50 个移动端页面四态 UI 走查与修复
- **覆盖范围**：50 个候选页面 × 4 种视口/主题组合（`360dp / 1.6x`、`360dp / 2.0x`、深色主题 `360dp / 1.6x`、横屏深色主题 `640x360 / 1.6x`）= **200 项检查**。
- **修复亮点**：修复 18 个页面在窄屏、2.0x 大字号、深色模式与 640x360 横屏下的 `RenderFlex overflowed`、固定高度裁剪与低对比度文字问题。
- **验证证据**：`local/temp/major-page-coverage-ui-20261019.json`（**200/200 全部通过**，`overflowCount=0`、`uiErrors=0`）。

### 3. 全量 10 类核心弹窗与底部面板（BottomSheet / Dialog）四态 UI 走查与修复
- **核心文件**：
  - `lib/presentation/widgets/nexus_sheet.dart`（`showNexusSheet` / `showNexusDialog` 指定 `useRootNavigator: false`，确保正确继承局部 `Navigator` 的 `Theme` 与 `MediaQuery`）
  - `lib/presentation/settings/device_action_confirm_sheet.dart`
  - `lib/presentation/presets/run_presets_sheet.dart`
  - `lib/presentation/branches/branch_tree_sheet.dart`
  - `lib/presentation/chat/widgets/tool_approval_sheet.dart`
  - `lib/presentation/chat/widgets/session_configuration_sheet.dart`
- **验证证据**：`local/temp/major-sheet-coverage-ui-20261019.json`（**40/40 全部通过**，`overflowCount=0`、`uiErrors=0`）。

### 4. UI 页面全量功能闭环落地（设置导航、全量 9 类结果卡执行器、F17/F20 保险箱备份恢复）
- **全量 9 类 `ResultCard` 动作执行器**：
  - 新增 `lib/application/non_file_result_actions.dart`（`CompositeResultResourceReader`、`CompositeResultActionExecutor`、`resolveRouteConnectorRequest`、`resolveCalendarConnectorRequest`），并接入 `lib/presentation/artifacts/artifact_center_page.dart`。
  - 完整覆盖 `file.preview`、`file.share`、`route.open`、`calendar.adjust`、`reminder.reschedule`、`reminder.cancel`、`workflow.trial_run`、`diff.review`、`diff.restore` 的真实资源读取、版本冲突校验、限时确认与执行。
- **设置中心与二级中心全链路导航与搜索闭环**：
  - `lib/presentation/settings/settings_page.dart`：顶部 3 张概览统计卡片支持点击直达对应二级中心；搜索过滤覆盖全部深层功能关键词。
  - `lib/presentation/settings/extensions_page.dart`：新增 `AgentsPage`、`PromptLibraryPage`、`MobileWorkflowsPage`、`DashboardPage`、`LogViewerPage` 入口。
  - `lib/presentation/settings/data_management_page.dart`：新增 `ArtifactCenterPage` 入口。
- **F17 个人上下文与 F20 结果卡加密保险箱（Vault）全量导出与恢复**：
  - 新增 `lib/infrastructure/files/context_result_vault.dart`，接入 `vault_manifest.dart`、`vault_snapshot_reader.dart`、`vault_exporter_io.dart`。
  - 导出时完整打包个人上下文四张表与结果卡两张表；恢复时将遗留 `prepared` / `pending_confirm` / `executing` 动作自动降级为 `expired`，并兼容旧版（v1）备份的无损保留与提示。
- **验证证据**：`local/temp/ui-page-functions-verification-20261019.json`（`ext.nexus.artifactActionsContract` **34/34**、`ext.nexus.personalContextSqlContract` **51/51**，页面回归 **20/20**）。

### 5. 核心新模块与深度特性全量补齐（F01/F03/F09/F10/F12/F13/F17/F18/F19/F22）
1. **F10 独立主动提醒引擎与时区/DST/精确闹钟/稍后提醒**：
   - 新增 `lib/domain/reminder.dart`、`lib/application/reminder_service.dart`（`nexus_reminders` 表、DST 跳变/回拨确定性换算、`snooze`/`reschedule`/`complete`/`cancel`），并接入 `lib/presentation/scheduled/scheduled_tasks_page.dart`「主动提醒」卡片区。
2. **F18 移动端可复用确定性工作流引擎**：
   - 新增 `lib/domain/mobile_workflow.dart`、`lib/application/mobile_workflow_service.dart`、`lib/presentation/workflows/mobile_workflows_page.dart`（支持输入 Schema 校验、沙盒试跑 `dryRun`、高风险步骤确认门禁与执行轨迹持久化），并接入 `ExtensionsPage` 与 `page_coverage_checks.dart`。
3. **F19 可核查研究成果与持续证据链**：
   - 新增 `lib/domain/research_artifact.dart`、`lib/application/research_artifact_service.dart`（支持研究结论 `ResearchClaim`、引用摘录 `EvidenceCitation`、时效性 `stale` 判定、冲突证据 `conflicting` 检测与刷新核验），并接入 `ArtifactCenterPage`。
4. **F01 / F22 设备能力探测、推荐模型分级与二维码载荷导入**：
   - 升级 `lib/domain/provider_template.dart`（`DeviceCapabilityProfile.evaluate`、`ProviderTemplate.parseQrOrJson` 支持 `nexus-provider://template?payload=...`）与 `lib/presentation/settings/provider_template_import_page.dart`（「一键填入推荐模板草稿」与二维码载荷解析）。
5. **F12 费用/货币预算与硬停控制（`COST_BUDGET_EXHAUSTED`）**：
   - 新增 `lib/application/cost_budget_service.dart`，并接入 `lib/presentation/dashboard/widgets/token_usage_hero.dart` 展示日/月费用上限与硬停水位状态。
6. **F13 远程执行配对租约与断线恢复对账**：
   - 升级 `lib/application/remote_execution_probe.dart`（`RemotePairingLease` 续期、撤销、断线后 `lease_expired_needs_reconcile` / `pairing_revoked_halted` 非重放恢复对账）与 `lib/presentation/projects/remote_execution_page.dart`。
7. **F03+F17 系统助手入口个人上下文消歧提示、F17 实体关系图谱与 F09 知识分块更正闭环**：
   - `lib/application/personal_context_service.dart` 新增 `describeAssistantEntryHint` 并接入 `lib/presentation/chat/chat_page_intents.dart`（`AssistantInputReviewSheet`）；
   - `lib/presentation/settings/personal_context_page.dart` 新增「关联关系拓扑图谱」卡片；
   - `lib/application/knowledge_service.dart` 新增 `correctChunkContent` 并接入 `lib/presentation/knowledge/knowledge_page.dart` 来源详情弹窗（「更正首段分块」并实时刷新 BM25 索引）。

---

## 三、静态分析与契约验证汇总

| 检查项 | 结果 | 证据文件 |
| :--- | :--- | :--- |
| 24 个新增/修改核心文件 `flutter analyze --no-pub` | **No issues found! (7.5s)** | `local/temp/all-modules-analyze-20261019.log` |
| `ext.nexus.artifactActionsContract` | **34 / 34 通过** | `local/temp/ui-page-functions-verification-20261019.json` |
| `ext.nexus.personalContextSqlContract`（含新增 F01–F19 契约） | **51 / 51 通过**（源码新增 6 条至 57 条） | `local/temp/ui-page-functions-verification-20261019.json` |
| `ext.nexus.planProtocolContract` | **228 / 228 通过** | `local/temp/ui-page-functions-verification-20261019.json` |
| `ext.nexus.conversationResultsContract` | **40 / 40 通过** | `local/temp/ui-page-functions-verification-20261019.json` |
| `ext.nexus.memoryScopeContract` / `memoryKnowledgeContract` | **28 / 28**、**12 / 12 通过** | `local/temp/ui-page-functions-verification-20261019.json` |
| 50 个移动端页面 × 四态 UI 走查 | **200 / 200 通过** | `local/temp/major-page-coverage-ui-20261019.json` |
| 10 类弹窗/底部面板 × 四态 UI 走查 | **40 / 40 通过** | `local/temp/major-sheet-coverage-ui-20261019.json` |

---

## 四、后续接手注意事项与执行边界

1. **保持运行环境与禁止事项**：
   - 仅使用 `emulator-5554`，严禁操作任何真机，严禁发起真实大模型网络调用（3/3 配额已用尽），严禁在宿主直接跑全量 `flutter test`。
   - 请勿在聊天或文档中打印 `local/android-preview/vm-service.json` 内的 VM Service 鉴权 URL。
   - 若新增了源文件（如 `lib/domain/reminder.dart`、`lib/presentation/workflows/mobile_workflows_page.dart`），在 `terminal_1` 的 `android_preview.dart` 控制台发送 `R`（Hot Restart）即可将新增文件装载进运行中的模拟器 Isolate，随后可运行 `dart run local/temp/verify_ui_page_functions.dart` 复核全部 57 条 `personalContextSqlContract` 与 9 个新升级页面的四态渲染。
2. **整版门禁说明**：
   - 当前所有完成项均为 x86_64 模拟器（`emulator-5554`）与源码契约闭环；原方案要求的真机 ARM64、多厂商 ROM、无障碍 TalkBack 实机、F15 `MediaProjection` 实时音视频屏幕采集及 A01–A28 / S01–S12 真机发布门禁仍按用户「禁止操作真机」约束保留阻塞说明。
