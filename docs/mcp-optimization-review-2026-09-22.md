# 项目优化审查：先修数据正确性，再做性能优化

日期：2026-09-22

> 历史审查快照：本文描述实施前的源码与复现结果。后续修复和最终验证见 [优化实施与验证报告](mcp-optimization-implementation-2026-09-22.md)。本文的旧行号与预期失败命令不代表当前版本状态。

## 结论

不建议现在先大规模拆文件或继续微调动画。当前最高收益的工作是修复长会话消息定位、跨会话异步结果隔离、备份文件路径边界，以及分页状态管理。

本轮审查新增了 **5 条隔离复现用例，全部在正确性断言处失败，确认了 5 个缺陷场景**；另外实跑 CI 的静默异常门禁，发现 3 处不满足当前规则。这不是“原有测试全失败”：上一轮 51 项相关测试通过，本轮是补充此前未覆盖的场景。

本轮没有修改业务源码或原有测试。复现脚本放在仓库根目录 `.mcp-optimization-probe_test.dart`，不加入默认 `test/` 测试集。数据库均为内存库；文件恢复探针只使用隔离临时目录，并在测试结束后清理。

### 优先级一览

| 优先级 | 工作项 | 依据 | 主要收益 |
| --- | --- | --- | --- |
| P1 | 编辑重发、分叉统一用稳定消息 ID | 两条主机用例已复现 | 防止改错消息、误截断历史、分叉内容错误 |
| P1 | 分页结果绑定会话及请求版本 | 主机用例已复现 | 防止旧会话数据进入新会话 |
| P1 | 备份恢复校验技能包根路径 | 隔离文件用例已复现 | 防止恢复写出预期技能目录 |
| P2 | 分页耗尽、失败和临时忙碌分开处理 | 耗尽跨会话残留已复现 | 避免历史加载永久失效 |
| P2 | 补齐实际 CI 门禁验证 | 门禁实跑失败，3 处 | 防止本地测试通过但 CI 失败 |
| P2 | 优化当前流式消息，而非重复优化历史气泡 | 源码确认，待设备性能测量 | 减少全文扫描和稳定前缀子树重建 |
| P2 | 备份容量、完整性、恢复摘要及分叉批处理 | 源码确认，待专项测试 | 降低内存峰值，减少部分恢复和长事务外循环风险 |
| P3 | 按职责拆分大文件，并建立设备性能基线 | 结构统计与源码确认 | 降低修改成本，让优化有可比较的数据 |

## 1. P1：长会话编辑重发与分叉的消息定位错误

### 证据

- `lib/application/chat_controller.dart:2831-2839`：初次只加载最新 200 条数据库消息。
- `lib/application/chat_controller.dart:1558-1585`：编辑对象取自当前窗口，但按窗口内用户消息序号调用全库 `userMessageIdByOrdinal`；已有 `target.id` 没用于定位持久化锚点。
- `lib/application/chat_controller.dart:3078-3092`：分叉直接用当前界面的 `messageIndex` 索引全库 `messagesFor` 结果。
- `lib/application/chat_controller.dart:724-755`：恢复时还会把工具调用和工具结果转为活动，不一一保留在界面消息列表中。因此“界面索引等于数据库索引”不仅在分页时不成立。
- `lib/infrastructure/database/app_database.dart:1043-1052`：`messagesFor` 仅按时间排序，没有与 `messagesPage` 一致的 rowid 决胜排序。

### 实测

用 240 条按时间递增的消息初始化会话，当前窗口第一条为 `a-40`：

1. 编辑窗口第 0 条，实际修改的是 `a-0`，并截断后续原始消息。测试输出为 `firstContent=EDITED`，`a-40` 已不在原消息中。
2. 在窗口第 0 条分叉，预期复制原消息 0 至 40，共 41 条；实际仅复制 1 条，末条内容是 `a-content-0`。

