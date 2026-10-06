# 一键 APK 构建脚本优化记录

日期：2026-09-22。入口保持为仓库根目录 `build-apk.bat`，继续支持双击构建，不引入 Python 作为构建依赖。

## 改动范围

- `build-apk.bat`：参数、检查顺序、互斥锁、构建日志、发布调用和失败提示。
- `tool/build-apk-tools.ps1`：Windows PowerShell 5.1 兼容的环境检查、校验发布、历史包保留。
- `tool/test_build_apk.py`：使用 Python 标准库的 Windows 隔离回归测试；仅测试需要 Python。
- `README.md`：更新参数、产物及保留规则说明。

未修改应用业务代码、签名配置、Gradle 配置或依赖版本，没有 Git 提交。

## 使用方式

```bat
build-apk.bat
build-apk.bat --check --no-pause
build-apk.bat --offline
build-apk.bat --online
build-apk.bat --online --keep 5
build-apk.bat --keep-all
build-apk.bat --no-pause --no-open
build-apk.bat --install
build-apk.bat --clean --online
build-apk.bat --fast
```

- 默认继续复用 Flutter、Gradle 和 SQLite 原生缓存。依赖配置时间戳没有变化时跳过 pub get；需要恢复时默认尝试 Pub 离线恢复。
- `--check`：只读检查入口。检查 Flutter/JDK、版本一致性、签名字段及实际 keystore 路径、Android SDK 平台、依赖配置和 SQLite ARM64 缓存，不构建、不清理、不安装设备。可能使用短生命周期的系统临时文件，不修改工程依赖。
- `--clean` 必须配合 `--online`，否则在任何清理发生前拒绝执行。冷构建仍会清除原有缓存，请仅在有必要时使用。
- `--keep N`：N 为 2～50，默认 3。成功发布后，最多保留 N 个有效时间戳包，再额外保留 `nexus-agent-latest.apk`。
- `--keep-all`：关闭当次自动历史 APK 清理；与 `--keep` 同时给出时以保留全部为准，但数值仍须合法。
- `--no-pause`：退出不等待按键；`CI=true` 时也不等待。
- `--no-open`：成功后不打开 Explorer；CI 模式也不打开。
- `--install` 保持原有行为：只在发布成功后安装，并尝试启动应用。安装或启动失败时明确提示 APK 已发布，不再误称“未发布”。
- `--fast`：本地迭代模式，通过 `--android-project-arg=fastBuild=true` 关闭 R8 与资源收缩，产物约 25MB（完整 release 约 21MB）。该产物**不发布**到 `dist/`、不更新 `nexus-agent-latest.apk`、不参与历史保留，也不会被 `--install` 使用；安装时改用本次构建的 fast APK。完整 release 仍强制 R8，保留原有体积与优化保证。

## 速度与警告处理（2026-09-22 增补）

- 构建脚本新增 `--android-skip-build-dependency-validation`，用于消除 Flutter 3.47.2 在每次构建中重复打印的 Gradle/AGP/Kotlin “will soon be dropped” 版本提示。此前这些提示会被包装成 PowerShell `NativeCommandError` 噪声；日志输出也由 `2>&1 | Tee-Object` 改为 cmd 重定向加 `type`，不再改写 Flutter 的 stderr。
- 该参数也会跳过 Flutter 的**最低版本**硬校验，因此 `tool/build-apk-tools.ps1` 的预检新增 `Assert-MinimumToolchain`：直接从 `android/settings.gradle.kts` 与 Gradle wrapper 读取实际版本，并按 Flutter 3.47.2 的下限（Gradle 8.14.0、AGP 8.11.1、Kotlin 2.2.20）重新强制校验。低于下限会在构建前失败，而不是静默通过。
- `android/gradle.properties`：新增 `org.gradle.daemon=true`、`org.gradle.parallel=true`，保留 `org.gradle.caching=true`；删除 `android.aapt2.daemon=false`（恢复 AAPT2 daemon）与 `android.overridePathCheck=true`（移除实验性提示）。`android.useAndroidX`、`android.newDsl=false`、`android.builtInKotlin=false` 与 `kotlin.jvm.target.validation.mode=warning` 保持不变。
- 配置缓存（`org.gradle.configuration-cache`）**未启用**：Flutter 3.47.2 + AGP 8.13 的 `assembleRelease` 任务动作会捕获 JDK `ReferenceQueue`，在 Java 17 下无法序列化，启用后构建直接失败。daemon、并行与任务缓存提供主要加速，且不改变正确性。
- 不升级 Gradle/AGP/Kotlin 到 9.1.0/9.0.1/2.3.20：Flutter 3.47.2 自带 Gradle 插件会把 Android 扩展强转为旧 `AbstractAppExtension`，AGP 9 下 `dev.flutter.flutter-gradle-plugin` 无法应用；KGP 2.3.20 还会让 Android 侧产生大量 `kotlin.Metadata 2.3.0 > 2.2.0` 信息刷屏。因此选择在被证实的兼容组合上消除提示，而不是升级到不兼容的工具链。
- `tool/build-apk-tools.ps1` 的 `Get-Hash` 与 `build-apk.bat` 内联校验改用 .NET `SHA256`：部分 Windows PowerShell 环境不提供 `Get-FileHash`，原实现会把“有缓存”误判为“缺缓存”并拒绝离线构建。

## 历史包保留规则

