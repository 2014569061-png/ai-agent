# 工作区目录与归档约定

本次目标：减少无用占用，让源码、文档、工具、交付包与本机材料可定位，并保留现有开发和恢复能力。业务目录沿用 Flutter 的构建、导入与测试路径；通过分类索引管理历史文档，避免批量搬迁破坏引用。

[文档分类](README.md) · [工具分类](../tool/README.md) · [整理报告](workspace-organization-2026-10-25.html) · [仓库文件索引](workspace-file-index.csv)

## 根目录

| 路径 | 分类 | 用途 |
|---|---|---|
| `lib/` | 产品源码 | application 协调流程，domain 定义模型与规则，infrastructure 接入存储和工具，presentation 提供界面，debug 放隔离验收入口。 |
| `test/` | 自动化测试 | 回归测试及 fixtures；保留原有目录与测试发现规则。 |
| `assets/` | 运行资源 | 字体、图片、内置技能、ARM64 Linux 运行时；压缩包也可能是必要资源。 |
| `shaders/` | 运行资源 | Flutter 着色器。 |
| `android/` | 平台工程 | Android 原生代码、Gradle wrapper、本机配置与签名材料；本机配置保持忽略。 |
| `windows/` | 平台工程 | Windows 原生宿主和安装器；flutter/ephemeral 为生成产物。 |
| `tool/` | 工程工具 | 构建、预览、验收、质量门禁与性能探针，详见工具索引。 |
| `docs/` | 工程文档 | 规范、评审、验收及设计预览；index.html 是原有下载站点，不替换。 |
| `architecture/` | 架构决策 | adr/ 保存架构决策记录。 |
| `.github/` | 持续集成 | 日常质量检查与发版工作流。 |
| `local/` | 本机环境 | SDK、模拟器、依赖缓存、外部素材、备份与临时文件；不上传 Git。 |
| `artifacts/` | 本机证据 | 按用途和日期存放日志、截图、基线与验收产物；不上传 Git。 |
| `dist/` | 交付包 | 保留现有 APK、Windows 包和校验文件；不上传源码仓库。 |
| `build/` | 构建产物 | 保留当前构建与增量产物，避免丢失尚未交付的输出。 |
| `.dart_tool/` | Dart 工具状态 | 仅清理过期 flutter_build 哈希目录；保留近期构建、包配置及 hooks_runner 离线原生库。 |
| `coverage/` | 覆盖率产物 | 当前覆盖率原始数据；可由测试重新生成。 |
| `chanpin/` | 本机工具链 | Visual Studio 安装目录，移动会破坏注册路径；保持原位。 |
| `.vs-cache/` | 本机工具链 | Visual Studio 安装管理缓存；不作为普通临时文件删除。 |
| `.vs-shared/` | 本机工具链 | Visual Studio 共享目录；保持原位。 |
| `.skill-install/` | 外部工具 | 技能安装包与提取内容，保留供外部工具使用。 |
| `.playwright-cli/` | 外部工具 | 浏览器工具的本地会话状态与快照；保留原路径。 |
| `.workbuddy/` | 外部工具 | 工具会话及记忆。 |
| `.workbuddy-ai/` | 外部工具 | 工具记忆。 |
| `.zcode/` | 外部工具 | 工具本地会话目录。 |
| `.idea/` | 编辑器配置 | IntelliJ / Android Studio 本机配置。 |
| `.git/` | 版本历史 | 保留对象、引用和索引；不手动清理。 |

根目录的 README / CHANGELOG / HANDOFF / AGENTS / THIRD_PARTY_NOTICES、pubspec、analysis_options、.metadata、.gitignore 继续作为项目入口与配置。android-preview.bat、build-apk.bat、run_desktop_verification_and_build.bat 保留便捷入口；pwsh.cmd、.flutter_tool_state、.flutter-plugins-dependencies、*.iml 为本机工具材料。

## local 本机目录

