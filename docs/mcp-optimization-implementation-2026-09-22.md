# 优化实施与验证报告

日期：2026-09-22

对应历史审查：[优化审查](mcp-optimization-review-2026-09-22.md)。本报告记录用户授权实施后的结果；历史审查中的失败探针、行号和“未修改业务代码”描述仅对应审查时点。

## 1. 范围与工作区保护

- 在现有 `mobile_agent` Flutter 工作区上增量修改，没有 reset、clean、提交、推送或清理其他人的改动。
- 修改前读取文件并使用版本哈希校验补丁；重连后重新核对关键文件。
- 报告已实际写入 `docs/`，但 `git check-ignore` 确认当前 Git 忽略规则排除了这两份报告；本轮未擅自更改忽略策略或暂存文件。需要提交报告时应由维护者显式纳入。
- 本次格式化范围为 `artifacts/baselines/2026-09-22/.mcp-optimization-scope.txt` 中的 32 个 Dart 文件，而非全仓格式化。
- 原有 CI 门槛保持不变：颜色常量上限 182、未记录意图的空 catch 上限 0、作者代码覆盖率最低 55%。颜色检查通过合并相同色值为语义别名实现，没有改色或提高阈值。
- 源码、主机测试、主机微基准与 Android 调试构建属于本次交付；设备 profile、真实杀进程恢复和发布签名不混入这些结果。

## 2. 已实现

### 消息定位与事务

- 编辑和分叉使用 `conversationId + messageId`，不再把可见窗口索引解释为数据库全局序号。
- `MessageHistoryStore` 统一 `(created_at, rowid)` 的顺序；编辑与范围删除在同一 SQLite 事务内完成。
- 分叉会话创建与 `INSERT … SELECT` 范围复制共用事务。锚点不存在或来自其他会话时失败，不留下半个分支。
- 新消息、流式占位及最终回复保留持久化 ID；运行开始时固定回复 ID，避免结束时从别的会话读取同位置消息 ID。
- 编辑、重新生成的数据库等待期间锁定运行状态；每次准备修改界面前同时检查会话切换代次和运行所有权。回归确认：A 操作等待时切 B，A 完成不改变 B 消息或运行状态。
- 异步消息菜单的编辑/分叉传递原消息身份，选择动作返回时重新按 ID 定位当前索引。

主要实现：`lib/infrastructure/database/message_history_store.dart`、`lib/application/conversation_fork_service.dart`、`lib/application/chat_controller.dart`、`lib/application/chat_run_execution.dart`。

### 历史分页与控件生命周期

- 新增 `ConversationHistoryPager`，管理 200 条初始窗口、100 条增量页、游标、请求合并及失效代次。
- 明确区分 `loaded / exhausted / busy / stale / failed`。只有 exhausted 锁定到底标记，失败可以再次触发加载。
- 控制器和分页器均校验会话身份；A 的未完成加载不会污染 B，也不会长期占住 B 的加载锁。
- 切会话时重置列表分页状态并清理消息键；更换 ScrollController 时移除旧监听、绑定新监听并使旧回调失效。
- 内存窗口和数据库加载后的滚动补偿回调都检查请求代次和 controller 身份，不把 A 的滚动偏移应用到 B。

主要实现：`lib/application/conversation_history_pager.dart`、`lib/domain/history_load_result.dart`、`lib/presentation/chat/widgets/chat_message_list.dart`。

### 保险箱与自动备份

- 安装目录使用技能 ID 的 SHA-256 值，不再直接拼接显示名称。
- 校验包名与相对路径，拒绝上级跳转、绝对路径、驱动器形式、非法字符、尾随点/空格、Windows 保留设备名、大小写冲突路径和孤立技能文件段。
- 对根目录/目标链接做检查，在发布前再次检查；文件在受控临时目录内解码、验证并写入。
- 清单记录版本、完整标记、条数和分段 SHA-256。恢复前检查格式、清单、容量和文件边界；旧 v1/v2 无清单备份继续兼容。
- 多表快照在 SQLite 事务中按 rowid 每 250 行分页读取，替代默认 getter 的 2000 条上限；超过预算明确失败，不静默截断。
- 缺失技能目录、链接、容量超限、检测到备份期间文件变化时拒绝生成“完整备份”。
- JSON 编码/校验等工作使用 isolate；仍保留有界整体快照，不声称改成了全流程流式加密。
- 文件发布与数据库恢复失败补偿配合：数据库事务回滚、还原被替换文件、安全存储失败时恢复旧密钥和原激活配置。
- 同一 isolate 内的恢复请求串行执行，防止一个失败恢复回滚另一个恢复的文件。对应并发失败测试已加入正式测试集。
- 文件补偿失败时保留临时恢复材料并报错，不删除唯一的回滚副本；提交后临时清理失败作为警告，不谎报数据库未恢复。
- 可选表行恢复不再逐条吞错；返回实际完成的恢复摘要。Provider 列表不再因模型名为空而静默跳过，激活配置随新快照保存；旧格式无此字段时按首项兼容。
- 自动备份先写唯一临时文件、flush 后 rename 为可发现备份；支持同时间并发发布。成功发布后才执行保留策略和更新时间戳。
- 导入 UI 在读取前检查文件长度；自动备份恢复增加覆盖确认，显示恢复报告。

