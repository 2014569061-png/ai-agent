# Windows 桌面实际运行验收记录（2026-10-16）

## 结论：部分检查完成，整体验收阻塞

**不是“全页面通过”。** 当前源码已成功进行 Windows Debug 构建并启动真实窗口；已进入并目视检查 **13 个不同页面/视图**，涉及原清单 14 个入口文件（SettingsPage 委托桌面分类设置，不重复计算视图）。其余 32 个入口未进入。

已查看画面暂未发现明显的文字溢出或操作遮挡，但运行日志出现布局异常和 Windows 无障碍树更新错误，因此暂停继续点页。**不能将静态截图正常等同于运行时没有问题；也尚不能确定这些错误的具体页面归属或共同根因。**

**后续更新：** 两处应用缺陷已确认并修复；独立 Flutter Slider 新路由仍可复现原生 AXTree 错误，整体验收继续阻塞。下文先保留首次现场，最新证据见文末续记。

## 首次现场的环境和真实运行证据（修复前）

- 目标是当前远程项目 `mobile_agent`，不是沙盒副本、Web 预览或 WidgetTester 夹具。
- 启动前检测到 Windows x64 桌面设备；`mobile_agent` 运行实例数为 0。
- 命令：`/c/src/flutter/bin/flutter run -d windows --debug --no-pub`。
- 构建成功，工具报告构建耗时 268.4 秒；生成 `build/windows/x64/runner/Debug/mobile_agent.exe`，非旧 Profile/Release 产物。
- 实际窗口标题 `NEXUS Agent`，本轮 PID 51956；Impeller / OpenGLESSDF。
- 外窗截图 1920×1200 物理像素；DPR 1.5；实际客户区 1898×1144，约 1265.3×762.7 逻辑像素。尚未进行紧凑窗、深色或大字号的本机切换验收。
- `artifacts/desktop-live/*.png` 是使用 Win32 PrintWindow 针对本项目窗口获取的真实运行截图；不抓取整块显示器或其他应用。
- 窗口探针 `artifacts/desktop-live/probe.ps1` 校验当前 Debug 可执行文件和 PID。原生点击/滚轮仅投递到该窗口的 Flutter 子窗口，并在操作前校验目标附近的截图像素与参考图一致；不使用全局鼠标点击。

## 实际进入范围

以下“已目视”仅针对本轮显示的状态和尺寸，不代表页面全部业务操作、权限路径或异常状态通过。

| 入口（相对 lib/presentation） | 现场状态 | 证据及边界 |
|---|---|---|
| `agents/agent_editor_page.dart` | 已进入 / 当前截图已目视 | `agent-editor.png`；空白新建表单和侧栏摘要；未输入或保存，返回后资源数量不变 |
| `agents/agents_page.dart` | 已进入 / 当前截图已目视 | `agents.png`；已有资源卡片、操作区和阅读宽度；未生成草稿或改权限 |
| `audit/audit_log_page.dart` | 已进入 / 当前截图已目视 | `audit.png`；空态、已关闭审计状态；未切换审计开关 |
| `chat/chat_page.dart` | 已进入 / 当前截图已目视 | `startup.png`；现有会话、中文字体、输入区、状态栏；未发送消息 |
| `dashboard/dashboard_page.dart` | 已进入 / 当前截图已目视 | `dashboard.png`；实际仪表盘、统计卡片和用量显示；不是长任务执行验证 |
| `diagnostics/log_viewer_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `diagnostics/run_analysis_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `feedback/feedback_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `history/history_page.dart` | 已进入 / 当前截图已目视 | `history.png`；现有记录、时间分组和筛选入口；未改收藏或置顶 |
| `jobs/jobs_inbox_page.dart` | 已进入 / 当前截图已目视 | `jobs.png`；收件箱现有记录、待处理数；未点开或标记已读 |
| `knowledge/knowledge_page.dart` | 已进入 / 当前截图已目视 | `knowledge.png`；空态、筛选和现有开关状态；未导入文档或改开关 |
| `mcp/mcp_servers_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `memory/memory_page.dart` | 已进入 / 当前截图已目视 | `memory.png`；空态、筛选和现有开关状态；未添加或改开关 |
| `onboarding/onboarding_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `plugins/plugins_page.dart` | 已进入 / 当前截图已目视 | `plugins.png`；声明式插件空态和导入入口；未导入插件 |
| `plugins/skill_market_page.dart` | 已进入 / 当前截图已目视 | `skill-market-bottom.png`；10 个内置技能，实际滚动至末项；未解析 GitHub 仓库或改启用状态 |
| `projects/project_change_set_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `projects/project_git_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `projects/project_home_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `projects/project_picker_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `projects/remote_execution_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `prompts/prompt_library_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `scheduled/scheduled_tasks_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `settings/appearance_theme_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `settings/data_backup_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `settings/data_management_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `settings/desktop_settings_page.dart` | 已进入 / 当前截图已目视 | `settings.png`；桌面分类导航与默认分类内容；其余分类尚未逐项进入 |
| `settings/device_automation_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `settings/device_backups_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `settings/device_capabilities_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `settings/extensions_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `settings/language_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `settings/linux_environment_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `settings/model_list_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `settings/provider_detail_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `settings/provider_list_page.dart` | 已进入 / 当前截图已目视 | `providers.png`；现有配置和内置模板列表；未编辑、切换默认项或测试连接 |
| `settings/settings_page.dart` | 已进入 / 当前截图已目视 | `settings.png`；已进入；本机桌面分派到 DesktopSettingsPage，与该视图不重复计数 |
| `settings/tool_list_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `settings/workspace_files_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `tasks/development_tasks_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `tasks/task_details_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `terminal/terminal_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `vault/vault_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `workbench/session_workbench_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `workspace/development_workbench_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |
| `workspace/workspace_editor_page.dart` | 未进入 | 继续验收前先分离复现运行异常 |

## 额外已检查的真实操作

- 五个主导航之间切换成功：会话、工作台、历史、任务、审计。
- 资源页进入/返回；Agent 新建表单未输入、未保存即返回，原有资源仍保持。
- 技能市场实际滚轮滚动到最后一项 `technical-writing`，顶部仓库输入区保持可用；这里只验证现有内置列表，不是下载、安装或远程仓库能力验证。
- 已返回原来的会话界面；待处理数量仍为 2，未点开收件箱记录、未标记已读。

## 运行日志发现：待分离复现，不能忽略

捕获日志见 `artifacts/desktop-live/runtime-errors.log`。本轮退出前完整捕获 20,348 字节的 Flutter 启动/运行输出，工具未报告丢失输出。以下是该段日志的重复条目计数，**不是独立缺陷数量**：

1. `Vertical viewport was given unbounded height`：1 条。
2. `RenderBox was not laid out`：24 条，涉及同一批级联布局错误。
3. `sliver_multi_box_adaptor.dart` 中 `child.hasSize` 断言失败：日志中出现。
4. `Null check operator used on a null value`：4 条。
5. Windows 原生 `Failed to update ui::AXTree`：73 条。

重要调查条件：

- 本机 UI Automation 初始仅暴露一个 `FLUTTERVIEW` 容器，没有可调用的页面子控件。
- 本轮曾调用 Windows MSAA `AccessibleObjectFromWindow`；接口返回成功，后续渲染树确认 `semantics enabled`。因此必须区分“不触发辅助功能的普通启动”和“请求辅助功能后的导航”两条路径。
- **尚未证明辅助功能请求是布局异常的原因，也未证明普通启动必现；布局错误与 AXTree 错误是否同因未知。** 不应把探针自身与应用代码、Flutter Windows 引擎兼容性混为一谈。
- 暂停时通过 VM Service 读取当前渲染树，保存为 `artifacts/desktop-live/render-tree.json`（约 11.9MB）。此时树中已无此前的 `RenderViewport#c3af5`，也没有 `size: MISSING`，所以还没有锁定异常的瞬时调用链；不能据此宣布错误已修复。
- 第三方 WebView 插件还输出 CMake CMP0175 开发警告，但构建成功；该警告未被认定为上述运行异常的根因。