1. 只有新 APK 已复制、校验，并且 latest 更新成功后才触发清理。
2. 始终保留本次新包；存在不同版本的历史包时，额外优先保留其中最新一个作为回滚候选。其余名额保留时间戳较新的包。
3. 只识别本脚本的完整 APK 命名，并要求有有效的同名 `.sha256` 配对；兼容过去的秒级时间戳名称。
4. 不删除不认识的文件、无校验文件、校验失败文件或链接文件；因此 dist 实际文件数可能超过名额。这是有意的安全设计。
5. APK 与 sidecar 成对处理，删除前重新校验；若清理失败，保留已发布 APK 并给出警告，不把成功构建误判为失败。
6. 自动清理是真正删除，不移入回收站，也不额外备份。重要发布包应先外部归档，或使用 `--keep-all`。
7. “回滚候选”不代表已验证降级安装及数据兼容性。

## 发布和故障恢复

- 唯一时间戳采用 UTC 毫秒加随机后缀，避免同秒构建覆盖归档包。
- 新 APK 先写入 dist 内本次专属暂存目录，核对 SHA-256 后发布。
- latest 的 APK 与 sidecar 各自使用同卷文件替换；两者不是跨文件原子事务，突然断电/进程强杀仍可能造成不一致。
- 可捕获的发布错误会尝试恢复旧 latest；恢复失败时保留 `.publish-*` 内的恢复文件并提示路径，不自动删除这些恢复材料。
- 发布后续步骤失败时，新时间戳包可能仍存在。这比清理掉唯一成功复制的新包更保守。
- 构建互斥目录：`artifacts/build-apk/.lock`。正常退出会移除；强制关闭窗口可能留下锁。必须先确认没有构建运行，再手工移除该空目录。不要按“锁很旧”自动删除。
- 日志路径：`artifacts/build-apk/build-<随机标识>.log`，保存 Flutter APK 构建阶段输出；环境预检、Pub 恢复、发布和安装提示仍主要在控制台，不宣称日志覆盖整个生命周期。日志未自动轮转，可按之前的清理规则归档。

## 环境兼容与边界

- 签名检查依据 `android/key.properties` 中的 `storeFile` 解析，不再假设必须叫 upload-keystore.jks；相对路径基于 android/app，与现有 Gradle 配置一致。不打印密码或私钥内容。
- 预检检查 `pubspec.yaml` 与 Android `versionName` 是否一致，防止文件名版本与包内配置版本混淆。
- 支持本机的 `android-37.0` SDK 平台目录，也支持常见的 `android-37` 形式。
- SQLite package_config 的 rootUri 改为相对配置文件正确解析，继续使用缓存哈希检查。
- 不修改全局 Flutter JDK 配置。
- `--offline` 约束 Pub 依赖恢复并检查 SQLite 缓存，不是网络防火墙；Gradle、Flutter 或其他 hook 仍可能需要网络。
- 密钥密码有效性、APK 实际签名、SDK licenses、NDK/Gradle 依赖完备性只能通过真实构建/专用 APK 校验进一步证明。本次未新增发布证书身份校验，也不把 sidecar 校验当成签名认证。
- 密钥路径只解析项目常用 Java properties 写法；复杂 Unicode 转义或续行路径会明确拒绝，建议使用正斜杠普通路径。

## 验证结果

已在用户 Windows 主机完成：

- 真实端到端构建：`build-apk.bat --no-pause --no-open` 成功（exit 0），完整 R8 release 产物 20.7MB，已发布并校验 SHA-256；构建日志仅 3 行（启动时间、`assembleRelease`、产物大小），**无任何版本警告或 `NativeCommandError`**。
- 因果确认：同一命令在**不加** skip 参数时，仍会打印 Gradle 8.14.3 / AGP 8.13.0 / Kotlin 2.2.20 三条“will soon be dropped”提示；加上后完全消失。
- `--fast` 端到端：Gradle 阶段 8.6 秒、25.5MB 未收缩包；`dist/nexus-agent-latest.apk` 的 SHA-256、修改时间与文件数量在构建前后完全一致，确认未发布、未保留、未覆盖。
- 工具链闸门负向测试：把 AGP 改为 8.10.0 后预检以退出码 1 拒绝，并给出明确下限提示。
- `python tool/test_build_apk.py`：8 项测试全部通过（新增 `--fast` 不发布用例与工具链下限夹具）。
- 测试在系统临时目录内生成假 APK 和假 SDK/签名文件，不运行真实 Flutter/Gradle，不读取或删除实际发行包，不安装设备。
- `build-apk.bat --check --no-pause --no-open`：本机预检通过；输出明确声明没有构建或设备安装。
- `get_diagnostics` 对 tool/ 返回 0 条错误/警告；此结果不替代 Windows 执行测试。
- `git diff --check -- build-apk.bat README.md` 通过；新增文件没有尾随空白。仅有 Git 的 LF/CRLF 转换提示，记录见 `artifacts/build-apk-validation/final-check.json`。

日志：

- `artifacts/build-apk-validation/tests.log`
- `artifacts/build-apk-validation/preflight.log`
- `artifacts/build-apk-validation/preflight-result.json`

本次已运行真实 release APK 构建（完整 R8，exit 0）与 `--fast` 构建；未运行全量 Flutter 测试或真机安装。构建提速为增量场景测量值（Gradle 阶段 8.6～32.5 秒），冷构建耗时未测量。