这是数据正确性问题，不应只作为“全量查询太慢”处理。此前对同秒排序的修复没有解决“局部序号与全库序号不同”的问题。

### 建议

- 编辑、分叉等动作传入稳定 `messageId` 和 `conversationId`；异步前固定目标，不在等待之后重新解释索引。
- 新消息生成时分配并保留同一个持久化 ID，避免无 ID 时退回全库序号猜测。
- SQL 按 `(created_at, rowid)` 定位锚点和范围，编辑及截断保持事务原子性。
- 分叉的会话创建及消息复制放在同一事务内，优先批处理或数据库范围复制。
- 回归覆盖：超过 200 条、加载过旧页、包含工具调用、同秒消息、编辑对话框打开后会话变化。

## 2. P1：旧分页请求能把 A 会话数据写进 B 会话

### 证据

`lib/application/chat_controller.dart:2859-2883` 的 `loadOlderMessages` 在请求前读取会话 ID，但等待数据库返回后，没有再次检查当前会话或请求版本，直接更新游标并把旧结果前插到 `state.messages`。

另一个应一起修的细节是 `lib/application/chat_controller.dart:2969-2973`：`switchConversation` 先 `_trackLoadedWindow`，后检查切换代数。即使丢弃旧界面结果，也可能先写入了旧游标。

### 实测

1. A 会话加载旧页，故意延迟数据库结果。
2. 切到只有 10 条消息的 B 会话。
3. 释放 A 的分页结果。

结果：`conversation=b messageCount=50 firstId=a-0`。当前会话仍为 B，但列表混入了 A 的 40 条旧消息。

### 建议

- 请求绑定 `conversationId + switchGeneration + cursor`；所有 `await` 后、修改任何游标或 state 前验证身份。
- 同一会话的分页请求合并或加锁，防止重复页、重复前插。
- 用已存在于 `loadContextRuns` 一类逻辑中的请求版本思路统一管理，减少各异步入口自行实现。
- 回归覆盖 A→B、A→B→A、运行状态在请求期间改变、重复触发旧页加载。

## 3. P1：备份恢复只检查文件相对路径，漏了技能包名

### 证据

`lib/infrastructure/files/vault_exporter_io.dart:459-471`：

- 用 `p.join(docDir, 'skills', pack.name)` 生成技能安装根路径。
- 只检查 `skillFiles` 中的相对文件名是否含 `..` 或为绝对路径。
- 未对来自备份的 `pack.name` 做同等边界校验。

### 实测与边界

在单独创建的临时文档目录中，用包名 `../escaped` 和普通相对文件名 `marker.txt` 恢复，文件实际生成在该临时目录的 `escaped/` 中，而不是 `skills/` 下。测试输出 `wroteOutsideSkills=true`。

复现没有写入真实应用目录或任意用户文件。实际风险需要触发备份导入并提供可解密、格式可接受的内容；不据此声称存在无需用户操作的远程攻击。

### 建议

- 文件系统目录使用受控 ID 或经过验证的单段目录名，显示名称不要直接成为路径。
- 对包根目录和每个目标文件同时做规范化包含关系检查，拒绝绝对路径、上级跳转和不符合平台规则的目录名。
- 考虑符号链接/重解析点边界，先暂存验证再替换，不只依赖字符串过滤。
- 完整校验应发生在清理原数据库、写文件之前；同时限制文件数、单文件大小和总恢复量。
- 回归覆盖包名越界、文件名越界、绝对路径、符号链接及正常中文名称。

## 4. P2：分页状态会永久阻断后续历史加载

### 已复现

`lib/presentation/chat/widgets/chat_message_list.dart:80-123,188-203`：切换会话时仅重置窗口和动画集合，没有重置 `_dbExhausted`。

用例先让 A 返回“无更多”，再切 B 并触发滚顶。结果 A 加载回调执行 1 次，B 执行 0 次。

### 同一链路中的其他源码问题

