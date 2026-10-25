# 开发与构建

适用于从公开仓库克隆源码的开发者。项目支持 Android 与 Windows，源码版本和依赖以 pubspec.yaml、pubspec.lock 为准。

## 环境要求
- Flutter 3.47.2（桌面构建已适配 Windows）
- Dart 3.13 或更高版本
- Android 构建需要 JDK 17

## 获取源码

```bash
git clone https://github.com/2014569061-png/ai-agent.git
cd ai-agent
```

## 本地运行
```bash
flutter pub get
flutter run
```

首次启动后，在“设置”中配置模型服务商、接口地址、模型和 API Key。

### 在电脑上调试手机版（无需 USB）

Windows 双击项目根目录的 `android-preview.bat`，或执行：

```powershell
./tool/run-android-preview.ps1
```

启动入口使用名为 `Nexus_Preview_API_36` 的 Android 模拟器（Android 16 / Google APIs / x86_64），等待系统就绪后运行 debug 应用。也可以用 `-Avd <名称>` 指定已有模拟器。

本机预览环境保存在当前工作区：`local/android-sdk/` 放模拟器和系统镜像，`local/android-avd/` 放虚拟手机数据，`local/android-user/` 放 Android 工具状态，`local/gradle-cache/`、`local/pub-cache/` 放后续依赖缓存。下载归档在 `local/preview-downloads/`，临时文件在 `local/temp/`。SDK 中的已有构建工具通过目录链接复用本机安装。上述目录均被 Git 忽略。预览运行复用已恢复的依赖；修改 `pubspec.yaml` 后需设置工作区 `PUB_CACHE` 并重新执行 `flutter pub get`。

在新机器上需先准备 SDK 与系统镜像，并在项目目录设置 `$env:ANDROID_AVD_HOME = "$PWD/local/android-avd"` 后创建对应虚拟设备，例如：

```powershell
$env:ANDROID_AVD_HOME = "$PWD/local/android-avd"
$env:ANDROID_USER_HOME = "$PWD/local/android-user"
./local/android-sdk/cmdline-tools/latest/bin/avdmanager.bat create avd -n Nexus_Preview_API_36 -k 'system-images;android-36;google_apis;x86_64' -d pixel_7
```

保持预览终端打开，修改并保存 `lib/`、`assets/` 或 `shaders/` 下的文件会自动触发 Flutter 热重载，包括外部编辑器和 Codex 写入的改动。在终端输入 `r` 后回车可手动热重载，`R` 后回车可重启 Dart 应用，`q` 后回车退出调试。修改启动初始化逻辑时使用 `R`；修改 Android 原生代码、权限或依赖后重新运行启动入口。

调试包支持 x64 模拟器，正式发布包仍只包含 ARM64。模拟器适合检查手机 UI、交互与通用功能；内置 Alpine/PRoot 运行时只支持 ARM64，需要在手机上验证。

Android release 默认要求正式签名。配置 `android/key.properties` 后执行正式构建；仅本地验证安装流程时，才显式允许 debug 签名：

```bash
flutter build apk --release
# 仅本地测试，产物不可作为发布包
cd android && ./gradlew app:assembleRelease -PallowDebugSigning=true
```

正式发布 tag 使用 `v<versionName>`；本版本 versionName 为 `0.9.0`；`+95` 作为 Android versionCode。

## Windows 桌面端
桌面版采用蓝白工作区，复用 Flutter、Riverpod 和 Drift/SQLite。窗口默认 1280×800，最小 900×640；宽屏同时显示项目导航、Agent 会话、代码差异/网页预览与终端，窄窗口通过弹窗打开工作台和终端。桌面跟随系统主题时默认使用蓝白浅色，也可以显式选择深色。Android 保持原有聊天入口。

