# 移动端页面覆盖台账（2026-10-18）

依据：mobile-next-major-implementation-2026-10-18.md。此表为源码页面候选清单，不冒充完整运行时路由注册表；弹层、动态入口和平台分支仍须补查。

用户约束：仅使用电脑上的 Nexus_Preview_API_36 模拟器；不得操作真机。ARM64、厂商助手入口及真实功耗保持未验证。

负责人：当前执行助手（源码与自动化）；验收负责人：用户，尚未确认整版验收。每页必须补入口、状态、截图和验收结论，不能因源码存在记为通过。

| 页面候选 | 手机适用性 | 实际访问/状态验证 | 证据 |
| --- | --- | --- | --- |
| `lib/presentation/agents/agent_editor_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/agents/agents_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/audit/audit_log_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/chat/chat_page.dart` | 手机实际入口已确认 | 仅当前默认状态已访问；其余状态未覆盖 | `local/temp/major-emulator-start-20261018.png` |
| `lib/presentation/dashboard/dashboard_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/diagnostics/log_viewer_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/diagnostics/run_analysis_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/feedback/feedback_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/history/history_page.dart` | 手机历史入口；真实DB查询，隔离数据库注入 | 早于最近62条会话的正文检索与客户端保留命中通过；其他状态未覆盖 | `local/temp/major-search-fixture-history-20261019.png` |
| `lib/presentation/jobs/jobs_inbox_page.dart` | 手机实际入口已确认；新增隔离夹具 | 三页签、旧审批/暂停/部分完成/待核实，全部已读后空收件箱且待处理仍为4已验证；全部状态/乱序竞态/无障碍未覆盖 | `local/temp/major-jobs-fixture-{before,after,pending-after}-20261019.png`；`docs/mobile-jobs-contract-2026-10-19.md` |
| `lib/presentation/knowledge/knowledge_page.dart` | 手机页面隔离夹具已访问；真实菜单路由待复核 | 已实际打开本地来源/分块弹窗并关闭；导入/删除UI/失败/大字等未全覆盖 | `local/temp/major-memory-fixture-knowledge-source-20261019.png` |
| `lib/presentation/mcp/mcp_servers_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/memory/memory_page.dart` | 手机页面隔离夹具已访问；真实菜单路由待复核 | 助手/未知来源、ID/范围/会话和模型发送说明已观察；编辑/删除交互及全部状态未完整覆盖 | `local/temp/major-memory-fixture-memory-20261019.png` |
| `lib/presentation/onboarding/onboarding_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/plugins/plugins_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/plugins/skill_market_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/projects/project_change_set_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/projects/project_git_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/projects/project_home_page.dart` | 手机实际入口已确认 | 概览/工具入口已访问，其他状态未全覆盖 | `local/temp/major-remote-navigation-20261018.png` |
| `lib/presentation/projects/project_picker_page.dart` | 手机实际入口已确认 | 仅当前默认状态已访问；其余状态未覆盖 | `local/temp/major-emulator-workspace-20261018.png` |
| `lib/presentation/projects/remote_execution_page.dart` | 手机实际入口已确认 | 模拟器真实认证握手通过，其他状态未全覆盖 | `local/temp/major-remote-handshake-20261018.png` |
| `lib/presentation/prompts/prompt_library_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/scheduled/scheduled_tasks_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/settings/appearance_theme_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/settings/data_backup_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/settings/data_management_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/settings/desktop_settings_page.dart` | 桌面专用（已确认排除：直接依赖 `DesktopTheme.of(context)`，移动端统一走 `settings_page.dart`） | 不适用（桌面壳层专用） | 源码审阅确认 |
| `lib/presentation/settings/device_automation_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/settings/device_backups_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/settings/device_capabilities_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/settings/default_assistant_page.dart` | Android“我的→默认系统助手”实际菜单已确认 | 生产状态页、系统选择/取消、真实角色/激活、session/助手键、撤权后进程重启/恢复原设置通过；安全锁屏/多厂商/大字/横屏/TalkBack未完成 | `local/temp/major-assistant-role-settings-entry-20261019.png`、`major-assistant-role-{unselected,active}-20261019.png`；`docs/mobile-default-assistant-contract-2026-10-19.md` |
| `lib/presentation/settings/extensions_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/settings/language_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/settings/linux_environment_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/settings/model_list_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/settings/provider_detail_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/settings/provider_list_page.dart` | 手机实际入口已确认 | 仅当前默认状态已访问；其余状态未覆盖 | `local/temp/major-emulator-provider-list-20261018.png` |
| `lib/presentation/settings/provider_template_import_page.dart` | 手机实际入口已确认 | 仅当前默认状态已访问；其余状态未覆盖 | `local/temp/major-emulator-template-preview-20261018.png` |
| `lib/presentation/settings/settings_page.dart` | 手机实际入口已确认 | 仅当前默认状态已访问；其余状态未覆盖 | `local/temp/major-emulator-mine-20261018.png` |
| `lib/presentation/settings/tool_list_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/settings/workspace_files_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/tasks/development_tasks_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/tasks/task_details_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/terminal/terminal_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/vault/vault_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/workbench/session_workbench_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/workspace/development_workbench_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |
| `lib/presentation/workspace/workspace_editor_page.dart` | 待逐入口确认 | 未覆盖 | 待补 |

## 自动化（不替代逐页访问）

新增页面（不计为原 47 个基线候选已通过）：`lib/presentation/settings/system_editors_page.dart`，手机“我的 → 系统编辑器连接”可达。模拟器已覆盖日历/联系人选择、真实接收方、预填、确认前禁用、拒绝返回；联系人外部编辑器已观察，日历完整编辑/保存因账号准备未通过。证据索引见 `docs/mobile-system-connectors-contract-2026-10-19.md`。大字/横屏/TalkBack/平台缺失与恢复仍未完整覆盖。

- 四导航：懒加载、草稿保留、子路由保留、系统返回顺序、360dp 导航布局。
- 配置导入：安全字段校验、端点预览、同意前禁用继续、修改输入使同意失效。
- `test/mobile_shell_test.dart`、`test/provider_template_test.dart`、`test/provider_template_import_page_test.dart`。
- 新增功能及桌面兼容选测：33 项通过；日志 `local/temp/major-navigation-template-test-20261018.log`。
- 模拟器预览已构建并确认 `[preview] Ready`；助手首页已截图，其他页面和状态仍待记录。

| `lib/presentation/search/global_search_page.dart` | 历史/任务/我的入口 | 模拟器隔离旧正文命中、来源重新读取通过；七类服务检查12/12；大字/横屏/TalkBack尚未覆盖 | `docs/mobile-search-contract-2026-10-19.md`；`local/temp/major-search-fixture-{search,source-capture}-20261019.png` |

| `lib/presentation/artifacts/artifact_center_page.dart`（新增） | 工作区/搜索/任务详情真实ID入口 | 隔离列表、真实完整副本正文、缺失提示、360dp/1.6字体列表/详情采样通过；系统分享/复制只读夹具禁用，尚未验证真实交付 | `docs/mobile-artifact-runtime-contract-2026-10-19.md`；`local/temp/major-artifact-fixture-*-20261019.png` |

360dp/1.6字体搜索及展开筛选/输入法浮层已采样：`local/temp/major-search-font16-width360*-20261019.png`；这不抵消其他字体、横屏和TalkBack缺口。

## 记忆/知识 schema29 后续增量（2026-10-19）
记忆编辑CAS失败保精确草稿/复制、放弃确认和遗忘屏障说明；知识导入明确全局/项目，卡片/来源显示范围，粘贴保存失败或取消范围留草稿，重试真正入库后才关闭。隔离模拟器UI已核实数据库及注入，最新九套143项契约通过。不是全页大字/完整键盘/TalkBack/独立进程/ARM64门禁；关联召回、使用记录、知识更正与范围管理仍待闭环。证据与迁移边界见mobile-memory-knowledge-contract-2026-10-19.md后续实施更新。

## 候选页面 360dp 窄屏、1.6x/2.0x 大字号、深色主题与 640x360 横屏 UI 走查与修复（2026-10-19）
- 通过隔离 UI 宿主 `ext.nexus.pageCoverageUi`（`lib/debug/page_coverage_checks.dart`）与驱动 `tool/verify_page_coverage_ui_emulator.py`，在 `emulator-5554` 上对全部 50 个移动端候选/新增页面（原表 46 个移动端页面 + 新增 `personal_context_page.dart`、`system_editors_page.dart`、`global_search_page.dart`、`artifact_center_page.dart`；另加 `chat_page.dart` 独立 11 场景 UI 走查，排除桌面专用的 `desktop_settings_page.dart`）执行了 `360dp` 竖屏（`1.6x`、`2.0x`）、深色主题（`360dp / 1.6x`）以及横屏深色主题（`640x360 / 1.6x`）共 200 项真实渲染检测（`modelCalls=0`、`realUserDataMutations=0`）。
- 修复了走查暴露的 6 处窄屏/大字号/横屏/深色主题 UI 溢出与渲染缺陷：
  1. `lib/presentation/agents/agent_editor_page.dart`：`_ParameterSlider` 标题行 `Text(label)` 补充 `Expanded` 包裹，消除 `360dp / 2.0x` 下 3 处右侧 `RenderFlex overflowed`。
  2. `lib/presentation/plugins/skill_market_page.dart`：补充 `Material` 与 `SafeArea(bottom: false)` 包裹，既兼容 `PluginsPage` 页签内嵌，也修复独立页面渲染时缺少 `Material` 祖先及状态栏重叠问题。
  3. `lib/presentation/settings/settings_components.dart`：`SettingsSectionTitle` 标题文本补充 `Flexible` 与单行省略，消除 `device_backups_page.dart`、`device_capabilities_page.dart` 等设置页在 `360dp / 2.0x` 下分组标题右侧溢出。
  4. `lib/presentation/settings/device_capabilities_page.dart`：顶部 2×2 指标网格值与徽章由固定 `Row` 改为自适应 `Wrap`，消除 `360dp / 2.0x` 下单元格 `13px` 右侧溢出。
  5. `lib/presentation/terminal/terminal_page.dart`：`AppBar` 补充 `foregroundColor: Colors.white`（修复浅色主题下深色终端顶栏图标不可见）、动作按钮采用紧凑密度，并为状态胶囊文本补充 `Flexible` 单行省略，消除 `360dp / 1.6x & 2.0x` 下顶栏 `94px` 溢出。
  6. `lib/presentation/onboarding/onboarding_page.dart`：引导页 `PageView.builder` 步骤内容增加 `LayoutBuilder + SingleChildScrollView + ConstrainedBox` 及紧凑高度（`<480dp`）下的自适应间距与图标尺寸，消除 `640x360 / 1.6x` 横屏模式下底部 `252px` 纵向溢出并保证首屏标题与说明立即可见。
- 证据：`local/temp/major-page-coverage-ui-20261019.json`（`1.6x=50/50`、`2.0x=50/50`、`dark1.6x=50/50`、`landscapeDark1.6x=50/50` 全部 200 项通过）、`local/temp/major-page-coverage-*-20261019.png`、`local/temp/major-page-coverage-analyze-20261019.log`。注意：此走查覆盖各页面在隔离合成数据下的 `360dp` 窄屏、`1.6x/2.0x` 大字号、深色主题与 `640x360` 横屏渲染无溢出，不替代各页面全部弹窗分支、TalkBack 与独立编译 APK 整版验收。

## 核心弹窗与底部面板（BottomSheet / Dialog）窄屏、大字号、深色主题与横屏 UI 走查与修复（2026-10-19）
- 通过 `ext.nexus.pageCoverageUi`（`mode='sheet'` / `mode='pop_sheet'`）与 `tool/verify_sheets_dialogs_ui_emulator.py`，在 `emulator-5554` 上对 10 类核心弹窗与底部面板（`confirm_danger_dialog`、`action_sheet`、`tool_approval_sheet`、`device_action_confirm_sheet`、`session_metrics_sheet`、`input_tool_grid_sheet`、`environment_setup_sheet`、`file_tree_sheet`、`run_presets_sheet`、`branch_tree_sheet`）执行了 `360dp / 1.6x`、`360dp / 2.0x`、深色主题 `360dp / 1.6x` 与横屏深色主题 `640x360 / 1.6x` 共 40 项真实渲染与截图复核（`modelCalls=0`、`realUserDataMutations=0`）。
- 修复了走查与视觉复核暴露的 3 类共 10 处弹窗/面板 UI 缺陷：
  1. 嵌套导航器上下文与主题透传（`lib/presentation/widgets/nexus_sheet.dart`）：`showNexusSheet` 与 `showNexusDialog` 调用 `showGeneralDialog` 时显式指定 `useRootNavigator: false`，确保弹层挂载在当前最近的 `Navigator` 下并正确继承局部 `Theme` / `MediaQuery`（如深色主题、字号缩放与横屏视口约束）。
  2. 深色/浅色主题下误用 `colorScheme.outline` 作为文字/图标颜色导致的低对比度不可读问题（修复为 `colorScheme.onSurfaceVariant`）：
     - `lib/presentation/settings/device_action_confirm_sheet.dart`（副标题、不可执行项状态色、卡片键值标签）
     - `lib/presentation/branches/branch_tree_sheet.dart`（非当前路径分支图标、右箭头与说明图标）
     - `lib/presentation/chat/widgets/session_configuration_sheet.dart`（未开启状态下的联网与计划模式图标）
     - `lib/presentation/workbench/session_workbench_page.dart`（轮次副标题次要文字色）
     - `lib/presentation/chat/widgets/tool_approval_sheet.dart`（底部授权范围提示文字色）
  3. `640x360` 横屏与 `2.0x` 大字号下的纵向 `RenderFlex overflowed` 修复：
     - `lib/presentation/settings/device_action_confirm_sheet.dart`：将副标题与高风险确认 `CheckboxListTile` 纳入中部 `Flexible(ListView)` 滚动区，仅固定顶部标题与底部操作按钮，消除 `2.0x`（`5.7px`）与 `640x360` 横屏（`27px`）底部溢出。
     - `lib/presentation/presets/run_presets_sheet.dart`：将说明文字、「保存当前设置为预设」按钮与预设列表/空状态统一放入 `Flexible(ListView)`，消除 `640x360` 横屏下 `61px` 底部溢出。
     - `lib/presentation/branches/branch_tree_sheet.dart`：将分支说明与空状态/分支列表统一放入 `Flexible(ListView)`，消除 `640x360` 横屏下 `23px` 底部溢出。
     - `lib/presentation/widgets/nexus_action_sheet.dart`、`lib/presentation/chat/widgets/session_configuration_sheet.dart`、`lib/presentation/diagnostics/log_viewer_page.dart`（筛选面板）、`lib/presentation/chat/chat_page_sheets.dart`（模式切换与审批模式面板）：补齐 `ClampingScrollPhysics` / `SingleChildScrollView` 滚动兜底并移除过窄的 `maxHeightRatio: 0.32` 限制。
- 证据：`local/temp/major-sheet-coverage-ui-20261019.json`（`1.6x=10/10`、`2.0x=10/10`、`dark1.6x=10/10`、`landscapeDark1.6x=10/10` 全部 40 项通过）、`local/temp/major-sheet-coverage-*-20261019.png`、`local/temp/major-page-coverage-analyze-20261019.log`（`No issues found!`）。

## UI 页面功能全量落地与端到端闭环（2026-10-19）
- **设置中心与二级中心全链路导航闭环**（`lib/presentation/settings/settings_page.dart`、`lib/presentation/settings/extensions_page.dart`、`lib/presentation/settings/data_management_page.dart`）：
  - `SettingsPage` 顶部 3 张概览统计卡片支持点击直达对应二级中心，搜索过滤覆盖助手角色、提示词模板、运行仪表盘、运行日志、成果中心等全部深层功能关键词；
  - `ExtensionsPage` 补齐 `AgentsPage`、`PromptLibraryPage`、`DashboardPage`、`LogViewerPage` 入口；
  - `DataManagementPage` 补齐 `ArtifactCenterPage` 入口。
- **成果中心与结果卡详情页全量 9 类动作执行器接入**（`lib/application/non_file_result_actions.dart`、`lib/presentation/artifacts/artifact_center_page.dart`）：
  - 通过 `CompositeResultResourceReader` 与 `CompositeResultActionExecutor` 支持 `file.preview`、`file.share`、`route.open`、`calendar.adjust`、`reminder.reschedule`、`reminder.cancel`、`workflow.trial_run`、`diff.review`、`diff.restore` 全部 9 类注册动作的真实资源读取、版本冲突校验、高风险限时确认与执行落地。
- **加密保险箱（Vault）F17 个人上下文与 F20 结果卡全量导出/恢复闭环**（`lib/infrastructure/files/context_result_vault.dart`、`lib/infrastructure/files/vault_manifest.dart`、`lib/infrastructure/files/vault_snapshot_reader.dart`、`lib/infrastructure/files/vault_exporter_io.dart`）：
  - 导出快照新增 `context_and_result_actions.json` 并纳入 `VaultManifest` 完整性校验；
  - 恢复时完整还原个人上下文与结果卡，自动将遗留的 `prepared` / `pending_confirm` / `executing` 动作降级为 `expired`，并兼容旧版（v1）保险箱的无损保留与覆盖提示。
- **证据**：
  - 合同套件：`ext.nexus.artifactActionsContract` **34/34**、`ext.nexus.personalContextSqlContract` **51/51**、`ext.nexus.memoryScopeContract` **28/28**、`ext.nexus.memoryKnowledgeContract` **12/12**、`ext.nexus.planProtocolContract` **228/228**、`ext.nexus.conversationResultsContract` **40/40**（`local/temp/ui-page-functions-verification-20261019.json`）。
  - 页面四态回归：`settings`、`extensions`、`data_management`、`artifact_center`、`data_backup` 在 `1.6x`、`2.0x`、`dark1.6x`、`landscapeDark1.6x` 下共 **20/20** 项全部 `overflowCount=0`、`uiErrors=0`（`local/temp/ui-page-functions-verification-20261019.json`）。
  - 静态分析：`local/temp/ui-page-functions-analyze-20261019.log`（`No issues found!`）。