- `loadOlderMessages` 在运行中、缺少游标或异常时都返回 `false`；列表却把所有 `false` 都记为永久耗尽。一次暂时忙碌或可重试错误不应变成“没有历史”。
- `_fetchOlderFromDb` 的异步结果也缺少会话身份校验。
- `_loadingOlder` 的复位不应依赖仍有 scroll clients，应放在可验证身份的 `finally` 路径。
- `_messageKeys` 未随会话切换清理；长时间跨会话使用会保留更多索引项，尚未测量实际内存影响。
- `ScrollController` 更换时，`didUpdateWidget` 未从旧 controller 移除监听并绑定新的 controller。

### 建议

将布尔加载结果改为明确状态，如 `loaded / exhausted / busy / failed`；仅 `exhausted` 锁定到底标记。切会话时复位分页状态，清理会话级索引；失败提供重试。上述属于同一个分页生命周期问题，宜一起修，而非分散加条件。

## 5. P2：定向测试通过，不代表当前 CI 门禁通过

已执行：

```sh
dart run tool/count_silent_catches.dart lib 0
```

退出码为 1。报告未记录意图的空 catch 共 3 处：

- `lib/infrastructure/terminal/android_shell_runtime_adapter.dart:374`
- `lib/infrastructure/terminal/android_shell_runtime_adapter.dart:384`
- `lib/infrastructure/terminal/android_shell_runtime_adapter.dart:424`

`.github/workflows/ci.yml:47-60` 已配置这道规则，门槛为 0。上一轮跑了定向 analyze、测试和 diff 检查，没有跑此门禁；因此不能把上一轮结果扩展为“CI 全绿”。

建议区分正常的进程消失竞争与权限/系统故障：前者写明为何返回 false，后者用不包含命令或秘密的诊断状态记录。不要只是为了降低计数而统一加无意义注释。

现有 CI 已有 analyze、全量测试、覆盖率门禁和 Android debug 构建，不需要重复建设一套。优先补齐本地同款验证入口，并把本轮复现用例在修复后纳入正式测试集。

## 6. P2：下一步性能目标应是“正在流式输出的那一条”

历史气泡复用已经做过，不建议再重复优化同一位置。

源码仍有以下成本：

1. `lib/presentation/markdown/markdown_render_policy.dart:43-82`：每帧从全文寻找代码围栏和段落边界，累计成本随输出长度增长。
2. `lib/presentation/chat/widgets/message_bubble.dart:692-710,773-804`：每次构建生成新的稳定前缀子组件。相同 `ValueKey` 保留 State，但不等于跳过 build；`RepaintBoundary` 隔离绘制，也不缓存 Markdown 解析。
3. `lib/presentation/markdown/math_block.dart:26-31,68-94`：构建时对收到的文本重新进行数学公式分段。
4. `MarkdownRenderPolicy.shouldDefer` 最终只是长度与阈值比较，却使用全文 hash 和 LRU；可以先简化这个纯判断，避免不必要的缓存维护。

建议先建立 5k/20k/50k 字符、不同刷新间隔、代码围栏和公式混排的 profile 基线，再决定增量扫描、稳定前缀 widget/块级缓存的范围。必须保留主题、文字缩放和跨段 Markdown 语义的正确性；文本被替换或重新生成时要清空增量状态。

本轮没有真机帧耗时、内存或解析次数数据，不承诺具体提升百分比。

## 7. P2：备份与分叉还需要“完整性 + 容量”工程化

### 分叉

`lib/application/conversation_fork_service.dart:19-44` 全量读取后逐条写入；会话保存与消息复制没有统一事务。失败时可能留下部分分支。`replaceSubsequent` 两个分支表达式相同，也需要明确参数语义或移除冗余。

### 备份

`lib/infrastructure/files/vault_exporter_io.dart:23-28,67-150,420-444` 全量聚合多张表、消息和技能文件，再进行 JSON、加密和编码。大备份会同时存在多份中间数据；JSON/base64 的同步处理也值得测量。

此外：

