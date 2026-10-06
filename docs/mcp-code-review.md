# NEXUS Agent 代码审查

> 2026-09-22 静态审查。只读应用代码，未做功能修复。
> 相关文档：`README.md`、`CHANGELOG.md`、`docs/mcp-project-completeness.md`、`docs/ui-improvement-handoff.md`。

## 1. 项目概览

Android 优先的多模型 AI Agent 客户端，包名 `mobile_agent`，产品名 NEXUS Agent，版本 `0.9.0+94`。

- 技术栈：Flutter / Dart，Riverpod，Drift/SQLite，Dio，flutter_secure_storage，MCP（`mcp_dart`），Sentry，WorkManager，dartssh2 + xterm。本机 `flutter --version` 为 Flutter 3.47.2 / Dart 3.13.2。
- 分层：`lib/domain`、`lib/application`、`lib/infrastructure`、`lib/presentation`。`find_files` 得到 `lib/**/*.dart` 303 个文件。入口是 `lib/main.dart`。
- 工作区：`/d/AIIIIII/ai agent/mobile_agent`。分支 `main`，跟踪 `origin/main`。最新提交 `cfa11b5 release: align v0.9 APK metadata`。
- 运行：`flutter pub get` 后 `flutter run`。发布包用 `flutter build apk --release --target-platform android-arm64` 或 `build-apk.bat`。
- 质量命令：`flutter analyze`、`flutter test`、`dart run tool/count_silent_catches.dart lib 0`、`dart run tool/check_coverage.dart coverage/lcov.info 55.0`。
- CI：`.github/workflows/ci.yml` 在 `main`、`feature/**` 和 PR 上跑 analyze、静默 catch 门槛、覆盖率 55% 和 arm64 debug APK。`.github/workflows/release.yml` 在 `v*` tag 上构建正式 APK。

本次验证：`flutter --version` 成功。`flutter analyze --no-pub` 从 `tool/` 启动时失败，错误是找不到 `pwsh`。从仓库根目录再跑时，Windows 批处理停在「终止批处理操作吗(Y/N)?」，没有分析结果。`flutter test` 未运行。下面的问题都来自源码阅读，不是本次测试输出。

## 2. 快速结论

1. 先把 `main` 上大量未提交改动分批提交并让 CI 跑过。当前最新提交仍是 v0.9 发布对齐，工作区是这批成果的主要副本。
2. 修复「重新生成」按秒级 `createdAt` 删除旧回复的逻辑，否则同秒的助手/工具消息会残留。
3. 应用锁在安全存储读取失败时直接当成未开启，应改为失败即锁定。
4. Android 终端是完整 `sh -c`，前台 `run()` 还会继承应用进程环境；「完全访问」会自动批准这个工具。
5. SSH 没有主机密钥校验回调；HTTP 私网策略不解析 DNS，公网域名可以连到内网地址。

## 3. Bug / 风险清单

