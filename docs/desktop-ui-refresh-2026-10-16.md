# NEXUS 桌面 UI 大迭代 · 本轮交付

日期：2026-10-16

## 方向与边界

用户确认采用专业工作台风格，覆盖桌面各页面，并运行静态分析和相关测试。
本轮以桌面公共设计系统、核心工作区和主要管理页面为改造主线，复用现有业务控制器、数据库、审批和终端行为。
工作区开始时已有大量未提交改动；本轮使用版本校验增量补丁，未执行 reset、clean、提交或覆盖已有业务改动。

## 已实施

- 浅色中性蓝灰画布、白色内容面板，以及独立深色配色；蓝色强调选中、聚焦与主操作。
- 统一圆角、字号 token、菜单、标签页、列表选中、按钮禁用、输入选择、进度和通知样式。
- 左侧活动导航增加文字和快捷键提示，保留现有导航键与回调。
- 改善项目/会话选中态、品牌栏与命令入口；主会话工具栏新增直接布局选择器，调用现有专注/执行/审查逻辑。
- 欢迎区升级为目标引导与快捷操作卡片；保留模型配置与项目选择前置条件。
- 输入区强化蓝色聚焦轮廓，保留 IME、Enter、Shift+Enter、附件、模型、执行模式和审批模式行为。
- 去除无条件“沙盒保护已就绪”宣传；按实际 Worktree 绑定显示“独立 Worktree”或“本地工作区”。
- 仪表盘、历史、任务和审计页使用已加载真实数据的紧凑摘要，不把近期记录数当作全库总数。
- 桌面设置改为图标分类导航、内容说明和操作卡片；窄窗口使用分类下拉，宽窗口支持分类搜索及无结果提示。
- 设置公共组件、扩展页、公共页头、表面与空状态适配桌面配色；移动端保留原有显示分支。
- 检查点时间线与工作区状态色收敛到 token；字号改用已有 AppTokens，未放宽质量门槛。

## 验证结果

### 静态分析

`flutter analyze --no-pub lib/presentation test/desktop_ui_refresh_test.dart`

结果：No issues found，exit code 0。

### 针对性回归

以下 11 个测试文件共 38 项全部通过，exit code 0：

- desktop_ui_refresh_test.dart（新增）
- desktop_a11y_motion_test.dart
- desktop_shell_test.dart
- desktop_workspace_interaction_test.dart
- desktop_command_center_test.dart
- desktop_preview_panel_test.dart
- desktop_jobs_strip_test.dart
- desktop_terminal_panel_test.dart
- desktop_checkpoint_timeline_test.dart
- code_quality_guard_test.dart
- render_desktop_test.dart

涵盖配色对比、窄屏摘要、移动端分支、设置分类/搜索、欢迎页权限前置条件、命令中心、布局、会话、上下文、预览、终端与检查点。
代码质量门槛未修改。中途发现的 token 数量超限与格式提示已清理，最终上述检查通过。

日志：
- local/desktop-ui-refresh-analysis.log
- local/desktop-ui-refresh-tests.log

### 渲染截图

输出位于 `artifacts/desktop/`，包括浅/深色、1440×900、1280×800、900×640、1.5×/2×文字缩放、设置和设备页。
人工查看了浅色欢迎工作台、900×640 深色会话、深色设置页；未发现明显溢出。
截图来自隔离测试夹具，包含测试模型、示例项目、模拟设备及 Git 数据，不能作为生产连接成功的证据。

## 未验证与后续范围

- 未运行全仓库测试、真实模型请求、真实设备操作、完整 Windows 构建、安装包或生产部署。
- 深层管理页面本轮通过公共组件和主题获得一致样式，并非每个子页面均做了独立的信息架构重构或逐项人工验收。
- 未升级依赖、修改数据库结构或重写 Agent 执行引擎。
- 若继续大迭代，建议逐页收敛复杂表单与管理列表、增加真实 Windows 交互验收，再生成安装包。
