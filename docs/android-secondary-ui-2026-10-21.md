# Android 二级页面蓝白风格补齐

日期：2026-10-21。

本轮沿用已落地首页的蓝白、柔光、圆角分组风格，继续适配其他 Android 页面。对 40 个二级页面文件作了直接修改，其余页面通过共享主题、设置组件、页头、列表、卡片和弹层继承同一套外观。未把手机切换为桌面布局。

## 页面与组件覆盖

| 范围 | 本轮调整 |
| --- | --- |
| 模型服务、服务商详情、模型选择、配置导入 | 统一表单、圆角分组、按钮、列表与详情页头；保留配置校验和导入确认 |
| Agent 列表、创建、编辑、描述生成 | 移除列表的重玻璃和创建按钮渐变光晕，统一编辑分组和输入控件 |
| 记忆、知识库、个人上下文 | 统一搜索框，支持大字体自然增高；启用状态与数据说明继续可见 |
| MCP、技能、插件 | 统一服务列表和配置弹层；技能页使用蓝色选中页签，内置技能说明与名称默认折叠 |
| 提示词、工作流、定时任务 | 统一卡片、输入区、动作按钮与状态；定时任务创建按钮收敛为单色 |
| 项目详情、Git、变更集、开发工作台 | 手机控件与表面统一圆角，保留原有差异、恢复、验证和运行入口 |
| 终端与辅助键 | 统一手机控制键外观；修复边框挤占空间导致的触摸高度不足，保持至少 48dp |
| 成果、研究、预览交付、远程验证 | 使用同一页头和卡片规范，保持实际成果与诊断状态 |
| 用量、费用、指标、运行分析、日志、审计 | 数据卡片改为实色白底，保留时间范围、未知值与可展开细节 |
| 设备、权限、备份、保险箱、系统助手 | 通过 SettingsGroupCard / SettingsTile 统一为白色圆角分组、清晰图标与列表 |
| 外观、语言、引导、反馈 | 统一表单、按钮、确认弹窗与页面背景 |
| 会话工具箱 | 手机端改为可滚动具名列表，保留每项实际回调和审批入口；桌面保留原布局分支 |
| 模型选择、计划、审批、会话抽屉等公共组件 | 调整手机圆角与表面；保留完整命令、风险说明、确认与拒绝操作 |

主要公共修改包括 `MobileTheme`、`SettingsGroupCard`、`SettingsSectionTitle`、`SettingsTile`、`NexusSurface`、`NexusMetricTile`，以及新增的 `NexusSearchField`。

按钮、输入框、菜单、对话框、筛选、分组和浮层使用统一手机主题。桌面仍走现有 DesktopTheme 分支。没有变更业务执行、权限、终端审批、数据备份或模型调用策略。

## 验证

- `flutter analyze --no-pub`：通过，No issues found。
- 31 个相关测试文件，231 项测试全部通过。
- 另对最后调整的技能页和页签进行了静态检查与模拟器展开/收起检查。
- 覆盖手机导航、窄屏大字体、深浅色、设置入口、数据读取、Agent 草稿、MCP 配置、滚动工具箱、审批、附件、项目、终端、浏览器、费用与指标等。
- 模拟器：`Nexus_Preview_API_36`，实际序列号 `emulator-5554`。
- 预览进程保持运行，已确认成功热重载。

日志：`local/temp/secondary-ui-final-analyze.log`、`local/temp/secondary-ui-final-tests.log`。工作区已有的其他未提交工作未被重置。

## 实际模拟器截图

- [扩展与环境](design-previews/android-secondary-2026-10-21/extensions.png)
- [模型提供商](design-previews/android-secondary-2026-10-21/providers.png)
- [Agent 列表](design-previews/android-secondary-2026-10-21/agents.png)
- [Agent 编辑](design-previews/android-secondary-2026-10-21/agent-editor.png)
- [记忆](design-previews/android-secondary-2026-10-21/memory.png)
- [知识库](design-previews/android-secondary-2026-10-21/knowledge.png)
- [数据管理](design-previews/android-secondary-2026-10-21/data-management.png)
- [MCP](design-previews/android-secondary-2026-10-21/mcp.png)
- [MCP 配置面板](design-previews/android-secondary-2026-10-21/mcp-form.png)
- [插件](design-previews/android-secondary-2026-10-21/skills.png)
- [技能市场](design-previews/android-secondary-2026-10-21/skill-market.png)
- [内置技能说明展开](design-previews/android-secondary-2026-10-21/skill-market-expanded.png)
- [提示词](design-previews/android-secondary-2026-10-21/prompts.png)
- [工作流](design-previews/android-secondary-2026-10-21/workflows.png)
- [定时任务](design-previews/android-secondary-2026-10-21/scheduled.png)
- [数据备份](design-previews/android-secondary-2026-10-21/backup.png)

这些是现有模拟器的实际页面，不是生成的概念图。查看配置时未保存新 Agent、MCP、任务或备份，也未发起新的模型请求。ARM64 专用运行时的真机验证不在本轮 UI 验收范围内。
