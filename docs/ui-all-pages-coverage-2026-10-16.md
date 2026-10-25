# 全页面 UI 优化覆盖清单（2026-10-16）

## 范围与边界

- 桌面端和手机端；延续蓝色专业风格。
- 清单来自 `lib/presentation`：46 个 `*page.dart` 页面入口、20 个弹层/对话框文件（其中包含弹层基础组件）。
- 保留功能、数据、授权、主要操作路径及现有未提交改动。
- **覆盖清单不是“所有运行状态已人工验收”的声明**：逐页源码检查与公共组件接入可确认；设备权限、真实网络、真实设备、长列表和复杂任务的运行态仍须按场景验收。

## 公共改动

- 普通页面按桌面 1240 / 手机和平板 760 逻辑像素约束最大阅读宽度；短表单桌面 920，并避让底部与横屏安全区；不改变页面原有滚动控制器和业务操作。
- 聊天、终端、编辑器、引导、桌面分类设置保留其专用布局，避免把所有界面机械套成一列。
- 二级标题提供完整提示和标题语义；放大字号时收起副标题，避免固定顶栏被挤爆。
- 移动端按钮主题最小 48dp，桌面继续紧凑；按钮统一 Inter 与中文回退链；双端表单错误/说明最多三行。
- 设置行大字号支持两行，尾部状态按宽度裁切，不与标题抢占固定 150dp。
- 桌面资源卡片宽屏把操作放在右侧；窄窗口、大字号和带复杂内容时恢复上下布局。
- 弹层根据键盘和安全区收紧最大高度；桌面使用清晰面板，手机保留用户的材质偏好。

## 页面覆盖（逐页源码检查）

| 页面路径（相对于 lib/presentation） | 本轮接入方式 |
|---|---|
| `agents/agent_editor_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `agents/agents_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `audit/audit_log_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `chat/chat_page.dart` | 保留专用聊天阅读列；复用双端主题及统一弹层 |
| `dashboard/dashboard_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `diagnostics/log_viewer_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `diagnostics/run_analysis_page.dart` | 接入自适应页面布局；核心指标改为自适应列数与自然高度，放大字号不依赖固定纵横比 |
| `feedback/feedback_page.dart` | 短表单阅读列；增加邮件提交说明、问题描述引导、联系信息隐私提示与触屏主按钮 |
| `history/history_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `jobs/jobs_inbox_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `knowledge/knowledge_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `mcp/mcp_servers_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `memory/memory_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `onboarding/onboarding_page.dart` | 保留引导专用布局；统一按钮、表单及触屏尺寸 |
| `plugins/plugins_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `plugins/skill_market_page.dart` | 嵌入插件页；复用父页面布局、公共表单与主题 |
| `projects/project_change_set_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `projects/project_git_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `projects/project_home_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `projects/project_picker_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `projects/remote_execution_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `prompts/prompt_library_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `scheduled/scheduled_tasks_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `settings/appearance_theme_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `settings/data_backup_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `settings/data_management_page.dart` | 短阅读列；数据入口复用 SettingsTile，统一标题、尾部计数、触屏高度及大字号布局 |
| `settings/desktop_settings_page.dart` | 保留分类导航双栏；公共主题、表单与资源页面联动 |
| `settings/device_automation_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `settings/device_backups_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `settings/device_capabilities_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `settings/extensions_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `settings/language_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `settings/linux_environment_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `settings/model_list_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `settings/provider_detail_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `settings/provider_list_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `settings/settings_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `settings/tool_list_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `settings/workspace_files_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `tasks/development_tasks_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `tasks/task_details_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `terminal/terminal_page.dart` | 保留终端全宽画布；复用主题、控件与弹层 |
| `vault/vault_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `workbench/session_workbench_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `workspace/development_workbench_page.dart` | 接入自适应页面布局；保留原有滚动、筛选与操作 |
| `workspace/workspace_editor_page.dart` | 保留代码编辑画布；复用标题、表单与状态样式 |

## 弹层与对话框检查清单

