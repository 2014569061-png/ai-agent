# Android UI 精修交付 · 2026-10-23

本轮基于 `android-ui-gemini-followup-review.md` 中的问题做增量修正，沿用蓝白、柔光、实色圆角和左侧抽屉。保留工作区既有修改，不提交或发布。本记录描述本轮已完成的具体工作，不将页面渲染通过表述为所有功能已在真机验收。

## 改动与入口

| 范围 | 精修结果 | 入口与行为 |
| --- | --- | --- |
| 侧栏 | 三个紧凑主入口，最近会话前移；我的与助手工具固定页脚；搜索按需展开 | 助手、任务、工作区的索引和各自导航栈保留；我的仍是第四个目的地。完整历史通过“全部”进入；重命名、删除、置顶等原有历史操作保留 |
| 助手与工具 | 从侧栏打开独立底部面板，避免工具挤占会话空间 | Agent、模型与运行、MCP、提示词、运行与费用、会话工具全部可达；修复抽屉销毁后面板重建的上下文问题 |
| 模型与服务商 | 已配置项优先，一个添加入口；空列表一个主要动作 | 添加面板保留兼容 API、官方 API、模板和所有可用预设；配置编辑、激活和删除保留 |
| Agent 编辑 | 执行步数、Temperature、输出 Token、Top P 归入高级参数，并显示当前摘要 | 名称、角色与实际工具授权更早出现；原控制器、保存逻辑及工具权限不变 |
| 项目概览 | 手机侧边距 20dp，分组圆角 24dp；项目位置、环境和低频工具按需展开 | 概览 / 文件 / 终端 / 任务 / 产物五标签保留；复制路径、环境重试、能力安装、Git、变更集、远程连接与预览入口保留 |
| 工具权限 | 文件读写和终端执行标题缩短；长授权说明完整换行；自动验证与修复集中展开 | 不修改开关值、依赖关系、自动执行条件、写入审批或修复次数限制 |
| 网页交付与远程连接 | 可读错误、真实重试、可展开原始诊断；远程安装帮助折叠 | 没有新增同步或执行能力；连接接收方、凭证和确认条件仍在操作位置可见 |
| 运行详情 | 手机标题改为运行详情；先显示状态、Token、耗时、预计费用 | 原指标与 Run ID 进入用量性能明细；报告复制、导出及日志入口保留 |
| 设备能力 | 首屏显示真实检测时间，技术矩阵折叠；Root 授权说明完整换行 | 不再用 LIVE 暗示实时刷新；Root 检测仍须用户手动触发 |
| 终端 | 手机复杂状态移到正文，页头保留标题空间；状态触摸区至少 48dp | 原连接、终端画布、辅助键和生命周期保持原逻辑 |
| 帮助与设置 | 外观诊断、完整备份清单、模板示例、默认助手长隐私帮助按需展开 | 不改主题选择、备份调度、恢复确认、模板地址同意与默认助手系统操作 |
| 费用 | 保留预算与估算提醒，记录规则和运行 / 请求 / 尝试编号按需展开 | 费用未知、待确认占预算、人工核对和明确同意的语义保持；支持展开后横屏与大字体 |
| 搜索与反馈 | 空任务标题以自然中文回退，已知状态中文化；反馈按钮明确打开邮件草稿 | 原始 ID 保留在数据和详情；不更改用户正文或暗示反馈已发送 |

## 公共组件与后续规范

- `SettingsTile.wrapText` 为必要授权说明提供完整换行，默认不改变普通列表和桌面布局。
- 新增 `NexusErrorNotice`：可读原因、恢复操作、可选择复制的诊断详情。网页交付和远程连接已使用。
- `MobilePrimaryNavigation.destinations` 支持抽屉主体与页脚分组，默认目的地集合仍完整。
- 更新 `android-ui-style.md`，后续页面继续复用既有规范。原评审与 Gemini 进度文档保留为历史记录，以本记录说明本轮实际结果。

## 验证

- 19 个相关测试文件合并运行：**222 项通过**。包含 58 个入口的普通 411dp 与窄屏 360dp / 1.6 倍文字渲染，及导航、草稿、返回、键盘、项目、服务商、设备、终端、费用、备份与动效诊断回归。
- 费用页加强展开后布局与原始编号可达性断言，单独复跑 **11 项通过**，包含横屏、深色与 2 倍文字。仍保留真实的人工确认、费用持久化和隔离数据库断言。
- 新增或增强回归覆盖：抽屉关闭后面板重建与草稿保留、权限文字不被截断、错误重试与诊断展开、项目折叠后路径复制 / 环境恢复 / 工具入口。
- 修改涉及的 25 个代码与测试文件静态检查：**No issues found**。
- 现有 `Nexus_Preview_API_36` / `emulator-5554` 中核对实际页面及折叠交互，预览持续显示 `Hot reload complete`，未新建重复调试会话。

## 实际模拟器截图

以下为本轮 Android 调试应用截图，设备端保存 PNG 后用 ADB 拉取。配置项中未展示密钥；没有发送真实模型请求。

| 页面 / 状态 | 截图 |
| --- | --- |
| 侧栏 / 工具面板 | [侧栏](design-previews/android-refined-2026-10-23/sidebar.png)、[工具面板](design-previews/android-refined-2026-10-23/tools.png) |
| 服务商 / 添加方式 | [已配置列表](design-previews/android-refined-2026-10-23/providers.png)、[添加面板](design-previews/android-refined-2026-10-23/provider-add.png) |
| Agent 编辑 | [默认折叠](design-previews/android-refined-2026-10-23/agent-editor.png)、[参数展开](design-previews/android-refined-2026-10-23/agent-advanced.png) |
| 项目概览 | [首屏](design-previews/android-refined-2026-10-23/project.png)、[完整路径](design-previews/android-refined-2026-10-23/project-details.png)、[低频工具](design-previews/android-refined-2026-10-23/project-tools.png) |
| 权限 | [首屏](design-previews/android-refined-2026-10-23/permissions.png)、[自动验证与修复](design-previews/android-refined-2026-10-23/permissions-details.png) |
| 设备能力 | [检测时间与权限说明](design-previews/android-refined-2026-10-23/device.png) |
| 默认系统助手 | [摘要](design-previews/android-refined-2026-10-23/default-assistant.png)、[完整说明](design-previews/android-refined-2026-10-23/default-assistant-details.png) |
| 外观 | [诊断折叠](design-previews/android-refined-2026-10-23/appearance.png)、[诊断展开](design-previews/android-refined-2026-10-23/appearance-diagnostics.png) |
| 数据备份 | [首屏](design-previews/android-refined-2026-10-23/backup.png)、[完整清单](design-previews/android-refined-2026-10-23/backup-details.png) |

## 隔离测试截图与边界

116 张页面渲染图位于 `local/temp/android-ui-gallery/`，使用内存数据库和隔离样例。选摘：[运行详情](design-previews/android-refined-2026-10-23/test-run-detail.png)、[网页错误态](design-previews/android-refined-2026-10-23/test-web-error.png)、[远程连接](design-previews/android-refined-2026-10-23/test-remote.png)、[费用页](design-previews/android-refined-2026-10-23/test-cost.png)。这些不是实际账户或真实执行截图。

本轮没有执行真实收费模型任务、覆盖恢复、清除数据、Root 授权、连接电脑执行器或导出含密钥数据。ARM64 内置 Alpine / PRoot 仍需真机验证，x64 模拟器不替代。运行详情和错误态由隔离样例验证，不声称所有复杂状态均已在模拟器手动验收。既有 B2–B7 损坏截图没有改名或用概念图替换。
