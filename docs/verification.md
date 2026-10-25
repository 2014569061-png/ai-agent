# 验证状态

最近一次本机完整检查：2026-10-25。以下结果是开发基线，GitHub CI 的最新状态请查看 [Actions](https://github.com/2014569061-png/ai-agent/actions)。

| 检查 | 结果 |
|---|---|
| 静态分析 | flutter analyze --no-pub 无问题。 |
| 静默异常门禁 | 未记录意图的空 catch 为 0，通过。 |
| 全量测试 | 2,740 通过、69 失败，尚未全部通过。 |
| 定向复测 | 其中 5 个环境或并发相关失败所在的 4 个文件，串行复测 56 项全部通过。 |
| 手写代码覆盖率 | 59.55%（42,474 / 71,327），超过 55% 门槛。 |

仍有 64 项已知测试失败。定向复测不能代替新的全量通过结果；组件或模拟器检查也不能代替 ARM64 真机及正式安装包验收。

## 复现质量检查

```bash
flutter pub get
flutter analyze --no-pub
dart run tool/count_silent_catches.dart lib 0
flutter test --no-pub --coverage
dart run tool/check_coverage.dart coverage/lcov.info 55.0
```

Windows 上将测试临时文件保存在仓库内部时，需设置 GIT_CEILING_DIRECTORIES 为临时根目录，避免没有独立 .git 的样例错误发现父仓库。

```powershell
$env:TEMP = Join-Path (Get-Location) 'local/temp'
$env:TMP = $env:TEMP
$env:GIT_CEILING_DIRECTORIES = $env:TEMP
flutter test --no-pub --concurrency=1 test/agent_remaining_mechanisms_test.dart test/repo_map_languages_test.dart test/preview_service_test.dart test/runtime_adapters_test.dart
```

## 已知失败分布

| 测试文件 | 失败项数 |
|---|---|
| [a11y_compliance_test.dart](../test/a11y_compliance_test.dart) | 2 |
| [agent_loop_hooks_test.dart](../test/agent_loop_hooks_test.dart) | 1 |
| [agent_pause_interrupt_test.dart](../test/agent_pause_interrupt_test.dart) | 1 |
| [ambient_glow_test.dart](../test/ambient_glow_test.dart) | 1 |
| [approval_mode_selection_test.dart](../test/approval_mode_selection_test.dart) | 1 |
| [background_execution_gateway_test.dart](../test/background_execution_gateway_test.dart) | 3 |
| [chat_mode_test.dart](../test/chat_mode_test.dart) | 2 |
| [code_quality_guard_test.dart](../test/code_quality_guard_test.dart) | 1 |
| [composer_skill_slot_test.dart](../test/composer_skill_slot_test.dart) | 2 |
| [dashboard_service_test.dart](../test/dashboard_service_test.dart) | 3 |
| [data_maintenance_chat_test.dart](../test/data_maintenance_chat_test.dart) | 3 |
| [deep_link_and_shortcuts_test.dart](../test/deep_link_and_shortcuts_test.dart) | 1 |
| [deepseek_style_bubble_test.dart](../test/deepseek_style_bubble_test.dart) | 1 |
| [desktop_command_center_test.dart](../test/desktop_command_center_test.dart) | 2 |
| [desktop_compact_layout_test.dart](../test/desktop_compact_layout_test.dart) | 2 |
| [desktop_jobs_strip_test.dart](../test/desktop_jobs_strip_test.dart) | 2 |
| [headless_session_log_test.dart](../test/headless_session_log_test.dart) | 4 |
| [input_tool_grid_sheet_test.dart](../test/input_tool_grid_sheet_test.dart) | 1 |
| [liquid_glass_multi_page_test.dart](../test/liquid_glass_multi_page_test.dart) | 3 |
| [message_bubble_semantics_test.dart](../test/message_bubble_semantics_test.dart) | 1 |
| [mobile_metrics_widget_test.dart](../test/mobile_metrics_widget_test.dart) | 7 |
| [nexus_components_test.dart](../test/nexus_components_test.dart) | 1 |
| [session_log_test.dart](../test/session_log_test.dart) | 1 |
| [static_web_delivery_page_test.dart](../test/static_web_delivery_page_test.dart) | 2 |
| [task_feedback_service_test.dart](../test/task_feedback_service_test.dart) | 1 |
| [ui_edge_states_test.dart](../test/ui_edge_states_test.dart) | 2 |
| [ui_foundation_touch_test.dart](../test/ui_foundation_touch_test.dart) | 4 |
| [ui_refactor_regression_test.dart](../test/ui_refactor_regression_test.dart) | 6 |
| [verification_repair_and_git_test.dart](../test/verification_repair_and_git_test.dart) | 1 |
| [wired_pages_smoke_test.dart](../test/wired_pages_smoke_test.dart) | 2 |

<details>
<summary>查看 64 项已知失败名称</summary>

- `a11y_compliance_test.dart`：A11y Compliance Tests NexusPageHeader back button satisfies >= 48dp touch constraints
- `a11y_compliance_test.dart`：A11y Compliance Tests empty chat actions expose labels to screen readers
- `agent_loop_hooks_test.dart`：an external continuation is asked before steering seals the run
- `agent_pause_interrupt_test.dart`：paused composer shows stop and resume side by side at 320dp
- `ambient_glow_test.dart`：空状态页挂载了光晕，且在内容之下
- `approval_mode_selection_test.dart`：approval strategy can be changed from the tools sheet
- `background_execution_gateway_test.dart`：a lost workspace lease cancels the live run immediately
- `background_execution_gateway_test.dart`：consecutive heartbeat failures cancel the live run
- `background_execution_gateway_test.dart`：gateway occupies workspace lease for a live task and releases it
- `chat_mode_test.dart`：composer exposes the full access approval mode entry
- `chat_mode_test.dart`：top bar prioritizes model and mode; workspace and context stay in tooltip
- `code_quality_guard_test.dart`：presentation token escape counts do not grow
- `composer_skill_slot_test.dart`：ChatPage 输入区：技能条不超过一条 空闲时只显示会话详情摘要，完整信息按需展开
- `composer_skill_slot_test.dart`：ChatPage 输入区：技能条不超过一条 运行中只显示运行详情摘要，让出输入区上方空间
- `dashboard_service_test.dart`：aggregates pending todos for approvals, plans, and recoverable tasks
- `dashboard_service_test.dart`：correctly aggregates today stats, weekly token trend, and task success rate
- `dashboard_service_test.dart`：loads summary from empty database
- `data_maintenance_chat_test.dart`：real ChatController SSE cancellation and clear refresh
- `data_maintenance_chat_test.dart`：real ChatController SSE cancellation and refreshFailure refresh
- `data_maintenance_chat_test.dart`：real ChatController SSE cancellation and restore refresh
- `deep_link_and_shortcuts_test.dart`：DeepLinkService 解析 只通知已识别入口，消费后可再次接收同一个热链接
- `deepseek_style_bubble_test.dart`：assistant reply is plain text with a muted meta action row
- `desktop_command_center_test.dart`：命令按分组展示，输入过滤后用键盘执行
- `desktop_command_center_test.dart`：输入关键词检索会话与任务并跳转
- `desktop_compact_layout_test.dart`：desktop explains modes, approval and focused keyboard shortcuts
- `desktop_compact_layout_test.dart`：inline mode selection preserves plan warning, running lock and session menu
- `desktop_jobs_strip_test.dart`：只有待处理任务时状态条显示待处理计数
- `desktop_jobs_strip_test.dart`：有进行中任务时显示状态条，点击展开浮层面板
- `headless_session_log_test.dart`：a task-bound background run is recorded under task:<id>
- `headless_session_log_test.dart`：deleting a task removes its session log
- `headless_session_log_test.dart`：repeated runs of the same task append to one session
- `headless_session_log_test.dart`：runs without a task or with a non-recording profile write nothing
- `input_tool_grid_sheet_test.dart`：首页输入区保留审批入口，不重复模式与高级选项
- `liquid_glass_multi_page_test.dart`：NexusBackground liquid glass behavior keeps the quiet phone canvas when material effects are flat
- `liquid_glass_multi_page_test.dart`：NexusBackground liquid glass behavior renders gradient when glass intensity is liquid
- `liquid_glass_multi_page_test.dart`：NexusSheet liquid glass integration opens sheet with LiquidGlass in liquid mode
- `message_bubble_semantics_test.dart`：desktop groups regenerate with reply actions without moving mobile actions
- `mobile_metrics_widget_test.dart`：diagnostics navigation keeps the injected database and isolates chat initialization
- `mobile_metrics_widget_test.dart`：metrics layout 360.0/800.0/1.6/Brightness.dark
- `mobile_metrics_widget_test.dart`：metrics layout 360.0/800.0/1.6/Brightness.light
- `mobile_metrics_widget_test.dart`：metrics layout 360.0/800.0/2.0/Brightness.light
- `mobile_metrics_widget_test.dart`：metrics layout 640.0/360.0/1.6/Brightness.dark
- `mobile_metrics_widget_test.dart`：read failures do not become zero metrics or expose error bodies
- `mobile_metrics_widget_test.dart`：target validation, explicit application and safe controller disposal
- `nexus_components_test.dart`：chat empty state renders only brand mark and greeting
- `session_log_test.dart`：model-visible means logged steering and executor-injected messages are captured
- `static_web_delivery_page_test.dart`：an edit after review cannot silently publish and refresh recovers
- `static_web_delivery_page_test.dart`：edit, review, save and retain an immutable ZIP through production services
- `task_feedback_service_test.dart`：v18 到 v19 创建 task_feedback 表并保留既有数据
- `ui_edge_states_test.dart`：empty state can scroll to its action in short large-text layouts in both themes
- `ui_edge_states_test.dart`：task filters distinguish zero matches and restore existing tasks at double text scale
- `ui_foundation_touch_test.dart`：settings back hit region dark=false scale=1.0
- `ui_foundation_touch_test.dart`：settings back hit region dark=false scale=2.0
- `ui_foundation_touch_test.dart`：settings back hit region dark=true scale=1.0
- `ui_foundation_touch_test.dart`：settings back hit region dark=true scale=2.0
- `ui_refactor_regression_test.dart`：ProviderListPage empty state layout tests ProviderListPage empty state has no overflow at 360.0x800.0 with textScale 1.3
- `ui_refactor_regression_test.dart`：ProviderListPage empty state layout tests ProviderListPage empty state has no overflow at 390.0x844.0 with textScale 1.3
- `ui_refactor_regression_test.dart`：Touch target size regression tests (>= 48x48) CapsuleTopBar drawer and new chat buttons have at least 48x48 touch targets
- `ui_refactor_regression_test.dart`：Touch target size regression tests (>= 48x48) FloatingCapsuleInput attachment and send buttons have at least 48x48 touch targets
- `ui_refactor_regression_test.dart`：Touch target size regression tests (>= 48x48) running input exposes stop through a long press on pause
- `ui_refactor_regression_test.dart`：Touch target size regression tests (>= 48x48) 审批磁贴在左侧，附件与发送磁贴在右侧，且窄屏不溢出
- `verification_repair_and_git_test.dart`：artifact records persist by project and round-trip inspection
- `wired_pages_smoke_test.dart`：KnowledgePage 空库渲染空态
- `wired_pages_smoke_test.dart`：SettingsPage 入口接线 通过数据管理入口行都能推入对应页面

</details>

## 发布验收

正式 APK 继续执行 tool/release_evidence_gate.py；缺失证据不能计为通过。ARM64、后台恢复、无障碍与性能需要按对应发布目标验收。本次源码与文档整理没有生成新的正式安装包验收结论。

[安全与发布边界](security.md) · [开发与构建](getting-started.md)