| 路径 | 用途 |
|---|---|
| `local/android-sdk/` | Android SDK、模拟器与系统镜像；其中 7 个目录链接复用本机工具。 |
| `local/android-avd/` | 虚拟手机用户数据与快照。 |
| `local/android-user/` | Android 工具状态。 |
| `local/android-preview/` | 预览进程的 VM 服务定位信息。 |
| `local/flutter/` | 本地 Flutter SDK 副本。 |
| `local/gradle-cache/` | Gradle 依赖、wrapper 与转换缓存。 |
| `local/pub-cache/` | Dart / Flutter 依赖缓存；现有 package_config 仍可能引用既有外部缓存。 |
| `local/preview-downloads/` | 新增下载归档的指定位置，目前为空。 |
| `local/temp/` | 当前临时文件；旧验收数据、数据库快照与运行日志按原路径保留。 |
| `local/archives/` | 按日期归档的源码备份及历史本机文件。 |
| `local/review/` | 测试分析及本次完整文件清单、计划、日志和验证结果。 |
| `local/tidy-backup/` | 此前整理产生的补丁、清单和失败分析，保留恢复能力。 |
| `local/batch1-baseline-20261020/` | 移动端验收基线备份。 |
| `local/desktop-tools/` | Windows 构建辅助工具。 |
| `local/sentry-native-exact/` | Sentry 原生依赖源码。 |
| `local/sentry-native-windows/` | Sentry Windows 构建依赖。 |
| `local/windows-sdk-nuget/` | Windows SDK NuGet 包。 |
| `local/remote-executor/` | 远程执行器本机状态。 |
| `local/reference-repos/` | 外部参考仓库。 |
| `local/vendor/` | 外部工程和第三方素材。 |
| `local/visual/` | 本地视觉素材。 |
| `local/presets/` | 外部预设导出。 |
| `local/tools/` | 本机一次性辅助脚本。 |

## 新文件放置

- 正式设计、评审、规范：`docs/`；设计附件放对应的 `docs/design-previews/<主题-日期>/`，并更新文档索引。
- 可复用工程脚本：`tool/`；历史脚本：`tool/legacy/`，并注明用途。
- 日志：`artifacts/logs/YYYY-MM-DD/`；截图：`artifacts/screenshots/YYYY-MM-DD/`；基线：`artifacts/baselines/`。
- 新增下载：`local/preview-downloads/`；临时文件：`local/temp/`；本机备份：`local/archives/YYYY-MM-DD/`。
- 交付安装包：`dist/`，保留对应校验文件；源码提交不包含本机包和缓存。

## 清理边界

只有明确过期的生成文件可直接清理。当前保留 build/ 与近期 Flutter 编译缓存；依赖、模拟器、签名、数据库快照、历史验收证据及外部参考材料不能因被 Git 忽略就删除。Visual Studio 安装目录和 Android SDK 链接不移动。

本次删除的是 2026-10-18 之前最后修改的 Flutter 哈希编译目录，以及 2026-10-23 之前的遗留 Flutter 临时编译目录；这些历史目标下次使用会重新编译。`hooks_runner/` 中 SQLite 原生依赖保持完整。

## 清单与恢复

完整本机递归盘点与操作记录在 `local/review/workspace-tidy-2026-10-25/`：`inventory-before.jsonl` 登记普通文件、目录和链接，`plan.json` 记录明确范围，`journal.jsonl` 记录已执行动作，`protected-before.json` 保存受保护文件哈希，`execution-result.json` 保存核验结果。这些本机材料不上传公开仓库。

45 个移动文件可依 plan.json 的 from/to 反向搬回；恢复前检查原路径未被新文件占用，并恢复相关文档引用。删除的过期编译缓存没有备份，需由 Flutter 重建。一次性 organize.py 已执行，禁止直接重复运行。

本次盘点覆盖所有普通文件的元数据，链接只登记不穿透，不是对全部文件逐行代码审计。大小为文件逻辑长度；稀疏文件、硬链接及压缩会使其与 Windows 实际占用不同。
