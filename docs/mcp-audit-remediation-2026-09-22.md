# NEXUS Agent 审查整改：高优先级第一轮

日期：2026-09-22

## 1. 结论与范围

本轮在当前未提交工作区上完成高优先级增量整改，重点为流式响应完整性、用量真实性、文件工具安全边界、终端作业资源管理与前台保活生命周期。**这不是整份历史审查清单的全项完成声明。**

- 改动范围：21 个 Dart 文件（15 个实现文件、6 个新增测试文件），清单见 `device-check/20260922-optimization/changed-files.txt`。
- 新增 55 个自动化回归用例。使用模拟 HTTP adapter、模拟终端运行时、隔离临时目录及测试数据库，不调用用户配置的真实模型。
- 保留既有未提交改动；没有 reset、clean、commit、push，没有清理用户备份或原有测试会话。
- 没有读取用户 API Key，没有修改模型服务设置，没有追加此前三次额度之外的真实模型请求。
- 构建及验证在开发机完成；本轮不安装到手机、不清除应用数据、不重新执行真机付费对话。

## 2. 先复核，而不是照旧行号重复修改

用户提供的审查发生在更早的工作区状态。以下项目在本轮开始前已经有实现，本轮保留并通过相关回归复核，不将它们冒记为本轮新修复：

| 历史问题 | 当前工作区状态 |
|---|---|
| 同秒消息截断、重新生成残留旧回复 | `lib/infrastructure/database/message_history_store.dart` 已使用 `(created_at, rowid)` 统一排序并在事务中截断；不是旧的单独 `createdAt > cutoff` 判断 |
| 编辑、分叉、历史分页的身份与异步竞争 | 已有稳定消息 ID、会话代次与事务保护；复跑 `test/optimization_regression_test.dart` |
| 保险箱恢复路径、分段失败与实际计数 | 已有清单校验、技能暂存、安全路径与失败补偿；本轮未重写恢复链，最终全量测试继续覆盖相关测试 |
| 新消息角标、深链接及历史回复元信息 | 已有 `chat_scroll_coordinator.dart`、深链接订阅与 `MessageDisplayMetadata`；本轮复跑相关主机回归，不重复覆盖这些实现 |
| APK URL 与资产自身 digest 错配 | 当前 `update_service.dart` 已在同一 APK 分支同时赋值 URL 和规范化 digest；多 APK 的 sidecar 选择及证书固定仍需单独完善 |

既有工作区报告可参考 `docs/mcp-device-fixes-2026-09-22.md`、`docs/mcp-optimization-implementation-2026-09-22.md`。它们的真机结果属于之前的验证，不混入本轮结果。

## 3. 本轮实际修改

### 3.1 流式响应与真实用量（P1）

文件：`lib/domain/models.dart`、`lib/application/agent_executor.dart`、三个 Provider 实现。

- `UsageEvent` 新增 `usageReported`，执行层累积真实上报标记，而不是见到事件就认为收到了测量值。
- Gemini、Anthropic 无用量或空用量对象时，不再将合成的零值声明成真实零 token。
- Anthropic 只有确实收到缓存字段时才报告 `cacheStatsReported`；真实上报的零和字段缺失保持区别。
- OpenAI 兼容解析不再因同帧带 usage 提前返回，保留同帧文本、推理、工具片段和停止原因；usage-only 帧继续有效。
- OpenAI 用量解析兼容 `input_tokens` / `output_tokens`，保留现有 DeepSeek hit/miss 和缓存解析。

### 3.2 文件工具边界（P2）

文件：`lib/infrastructure/tools/workspace_tools.dart`、新增 `lib/infrastructure/files/bounded_text_reader.dart`。

- 删除和移动操作拒绝工作区根目录及其规范化别名，普通根目录列表与工作目录解析仍允许。
- `edit_file` 拒绝空 target、重复匹配和重叠匹配；失败不写文件，要求补充唯一上下文。
- 文本读取先检查文件长度，再实际限量读取；文件在检查后增长也不能突破读取预算。
- 普通文本读取上限为 2 MiB，搜索单文件上限为 1 MiB；NUL 二进制和无效 UTF-8 不作为文本处理。
- 搜索跳过 `.nexus`、`.gradle`、`.venv`、`__pycache__`、`target` 及原有生成目录，跳过已知二进制扩展名；单条匹配预览限制为 500 字符。
- 写入前的旧内容读取、编辑及删除的变更元数据读取也复用有界读取，避免旁路全量读入。

限制：大文件即使请求少量行也会明确拒绝，可改用经授权的终端片段读取；搜索是有边界的辅助检索，不能把无结果解释为全盘没有该内容。本轮没有实现流式大文件编辑；这些读取上限也不限制传入的新写入/替换字符串或所有其他运行时内存。

### 3.3 插件 HTTP 方法与网络目的地（P2）