- 左侧导航提供会话、工作台、历史、任务与审计；历史和任务可打开关联会话。
- `Ctrl+K` 打开命令面板，`Ctrl+P` 搜索会话标题、项目名称/路径及任务关键词，`Ctrl+1`～`Ctrl+5` 切换页面。搜索使用数据库查询，可找到早期记录。
- 项目导航提供项目切换、当前项目会话和文件树；文件可加入输入上下文，并在发送前移除。模型、执行模式、审批模式、附件与暂停/继续沿用实际会话控制器。`Enter` 发送，`Shift+Enter` 换行。
- 右侧「改动」读取实际 Git 工作区与暂存区差异，支持选择文件、检查改动、暂存/取消暂存；「任务记录」保留 Agent 的文件变更记录与恢复入口。顶部可切换现有本地分支。检查改动会准备审查提示词，点击发送后才请求模型。
- 「预览」可直接托管项目内的 HTML，或打开已启动开发服务器的 HTTP/HTTPS 地址，支持刷新、桌面/390px 移动视口及系统浏览器。Windows 内嵌预览需要 WebView2 Runtime；不可用时显示明确错误并提供浏览器入口。开发服务器由用户在终端启动。
- 终端使用当前项目目录，支持执行、停止、输出与项目内任务连续性；运行日志和问题页显示实际工具记录。已有命令白名单和审批规则继续生效。面板宽高和展开状态保存到本地。
- 点击「设备」或在命令面板选择「Android 设备」，可选择设备、启动/停止 scrcpy、返回、主页、输入文字、截图并保存 PNG。
- 设备列表每 5 秒刷新。未授权或离线设备禁止操作；所有命令显式指定设备序列号。操作写入审计日志，输入正文及截图字节不进入日志。