- `tasks` 和 `collaborationRuns` 导出显式限制为 2000 条，与文件顶部“全量本地数据”的描述不完全一致。应分页取完，或在清单中明确截断，不能静默丢失。
- 数据库恢复已有事务，不能说“恢复完全没有事务”；但技能文件和安全存储恢复在事务提交之后，跨资源一致性仍需要设计。
- `_restoreOptionalRows` 和技能文件恢复允许跳过失败项，最终成功摘要主要来自输入条数，应改为实际成功/跳过/失败计数。

建议先补备份 manifest（版本、条数、范围、校验及缺失项），进行格式和容量预检，再处理分页读取、分批写入和 CPU 密集部分的隔离执行。若改为分块加密，需同时设计版本迁移、块顺序和完整性认证，不能简单逐块拼接现有密文。

## 8. P3：大文件拆分与衡量指标

当前统计（不把生成的 `app_database.g.dart` 计为手写代码问题）：

- `lib/presentation/chat/chat_page.dart`：3468 行。
- `lib/application/chat_controller.dart`：3270 行。
- `lib/infrastructure/database/app_database.dart`：2131 行。
- `lib/presentation/chat/widgets/session_metrics_sheet.dart`：1660 行。
- 正式 `test/` 原有 `*_test.dart` 文件约 156 个；文件数量不等于覆盖充分。

建议按数据不变量和职责拆分，而不是机械按行数切开：

- 会话窗口、游标、请求版本归入一个负责分页状态的模块。
- 消息编辑/分叉用稳定 ID 的事务服务。
- 聊天页面拆出附件输入、历史动作菜单、工具审批等相对独立交互。
- 数据库以查询/事务边界组织 DAO，避免每次修改都触碰一个大文件。

配套记录：会话切换耗时、分页耗时、流式帧的 build/raster 分布、长会话内存峰值、备份大小与峰值内存、停止到实际进程退出的时间。已有渲染统计中从 build 开始到 post-frame 的耗时并不是纯 Markdown 解析 CPU 时间，指标名称与解释要准确。

`AdaptiveLinuxRuntimeAdapter` 未选中运行时时能力默认 true、选择阶段取消传播等，也值得作为后续防御性审查项；本轮未证明当前默认候选组合存在安全绕过，不将其提升为已确认漏洞。

## 9. 推荐执行顺序与验收

1. **先修消息定位与分页请求隔离**：两类数据正确性问题；让本轮编辑、分叉、跨会话和耗尽状态共 4 条用例通过。
2. **修备份路径校验**：让路径越界用例通过；补合法恢复、绝对路径及链接边界测试。对外发布前完成。
3. **恢复 CI 门禁**：静默异常规则为 0；新增用例并入正式测试，再跑完整 CI 对应命令。
4. **做长回复与备份基线**：有数据后实施增量扫描、稳定块缓存和容量治理。
5. **再拆核心大文件**：以已经通过的行为测试保护重构，不同时大改 UI、持久化和工具执行协议。

没有设备时可完成前面的源码和主机回归工作；真机杀进程恢复、锁屏审批和实际帧表现仍需设备验证。

## 10. 可复现命令与本轮范围

```sh
# 当前源码上预期失败：5 条正确性断言，均为内存数据库/临时目录测试。
flutter test .mcp-optimization-probe_test.dart --reporter expanded

# 当前源码上失败：3 处未记录意图的空 catch，门槛为 0。
dart run tool/count_silent_catches.dart lib 0
```

日志：`artifacts/logs/2026-09-22/.mcp-optimization-probes.log`、`artifacts/logs/2026-09-22/.mcp-optimization-catches.log`、`artifacts/logs/2026-09-22/.mcp-optimization-inventory.log`。

本轮为定向源码审查，不是完整安全审计；未运行全量测试、未做全仓 analyze、未构建 APK、未进行真机或大数据性能测试。已确认缺陷与源码推断的优化机会在上文分别标注。业务源码保持不变。
