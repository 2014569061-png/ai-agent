# 前后端代码审查交接

日期：2026-10-18  
工作区：`D:\AIIIIII\ai-agent\mobile_agent`  
阶段：审查完成，业务修复尚未开始。

## 1. 本轮结论与范围

项目以 Flutter 界面和本地业务后端为主。Agent 执行、工具调用、SQLite、后台调度均在客户端；本轮没有发现独立服务端工程。建议下一阶段优先修复可靠性问题，再拆分核心职责、简化产品入口。

本轮审查了服务商配置、聊天执行、定时任务、备份恢复、项目预览、数据库、知识库、部分界面及 CI。没有逐行审查全仓库，没有做真实模型请求、真机后台运行或全页面 UI 验收。

本轮未修改业务代码。新增的隔离测试与日志位于被 Git 忽略的 `local/temp/`；本交接文档位于 `docs/`。

**证据等级约定：**

- **测试复现**：已用内存数据库、假凭证或现有测试验证具体行为。
- **代码链路确认**：已读取调用关系，尚未做完整运行时复现。
- **优化建议**：待结合性能数据和产品方向决定，不视为已发生故障。

## 2. 接手约束

- 先阅读根目录 `AGENTS.md`。工作区存在大量既有未提交、已暂存及未跟踪改动，按文件增量修改，保留其他工作的成果；不要批量回滚、清理或混合提交。
- 行号为本轮快照，接手时按类名、方法名重新定位，并检查是否已有其他人修复。
- 新下载、缓存和临时材料留在当前工作区 `local/` 下。测试使用本地 `PUB_CACHE`、`TEMP` 和 `TMP`。
- 不并发启动多个 `flutter test`，避免 Windows 编译缓存冲突。
- Android 预览已有运行入口和自动热重载机制。需要 UI 验收时先检查设备、实际 AVD 名称及现有调试进程，避免重复启动；ADB 命令显式指定查询到的设备序列号。
- 不用含真实数据的模拟器做覆盖恢复演练。恢复及清库测试使用内存库、临时目录或一次性测试设备；模拟器不能代替 ARM64 PRoot 真机验收。

## 3. 第一批：可靠性修复

### R1：删除最后一个服务商后遗留凭证仍可读回

**优先级：高。证据：测试复现。**

定位：

- `lib/infrastructure/providers/provider_config_store.dart:167`，`deleteProfile()`。
- 同文件 `load()`（约第 63 行）、`save()`、`restoreProfiles()`。

触发：保存一个服务商，删除该配置，再调用 `loadAll()` 和 `load()`。配置列表为空，但 `load()` 仍能返回旧的 API Key。原因是保存时同时写入 profile 专属键和旧的活动配置键；删除最后一个配置时没有清除旧密钥、Base URL 和模型，随后加载回退到旧配置。

隔离测试使用 `FAKE-AUDIT-KEY`，没有读取真实凭证。断言期望空字符串，实际得到假密钥，测试失败。

建议：删除最后一个配置时清除遗留活动配置；明确旧格式迁移的边界，后续收敛为一个正式配置来源。不要直接删除兼容逻辑而破坏已有用户迁移。

验收：

- 删除唯一配置后，新建 Store 实例也不能读回旧密钥或旧端点。
- 删除活动配置但仍有其他配置时，正确切换到保留配置。
- 删除非活动配置不影响当前配置；旧格式迁移、备份恢复和清除全部凭证仍正常。

### R2：备份恢复、清库没有统一阻止正在运行的任务写回

**优先级：高。证据：代码链路确认 + 控制器级隔离验证；未复现真实任务造成的数据污染。**

定位：

- `lib/infrastructure/files/vault_exporter_io.dart:260`，`restoreVault()`、`_restoreVault()`。
- `lib/presentation/settings/data_backup_page.dart`，`_restoreAutomaticBackup()`、`_clearLocalData()`。
- `lib/presentation/vault/vault_page.dart`，导入入口。
- `lib/application/run_coordinator.dart`、`lib/domain/session_operation_guard.dart`。

现状：恢复内部有 SQLite 事务及文件、密钥补偿逻辑，也有同 isolate 内恢复操作串行队列；这些机制并不负责停止正在执行的 Agent。隔离测试先调用 `RunCoordinator.beginRun()`，再执行实际的空快照恢复，恢复后 `ownsRun()` 仍返回 true。

风险：旧运行在恢复或清库后继续写入；界面内存状态与恢复后的数据库不同步。现有 `SessionOperationGuard` 是 isolate 内静态状态，不能单独解决 WorkManager 后台 isolate 的协调问题。

建议：在 application 层引入统一维护入口，阻止新运行、取消并等待已有运行结束，再恢复/清库，最后刷新会话、配置和连接状态。跨 isolate 协调需要持久化维护状态或租约，并让写入方检查有效代次。复用已有恢复事务与补偿机制。

验收：

