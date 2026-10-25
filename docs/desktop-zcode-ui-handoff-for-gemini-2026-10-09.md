# 给 Gemini：Windows 桌面 UI 改版任务书

日期：2026-10-09。

## 1. 用户目标与当前状态

用户认为当前桌面页面不好看，要求参考 GitHub 上 ZCode 的设计风格。本任务负责完成 **Windows 桌面端的视觉与布局改版**，保留现有业务行为和手机端体验。

请在当前工作区继续实现、渲染、检查并交付实际可运行版本，不停留在建议、效果图或替换颜色。

```text
工作区：D:\AIIIIII\ai-agent\mobile_agent
技术栈：Flutter 3.47.2 / Dart 3.13.2 / Riverpod / Drift
Flutter：C:\src\flutter\bin\flutter.bat
Dart：C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe
```

这里已经有 Android 应用和可构建的 Windows 桌面端。2026-09-25 的前端交接文档中「Android-only」已经过时，本次以当前代码与本文件为准。

**注意：当前代码已经包含一部分 UI 草稿，尚未完成视觉验收。** 用户指定交给 Gemini 后，Codex 停止扩展 UI 实现，仅做格式、静态检查和交接整理。Gemini 可以调整这些草稿，不应把它们当作定稿。

Git 工作区还混有上一轮桌面功能实现和用户原有改动，没有为本次 UI 单独建立提交。`git diff` 不是纯 UI 差异。不要使用 `git reset --hard`、整文件恢复到 HEAD 或 `git clean`；不要因此丢失已经完成的搜索、设备管理和 Windows 工程。

## 2. 已查到的设计参考

