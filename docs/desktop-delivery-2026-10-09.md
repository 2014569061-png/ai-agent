# Windows 桌面端交付记录

日期：2026-10-09。版本：`0.9.0+95`。本次补齐已有 Flutter 桌面壳的功能和 Windows 发布链路。

## 已完成

| 工作项 | 交付结果 |
| --- | --- |
| 桌面入口 | Windows 使用 DesktopShell；默认窗口 1280×800，最小逻辑客户区 900×640，窄窗口收起右栏。Android 保留原入口。 |
| 导航与快捷键 | 会话、工作台、历史、任务、审计及设置接入现有页面；Ctrl+K 命令面板、Ctrl+P 搜索、Ctrl+1～5 导航。历史和任务可打开关联会话。 |
| 搜索 | 查询真实 Drift 数据库中的会话标题、项目名称/路径和任务关键词，按更新时间排序；支持较早记录、字面量查询及结果跳转。 |
| 运行上下文 | 显示实际设备、Agent、模型、项目和本机运行时；终端使用选中项目的目录与已有受限命令执行器。 |
| Android 设备管理 | 每 5 秒检测设备、选择序列号、显示离线/未授权状态；接入 scrcpy 启停、返回、主页、文字输入、PNG 截图预览和保存。支持选择工具路径。 |
| 设备操作记录 | 操作审计区分成功/失败，设备标识经哈希处理；输入正文和截图字节不入日志。所有操作显式指定设备。 |
| 进程生命周期 | Windows Job Object 管理由应用启动的投屏进程，关闭应用时结束它；原生通道拒绝登记非本应用子进程。 |
| 平台初始化 | Windows 通知配置就绪；Android 前台服务、分享与 WorkManager 初始化按平台限制。 |
| 原生构建 | 补齐 Windows runner，修复 MSVC 14.51 的旧 WinRT 协程兼容、首次配置中断后的安装目录及高 DPI 最小窗口尺寸。 |
| 发布与 CI | PowerShell 脚本生成完整 ZIP 和 SHA-256，包含 Flutter 数据、插件及 MSVC 运行库；新增 Windows 构建和产物上传任务。远端 CI 尚未执行。 |

## 验证结果

- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --coverage`：**1840 项通过**，包含 16 项桌面服务和界面测试。
- 源码覆盖率：**65.35%**（28565 / 43714），通过现有 55% 门槛。
- 静默 catch 门槛：未记录意图的空 catch 为 0，通过。
- Windows Release 构建：通过；Flutter 3.47.2、Visual Studio 2026 / MSVC 14.51、Windows SDK 10.0.26100.0。
- 从最终 ZIP 解压运行：窗口标题 NEXUS Agent，响应正常，关闭后退出码 0。
- 150% 显示缩放：尝试缩小窗口后，逻辑客户区保持 900×640。
- 发布 ZIP：74 个文件，与 Release 目录逐文件字节一致，ZIP 完整性和 SHA-256 校验通过。

本机验证记录位于 `artifacts/desktop/`：`analyze-2026-10-09.log`、`full-coverage-tests-2026-10-09.log`、`coverage-gate-2026-10-09.log`、`windows-build-2026-10-09.log`、`windows-smoke-2026-10-09.json`、`windows-native-startup.png`、`package-verification-2026-10-09.log`。这些产物目录不进入 Git。

## 发布产物

```text
dist/windows/nexus-agent-0.9.0-95-windows-x64.zip
dist/windows/nexus-agent-0.9.0-95-windows-x64.zip.sha256
```

ZIP 大小：26,222,989 字节。

```text
SHA256 6fd33b8f93ab83eb413c1dcd923bf4aa7cdc43f2deb04c564e3ecf04934cfb3e
```

解压整个 ZIP，运行 `mobile_agent.exe`。保留同目录的 DLL 和 `data/`。

构建入口与设备工具配置见 README 的「Windows 桌面端」。本机为避免重复下载，构建复用了版本一致的 Sentry Native 0.16.4 源码和 Crashpad 子模块；脚本的 `-SentryNativeSource` 可选参数会检查 SDK 版本。正常联网构建可省略此参数。

## 待外部条件具备后验证

当前 ADB 未检测到连接设备，未进行真机投屏、手机按键、文字输入及截图保存的端到端验收。相关授权门禁、指定序列号、失败审计、PNG 二进制返回和投屏生命周期已通过自动化测试。真机验收需要连接已授权的 Android 手机并安装 adb / scrcpy。

Windows 桌面版不提供 Android 的常驻前台服务与 WorkManager 后台调度。模型调用仍需用户配置服务商及 API Key；本次未调用付费模型服务。macOS / Linux 发布不在本次交付范围内。