文件：`lib/infrastructure/plugins/plugin_store.dart`、`lib/domain/network_access_policy.dart`。

- 明确支持 GET、HEAD、POST、PUT、PATCH、DELETE，禁止未知方法静默变成 GET。
- 不支持的方法在 DNS 与发请求前失败；GET/HEAD 使用查询参数，其余方法使用请求体，副作用分类随真实方法变化。
- 插件请求连接到已通过策略检查的 DNS 地址，关闭自动重定向，保留原主机名的 HTTP/TLS 语义。
- 不自动重放写请求，每次结束关闭该次 Dio 客户端。
- 在既有 DNS 复检基础上补充元数据域名后缀/尾点、0/8、192.0.0/24、198.18/15、多播/保留 IPv4，以及 IPv6 未指定和多播地址的拒绝。

限制：本轮不将此声明成所有网络通道的完整 SSRF 审计。尤其 MCP HTTP 传输仍需单独核对 DNS 固定与重连；没有擅自增加会破坏已有服务配置的通用端口白名单。

### 3.4 终端作业与日志（P1/P2）

文件：`lib/infrastructure/tools/command_tool.dart`、新增 `lib/infrastructure/terminal/terminal_job_log_store.dart`。

- 最近已完成作业默认最多保留 50 条，完成、失败和逻辑取消均关闭事件 controller 并进入同一回收路径。
- 不再在作业对象中保存已完成 Future，避免其继续引用原始大输出；常驻结果保留末尾最多 262144 个 UTF-16 code units，并明确标记截断。
- 日志采用条数和时间保留策略：默认最多 50 个非活动 job 日志、7 天；保护当前活动日志，不处理其他命名的用户文件。
- 活动路径在日志层用规范化路径比较，避免 Windows 分隔符形式不同导致误删。
- job 的新落盘命令与输出复用 `SensitiveToolPolicy` 脱敏，实时内存结果仍可供当前任务读取。
- 普通异步 session 作业复用同一注册、started 事件、结果和日志链；关闭 session 不再让运行中的句柄消失。
- 订阅先建立再回放历史事件，避免回放期间错过完成事件。
- 无可验证独立 PID 的 daemon 返回无法单独停止，不再调用全局 runtime.stop() 误伤其他任务。
- `daemon_start` 在工具入口保持 24 小时默认超时，普通命令仍沿用原默认值。

限制：这里只保证已完成作业的保留边界，不宣称所有底层运行时、活动进程或 daemon 的峰值输出都已限量。现有普通 job 取消不是完整的每进程隔离方案；实际流式取消仍需独立验证。旧版已写入的原始日志不被冒称为已全部清除，清理策略在后续作业维护时生效。

### 3.5 前台服务超时与引用配平（P2）

文件：新增 `lib/infrastructure/background/foreground_run_lease.dart`、`foreground_service.dart`、两个执行入口。

- 启动期限由服务自身管理，移除调用方外包的 `.timeout(2s)`，避免调用方放弃等待而引用永远不释放。
- 启动失败或超时释放逻辑 owner；平台请求迟到完成后在串行队列中补偿清理。
- 清理前再次检查是否已有新 owner，防止旧请求的补偿停止新任务。
- 对已超时且仍在排队的启动请求，不再执行平台启动；失败不会污染后续队列。

限制：Dart Future 的超时不等于取消原生调用。若平台永久不返回，不能据此宣称已强行结束真实服务；本轮覆盖的是逻辑引用、迟到完成和失败路径，未新增 Android 锁屏/系统权限真机验收。

## 4. 回归与质量证据

新增测试：

| 文件 | 用例数 | 范围 |
|---|---:|---|
| `test/provider_stream_integrity_test.dart` | 11 | 三 Provider 的无用量、空用量、真实零、缓存字段，以及 OpenAI 同帧内容完整性 |
| `test/workspace_safety_regression_test.dart` | 11 | 根目录别名、移动根、唯一编辑、文件大小、私有/生成目录和二进制跳过 |
| `test/terminal_lifecycle_regression_test.dart` | 5 | 内存/磁盘保留上限、脱敏、关闭 session 后取结果、daemon 停止隔离及默认期限 |
| `test/terminal_job_log_store_test.dart` | 3 | 输出上限、按年龄/数量保留与活动路径保护、脱敏策略 |
| `test/foreground_run_lease_test.dart` | 7 | 并发引用、失败、超时、晚成功、晚失败、旧清理与过期排队 |
| `test/declarative_tool_http_test.dart` | 18 | 六种方法、未知方法、私网 DNS 拒绝及特殊地址段 |

修复前真实复现：Provider 新增测试 8 项失败，文件工具 10 项失败，终端生命周期 5 项失败；日志分别为 `device-check/20260922-optimization/provider-red.log`、`workspace-red.log`、`terminal-red.log`。