设备功能需要 [Android SDK Platform Tools](https://developer.android.com/tools/releases/platform-tools) 与 [官方 scrcpy](https://github.com/Genymobile/scrcpy)。程序自动检测 PATH、`ANDROID_HOME`、`ANDROID_SDK_ROOT` 和程序目录的 `tools/`；也可以在设备工具设置中选择 `adb.exe` 与 `scrcpy.exe`。连接手机后需开启 USB 调试并在手机上确认授权。ADB 文字输入支持英文、数字和常用标点，中文可在投屏窗口粘贴。

构建环境需要 Flutter 3.47.2、Visual Studio 的「使用 C++ 的桌面开发」工作负载、Windows SDK，以及 [NuGet CLI](https://learn.microsoft.com/nuget/install-nuget-client-tools)。在项目根目录执行：

```powershell
./tool/build-windows.ps1
# 已恢复依赖时复用缓存
./tool/build-windows.ps1 -SkipPub
# NuGet 未在 PATH 时指定路径
./tool/build-windows.ps1 -NuGetExe 'D:/tools/nuget.exe' -SkipPub
# 网络较慢时，可复用版本一致、包含 Crashpad 子模块的 Sentry 原生源码
./tool/build-windows.ps1 -SentryNativeSource 'D:/tools/sentry-native' -SkipPub
```

脚本生成 `build/windows/x64/runner/Release/mobile_agent.exe`，并将完整 Release 目录（含 MSVC 可再分发运行库）打包至 `dist/windows/nexus-agent-0.9.0-95-windows-x64.zip`，附带 SHA-256 校验文件。解压后运行 `mobile_agent.exe`；DLL 和 `data/` 必须一起保留。升级 Visual Studio 后，脚本会归档旧实例的 CMake 缓存。

Windows 不使用 Android 的前台服务、分享接收或 WorkManager 后台调度；定时后台运行和 Android 系统自动化仍由手机端提供。关闭桌面程序会结束由它启动的投屏进程。桌面版尚未声明 macOS/Linux 发布支持。

桌面端“检查更新”只选择 Windows x64 ZIP，下载后验证 SHA-256，并提供“打开下载位置”。关闭程序后，将完整压缩包解压到新目录，运行其中的 `mobile_agent.exe`；保留同目录 DLL 与 `data/`。用户数据继续使用应用文档目录。若新版本尚未提供 Windows 包，会显示明确提示。

桌面侧栏会话和任务记录首次显示 30 条，有更多记录时提供“加载更早”入口。项目菜单展示最近项目，完整项目列表通过“打开或管理项目…”访问。

CI 覆盖 `main`、`feature/**`、`refactor/**`、`codex/**` 和所有 PR；Windows 构建前运行平台关键回归。Tag 发布工作流同时配置 Android APK、Windows ZIP 及各自的 SHA-256 校验文件。

验证命令：

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

平台验证与现有失败见[验证状态](verification.md)。

## 构建 APK
日常本地构建推荐使用根目录的 `build-apk.bat`。它默认复用 Flutter、Gradle 和 native-assets 的增量缓存，不会执行 `flutter clean`，也不会修改全局 Flutter 的 JDK 配置：

```bat
build-apk.bat
```

脚本模式：

```bat
build-apk.bat --offline       rem 只使用本机 Pub/native-assets 缓存，缓存缺失时快速失败
build-apk.bat --online        rem 显式允许恢复 Pub 依赖和 native-assets
build-apk.bat --check --no-pause rem 只检查环境、版本、签名文件与缓存，不构建
build-apk.bat --keep 5        rem 成功发布后最多保留 5 个时间戳包，另加 latest
build-apk.bat --keep-all      rem 当次构建不清理旧 APK
build-apk.bat --no-pause --no-open rem 自动化调用，不等待按键、不打开文件夹
build-apk.bat --install       rem 构建发布成功后安装到设备
build-apk.bat --clean --online rem 冷构建；--clean 必须搭配 --online
build-apk.bat --fast          rem 本地快速迭代；跳过 R8/资源收缩，且不发布到 dist/
```

首次 checkout 或依赖、Flutter/Android 工具链尚未缓存时仍需要网络。`--offline` 能约束 Pub 依赖恢复，但 Flutter 的 `sqlite3` native-assets hook 还需要本地已有经过 hash 校验的 ARM64 库；缺少时脚本会在构建前提示，而不是等待 GitHub 网络超时。完全断网、可复现的构建还需要将该原生资源放入受控的内部制品源或随构建环境预热，不能仅靠 Gradle `--offline` 实现。

`build-apk.bat` 继续请求正式签名 ARM64 构建，检查 APK 新鲜度、非空和 SHA-256，并将可分享副本写入 `dist/`。默认 release 会执行 R8 和资源收缩；本地迭代可使用 `--fast` 跳过这两个耗时步骤，但 `--fast` 产物不可作为正式发布包。Gradle daemon、并行任务和构建缓存默认开启；配置缓存因 Flutter 3.47.2/AGP 8.13 的任务序列化兼容性问题保持关闭。环境与发布逻辑位于 `tool/build-apk-tools.ps1`，需要 Windows PowerShell；构建本身不需要 Python。

默认成功发布后保留 **3 个带时间戳的有效 APK 加 1 个 latest**，其中优先为最新的不同版本保留一个回滚候选名额（未保证降级兼容）。只删除名称符合规则且 SHA-256 正确的旧包及其配套校验文件；未知文件、无效校验包不会删除，所以实际文件数可能超过此上限。重要历史包请外部备份，或使用 `--keep-all`。

Flutter 构建日志写入 `artifacts/build-apk/`，构建失败不覆盖已发布的 latest；发布阶段会校验暂存副本，并在可捕获的替换错误后尝试恢复旧 latest。APK 和校验文件不是跨文件原子事务，断电后需重新校验。若进程被强制关闭，先确认没有构建正在运行，再移除遗留的 `artifacts/build-apk/.lock` 空目录。

Windows 脚本回归测试：`python tool/test_build_apk.py`（使用隔离假产物，不运行真实 Flutter 构建）。如果只需要 Flutter 默认构建，也可以直接运行：

```bash
flutter build apk --release --target-platform android-arm64
```

产物路径：

```text
build/app/outputs/flutter-apk/app-release.apk
```

## 提交约定

产品源码放 lib/，回归放 test/，可复用脚本放 tool/，当前工程文档放 docs/。SDK、依赖缓存、构建产物、设备数据、签名文件与内部过程记录不提交。依赖锁文件、Gradle wrapper、运行资源和第三方声明保留。新增加载的资源须同步登记 pubspec.yaml。

参考[架构概览](architecture.md)、[安全与数据边界](security.md)和[Android UI 规范](android-ui-style.md)。