- 模型流式返回、等待审批、工具执行期间触发恢复，行为明确且不会产生旧运行晚到写入。
- 后台调度不能绕过维护状态；维护失败后可恢复正常使用。
- 恢复成功后当前会话、服务商和相关缓存重新加载。
- 文件或密钥写入失败时现有回滚能力仍有效。

### R3：定时任务丢弃执行结果状态，可能把失败记录为成功

**优先级：高。证据：代码链路确认。**

定位：

- `lib/application/scheduled_task_runner.dart:100`，`.then((result) => result.text)`。
- `lib/application/headless_executor.dart`，`HeadlessRunResult`、`runDetailed()`。
- `lib/application/background_execution_gateway.dart`。

现状：HeadlessExecutor 会将部分失败转换为含 `status/error/failureKind` 的结果返回，而非抛异常；调度器只取文本，`runStatus` 默认是 `success`。因此返回失败、暂停或取消结果时，调度记录可能仍显示成功。

建议：保留完整结果，明确映射 completed、failed、paused、cancelled 和调度超时。记录 `runId` 和可展示的错误原因。定义失败是否允许重试，避免仅更新 `lastRunAt` 后无解释地等到下一周期。

验收：用可注入执行器覆盖完成、鉴权失败、网络失败、预算暂停、取消和超时；审计状态、结果文案及通知一致。为超时取消后的等待设置有界退出策略，避免不响应取消的工具挂住整个调度批次。

### R4：预览换端口未同步启动命令

**优先级：中。证据：代码链路确认，未做端口占用端到端复现。**

定位：`lib/application/preview_service.dart:54`，`start()`；调用方为 `lib/presentation/projects/project_home_page.dart` 的 `_togglePreview()`。

现状：首选端口被占用后选择新端口，但向终端传递的 `command` 原样不变；就绪检查和最终 URL 使用新端口。`allowLan` 也只决定展示地址，没有在该服务中修改命令监听地址。

建议：结构化描述预览命令的端口和绑定地址，统一生成命令、探活目标和 URL；无法安全调整的自定义命令应明确报端口冲突。仅端口连通不等于当前作业就绪，应检查作业退出状态及对应服务响应。

验收：首选端口空闲/占用、启动进程立即失败、慢启动、重复点击启动/停止、本机与局域网模式均有确定性测试。不要把桌面静态 HTML 服务器的测试通过等同于此终端预览链路通过，两者实现不同。

### R5：Windows 每日自动备份缺少调度接线

**优先级：中。证据：代码链路确认，未做跨日桌面运行验证。**

定位：`lib/application/desktop_scheduler.dart:26`；`lib/application/scheduled_task_runner.dart` 的 `_runAutomaticBackup()`；`lib/main.dart` 的 WorkManager 平台分支。

现状：每日备份检查仅由 WorkManager 回调调用；桌面调度器只调用 `runDueScheduledTasks()`。桌面仍能通过数据管理进入自动备份设置，形成开启开关但没有对应桌面执行路径的缺口。

建议：抽出平台无关的备份到期检查，由 Android 后台入口和桌面调度入口共用，保留原子发布、保留数量和成功后更新时间等机制。

验收：桌面开启自动备份后到期生成可解密快照；未到期不重复生成；失败不更新时间；界面明确桌面程序关闭时无法调度。

### R6：分层守护测试失败

**优先级：中，影响当前质量门。证据：现有测试复现。**

定位：`lib/infrastructure/tools/parallel_sub_agents_tool.dart:1` 引入 `../../application/context_window.dart`，违反 infrastructure 不反向依赖 application 的仓库规则。

建议：将需要的纯计算能力放到允许共用的模块，或注入接口。先确认该文件调用了哪些具体能力，避免搬动整个 ContextWindow 形成更大的依赖问题。不要通过提高阈值或跳过测试消除报错。

验收：`test/layering_test.dart` 通过，相关并行子任务和 Token 预算行为保持一致。

## 4. 第二批：结构与性能优化

以下是优化候选，不能据此宣称已有性能故障。

| 方向 | 当前证据 | 建议与验收 |
| --- | --- | --- |
| 控制器职责拆分 | 本轮统计 ChatController 约 3,337 行，chat_run_execution 约 1,702 行；控制器包含项目、工具组装、记忆、计划、运行恢复等逻辑 | 逐步抽出独立服务，每次保持公开行为及相关回归不变。仅拆成 part 文件不等于解除共享状态耦合 |
| 页面与基础设施解耦 | presentation 有 78 处 infrastructure 导入，分层测试允许数量不增长 | 优先迁出恢复、清库、配置保存等写操作，再迁查询；逐步降低基线，不做一次性全仓重写 |
| 统计查询 | data_management_page.dart 的 _loadStats() 加载完整列表后取 length | 改为 COUNT 聚合，并验证错误态与返回页面后的刷新 |
| 知识库规模 | knowledge_service.dart 的 _buildIndex() 全量载入分块，在当前 isolate 计算；BM25 遍历所有分块 | 用固定大数据集测首次索引耗时、检索耗时和峰值内存，再评估后台 isolate 或持久化索引 |
| 长会话表现 | 已有消息窗口、增量 Markdown 和局部订阅，相关选测通过 | 保留现有机制，补长代码块、多工具活动、长会话的实际设备性能基线 |