中间失败没有隐藏：新增前台服务测试曾使用不符合项目 Dart 3.5 语言版本的重复 `_` 参数，已修正；首轮 analyze 有 4 条 lint，已修正；首轮全量测试发现 Windows 活动日志路径比较问题，已修正并重新执行验证。首轮日志不当成最终成功证据。

### 最终结果

| 验证 | 最终结果 | 证据（均在 `device-check/20260922-optimization/`） |
|---|---|---|
| `flutter analyze --no-pub` | 0 issues，退出码 0 | `final-analyze.log`、`.exit` |
| `flutter test --no-pub --coverage --reporter expanded` | **1147 项通过，0 失败**，退出码 0 | `final-tests.log`、`.exit` |
| 生命周期专项复跑 | 15 项全部通过 | `lifecycle-final.log`、`.exit` |
| 作者代码覆盖率（门槛 55%） | **58.76%（19353/32933）**，退出码 0 | `final-coverage.log`、`.exit` |
| 含生成代码的覆盖率 | 53.33%（22960/43055），单独展示，不混淆门槛口径 | `final-coverage.log` |
| 未记录意图的空 catch（门槛 0） | **0**；另有 99 处已记录意图的注释型 catch | `final-catches.log`、`.exit` |
| 本轮 21 个 Dart 文件格式检查 | 0 changes，退出码 0 | `final-format.log`、`.exit` |
| 本轮文件 `git diff --check` | 退出码 0；仅存在 Git 的 LF/CRLF 提示 | `final-diff.log`、`.exit` |
| Debug APK | 成功，退出码 0 | `debug-build.log`、`.exit` |
| 验证前后本轮源码摘要一致性 | 一致，退出码 0 | `source-stability.log`、`.exit` |

全量测试中仍可见既有 Drift 多数据库实例警告，本轮没有通过关闭警告来伪造通过，也不将测试中的该提示直接等同于真机数据损坏。

最终验证使用的源码摘要见 `device-check/20260922-optimization/final-source-before.sha256` 与 `final-source-after.sha256`；一致性结果见 `source-stability.exit`。

### 构建产物

- 命令：`flutter build apk --debug --no-pub`。
- 结果：成功；Gradle 阶段 47.4 秒。
- 路径：`build/app/outputs/flutter-apk/app-debug.apk`。
- SHA-256：`6a17a3cf07862ecea4b9909fae86ce0271a340e043d845c7dd66f55fd36446b5`。
- 仅生成 Debug 包，未安装到手机，也没有构建、发布或验证 Release 签名包。
- 构建仍提示现有 Gradle 8.14.3、AGP 8.13.0、Kotlin 2.2.20 的未来支持迁移警告。未使用跳过依赖验证的参数，也未在本轮顺手进行未经回归的原生工具链大版本升级；建议单独安排升级验证。

## 5. 尚未在本轮解决的审查项

以下保留为后续工作，不虚报已完成；没有复核到当前源码的项仍只是待复核，而不是重新宣告它们已证实：

1. **MCP 客户端自愈与配置并发**：缓存连接失效摘除、同服务器并发连接合并、下一次重连，以及 Provider/MCP store 的读改写串行化。不得通过自动重放远端写工具“修复”连接失败。
2. **知识库与大附件**：索引缓存生命周期、批量事务入库、图片路径引用与惰性读取、超大附件的提早限量、工具 manifest 缓存。
3. **安全与产品取舍**：应用锁应补全还是移除、锁屏遮罩与认证错误提示、定时任务工作区权限及租约策略。需要明确行为契约，不能静默扩大后台权限。
4. **更新与发布链**：受信签名证书固定与轮转规则、多 APK/sidecar 精确匹配、预发行版本排序，以及 release/CI 门禁对齐。证书固定不能用临时猜测的指纹代替。
5. **其余正确性与维护**：配置清空后的工具信任状态、HTTP 非幂等重试、维护任务补偿异常、emoji 标题边界、KPI 交互、SSE 尾字节语义、Skill 读取时校验、剩余大类拆分。需以当前代码逐项确认，避免照旧报告误改。
6. **仓库卫生**：未擅自删除 `.bak/.mine`、截图、日志或其他人的开发产物，也未强行暂存被忽略的报告。忽略规则整理应单独给出可审查清单。
7. **设备和端到端验证**：真实中途取消、长历史/大消息压力、活跃任务中断恢复、Release/Profile 性能，以及发送→审批→持久化→重启恢复完整链路仍未宣告通过。

## 6. 证据位置

- 本轮日志、基线与源码摘要：`device-check/20260922-optimization/`。
- 原始工作区状态：`device-check/20260922-optimization/baseline.txt`。
- 最终质量汇总：`device-check/20260922-optimization/final-quality-summary.txt`。
- 本报告：`docs/mcp-audit-remediation-2026-09-22.md`。

本轮属于有回归保护的第一阶段整改，不是架构重写或整体验收；没有把覆盖率、Debug 构建成功解释为真机性能或全部安全问题已解决。