容量预算：JSON 64 MiB、密文 96 MiB、记录合计 100000 条、技能文件 2000 个、单文件 8 MiB、技能总内容 32 MiB。数据库原始列字节预检更保守，先在 32 MiB 拒绝过大数据库快照，再检查实际 JSON 大小；因此这是明确的安全预算，不保证每个小于 64 MiB 的逻辑数据集都可导出。

主要实现：`lib/infrastructure/files/vault_manifest.dart`、`vault_snapshot_reader.dart`、`vault_skill_staging.dart`、`vault_exporter_io.dart`，以及 `lib/application/scheduled_task_runner.dart`。

### 流式 Markdown 与模块拆分

- 长文本延迟渲染判断改为长度/视口阈值判断，不再为该判断计算全文 hash 或维护缓存。
- `StreamingMarkdownScanner` 保存扫描位置、围栏状态及稳定段落边界；追加时扫描新增换行范围，重写时重置。
- 稳定 Markdown 区域复用同一个子组件实例，不仅保留 key；尾部继续作为文本显示。
- 自定义 MarkdownStyleSheet 的值、主题和文字缩放进入缓存失效签名，避免样式更新后继续复用旧内容。
- 按职责提取历史分页、数据库消息范围操作、保险箱清单/读取/暂存、流式渲染和消息菜单。
- `chat_state.dart` 与 `database_tables.dart` 采用 part，保持现有库私有性和生成代码兼容。这是受测试保护的责任拆分，不宣称完成全面分层或消除所有大文件。

### 终端防御性处理

- 处理已退出进程、权限及 `/proc` 检测失败的返回语义，并记录可忽略异常的具体原因，修复 3 处空 catch 门禁问题。
- Adaptive adapter 未选择运行时时使用候选能力的交集，不默认宣称全部能力可用。
- 检测请求共享同一个 Future；取消代次阻止检测或 fallback 后继续启动前台命令。
- 分离进程启动期间收到取消时，按原 owner token 补偿停止；无法确认停止时明确抛错，不宣称取消成功。

## 3. 回归覆盖

本轮新增 28 项正式回归，分布如下：

- `test/optimization_regression_test.dart`：原五个审查探针的正式版本、分叉事务、外会话锚点、分页重试、编辑/重新生成跨会话竞争、controller 替换。
- `test/streaming_markdown_incremental_test.dart`：逐字符前缀与重新扫描结果一致、CRLF/不同围栏、重写重置、50k 追加扫描工作量、稳定子树复用及主题/样式失效。
- `test/vault_safety_test.dart`：便携路径和保留名、孤立技能文件、清单/类型验证、密钥补偿、已发布文件与数据库失败回滚、并发恢复、2005 条审计记录完整导出。
- `test/adaptive_runtime_regression_test.dart`：能力声明、共享检测、检测/降级期间取消、后台启动期间取消。
- `test/automatic_backup_test.dart` 新增并发发布测试，原有备份和保留策略测试继续运行。

根目录 `.mcp-optimization-probe_test.dart` 保留为原始审查证据，不再用它的旧预期作为当前验收；正式测试中的越界恢复预期是抛出异常且不改变原数据。

## 4. 最终验证结果

最终源码上的本地主机验证全部通过。以下为实际运行结果，不代表 GitHub Actions 或 release 发布已执行。

| 检查 | 最终结果 | 证据日志 |
| --- | --- | --- |
| `flutter analyze --no-pub` | No issues found；退出码 0 | `artifacts/logs/2026-09-22/.mcp-final-analyze.log` |
| `flutter test --coverage --reporter expanded` | **1070 项通过，0 失败**；测试输出约 83 秒 | `artifacts/logs/2026-09-22/.mcp-final-tests.log` |
| 作者代码覆盖率，门槛 55% | **57.97%（18952 / 32695）**，通过 | `artifacts/logs/2026-09-22/.mcp-final-coverage.log` |
| 含生成代码覆盖率（仅展示） | 52.76%（22540 / 42724） | `artifacts/logs/2026-09-22/.mcp-final-coverage.log` |
| 未记录意图的空 catch，门槛 0 | **0**，通过；另有 97 处已有意图注释的 catch | `artifacts/logs/2026-09-22/.mcp-final-catches.log` |
| `git diff --check` | 退出码 0，无空白错误；有既有 CRLF 转换提示 | `artifacts/logs/2026-09-22/.mcp-final-diff.log` |
| 本次范围格式校验 | 32 文件，0 changed，退出码 0 | `artifacts/logs/2026-09-22/.mcp-final-format.log` |
| Android Debug APK | **构建成功**，退出码 0；最终增量 Gradle 构建约 18.1 秒 | `artifacts/logs/2026-09-22/.mcp-final-build.log` |
| 编辑器诊断 | 当前返回 0 项；以完整 analyze 结果为主要依据 | MCP `get_diagnostics` |

