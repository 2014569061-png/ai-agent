# AGENTS.md

本文件是 NEXUS Agent 仓库级开发规则。规则适用于整个仓库；若某个子目录需要更严格的约束，使用该目录下的 `AGENTS.override.md` 或 `AGENTS.md`，并保持范围足够小。

## 项目概况

- 这是一个 Flutter/Dart 移动端多模型 AI Agent 工作台，主界面文案为中文，采用 BYOK：用户自行配置服务商、接口地址、模型和 API Key。
- 当前验证目标是 Android-only、ARM64（`arm64-v8a`）APK。Web/桌面发布、云同步、账户体系和新增模型 Provider 不在当前产品范围内，除非任务明确要求。
- 主要目录：`lib/domain`（领域模型与策略）、`lib/application`（用例与编排）、`lib/infrastructure`（数据库、Provider、工具、终端、平台能力）、`lib/presentation`（页面、组件、主题与文案）、`android`（Android 工程）、`assets`（资源和内置技能）、`test`（单测与 Widget 测试）。
- 修改前按任务需要阅读 `README.md`、`ENGINEERING.md`、`DESIGN.md`、`PRODUCT.md`；其中已有决策和回归护栏优先于凭直觉重构。

## 工作方式

- 先检查 `git status` 和目标文件的现状，只修改完成任务所需的最小范围；保留用户已有改动和未跟踪文件。
- 不使用 `git reset --hard`、`git checkout --`、批量删除或覆盖来“清理”工作区；不主动提交、推送、改写 Git ref，除非用户明确要求。
- 不把构建成功、测试通过或问题已修复写成推测。汇报时列出实际执行的命令和真实失败原因。
- 行为改变应补充或更新靠近该行为的测试。发现第三方组件语义不确定时，优先写最小探针/回归测试验证，不要只依据源码猜测。
- 不为顺手重构而扩大需求；尤其不要重新实现 `ENGINEERING.md` 中“已否决方向”或已删除的死代码。

## 环境与常用命令

目标环境为 Flutter 3.47+、Dart 3.13+；Android 构建使用 JDK 17。命令均从仓库根目录执行。

```bash
# 依赖
flutter pub get

# 静态分析：必须零告警
flutter analyze --no-pub

# Windows 本机测试：必须经脚本修正 flutter_tester 和代理环境
bash tool/test.sh
bash tool/test.sh test/<focused_test>.dart

# 中文文案门禁
bash tool/check_inline_zh.sh

# 本地运行
flutter run
```

- CI 在 Ubuntu 上直接运行 `flutter test`；Windows 本机禁止直接运行 `flutter test`，使用 `bash tool/test.sh`。
- 代码改动至少运行相关聚焦测试和 `flutter analyze --no-pub`；涉及跨模块行为、状态恢复或公共流程时再运行完整测试。修改 `lib/presentation` 的用户可见文案时，必须运行中文门禁。
- `flutter pub get` 只在依赖配置或锁文件需要更新时运行。不要提交 `.dart_tool/`、`build/`、签名文件或其他本地产物。

## 构建与发布

- 正式 APK 使用：

  ```bash
  flutter build apk --release --split-debug-info=build/symbols --obfuscate
  ```

  产物是 `build/app/outputs/flutter-apk/app-release.apk`，正式构建必须使用 `android/key.properties` 提供的正式签名；密钥、密码和 `android/app/upload-keystore.jks` 不得入库。
- `-PallowDebugSigning=true` 仅用于本地验证安装流程，不能把该产物当作发布包，也不能用它替代正式签名检查。
- 发布 tag 遵循 `v<versionName>`；发布归档必须包含 APK、同名 `.sha256` 校验文件和 `build/symbols/**`。当前包名为 `com.nexusagent.app`，验证 ABI 为 `arm64-v8a`。
- 需要连接真机时，优先使用仓库已有的 `一键热重载调试.bat`、`一键安装到手机.bat` 和 `构建.bat`，不要复制脚本逻辑到新的临时脚本。

## 架构与代码边界

- 保持现有目录职责，不做无关的跨层迁移。当前 `application` 负责组装和编排 `infrastructure` 能力，但禁止新增 `infrastructure -> application` 的反向依赖；需要跨层抽象时，优先在 `domain` 定义稳定接口。
- `presentation` 负责 Flutter UI 和交互，业务状态/编排放在 `application`，外部服务、持久化、终端、工具和平台适配放在 `infrastructure`。新代码先找现有服务、Provider、Token 和测试，再决定是否新增文件。
- Riverpod `Notifier.state` 是受保护成员。不要为了“拆文件”把必须访问状态的胶水层机械搬出 `Notifier`；必要时沿用现有的库内转发/`part` 方案。
- `ChatController` 的现有拆分和计划状态纯函数已有护栏测试；除非任务明确要求，不要重新开启 `ENGINEERING.md` 记录的第 2/4、3 步胶水层拆分。

