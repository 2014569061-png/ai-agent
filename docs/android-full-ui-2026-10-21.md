# Android 全页面风格统一验收

2026-10-21。沿用用户确认的蓝白、柔光、圆角分组风格。后续默认规范已写入根目录 `AGENTS.md` 与 [Android UI 规范](android-ui-style.md)。

## 本轮补齐

- 兼容公共组件的语义配色接入 `MobileTheme`，解决同一屏混用旧蓝色、灰底与新主题的问题。显式主色通过 `MobileTheme.brand(context)` 区分手机与桌面。
- 22 个共享视图中的旧几何改用手机/桌面分开的圆角选择器；清理任务详情的固定 12dp 卡片覆盖与重复玻璃操作栏。
- 终端使用统一手机页头、更多菜单、配置面板和辅助键，输出保留深色等宽画布。文件编辑器接入同一页面画布，保存、引用、跳行与未保存退出保护保留。
- 历史、提示词、个人上下文、全量搜索采用统一搜索框；保留查询、提交、清空及长度限制。
- 成果、研究、费用、搜索补齐统一空状态与重试。提示词读取失败现在有清晰的错误和重试入口。
- 指标页保留统计范围与数据质量结论，冗长定义、降级计数、关联细节可展开。引导与技能市场也使用统一画布。

## 验证范围与结果

- 手机页面文件 57 个，另含运行详情入口，共 58 个 Android 页面入口；桌面专用设置页不计入手机清单。
- 每个入口在 411×891 / 正常字号、360×891 / 1.6 倍字号下渲染，共 116 个页面样本。清单守卫和提示词失败→重试测试另计，总计 118 项清单测试。
- 使用内存数据库、隔离文件、测试浏览器画布，不发起模型请求、安装运行时或执行工作流。原生服务不可用时同时检查现有失败/未连接界面；这不是设备能力和 ARM64 运行时的功能验收。
- 全量静态检查通过（`No issues found`）。39 个相关测试文件共覆盖 433 项检查；初轮的两处旧视觉断言分别涉及旧主色与深色危险文字，更新后相关 7 项复测通过。业务回调、权限与执行策略未因样式修改而放宽。
- 页面的正常字号截图已按分组复查；窄屏大字体渲染无布局溢出。截图位于 `local/temp/android-ui-gallery/`，可通过清单测试重新生成。
- 已有 Android 模拟器实际复查首页、搜索、设备、外观、个人上下文、成果、项目、文件编辑器和终端，确认热重载成功。更早两轮的主要页面与二级页模拟器截图继续保留。

日志：`local/temp/full-ui-final-analyze.log`、`local/temp/full-ui-final-tests.log`、`local/temp/full-ui-corrected-tests.log`。这些是分层验证，不表示穷尽了每个原生服务、所有数据组合和全部异常状态。

## 页面入口登记

| 页面来源 / 入口 | 手机外观接入 | 渲染检查 |
| --- | --- | --- |
| `agents/agent_editor_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `agents/agents_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `artifacts/artifact_center_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `artifacts/research_artifacts_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `audit/audit_log_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `browser/browser_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `chat/chat_page.dart` | 对话专用布局，共享主题、消息与输入组件 | 正常 / 窄屏大字体通过 |
| `dashboard/cost_ledger_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `dashboard/dashboard_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `diagnostics/log_viewer_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `diagnostics/operational_metrics_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `diagnostics/run_analysis_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `feedback/feedback_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `history/history_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `jobs/jobs_inbox_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `knowledge/knowledge_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `mcp/mcp_servers_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `memory/memory_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `onboarding/onboarding_page.dart` | 共享主题与 MobileCanvas 嵌入视图 | 正常 / 窄屏大字体通过 |
| `plugins/plugins_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `plugins/skill_market_page.dart` | 共享主题与 MobileCanvas 嵌入视图 | 正常 / 窄屏大字体通过 |
| `projects/project_change_set_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `projects/project_git_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `projects/project_home_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `projects/project_picker_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `projects/remote_execution_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `projects/static_web_delivery_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `prompts/prompt_library_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `scheduled/scheduled_tasks_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `search/global_search_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/appearance_theme_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/data_backup_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/data_management_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/default_assistant_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/device_automation_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/device_backups_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/device_capabilities_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/extensions_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/language_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/linux_environment_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/model_list_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/personal_context_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/provider_detail_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/provider_list_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/provider_template_import_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/settings_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/system_editors_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/tool_list_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `settings/workspace_files_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `tasks/development_tasks_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `tasks/task_details_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `terminal/terminal_page.dart` | 统一页头与页面布局，深色终端画布 | 正常 / 窄屏大字体通过 |
| `vault/vault_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `workbench/session_workbench_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `workflows/mobile_workflows_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `workspace/development_workbench_page.dart` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |
| `workspace/workspace_editor_page.dart` | 统一页头与页面布局，等宽文件编辑区域 | 正常 / 窄屏大字体通过 |
| `diagnostics/run-detail` | 共享主题、页头、布局与内容/设置组件 | 正常 / 窄屏大字体通过 |

## 本轮模拟器截图

- [appearance](design-previews/android-full-2026-10-21/appearance.png)
- [artifacts](design-previews/android-full-2026-10-21/artifacts.png)
- [assistant](design-previews/android-full-2026-10-21/assistant.png)
- [device-capabilities](design-previews/android-full-2026-10-21/device-capabilities.png)
- [file-editor](design-previews/android-full-2026-10-21/file-editor.png)
- [global-search](design-previews/android-full-2026-10-21/global-search.png)
- [personal-context](design-previews/android-full-2026-10-21/personal-context.png)
- [project-home](design-previews/android-full-2026-10-21/project-home.png)
- [terminal](design-previews/android-full-2026-10-21/terminal.png)