主参考是官方仓库 [zai-org/ZCode](https://github.com/zai-org/ZCode)，不是第三方同名 CLI。调研时 GitHub main 的提交为 `29628c9acdb81b703bbd4080c207a0e7ce5e276e`。

| 来源 | 用途 |
| --- | --- |
| [ZCode DESIGN.md，固定提交](https://github.com/zai-org/ZCode/blob/29628c9acdb81b703bbd4080c207a0e7ce5e276e/DESIGN.md) | 主设计依据：工作台的信息密度、语义表面、文字层级、圆角和操作层级。 |
| [VS Code 设计语言](https://github.com/microsoft/vscode/blob/main/.github/skills/design-philosophy/SKILL.md) | 辅助参考：统一控件比例、图标与边框，减少界面装饰。此处仅作为外部设计参考。 |
| [Zed 外观文档](https://github.com/zed-industries/zed/blob/main/docs/src/appearance.md) | 辅助参考：UI 与代码字体分开、浅深色适配、工具面板的布局组织。 |

对 ZCode 的借鉴重点：界面适合长时间工作；背景、内容面板和浮层有明确层级；正文与路径有不同字体；导航与操作紧凑；品牌色用在关键强调；普通界面不依赖大阴影和光晕。请先阅读来源，再查看它的相关组件和主题文件，必要时进一步核对实际截图。

这些来源提供的是设计参考。当前项目仍使用 Flutter；不引入 Electron、React、Tailwind 或整套上游运行时，也不复制 ZCode 品牌资源。

## 3. 期望的视觉与布局

以下是本项目的落地建议，可按实际渲染微调，不是必须逐像素复制上游。

```text
原生 Windows 标题栏
┌────────────────┬──────────────────────────────────┬─────────────────┐
│ NEXUS          │ 工作区 / 当前页面     搜索  命令   │ 运行上下文      │
│ 工作项目选择   ├──────────────────────────────────┤ 设备 / Agent    │
│ 会话           │ 会话标题、模型与会话操作         │ 模型 / 项目     │
│ 工作台         │                                  │ 终端入口        │
│ 历史           │ 正文 / 新会话引导                │                 │
│ 任务           │                                  │                 │
│ 审计           │ 配置提示（仅需要时）             │                 │
│                │ 输入区：任务文本 + 操作栏        │                 │
│ 设置           │                                  │                 │
└────────────────┴──────────────────────────────────┴─────────────────┘
```

- 桌面主体采用中性色背景、细分隔线和少量强调色。浅色接近白/浅灰，深色接近中性炭灰；普通输入区、卡片、导航不加光晕与玻璃折射。
- 主导航建议约 208～224 宽，右栏约 224～260 宽；正文按可用空间伸缩。宽度 1150 以下可收起右栏，900 宽必须保留桌面导航和核心入口。
- 字体建议统一为 14 正文、12 辅助、16 次标题、18 标题；更大的字号只用于确有需要的内容。路径、模型标识、命令使用等宽字体并提供合适的中文回退。
- 间距围绕 4 / 8 / 12 / 16 / 24；普通控件约 28～36 高，但需要允许文字缩放；图标主要为 16，紧凑辅助图标为 12。
- 控件圆角建议 6～8，内容/输入面板 12，独立对话框 16。圆形仅用于有明确意义的头像、状态点等形状。
- 选中导航采用中性底色、字重或小标记；主要按钮与重点链接使用强调色。不要给所有功能卡片都填蓝色。
- 顶部工作区导航与会话工具栏必须职责清楚。如果合并成一条，保留搜索、命令、会话列表、新会话、模型选择、上下文用量等现有操作。不要保留两个重复的大标题栏。
- 首页用简洁标题、适量可点击的任务建议及清晰输入区。去掉营销式大 Hero、粒子、光晕和重复引导；保留项目/模型未配置时真实有用的提示。
- 不使用虚构的最近会话、项目、Git 分支、在线状态、完成任务数或终端内容来填充页面。

## 4. 已经改了哪里：当前 UI 草稿清单

以下路径均相对上述工作区。请先审查这些文件的当前内容，避免重复搭建。

| 文件 / 定位 | 已有改动 | Gemini 接续工作 |
| --- | --- | --- |
| `lib/presentation/theme/desktop_theme.dart` / `DesktopTheme` | 新增桌面 ThemeExtension：浅/深色表面、字体、按钮、输入、卡片和弹窗主题。 | 收敛语义 token，检查文字对比度、控件状态、等宽字体与现有主题扩展；当前色值是初稿。 |
| `lib/main.dart` / `MobileAgentApp.build` | 桌面平台应用 DesktopTheme；手机沿用 AppTheme。 | 保留平台判断和启动流程，只核对主题接线。 |
| `lib/presentation/navigation/app_shell.dart` / `DesktopShell`、`_DesktopRail`、`_DesktopTopBar`、`_DesktopContextPanel` | 桌面壳增加 4px 面板间距与面板边框；导航更紧凑；加入真实项目选择入口；右栏改为标签与数值两层；搜索与命令入口保留。 | 完成主工作台的比例、层级、顶部栏协调与交互状态；保留导航键、回调和实际状态订阅。 |
| `lib/presentation/chat/chat_page.dart` / `build` | 桌面纯色背景、flat 材质、屏蔽手机聊天背景图、调整顶部间距。 | 核对消息列表、悬浮顶栏与输入区的留白；避免内容被覆盖。此文件业务逻辑很多，不宜整文件重写。 |
| `lib/presentation/chat/widgets/capsule_top_bar.dart` / `_desktopBar`、`capsuleTopBarHeight` | 新增 40px 桌面会话操作栏，保留会话列表、模型、上下文与新会话入口。 | 与工作区顶栏协调；补齐运行、暂停和模型失败状态的可见表达；检查长标题和文字缩放。 |
| `lib/presentation/chat/widgets/chat_empty_state.dart` / `_desktopWelcome`、分类栏、任务卡 | 新增无光晕的桌面首页，复用原有分类和动作回调，卡片改为中性细边框。 | 做实际视觉验收，调整栅格、正文和卡片尺寸；确保所有建议仍触发真实动作。 |
| `lib/presentation/chat/widgets/floating_capsule_input.dart` / 输入区与三个按钮类 | 桌面输入两行起步；新增 flat 输入面板、无发光聚焦框；模式/审批有文字标签；附件/发送改为紧凑按钮。 | **重点审查功能保真**：桌面按钮早返回分支目前没有完整传递旧控件的所有语义和手势，例如 `_FilledCircleButton.onLongPress`、`_ModeTile.selected`。必须保留这些原有行为，或撤销该分支后重新实现。 |
| `lib/presentation/chat/widgets/provider_setup_hint.dart` | 桌面未配置模型提示改为中性色与细边框，保留配置和关闭动作。 | 收紧高度和动作层级，验证关闭/配置中/成功后消失的行为。 |
| `lib/presentation/widgets/glass_surface.dart` | 发现 DesktopTheme 时返回 flat 表面，不执行玻璃效果。 | **重点审查公共组件范围**：当前桌面分支按 role 统一圆角，可能与调用方的外层裁剪或特殊形状不一致；审查 overlay、交互、margin/padding 与明确形状。不要机械替换全部公共控件。 |
| `lib/presentation/widgets/nexus_background.dart` | 桌面使用纯色画布，手机保留既有背景。 | 保持该平台隔离原则；不要通过修改用户偏好来实现桌面样式。 |

这十个文件只是起点，不代表整套界面已经改完。直接写死 AppPalette 色值、LiquidGlass、NexusSurface 等的其他页面，未必会完整接受新主题。

## 5. 哪些地方可以继续改

以 `lib/presentation/` 为主：

- 上述十个文件及必要的新桌面组件。
- `lib/presentation/navigation/desktop_devices_dialog.dart`：设备对话框的布局、按钮层级、错误信息显示；服务调用保持原样。
- `lib/presentation/dashboard/`、`history/`、`jobs/`、`audit/`、`settings/`、`projects/`：统一桌面下的页头、列表、空状态、表单、弹窗与表面；复用真实数据和现有入口。
- 聊天消息、工具活动、计划和指标相关组件：改桌面视觉时保留流式更新边界与原回调，避免大组件随每个 token 重建。
- 相关界面测试：补实际行为与响应式回归，不写仅验证新增颜色常量的测试。

共享组件的改动必须通过桌面主题或清楚的桌面作用域限定。不能全局把 AppPalette / AppTheme 改成新样式导致手机端一起变化。

## 6. 哪些地方不要改

| 范围 | 必须保留 |
| --- | --- |
| `lib/application/desktop_search_service.dart` | 真实数据库查询、归档过滤、排序、较早记录匹配、字面量搜索与查询 debounce。 |
| `lib/application/desktop_device_service.dart` | ADB/scrcpy 检测、配置、选择序列号、未授权禁用、超时/输出限制、PNG 校验、投屏生命周期及操作审计。 |
| `lib/application/desktop_runtime_service.dart` | 真正的运行时检测；不重新写成静态「就绪」。 |
| `lib/application/chat_controller.dart` 及其 part、Agent/任务执行服务 | 会话状态、运行、暂停、恢复、审批、工具执行与数据持久化。UI 回调照接。 |
| `lib/domain/`、`lib/infrastructure/`、数据库结构 | 不为视觉改版变更协议、表结构、网络请求、工具白名单、沙箱或审计脱敏。 |
| `lib/infrastructure/notifications/notification_service.dart` 与 `main.dart` 的平台初始化部分 | 已修好的 Windows 通知与 Android 平台服务判断。 |
| `android/`、手机端入口与设置偏好 | 原有前台服务、分享、WorkManager、手机聊天布局、背景、动画和玻璃设置。 |
| `windows/runner/flutter_window.cpp` / `nexus/desktop_process` | Job Object 和子进程所有权检查；关闭应用结束自启动投屏。 |
| `windows/runner/win32_window.cpp` | 高 DPI 最小逻辑客户区 900×640；不要改成物理像素。 |
| `windows/CMakeLists.txt`、`tool/build-windows.ps1` | MSVC 兼容、Sentry 版本校验、正确 bundle 输出、运行库、完整 ZIP、哈希与旧缓存归档。 |
| `.github/workflows/ci.yml`、质量门槛 | 保留 Windows 构建任务及既有质量检查，不降低覆盖率或分层门槛。 |
| `.metadata`、`pubspec.lock`、用户其他未提交改动 | 不覆盖、不清理；本轮通常不需加依赖或修改锁文件。 |

不要为了通过 UI 验收隐藏错误、硬编码成功状态、使用假数据替换服务或删掉有用的入口。保留 Ctrl+K、Ctrl+P、Ctrl+1～5；历史和任务仍能打开关联会话；终端仍在当前项目目录执行。

## 7. 实现路线与先后顺序

1. **接收基线**：读当前差异和上述文件；先运行交接检查。区分业务成果与 UI 草稿。记录现有界面，确认没有并行构建进程。
2. **完成设计基础**：统一 DesktopTheme 的语义表面、字阶、间距、圆角、状态与焦点；清理必要的桌面直接色值。验证手机没有进入新主题作用域。
3. **完成主工作台**：主导航、项目选择、顶部栏、右侧上下文；让页面层级和布局比例一致。优先实际可用的桌面信息，不添加装饰性数据。
4. **完成聊天核心**：首页、输入、会话工具栏、消息与执行状态。修复第 4 节列出的手势/语义风险，核对空白会话和正常会话。
5. **统一其他页面**：工作台、历史、任务、审计、设置、项目与设备弹窗。重点检查标题、列表行、表单、加载/空/失败状态；这些页不能继续维持旧的装饰风格。
6. **渲染与交互验收**：浅色/深色 × 1440×900、1280×800、900×640；桌面至少检查 1.5 和 2.0 倍文字；手机约 390～430 宽做对照。检查文字折行、正文滚动、按钮可达和焦点。
7. **最终构建与交付**：运行必要回归、分析和质量门，再 Windows Release 构建；从最终 ZIP 解压启动。交付新截图、包、变更清单和实际未验证项。

每完成一个主要阶段就看真实渲染。不要最后才发现页面溢出或几个组件有三套视觉语言。UI 验收不能只用 Ahem 测试字体；中文需要加载真实字体。

## 8. 当前验证结果与剩余检查

本轮交接检查：

- 十个 UI 相关文件的 Dart 静态分析：无问题。
- `desktop_shell_test`、`nexus_components_test`、`provider_setup_hint_test`、`glass_surface_test`、`startup_gate_test`、`nexus_theme_test`、`layering_test`：**27 项通过**。
- 日志：`artifacts/desktop/zcode-handoff-analyze.log`、`artifacts/desktop/zcode-handoff-tests.log`。
- **尚未完成本轮 UI 的截图验收、全量回归和新的 Windows Release 构建。**

上一轮功能交付曾通过 1840 项测试、65.35% 源码覆盖率，以及 Windows 启动/退出/高 DPI 检查，记录在 `docs/desktop-delivery-2026-10-09.md`。这些属于改版前结果，不能作为新 UI 已通过全部验收的证据。

现有 `dist/windows/nexus-agent-0.9.0-95-windows-x64.zip` 和 `artifacts/desktop/windows-native-startup.png` 仍是改版前产物；不要把它们称为本轮新界面成品。`artifacts/desktop/render_current_test.dart` 是早期临时渲染脚本，只适合参考；它的聊天初始化未完整模拟，可能显示 skeleton，不能作为最终页面验收。

建议先用以下命令；测试范围随后按实际改动扩展：

```powershell
Set-Location 'D:/AIIIIII/ai-agent/mobile_agent'
& C:/src/flutter/bin/flutter.bat analyze --no-pub
& C:/src/flutter/bin/flutter.bat test --no-pub test/desktop_shell_test.dart test/nexus_components_test.dart test/provider_setup_hint_test.dart test/glass_surface_test.dart test/startup_gate_test.dart test/nexus_theme_test.dart test/layering_test.dart

# 完成改版后，按现有 CI 标准检查
& C:/src/flutter/bin/flutter.bat test --no-pub --coverage
& C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe run tool/check_coverage.dart coverage/lcov.info 55.0
& C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe run tool/count_silent_catches.dart lib 0
git diff --check

# Windows 发布构建。该本机缓存已存在，且包含 Windows 所需子模块。
./tool/build-windows.ps1 -FlutterExe C:/src/flutter/bin/flutter.bat -SkipPub -SentryNativeSource local/sentry-native-windows
```

其他机器没有本机 Sentry 缓存时省略 `-SentryNativeSource`，按 README 准备 NuGet 和 C++ 环境。不要通过修改全局 Pub 缓存来修复构建。

## 9. 完成标准与交付内容

- 当前桌面壳、聊天和主要业务页面的视觉语言一致，浅深色均可读。
- 不再出现大胶囊重复顶栏、首页光晕、大面积品牌色卡片或不必要的发光输入框。
- 快捷键、会话列表、新会话、搜索跳转、设置、项目、设备和终端原有交互继续可用。
- 生成截图至少覆盖浅色/深色主界面、900×640 窄窗口、聊天有内容、设置及设备弹窗；测试状态来自真实服务或明确隔离的测试数据。
- Android 页面和偏好没有因公共组件改动而回归。
- 静态分析和相关测试通过；最终报告说明全量回归、覆盖率与 Windows 发布检查的真实结果。
- 发布完整新 ZIP 和 SHA-256，写明解压后运行方式；源码和产物对应同一轮改动。
- 总结改动文件、视觉决策、测试结果、剩余问题。未连接 Android 真机时明确说明，不能声称投屏/手机控制端到端已验证。

用户已授权完成上述 UI 改版，不必在普通配色、间距和组件选择上反复请求确认。本任务没有要求提交、推送、上线或发布到外部平台。
