# B 方案：蓝白 Agent 工作区

用户选定 B 方案后，在现有 Flutter 应用中完成桌面工作区改版。复用原有会话、Agent、任务、审批、数据库和终端服务，所有状态来自这些实际服务。

本次改版于 2026-10-10 开始，最终交付验收日期为 2026-10-11。

## 页面与操作

| 区域 | 已实现的行为 |
| --- | --- |
| 活动栏与项目导航 | 会话、工作台、历史、任务、审计、设置、设备；项目切换、当前项目会话、新建会话、项目文件树；Agent/知识库/记忆/技能与 MCP 入口 |
| 会话输入 | 模型、执行模式、审批模式、附件、代码块；文件上下文芯片可移除；Enter 发送，Shift+Enter 换行；沿用实际暂停、继续与停止流程 |
| 改动审查 | Git 工作区/暂存区、文件选择、增删差异、所选文件暂存与取消暂存、刷新、冲突状态；检查改动将提示词放入会话草稿，发送后才请求模型 |
| 任务记录 | 保留原有 Agent 文件变更记录、补丁和恢复操作 |
| 文件面板 | 目录导航、UTF-8 文本预览、文件引用、外部编辑器与编辑器配置；大型或二进制文件有明确提示 |
| 网页预览 | 项目内 HTML 与资源的本机 HTTP 托管；开发服务器 URL；刷新、桌面/390px 移动视口、外部浏览器；项目切换释放旧服务器 |
| 终端与执行 | 当前项目目录的实际命令执行、停止、作业输出；面板切换保留作业；运行日志、失败工具记录与审批入口 |
| 顶栏与状态栏 | 当前项目、实际 Git 分支及本地分支切换、搜索、命令面板、当前运行状态与改动计数 |
| 自适应布局 | 默认蓝白浅色、显式深色主题；宽屏并排工作台；窄窗口工作台/终端弹窗；可调整面板宽高并保存；大字体保留可达操作 |

Git 操作使用原生参数数组和字面路径，支持包含空格、方括号与 shell 特殊字符的文件名。取消暂存保留工作区文件，支持尚无首次提交的仓库。静态预览仅监听 loopback，文件访问检查项目与符号链接边界。预览不会自动启动项目代码；动态网页需要先在终端启动开发服务器，再输入地址。

## 使用方式

1. 打开程序并选择项目，在设置中配置模型服务商与 API Key。
2. 在左侧选择会话；文件页的「加入上下文」把实际文件引用加入待发送内容。
3. 在「改动」选择工作区或已暂存文件；「检查改动」准备审查提示词，「暂存改动」操作当前所选文件。
4. 静态项目点击「预览项目」，自动寻找 `index.html`、`dist/index.html`、`build/web/index.html`、`public/index.html`，或选择项目内 HTML；动态项目填写终端中已启动的开发服务器地址。
5. `Ctrl+K` 打开命令面板，`Ctrl+P` 搜索项目/会话/任务，`Ctrl+1`～`Ctrl+5` 切换主页面。

Windows 内嵌预览使用 [webview_windows 的 WebView2 实现](https://github.com/jnschulze/flutter-webview-windows)，需要 WebView2 Runtime；缺失或页面加载失败时显示实际错误，并可在系统浏览器打开。

关闭 Windows 窗口时，原生窗口先通知 Flutter 释放预览纹理、WebView2 控制器和本地服务器，再销毁引擎。重复关闭请求不会重复释放资源；宽窗口保留活动网页时也可正常退出。

## 正式交付

正式发布使用正常 `lib/main.dart` 入口，版本 `0.9.0+95`。Windows Release 构建成功；交付目录内的 **77 个文件**逐一进行 SHA-256 校验，与构建输出一致。完整压缩包为 26,700,222 字节（约 25.5 MiB），包含程序、Flutter 资源、WebView2 插件与 MSVC 运行库。

- 程序目录：`dist/windows/NEXUS-Agent-Blue-20261011/`，运行其中 `mobile_agent.exe`。
- 压缩包：`dist/windows/nexus-agent-0.9.0-95-blue-workspace-windows-x64.zip`，解压完整目录后运行，保留同目录 DLL 和 `data/`。
- SHA-256：`bcf637c77c17c46d7704e5d406ec1b58cfc01ad078f73e0c3769541169a8df4e`；旁边的 `.sha256` 文件提供相同校验值。
- 已更新桌面快捷方式：`C:/Users/HJIE/Desktop/NEXUS Agent.lnk`，指向新版程序；原快捷方式备份为 `artifacts/desktop/NEXUS Agent-before-blue-20261011.lnk`。
- 保留旧版目录 `dist/windows/NEXUS-Agent/` 及旧版压缩包，便于回退。

对交付目录中的正式程序进行启动验收：以安装目录为工作目录，程序正常响应，144 DPI 下最小客户区 900×640，关闭退出码 0。记录见 `artifacts/desktop/blue-release-window.json`、`blue-release-smoke.log`。文件校验清单见 `artifacts/desktop/blue-package-manifest.json`，构建日志见 `artifacts/desktop/blue-build.log`。

## 可复现验收

2026-10-11 最终源码检查：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 全部 **1,856** 项通过。回归覆盖实际 Git 文件操作、HTML 服务、输入快捷键、会话草稿和文件引用，以及浅色/深色、900px 窄窗口与大字体的桌面渲染。

Windows 原生验收在隔离项目内实际读取 HTML DOM（标题「验收演示网页」），完成 Git 暂存和取消暂存，并从界面运行 `git diff --stat`，验证命令输出及退出码 0。环境使用 WebView2 `154.0.4258.62`。144 DPI 下，900×640 最小窗口及保留活动预览的宽窗口都正常关闭，程序退出码均为 0。

本地验收记录：

- 静态检查：`artifacts/desktop/blue-analyze.log`
- 全量回归：`artifacts/desktop/blue-regression.log`
- 原生窄窗口：`artifacts/desktop/blue-native-window.json`
- 原生宽窗口：`artifacts/desktop/blue-native-wide-window.json`
- 实际运行截图（隔离项目）：`artifacts/desktop/blue-native-wide-window.png`

```powershell
flutter analyze --no-pub
flutter test --no-pub
./tool/build-windows.ps1 -SkipPub -SkipPackage
```

原生集成验收入口 `tool/desktop_blue_smoke.dart` 使用独立临时 Git 仓库、内存数据库和隔离首选项，不读取模型账户、不发送模型请求。它实际加载 HTML 并读取 DOM，执行 Git 暂存/取消暂存，调用界面预览与终端操作，并检查终端真实输出。使用以下步骤构建与验收；随后必须重新构建正常 `lib/main.dart` 入口，验收程序不能作为发布包：

```powershell
$env:PATH = (Join-Path (Get-Location) 'local/desktop-tools') + ';' + $env:PATH
flutter build windows --release --no-pub --target tool/desktop_blue_smoke.dart
./tool/verify-blue-workspace.ps1 -Executable build/windows/x64/runner/Release/mobile_agent.exe -NativeProbe
./tool/build-windows.ps1 -SkipPub -SkipPackage
```

真实模型账号连通性与 Android 真机投屏不在隔离验收范围内，需使用已配置账号与已授权设备检验。