优先级 | 文件:行号 | 问题 | 证据/代码片段 | 影响 | 复现/验证方式 | 建议修复 | 预估工作量
--- | --- | --- | --- | --- | --- | --- | ---
P1 | `lib/infrastructure/database/app_database.dart:1095-1110`；调用点 `lib/application/chat_controller.dart:1474-1491` | 重新生成只按 `createdAt` 严格大于最后一条用户消息来删除助手/工具消息。同文件 `1055-1058` 已写明 Drift 的 DateTime 按秒存储，同秒消息不能只用时间比较。编辑重发 `1113-1127` 已经改成按 id 删除。 | `createdAt.isBiggerThanValue(cutoff)`；内存侧也只删掉最后一条助手消息。 | 快速工具轮里，旧回复或工具结果删不掉。重开会话后旧内容回来，或和数据库不一致。 | 未运行验证。构造同一秒内的 user/tool/assistant 三行，调用 regenerate，再重新加载会话。 | 与 `editMessageAndTruncate` 一样按消息 id 删除该用户消息之后的行；内存状态同步删除整轮，而不是只删最后一条。 | 0.5 天
P1 | `lib/application/app_lock_service.dart:18-34` | 应用锁开关读取失败时返回 false，等于未上锁。 | `catch (_) { return false; }` | 安全存储短暂失败、迁移异常或平台通道错误时，已开启的应用锁被绕过。 | 未运行验证。让 `FlutterSecureStorage.read` 抛错，确认 `isEnabled()` 是否仍放行。 | 读取失败应视为已锁定，并给出重试；不要在异常路径返回 false。`setEnabled` 的空 catch（第 44 行）也应记录失败。 | 0.5 天
P1 | `lib/infrastructure/terminal/android_shell_runtime_adapter.dart:72-78`；对照 `121-127` | 前台执行用 `sh -c commandLine`，且没有关闭父进程环境继承。后台 detached 路径显式 `includeParentEnvironment: false`。 | `['-c', request.commandLine]`；detached 才设置 `includeParentEnvironment: false`。 | 模型或提示注入给出的命令可以看到应用进程环境。若以后有密钥进入环境变量，会直接泄露。超时只杀 shell 进程，子进程可能残留。 | 未运行验证。在 Android shell 上执行 `env`，对比应用进程环境。 | `run()` 与 detached 一样不继承父环境；超时杀进程组；在 UI 上把「cwd 不是沙箱」放在批准文案里。 | 1 天
P1 | `lib/application/approval_policy.dart:36-37`；`lib/infrastructure/tools/command_tool.dart:773-784,1154-1157,1203` | Android 运行时 `supportsShellSyntax == true`，白名单和管道拦截被跳过。terminal 风险是 `requiresConfirmation`，完全访问模式会自动批准。 | `if (!_runtime.supportsShellSyntax)` 才做白名单；`ApprovalMode.fullAccess` 返回 auto。 | 完全访问下，提示注入可以驱动手机 shell 执行管道、重定向和解释器脚本，并访问工作区外文件。README 已说明这不是完整沙箱，但默认风险仍偏高。 | 未运行验证。完全访问模式下让模型调用 terminal 执行 `echo hi | wc`。 | 保持危险级命令永远确认；或把 Android shell 的管道/解释器也纳入确认，而不是跟着完全访问自动放行。 | 1 天
P1 | `lib/infrastructure/terminal/ssh_terminal_session.dart:75-81` | 建立 SSH 客户端时没有 `onVerifyHostKey`。全仓库搜索该回调为 0。 | `SSHClient(socket, username: ..., onPasswordRequest: ..., identities: ...)` | 连接远程主机时可能接受任意主机密钥。本地 Termux 风险较低，远程 SSH 有中间人风险。库的默认行为本次未在 pub-cache 源码中复核。 | 未运行验证。连接一次未记录指纹的主机，看是否直接进入 shell。 | 首次连接展示指纹并让用户确认，之后钉死 known_hosts。校验失败必须断开。 | 1 天
P1 | `lib/domain/network_access_policy.dart:48-50`；`lib/infrastructure/tools/core_tools.dart:119-136` | 私网拦截只解析字面 IP。域名不做 DNS 查询。 | `InternetAddress.tryParse(host)` 失败就返回 false，随后允许访问。 | 攻击者控制的公网域名可以解析到 `10/8`、`192.168/16` 或链路本地地址，绕过注释里声称的 SSRF 防护。重定向逐跳校验挡不住这种解析。 | 未运行验证。用解析到 `127.0.0.1` 的域名调用 `http_request`。 | 连接前解析全部 A/AAAA 记录，任一私网/链路本地/环回地址都拒绝。考虑钉死解析结果再连接，避免 DNS rebinding。 | 1-2 天
P1 | 工作区 git 状态 | 大量改动未提交，CI 没有跑过这批代码。 | `git status -sb` 显示 `## main...origin/main`，porcelain 约 187 行。HEAD 为 `cfa11b5`。 | 误清理或磁盘故障会丢掉尚未推送的成果，也无法 bisect。 | 已用 git status 核对。 | 按功能分批提交到 `feature/**`，让 `.github/workflows/ci.yml` 跑 analyze、测试和覆盖率。 | 0.5-1 天
P2 | `lib/infrastructure/terminal/adaptive_linux_runtime_adapter.dart:28-32` | 尚未选中运行时时，`supportsShellSyntax` 和 `supportsInterpreterEvaluation` 默认 true。 | `=> _selected?.supportsShellSyntax ?? true` | 当前 Android 候选都支持完整 shell，所以现在不会误放行到桌面受限进程。以后若插入受限运行时，门禁会在选中前被绕过。 | 未运行验证。单测里在 `_selected == null` 时断言默认值。 | 默认改为 false，选中后再按真实运行时决定。 | 0.5 天
P2 | `lib/application/background_execution_gateway.dart:63-70,121-128` | 租约心跳失败被吞掉。注释写明租约 TTL 约两分钟，心跳 30 秒。 | `catch (_) {}` 只说明不要变成未处理异常。 | 数据库短暂失败后，另一个任务可能在本任务仍写工作区时拿到租约。 | 未运行验证。让 heartbeat 抛错并观察第二个任务能否 acquire。 | 心跳失败应取消或暂停当前 run，不能只记日志。 | 1 天
P2 | `lib/infrastructure/files/local_crypto_service.dart:31-38` | 保险箱口令只用 PBKDF2-HMAC-SHA256 10 万次。设备密钥在口令为空时使用固定字符串 `nexus-local`。 | `Pbkdf2.hmacSha256(iterations: 100000, bits: 256)` | 备份文件泄露后，弱口令比当前建议的迭代次数更容易被离线破解。设备密钥本身还依赖安全存储，这一点可接受。 | 未运行验证。看密文是否只含盐和 AES-GCM 盒子。 | 新备份改用更高迭代或 Argon2，并保留旧参数解密。不要把固定口令写进注释以外的可推导路径，除非明确这只是安全存储里的盐。 | 1 天
P2 | `android/app/src/main/AndroidManifest.xml:71-77`；`lib/infrastructure/share/deep_link_service.dart:23-34`；`lib/presentation/chat/chat_page.dart:1047-1050,436-440` | `nexus` scheme 可被浏览器和其他应用唤起，且不限制 host。未知 host 也会把 `prompt` 写入输入框。 | intent-filter 含 `BROWSABLE`；`default` 分支设置 `pendingPrompt`。 | 不会自动发送，所以不是直接越权。用户可能不看内容就点发送，把外部提示词交给模型和工具。 | 未运行验证。用 `adb shell am start -a android.intent.action.VIEW -d "nexus://evil?prompt=test"`。 | 只接受 `new-chat`、`new-agent`、`memory`。预填前提示来源，不要静默填入。 | 0.5 天
P2 | `android/app/src/main/AndroidManifest.xml:11`；`lib/presentation/projects/storage_access_flow.dart:10-23` | 申请「所有文件访问」权限，用来读写任意目录。 | `MANAGE_EXTERNAL_STORAGE`；Android 上导入项目前会引导授权。 | 授权后，Agent 终端和文件工具的实际可达范围远大于「工作区沙箱」这句话给用户的印象。 | 未运行验证。在未授权和已授权两台设备上导入工作区外目录。 | 优先用 SAF 持久化 URI，而不是所有文件权限。若必须保留，在完全访问和终端批准文案里写明。 | 1-2 天
P3 | `lib/presentation/chat/chat_page.dart` 3468 行；`lib/application/chat_controller.dart` 3255 行；`lib/infrastructure/database/app_database.dart` 2097 行 | 核心文件继续变长。交接文档里的拆分目标已经回退。 | `read_files` 返回的 `total_lines`。 | 回归难定位，评审和测试都集中在少数超大文件。 | 直接打开文件看行数。 | 按输入区、会话切换、运行控制、消息列表继续拆，拆完加行数守护测试。 | 2-4 天
P3 | `.github/workflows/release.yml:36-39` | 发布工作流只有 analyze 和 test，没有静默 catch 门槛，也没有覆盖率门槛。 | 对照 `ci.yml:47-69`。 | tag 发布可能绕过日常门禁。 | 阅读两个 workflow。 | 发布 job 复用同一组质量命令。 | 0.5 天
P3 | `android/app/src/main/res/xml/file_paths.xml:4-6` | FileProvider 暴露整个 files、external-files 和 cache。 | `path="."` | 组件本身 `exported=false`。若以后把 grant 用到非 APK 文件，其他应用可能读到私有文件。 | 阅读 XML 和 Manifest 第 101-108 行。 | 只暴露更新 APK 子目录。 | 0.5 天

