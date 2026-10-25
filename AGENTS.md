# 项目协作与 Android 预览

用户的明确任务范围优先于本文。工作区已有大量未提交改动，请保留其他 agent 的工作，按文件增量修改。

## Android UI 默认风格

- 用户已确定手机端持续采用当前蓝白、柔光、圆角分组风格。后续新增、修改的 Android 页面和弹层必须沿用，不再引入独立视觉方案。
- 具体规范、组件选择与专用画布边界见 [Android UI 规范](docs/android-ui-style.md)。以已实现的 `MobileTheme` 与公共组件为准，用户后续明确提出的新要求优先。
- 普通页面使用 `NexusPageHeader` / `NexusPageLayout`；分组使用 `SectionCard` 或 `SettingsGroupCard`；列表使用 `NexusListTile` / `SettingsTile`；搜索使用 `NexusSearchField`；异步状态使用 `AsyncStateView`；弹层优先使用 `showNexusSheet`。
- 配色从 `Theme.of(context).colorScheme` 或 `AppTheme.semanticOf(context)` 读取；手机几何使用 `MobileTheme`，不要直接复用旧的桌面 `AppTokens.radiusCard/radiusControl`。保留语义状态色。
- 新增 Android 页面时同步登记 `test/android_ui_inventory_test.dart`，检查正常手机尺寸与窄屏大字体；涉及布局的变更须在现有模拟器中核对。不要把“继承全局主题”等同于“已经逐屏验收”。
- 保留全部真实能力、授权说明和入口。终端、代码、Git 差异、网页内容可保留专用画布，导航、工具栏、列表、表单及操作面板仍使用本规范。

- Android 主导航已按用户要求改为左侧抽屉，首页底部仅保留输入区；新增页面通过统一菜单、返回与边缘滑动保持入口可达，不重新引入底部导航栏。

## 已有安卓模拟器

- 本项目已经配置 **Android 模拟器**，可以在电脑上直接查看手机版，不需要连接 USB 手机或反复手动安装 APK。
- AVD 名称：`Nexus_Preview_API_36`，Android 16 / Google APIs / x86_64。
- 启动入口：项目根目录 `android-preview.bat`，或在根目录执行 `./tool/run-android-preview.ps1`。
- 先检查已有预览进程和设备，避免重复启动 Flutter 调试会话。只打开模拟器或 App，不代表自动热重载进程仍在运行。
- 检查设备：`./local/android-sdk/platform-tools/adb.exe devices`。设备序列号可能变化，后续 ADB 操作必须显式指定实际序列号。
- 检查 AVD：`./local/android-sdk/platform-tools/adb.exe -s <序列号> emu avd name`。
- 调试包名是 `com.nexusagent.app.debug`。

## 热重载与 UI 验收

- `tool/android_preview.dart` 通过 Flutter machine 协议运行调试应用，轮询当前工作区的 `lib/`、`assets/`、`shaders/`，文件保存后自动热重载；其他 agent 写入同一工作区的改动也可以触发。
- 保持预览进程运行。预览终端应显示 `[preview] Ready`；成功刷新会显示 `[preview] Hot reload complete.`。热重载失败时应检查该运行终端的编译错误，不能只确认模拟器窗口存在。
- 预览终端输入 `r` 后回车可手动热重载，`R` 后回车可热重启，`q` 后回车可退出调试。修改初始化逻辑可能需要热重启；Android 原生代码、权限、依赖变更需要重新启动预览并构建。
- 本项目有独立的 Android 与 Windows 布局。`DesktopTheme.maybeOf(context) != null` 等条件可能进入桌面专用页面。用户期望在模拟器中看到改动时，要修改 Android 实际执行的主题、公共组件和页面分支；只改桌面分支不会改变手机界面。
- 用户要求“手机版所有页面”时，覆盖 Android 的全局主题、公共组件、导航与各页面手机布局，并在已有模拟器里检查实际显示。不要直接强制 Android 进入桌面布局来模拟完成适配。
- 在其他 worktree/目录写入的文件不会被当前预览监听；先确认编辑目录与预览使用的工作区一致。
- 模拟器适合手机 UI 和通用功能验证。项目的内置 Alpine/PRoot 运行时仅支持 ARM64，x64 模拟器不能替代其真机验证。

## 下载位置

- 用户要求所有新增下载位于**当前工作区内**。
- 模拟器及镜像：`local/android-sdk/`；虚拟手机数据：`local/android-avd/`；Android 工具状态：`local/android-user/`。
- 下载归档：`local/preview-downloads/`；依赖缓存：`local/gradle-cache/`、`local/pub-cache/`；临时文件：`local/temp/`。
- 启动脚本会设置上述本地路径。单独运行下载、依赖恢复或安装命令时，也要显式使用工作区路径，避免写入默认用户目录。
- 现有 SDK 构建工具通过目录链接复用本机安装；不需要重复下载整套 SDK。`local/` 已被 Git 忽略，不要提交模拟器、镜像或缓存。