## 首次现场的数据、源码与退出状态（修复前）

- 未在应用内发送模型消息、运行任务或执行终端命令；未测试 API/MCP 连接、导入文件、保存表单、备份恢复或切换权限/审计/技能开关。
- 只进行了页面浏览、返回和列表滚动；应用正常启动、加载和导航仍可能按原有实现更新内部运行元数据，不声称数据库字节完全不变。
- 未修改 Dart/C++ 业务源码；本轮新增验收探针、现场产物和此记录。既有未提交改动保留，未重置或提交 Git。
- 前轮 77 个文件 / 406 项测试通过仍是前轮证据；本轮未重跑，也不能用它替代这次现场错误的复现与修复。
- 已用本轮 `flutter run` 的 `q` 正常退出；工具返回 `Application finished`、退出码 0，并按原 PID 确认进程已退出。只关闭本轮启动的 Debug 实例。

## 首次现场建议（执行进展见下方续记）

1. 先建立普通启动与辅助功能触发的对照复现，提前捕获首个完整 Flutter 错误事件，确定具体页面及约束来源。
2. 如果属于应用布局，添加对应数据状态与 semantics 路径的回归再做最小修复；若属于引擎或探针兼容性，分开记录，不盲改公共布局或降低测试。
3. 在受影响路径真实窗口复验并确认没有新增错误后，再继续其余 32 个入口及需要真实设备、数据、网络或写入行为的操作。

## 后续复现与修复续记

完整记录：[Windows 运行异常修复与 SDK 隔离](ui-runtime-repair-2026-10-16.md)。

- 已修复启动 binding/runApp 的 Zone 不一致，以及 AgentEditor pending 工具骨架嵌套 ListView 的高度约束；未修改编辑器业务流程。
- 新增 6 项回归，含明确关闭/开启 semantics、有界根骨架、桌面/移动 pending→loaded；最终 79 个选定文件共 413 项通过，静态分析与 diff-check 通过。
- 修复后两次全新正常入口运行不再出现 Zone 或布局级联，但编辑页仍有原生 AXTree 错误；不主动请求 UIA/MSAA 也可发生。之后单独请求两接口没有新增日志，不代表树健康。
- 在无业务导入/数据库的独立标准 Flutter Slider 入口，同一 SDK 的首页正常、推入 Slider 路由即复现同类 AXTree 错误，与上游 #190357 一致；不能再把全部 AX 错误归为加载骨架级联。
- 正常应用入口已重新构建恢复，所有自启实例均已正常退出，最终进程数为 0。未升级全局 SDK、关闭语义或保存业务表单。
- **13 个不同业务视图、32 个入口待进入的统计不变；无障碍兼容问题仍阻塞整体验收，等待选择后续路线。**