未发现 `TODO`、`FIXME`、`UnimplementedError`。文件工具有符号链接逃逸检查（`workspace_tools.dart:35-52`）。Skill 安装有路径穿越、符号链接和类型白名单（`skill_installer.dart:503-563`）。数据库迁移从 v2 到 v24 都有 `if (from < N)`。这些不是问题，而是已经做对的边界。

## 4. 未完善功能

- 桌面小组件只做深链入口，不显示任务进度。证据：`AndroidManifest.xml:84-88` 和 `CHANGELOG.md` 对 RemoteViews 的说明。这是有意取舍，不是空按钮。若要补，需要单独的跨进程数据通道。
- 手机环境不能产出 Windows `.exe`。证据：`README.md:29`。应继续在环境页保持这个限制，不要做成看起来能构建的入口。
- 国际化不完整。存在 `lib/presentation/l10n/app_strings.dart`，但聊天、设置和工具文案仍大量硬编码中文。本次没有重新统计引用文件数。若只做中文产品，应在 README 写明；否则补字符串表。
- `chat_page.dart` 的拆分没有守住。当前 3468 行。交接文档里的目标已经过时，不能再把它当成待办状态的依据。
- `docs/ui-improvement-handoff.md` 与 `docs/mcp-project-completeness.md` 的部分结论需要以当前工作区为准。本次未逐项重跑其中的测试数字。
- 真机清单未在本次执行：压缩标记持久化、深色模式、杀进程恢复、长列表掉帧、锁屏审批。这些需要设备和 `adb`，本次未确认设备是否连接。