### 数据库

- 当前 Drift schema version 是 19。任何 schema 变更都必须：递增版本、编写 `onUpgrade` 迁移、增加迁移测试。
- 绝不手改 `lib/infrastructure/database/app_database.g.dart`；它由生成器维护。PRAGMA 配置继续放在 `database_executor_io.dart` 的每连接 `setup` 中。
- 删除会话、任务或运行记录时，维持现有的关联事件、日志和审批轨迹清理语义；涉及敏感数据的持久化出口必须经过脱敏策略。

### 工具安全与隐私

- `UnifiedTool.sensitive` 表示审批升级；`SensitiveToolPolicy` 表示 SQLite、日志和导出出口的持久化脱敏。两者绝不可混用。
- 不要为了脱敏给 `read_file`、`terminal` 或 `write_file` 增加 `sensitive: true`；这样会错误改变审批行为。`read_file` 返回给用户复核的结果保持原文。相关改动必须检查 `test/sensitive_tool_policy_test.dart`。
- API Key、原始工具参数、运行日志、会话/保险箱导出不得泄露秘密。沿用系统安全存储和既有加密键名；不要改名 `sync.salt`、`sync.secret`，旧数据解密依赖它们。
- 不要删除 `MANAGE_EXTERNAL_STORAGE` 或破坏 `/sdcard/pocketforge-bridge` 的 Termux/终端桥能力。工作区不是完整文件系统沙箱；执行终端、网络、删除和发布命令前检查命令、参数和目标路径。

## UI、文案与视觉规范

- 产品当前只做中文，不做 ARB/gen-l10n。新增用户可见文案优先放入 `lib/presentation/l10n/app_strings.dart`；除 `lib/presentation/l10n/` 外，`lib/presentation` 内联中文内容行数不得超过 `tool/inline_zh_baseline.txt` 的基线。不要为了让门禁通过而随意改基线。
- body 内读取键盘高度一律使用 `lib/presentation/utils/keyboard_insets.dart` 的 `keyboardInset` / `isKeyboardVisible`；不要在 Scaffold body 内使用 `MediaQuery.viewInsetsOf` 代替它。
- 业务组件的颜色一律优先使用 `AppPalette` Token。硬编码色值只可出现在 `ENGINEERING.md` 列出的有意保留区；新增硬编码颜色先说明理由并补测试或评审依据。
- 遵守 `DESIGN.md`：4px 间距基栅、400/500 字重、卡片圆角不超过 16px（Pill 除外），禁止背景渐变、高斯模糊、彩色光晕、重阴影和回弹曲线。
- 修改字体时同时核对 `pubspec.yaml` 的 assets/fonts 声明与 `lib/presentation/theme/app_theme.dart` 的字体族/回退栈，不能只改其中一处。
- 聊天输入区保持既定顺序：附件行 → 指标条 → RunStatusCard → 压缩提示 → 技能槽 → 输入框。三类技能提示共用 `lib/presentation/chat/composer_skill_slot.dart` 的单一槽位，优先级为 `/` 补全 > 自动建议 > 已加载，running 时不显示。

## 验证与代码审查规则

提交或交付前，根据改动范围执行并报告：

- Dart/Flutter 代码：`flutter analyze --no-pub`，以及相关聚焦测试；Windows 本机测试使用 `bash tool/test.sh`。
- UI 文案：`bash tool/check_inline_zh.sh`，并确认新增文案位于合法文案表或有明确例外。
- 数据库：对应迁移测试，并确认没有手改 `app_database.g.dart`。
- Provider、终端、工具审批、导出或权限：检查隐私/审批边界和对应回归测试。
- 发布/Android 改动：确认签名、包名、versionName、ABI、混淆符号和 SHA-256 归档要求没有被破坏。

Code Review 时优先拦截以下问题：新增 `infrastructure -> application` 依赖、把脱敏概念混成审批标记、绕过键盘 inset helper、硬编码业务色值、中文门禁基线无理由上调、数据库无迁移就改 schema、泄露密钥/原始敏感日志、把 debug 签名产物当作正式发布包。