本轮共新增 28 项正式回归（四个新测试文件中的 27 项，以及既有自动备份测试文件中的 1 项）。并发恢复的最后补丁之后，重新跑了完整 analyze、1070 项测试、覆盖率/空 catch/格式/diff 门禁和 APK 构建，非仅沿用补丁前结果。

构建产物：`build/app/outputs/flutter-apk/app-debug.apk`。

- 大小：125737112 字节（Debug 包，不代表 release 体积）。
- SHA-256：`c6491e782eab61a44719ebf16154d9fffa0dbbaa3195f4ee2161bda4068132ba`。
- 产物核验：`artifacts/logs/2026-09-22/.mcp-final-artifacts.log`。
- 本次 32 个 Dart 文件的最终源码哈希：`artifacts/baselines/2026-09-22/.mcp-final-source-hashes.txt`。

主要文件拆分后行数：ChatController 2956、ChatPage 3281、AppDatabase 1599；提取的 chat state 367、数据库表定义 492、消息菜单 210、流式 Markdown 161。行数只是结构记录，不作为性能收益或完整架构重写的证据。

## 5. 可复现性能基线

脚本：`tool/benchmark_streaming_markdown.dart`。

保存结果：`tool/streaming_markdown_baseline_2026-09-22.json`。

环境：Windows x64、Dart 3.13.2，主机 JIT；每次追加 100 字符，两轮预热、七轮取中位数，交替测量顺序。计时不包括输入前缀数组的构造。对照是“每帧创建新扫描器”，不是旧发布版或整页渲染。

| 字符数 | 内容 | 重新扫描中位数 μs | 增量扫描中位数 μs |
| --- | --- | ---: | ---: |
| 2000 | 单段 | 17 | 15 |
| 2000 | 多段 | 888 | 100 |
| 10000 | 单段 | 351 | 238 |
| 10000 | 多段 | 9788 | 422 |
| 50000 | 单段 | 6223 | 6309 |
| 50000 | 多段 | 236725 | 6742 |

50k/500 帧下，扫描工作量计数从重新扫描的 12525000 个字符降至 50000 个字符。**这不是整体 CPU 复杂度或 250 倍速度声明**：`startsWith` 前缀验证、稳定字符串和尾部切片仍有成本；实测 50k 单段输入略慢于对照。稳定子树复用另有 widget 身份断言，不将主机时间外推为手机帧率或内存下降。

脚本记录的峰值 RSS 为整个基准进程的高水位，包含输入集合及两种算法，不能归因于某一种算法，也不能用于声称内存节省。

## 6. 明确边界与未测项目

- 未安装本次 APK 到连接的设备，未执行真机交互、build/raster 帧分布、长会话峰值内存、锁屏审批、杀进程恢复或停止延迟测量。发现设备不等于完成设备验证。
- SQLite、文件系统和安全存储不是跨资源原子事务；当前覆盖受控失败补偿及同 isolate 并发隔离，未提供断电/进程被杀后的持久恢复日志，也不声称跨进程/跨 isolate 恢复串行化。
- 文件系统链接检查不是对具有同等系统权限的并发恶意进程的无竞态安全保证；未在 Windows/Android 所有重解析点及 ROM 组合上验证。
- 新清单能检测意外缺段和内容变化；旧备份没有清单时无法证明导出端曾包含全部数据。兼容旧备份不应解释成给旧快照补上完整性保证。
- 行转换或数据库约束错误仍可能在恢复事务内被发现，此时整次失败并补偿；不将部分转换成功报告为成功恢复。
- 仍物化有界 JSON 和加密数据；没有做分块认证加密格式迁移，也没有内存优化前后对照数据。
- 增量扫描的稳定边界基于段落和围栏，不能把所有 Markdown 跨段引用语义都视为绝对不变；完整回答结束后仍走完整 Markdown 渲染。
- Debug 构建不等于 release 签名、商店发布或线上 CI 已运行。仓库已有 Gradle/AGP/Kotlin 版本弃用预警，本轮不顺带升级构建工具链。

## 7. 复现命令

```sh
flutter analyze --no-pub
flutter test --coverage --reporter expanded
dart tool/check_coverage.dart coverage/lcov.info 55.0
dart tool/count_silent_catches.dart lib 0
git diff --check
xargs dart format --output=none --set-exit-if-changed < artifacts/baselines/2026-09-22/.mcp-optimization-scope.txt
flutter build apk --debug --no-pub
dart run tool/benchmark_streaming_markdown.dart > benchmark.json
```

本机使用 Flutter 自带的 Dart（`/c/src/flutter/bin/cache/dart-sdk/bin/dart.exe`），避免 `flutter doctor` 提示的 PATH 中独立 Dart SDK 优先问题。复现时应保证 Flutter/Dart 版本与基线一致。