## 5. 优化建议

性能

- 会话切换已避免一次读入大量运行事件，这是对的。接下来应给消息分页和上下文快照查询补大会话基准，而不是再靠全量 `messagesFor`。
- `chat_page.dart` 仍是重建热点。流式回复应继续限制在消息气泡和进度条，避免整页 setState。

架构

- 终端安全策略散落在 CommandTool、Adapter 和 ApprovalPolicy。应有一个地方同时决定「能不能执行」和「要不要确认」。
- `AdaptiveLinuxRuntimeAdapter` 的默认能力不要乐观地设为 true。

可读性

- 先拆 `chat_page.dart` 和 `chat_controller.dart`。数据库迁移可以留在 `app_database.dart`，但 `onUpgrade` 应按版本拆成私有方法，避免 2097 行文件继续加分支。

依赖

- `pubspec.yaml:66-84` 把 `sqlite3` 钉在 `>=3.5.2 <3.6.0`，并用 `ghfast.top` 镜像下载原生库。哈希校验还在，供应链风险可控，但换机器或镜像失效时构建会失败。应把通过校验的 ARM64 库放进受控缓存。
- `sentry_flutter` 被钉在 9.28.0，注释说明 9.30 在 AGP 8.13 上会让 release 编译失败。升级前要单独验证 release，不要顺手升。

测试

- 已有审批、迁移、沙箱和敏感工具守护测试，方向正确。缺的是：同秒重新生成、应用锁存储失败、SSH 指纹拒绝、DNS 解析到私网、Android shell 不继承环境。
- 本次没有重新测量覆盖率。CI 门槛是 55%。不要把旧文档里的 57.30% 当成当前数字。

CI/CD

- 日常 CI 比发布 CI 更严。发布应复用同一组命令。
- 未提交代码不会触发 CI。提交本身就是门禁的一部分。

安全

- 见第 3 节。优先做失败关闭的应用锁、终端环境隔离、SSH 指纹和 DNS 级 SSRF。
- `network_security_config.xml` 默认禁止明文，只对 localhost 和模拟器别名放开，这一点是好的。
- 审批超时按拒绝处理，通知正文按敏感工具脱敏。这两点应保持，不要为了少弹窗放宽。

## 6. 建议修复顺序

第一轮

1. 分批提交当前工作区，推到 `feature/**`，看 CI 是否全绿。
2. 修复重新生成的同秒删除，并加回归测试。
3. 应用锁改为失败关闭。

第二轮

1. Android shell 不继承父环境，超时清理子进程。
2. SSH 主机密钥确认。
3. HTTP 策略在连接前解析并拒绝私网地址。
4. 收紧深链 host，并在预填外部 prompt 时提示来源。

第三轮

1. 拆 `chat_page.dart` / `chat_controller.dart`。
2. 发布 CI 对齐日常门禁。
3. 保险箱 KDF 参数升级，并保留旧备份解密。
4. 更新滞后文档；补真机验证清单。

## 7. 不确定项 / 需要我确认的问题

- 本次没有成功跑完 `flutter analyze`，也没有跑 `flutter test`。需要一份当前工作区的 analyze 和 test 输出，才能确认没有编译错误。
- `dartssh2` 在未提供 `onVerifyHostKey` 时是接受还是拒绝主机密钥，本次没在 pub-cache 里找到源码。需要该包的 `ssh_client.dart`，或一次真实连接日志。
- porcelain 约 187 行里包含仓库里原有的 `tmp-mcp-*.txt`。需要 `git status --porcelain` 的干净输出，才能给出精确的产品改动文件数。
- DNS rebinding 是否能在 Android 的 Dio/HttpClient 上稳定打到内网，需要一台设备和一条可控解析记录。
- 未确认是否有已连接的真机，因此交接文档里的 UI 清单全部未验证。
- 覆盖率、测试总数和「1002 项全绿」来自既有文档，不是本次测量。
