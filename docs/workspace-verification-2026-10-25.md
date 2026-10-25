# 工作区验证记录 · 2026-10-25

对应工作区整理与主分支源码同步。本次整理及首页编辑没有修改产品源码或测试文件；以下为本机实际检查结果，远程 CI 状态以 GitHub Actions 为准。

## 检查结果

| 检查 | 命令 / 方法 | 结果 |
|---|---|---|
| 静态分析 | `flutter analyze --no-pub` | 通过，无问题。 |
| 静默异常门禁 | `dart run tool/count_silent_catches.dart lib 0` | 通过，未记录意图的空 catch 为 0。 |
| 全量测试 | `flutter test --no-pub --coverage --reporter expanded` | 2,740 通过、69 失败，未全部通过。 |
| 覆盖率门禁 | `dart run tool/check_coverage.dart coverage/lcov.info 55.0` | 手写代码 59.55%（42,474 / 71,327），通过。 |
| 定向复测 | 下述 4 个文件，`--concurrency=1` | 56 项全部通过。 |
| 归档完整性 | 移动前后 SHA-256 | 45 个文件一致；操作后 1,715 个受保护文件一致。 |
| 页面检查 | Chrome，1440px / 390px，文件搜索 | 无页面横向溢出、无脚本异常，搜索可定位搬移后的覆盖率脚本。 |

## 全量失败与定向复测的区别

全量首轮的 69 个失败中，64 个与整理前 `local/review/full-test.txt` 的失败名称相同，见下表。另 5 个涉及符号索引、预览及 PRoot 样例，在处理测试环境并串行复测相关文件后通过。定向复测不能替代新的全量通过结果。

测试临时文件放在仓库内 `local/temp/` 时，没有独立 .git 的样例目录会向上发现主仓库，从而错误采用主仓库索引及忽略规则。通过设置 `GIT_CEILING_DIRECTORIES` 为该临时根目录阻止向上发现；该设置只用于测试进程，不修改产品行为。预览与 PRoot 失败串行复测通过，完整并发环境下仍需后续确认。

```powershell
$env:PUB_CACHE = Join-Path (Get-Location) 'local\pub-cache'
$env:TEMP = Join-Path (Get-Location) 'local\temp'
$env:TMP = $env:TEMP
$env:GIT_CEILING_DIRECTORIES = $env:TEMP
flutter test --no-pub --concurrency=1 --reporter expanded `
  test/agent_remaining_mechanisms_test.dart `
  test/repo_map_languages_test.dart `
  test/preview_service_test.dart `
  test/runtime_adapters_test.dart
```

### 与整理前记录一致的失败

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

合计 64 项，分布于 30 个测试文件；本轮没有通过删除测试、放宽断言或修改产品代码处理这些失败。

<details>
<summary>展开 64 项失败名称</summary>

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

## 验证范围

本次仅同步源码与文档。没有生成正式安装包发布验收证据；ARM64 真机、后台恢复、无障碍与性能等发布要求继续执行现有门禁。现有本机测试结果不能代表正式包或 GitHub Actions 已通过。

完整原始日志、盘点清单及移动哈希保存在 `local/review/workspace-tidy-2026-10-25/`，不上传公开仓库。测试正常重写的 hooks_runner 锁和输出元数据单列记录，SQLite 离线原生库本体保持完整。

[返回仓库首页](../README.md) · [文档分类](README.md) · [工作区约定](workspace-layout.md) · [HTML 整理报告](workspace-organization-2026-10-25.html)
