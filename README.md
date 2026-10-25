# NEXUS Agent

面向移动端与 Windows 桌面端的多模型 AI Agent 工作台，当前源码版本为 **v0.9.0+95**。

支持 Android 与 Windows，提供多模型对话、Agent 工具执行、项目工作区及审批记录。

| 入口 | 内容 |
|---|---|
| [下载已发布版本](https://github.com/2014569061-png/ai-agent/releases) | APK、Windows 交付包与对应版本说明，以各 Release 实际附件为准。 |
| [本地运行](#本地运行) / [Windows 桌面端](#windows-桌面端) | 开发环境、Android 模拟器预览与 Windows 构建。 |
| [文档分类](docs/README.md) / [工具分类](tool/README.md) | 设计规范、验收记录、构建脚本与工程工具。 |
| [工作区约定](docs/workspace-layout.md) / [整理报告](docs/workspace-organization-2026-10-25.html) | 目录职责、归档位置与本轮清理结果。 |

## 当前验证状态

2026-10-25 本机检查结果如下；当前源码仍在开发中，安装包发布按[发布审查门禁](#发布审查门禁)执行。

| 检查 | 结果 |
|---|---|
| 静态分析 | `flutter analyze --no-pub` 无问题。 |
| 静默异常门禁 | 未记录意图的空 catch 为 0，通过。 |
| 全量测试 | 首轮 2,740 通过、69 失败；其中 64 项与整理前失败记录一致。 |
| 定向复测 | 另 5 个环境 / 并发相关失败所在的 4 个测试文件，串行复测 56 项全部通过。 |
| 手写代码覆盖率 | 59.55%，超过 55% 门槛。 |

全量测试尚未全部通过。完整结果、复测方法和待处理清单见[验证记录](docs/workspace-verification-2026-10-25.md)。

## 核心能力

- 支持 OpenAI 兼容接口、Anthropic、Gemini 和托管代理。
- 支持流式对话、多轮 Agent 执行、工具调用、计划确认、风险审批和失败重试。
- Android 内置浏览器支持独立临时会话、正文/DOM 观察及逐次审批的导航、点击、输入、滚动；触碰网页可接管。入口：左上角会话列表 → 会话与工具 → 内置浏览器。需系统 WebView 支持多 profile，关闭后需重新登录，见[浏览器使用与验收](docs/eta-improvements-phase3-browser-2026-10-20.md)。
- 内置工作区文件工具、MCP 服务、长期记忆、知识库和定时任务。终端在所有模式下均需逐次确认，保存的信任不能跳过；cwd 不是完整沙箱边界。
- 使用 Drift/SQLite 保存会话、任务和运行记录，支持离线数据和运行恢复。
- 提供运行时间线、Token/费用统计、缓存命中信息、诊断日志和报告导出；仪表盘「本周有帮助任务」按近 7 天窗口统计你标记为有帮助的开发任务。
- 长按助手消息可调用系统 TTS 朗读回复，朗读中同位置可随时停止（仅 Android 真机提供入口）。
- 支持协作分析：启动前确认角色、预算、轮次和只读权限，多个子 Agent 并行分析后生成结构化汇总。
- 支持「对话式创建 Agent」：说一句目标即可生成角色、系统指令、工作步骤、约束边界与工具范围的草稿，确认后才保存；草稿默认只勾选安全级工具。
- 支持系统级入口：长按应用图标可通过快捷方式直达「描述建 Agent」「新对话」「记忆」，桌面小组件「NEXUS 指挥台」提供同样的三个入口。
- 支持后台待审批通知：通知仅提供「打开查看」和「拒绝」，不能在锁屏直接批准。批准须回到前台，高风险工具还须验证身份；旧版通知的批准动作也会被后台入口拒绝，超时保守拒绝。
- API Key 使用系统安全存储，隐私保险箱支持加密备份与恢复。

## 开发目标与环境检测

环境页按当前开发目标检查工具，避免把无关 SDK 当成必需依赖：

- **静态网页**：无需 Node.js、Python、Flutter、JDK、Android SDK 或 Termux，可直接编辑和预览 HTML/CSS/JavaScript。

- **Node Web / Electron**：需要 Node.js 和 npm。
- **Python**：需要 Python。
- **Go**：需要 Go。
- **Flutter Android**：需要 Flutter SDK、JDK 和 Android SDK Build Tools。
- **原生 Android**：需要 JDK 和 Android SDK；优先使用项目自带的 `gradlew` / `gradlew.bat`，不要求单独安装系统 Gradle。
- **Windows `.exe`**：手机 Linux 环境不能直接生成 Windows `.exe`，最终构建必须在 Windows 主机完成。

静态网页项目可从「工作区 → 项目主页 → 网页预览与交付」直接打开本机浏览器预览，点击文件继续编辑，核对文件后保存 ZIP 成果副本并导出。无需安装 Linux 或 Python；已有自定义预览命令仍可单独使用。预览支持相对资源路径，退出交付页会停止服务。成果中心保存独立副本，后续源码修改不会替换已有交付。

可在环境页切换开发目标。默认只显示当前目标相关工具；完整运行时清单仅用于高级诊断。目标化安装不会安装无关工具，检测失败时仍提供错误信息和重试入口。

## Android 隐私边界

当前保险箱已纳入个人上下文（含关系、别名、遗忘保护与修订）、结果卡、提醒、移动工作流及研究成果。旧版 v1/v2 备份可能缺少这些分区：恢复时保留本机缺失分区并提示，不代表新设备能恢复备份里没有的数据。恢复的提醒保持暂停，未完成的结果动作不会自动执行。用户明确“清除全部数据”会清除相应本地数据。具体兼容边界见 [移动端续办验收记录](docs/mobile-completion-verification-2026-10-20.md)。

- 剪贴板和图片附件只在模型明确请求的当前回合按需读取，不会作为后台监听持续采集。
- 敏感工具的原始参数、结果、运行日志、会话导出和保险箱导出均在持久化出口脱敏；当前回合只向模型提供完成任务所需的原文。
- 删除会话会联动删除关联的运行事件、日志和审批轨迹。
- 审批授予记录会写入审计日志，可在设置的「审计日志」页查看。

## Android 权限、侧载与后台任务

- Android 发布目标为 ARM64（`arm64-v8a`）。Windows x64 通过独立构建脚本打包，见下面的桌面说明。
- 从 GitHub Releases 下载 `app-release.apk` 侧载安装。系统可能要求在设置中允许本应用安装未知来源应用；请只安装可信 Release，并在安装前用同名 `.sha256` sidecar 校验 SHA-256。
- 网络、通知、前台服务和电池优化豁免等权限只为对应功能使用。后台任务依赖系统调度与资源，是尽力而为，不保证精确到点。

## 终端与工作区边界

工作区是默认工作目录，不是完整文件系统沙箱。终端/解释器脚本可能访问工作区外文件和网络；终端始终需要逐次确认，即使已选完全访问或保存过信任。执行前请检查命令、参数和目标路径。其他工具仍遵循其风险、审批模式及授权边界。

## 发布审查门禁

Android Release 上传前运行 `tool/release_evidence_gate.py`，要求 `release/mobile-evidence.json` 中的候选 APK、签名证书、源码及验收报告哈希匹配，并逐项通过静态分析、Agent 回归、审批安全、ARM64、后台恢复、无障碍与性能门禁。缺失、运行中、超时或未授权的门禁不能算通过。当前没有生成通过证据；在真机验收获授权并完成前，正式上传将被阻止。

费用预算包含已结算估算和待确认预留，不是服务商账单。仪表盘可查看本机逐请求/尝试明细并人工对账，未知费用不按0处理；本地逻辑请求ID不是服务商requestId，未实现自动账单验证。费用账本及核对审计暂未纳入跨设备保险箱恢复，历史runRecords估算不等价，不能声称跨设备共享预算。研究来源近期核对只表示来源状态，不保证结论真实；远程执行页仅提供连接诊断，不表示持久远程作业已签收。实时音视频未完成，不作为当前交付能力。

## 手机本地开发能力

- 应用首次启动会幂等安装两项内置技能：`mobile-dev-basics` 用于在内置 Alpine PRoot 环境中体检并按需安装 Python、Node.js、Go、C/C++、Java 等工具链；`android-build` 用于将小型 Java/静态资源项目直接构建为可安装 APK。
- 开发项目应放在工作区内：工作区同时是文件工具和终端的默认工作目录。Alpine rootfs 与通过 `apk` 安装的包保存在应用目录，可跨会话复用。
- 手机直构建 APK 面向单 Activity/View 的 Java 小项目（例如贪吃蛇或工具页），使用 JDK 17、静态 `aapt2`/`zipalign`、D8 与 apksig，不适用于 Flutter 或大型 Gradle 工程。
- 首次安装手机 APK 工具链约需 500MB 且需要网络。下载失败时可按技能提示切换可用镜像或重试；每一步均应以终端真实输出为准。

## 环境要求

- Flutter 3.47.2（桌面构建已适配 Windows）
- Dart 3.13 或更高版本
- Android 构建需要 JDK 17

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

桌面版采用 B 方案的蓝白工作区，复用 Flutter、Riverpod 和 Drift/SQLite。窗口默认 1280×800，最小 900×640；宽屏同时显示项目导航、Agent 会话、代码差异/网页预览与终端，窄窗口通过弹窗打开工作台和终端。桌面跟随系统主题时默认使用蓝白浅色，也可以显式选择深色。Android 保持原有聊天入口。

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

B 方案的交付、验收结果与原生预览测试方法见 [桌面蓝白工作区交付记录](docs/desktop-blue-workspace-delivery-2026-10-10.md)。

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

## 项目结构

```text
lib/           应用源码、领域模型与界面
test/          自动化回归与测试夹具
assets/        字体、图片、内置技能与 Linux 运行资源
shaders/       Flutter 着色器
android/       Android 原生工程
windows/       Windows 原生工程与安装器
tool/          构建、预览、验收与质量门禁
docs/          工程文档、设计预览与分类索引
architecture/  架构决策记录
.github/       CI 与发布工作流
```

## 发布版本

前往 [GitHub Releases](https://github.com/2014569061-png/ai-agent/releases) 查看已发布版本。Android 安装包与 Windows ZIP 的可用性以该版本附件为准，下载后核对对应 SHA-256 校验文件。