- `branches/branch_tree_sheet.dart`：复用 showNexusSheet 的宽度、键盘与材质适配。
- `chat/widgets/environment_sheet.dart`：保留专用容器；通过双端表单、按钮和对话框主题统一。
- `chat/widgets/input_tool_grid_sheet.dart`：复用 showNexusSheet；工具网格按宽度与字号调整列数，受限高度时滚动；保留全部工具与回调，补充关闭提示。
- `chat/widgets/model_picker_sheet.dart`：保留专用容器；通过双端表单、按钮和对话框主题统一。
- `chat/widgets/session_configuration_sheet.dart`：保留专用容器；通过双端表单、按钮和对话框主题统一。
- `chat/widgets/session_metrics_sheet.dart`：复用 showNexusSheet 的宽度、键盘与材质适配。
- `chat/widgets/tool_approval_sheet.dart`：保留专用容器；通过双端表单、按钮和对话框主题统一。
- `navigation/desktop_devices_dialog.dart`：保留专用容器；通过双端表单、按钮和对话框主题统一。
- `navigation/desktop_run_dialog.dart`：保留专用容器；通过双端表单、按钮和对话框主题统一。
- `navigation/desktop_task_result_dialog.dart`：保留专用容器；通过双端表单、按钮和对话框主题统一。
- `navigation/desktop_workflows_dialog.dart`：保留专用容器；通过双端表单、按钮和对话框主题统一。
- `presets/run_presets_sheet.dart`：复用 showNexusSheet 的宽度、键盘与材质适配。
- `projects/install_job_sheet.dart`：保留专用容器；通过双端表单、按钮和对话框主题统一。
- `settings/device_action_confirm_sheet.dart`：复用 showNexusSheet 的宽度、键盘与材质适配。
- `settings/update_sheet.dart`：保留专用容器；通过双端表单、按钮和对话框主题统一。
- `tasks/collaboration_plan_sheet.dart`：保留专用容器；通过双端表单、按钮和对话框主题统一。
- `widgets/nexus_action_sheet.dart`：复用 showNexusSheet 的宽度、键盘与材质适配。
- `widgets/nexus_sheet.dart`：复用 showNexusSheet 的宽度、键盘与材质适配。
- `workspace/file_tree_sheet.dart`：复用 showNexusSheet 的宽度、键盘与材质适配。
- `workspace/terminal_sheet.dart`：复用 showNexusSheet 的宽度、键盘与材质适配。

## 验收维度

自动检查和代表性截图分别记录，不把编译通过当成视觉验收。测试覆盖：双端主题、设置、资源页、列表、任务、项目、审批、弹层、输入法、文本选择、紧凑窗口与放大字号。

建议人工补验：手机键盘与横屏、真实 Android 权限/设备列表、API 连接失败、长任务执行状态、备份恢复和大数据量列表；未执行发布构建、未提交 Git。

## 本轮实际验证结果

- `dart format --output=none --set-exit-if-changed`：本轮 51 个 Dart 文件检查通过，0 个待格式化文件。
- `flutter analyze --no-pub`：整个项目 **No issues found**。
- `git --no-pager diff --check`：退出码 0；仅有当前工作区既有的 LF→CRLF 提示。保留了此前未提交的改动；未重置或提交 Git。
- 跨模块回归：**76 个测试文件、394 项测试全部通过**，不是整个仓库所有测试的声明。
- 新增 `test/nexus_all_pages_layout_test.dart` 的 10 项检查：46 页普通布局/专用布局覆盖守卫；桌面/平板/手机宽度和滚动；320px 双倍字号设置行；标题返回和大字号；资源卡片操作；键盘弹层；自适应指标网格；窄屏双倍字号带键盘工具箱的滚动与审批回调；双端表单校验文本；手机二级页双主题截图。
- 更新设置回归：按具体权限行验证工作区/终端独立开关、禁用关系和持久化；先滚动再断言懒加载工具行，保留危险筛选断言。没有为通过测试移除功能检查。
- 本轮回归覆盖：桌面导航/资源管理/工作台/终端/项目/Git；任务与会话；设备与 Linux 环境；设置/供应商；审批/分支/文件树/工具箱/模型选择/指标弹层；文本选择与长按；主题、动效和无障碍语义等。

## 当前截图与目视检查

- 手机端 390×844 逻辑像素、2 倍输出；使用实际页面、生产背景容器和已注册字体，避免透明底变黑或测试字体缺字造成假问题：
  - `artifacts/ui-all-pages/mobile-language-light.png`
  - `artifacts/ui-all-pages/mobile-language-dark.png`
  - `artifacts/ui-all-pages/mobile-feedback-light.png`
  - `artifacts/ui-all-pages/mobile-feedback-dark.png`
- 桌面端重新生成资源页及主工作台夹具截图。已目视检查以下 1440×900 页面：
  - `artifacts/desktop/deep-agents-light.png`
  - `artifacts/desktop/deep-knowledge-light.png`
  - `artifacts/desktop/deep-mcp-dark.png`
  - `artifacts/desktop/deep-provider-editor-dark.png`
- 上述为当前代码的隔离数据界面截图，不是实际联网或真实设备运行证明；其余渲染产物不等同于已逐张人工验收。
- **仍需人工/真实环境确认**：实际手机键盘与横屏、Android 权限和设备列表、真实 API 连接/失败、长任务执行态、备份恢复、大数据量列表及发布包。当前未执行发布构建，也未声称这 46 页的每种运行状态均已人工通过。

## 后续复杂状态补强

已完成公共空态、刷新/部分失败、长任务筛选与减少动效的后续补强。最新跨模块回归为 **77 个文件、406 项测试通过**；前述 76/394 为全页面适配阶段记录。范围、12 项新增检查与真实环境边界见 [复杂状态 UI 补强记录](ui-complex-states-2026-10-16.md)。


## 后续 Windows 现场验收（部分完成，阻塞）

已使用当前源码成功构建并启动 Windows Debug 真实窗口，目视检查 13 个不同页面/视图。运行日志发现布局及 Windows 无障碍树错误，尚未分离复现其页面归属和根因，因此不是全页面通过。剩余入口、具体截图、工具触发条件和退出状态见 [桌面实际运行验收记录](ui-desktop-live-2026-10-16.md)。本段更新的是后续现场状态，不把此前隔离截图追认为实机验收。