## 5. 产品增加与精简建议

以下尚未实施，也不代表用户已经确定具体产品方案。

建议增加：

1. 统一任务结果展示：完成、失败、预算暂停、等待审批、取消使用一致语义，并给出对应下一步操作。
2. 备份可恢复性检查：展示覆盖范围、完整性校验、设备密钥或密码依赖；恢复前自动保存现状。
3. 跨模块故障测试：断网、流中断、后台进程被杀、恢复与运行冲突、重复调度。
4. 可重复性能基线：固定数据集测首次打开、历史分页、知识库检索、流式输出和内存。

建议精简：

1. 合并任务导航入口：收件箱、开发任务、定时任务可共用入口和类型筛选，保留各自执行语义。
2. 统一备份信息架构：明确应用数据备份、密码保险箱和设备应用备份的范围与恢复方式，避免同名不同义。
3. 收敛半成品设置：语言页已注明英文未完整翻译且暂无完善计划，可考虑移到实验设置。
4. 为兼容路径设退出条件：先处理服务商双份存储；会话日志双写须完成影子校验、恢复验证后再退出旧路径，不能直接删除。

## 6. 已完成验证与证据

### 静态分析

`flutter analyze --no-pub`：无问题，日志记录耗时 40.4 秒。这是本轮代码快照结果，不能替代后续变更后的检查。

日志：`local/temp/code-review-analyze-20261018.log`。

### 现有回归选测

以下七个文件合计 **58 项通过、1 项失败**；唯一失败为 R6 分层问题：

```powershell
$env:PUB_CACHE = Join-Path $PWD 'local/pub-cache'
$env:TEMP = Join-Path $PWD 'local/temp'
$env:TMP = $env:TEMP
flutter test --no-pub --reporter expanded test/providers_test.dart test/scheduled_task_service_test.dart test/vault_safety_test.dart test/chat_rebuild_scope_test.dart test/chat_message_list_window_test.dart test/layering_test.dart test/desktop_preview_service_test.dart
```

日志：`local/temp/code-review-regression-20261018.log`。

没有运行本轮全量测试、全量覆盖率或正式构建。既有交付文档中的全量通过记录不能当作当前快照结果。

### 额外隔离验证

文件：`local/temp/code_review_20261018_test.dart`。日志：`local/temp/code-review-repro-20261018.log`。

```powershell
flutter test --no-pub --reporter expanded local/temp/code_review_20261018_test.dart
```

最终结果：**2 项通过、1 项失败**。

- 删除最后一个服务商应清除凭证：失败，复现 R1。
- 新建数据库包含 Drift 声明索引：通过。
- 恢复完成后已有 RunCoordinator 仍拥有执行权：通过，这是对当前风险行为的观察断言，不是正确行为的验收测试。修复后应改成维护流程的安全行为断言。

隔离测试第一版因安全存储 mock 缺少三个接口方法编译失败，补齐后重跑得到上述最终结果；最终日志已覆盖早期失败日志。该临时文件不属于正式回归套件，后续应将有效用例整理到 `test/`，不要直接将观察风险行为的断言作为永久标准。

这些材料位于 Git 忽略目录，换机器或新 clone 不会自动带上。若需要跨机器交接，应搬运脱敏日志及整理后的正式测试；不要提交整个 local 目录。

### 已撤回的判断

审查中曾怀疑新建数据库缺少升级路径中的索引。继续读取 `database_tables.dart` 和生成代码，并实际测试后确认，相关索引由 Drift 的 `@TableIndex` 正常创建。**此项不列为缺陷，不要重复修复或因此无必要地增加 schemaVersion。**

## 7. 推荐执行顺序与完成条件

1. 先修 R1、R3、R6：范围较小，增加正式行为回归，恢复相关质量门。
2. 设计并完成 R2：覆盖前台运行、后台 isolate、恢复/清库及 UI 刷新，不以仅添加一个静态布尔锁验收。
3. 修 R4、R5：分别补端口占用预览和桌面自动备份的可重复测试。
4. 在可靠性修复稳定后，逐项推进结构、性能和产品入口调整。

每批完成后记录：修改文件、问题触发条件、行为变化、运行的测试、未覆盖平台或场景。相关测试通过后再执行必要的静态分析与整体验证；涉及手机 UI 的修改按根目录 AGENTS.md 在现有 Android 预览验收，涉及 ARM64 运行时的修改补真机验证。

本交接的完成状态是“审查及验证材料已整理”，不代表任何 R1–R6 已修复。
