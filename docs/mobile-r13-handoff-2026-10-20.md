# NEXUS 移动端整改交接文档

**交接日期：2026-10-20**  
**交接原因：用户暂停实施，要求编写交接文档。**  
**当前主线：R13 可观测性与参考 SLO；尚未完成验收。**

> 最重要的结论：代码已修改，最新静态分析无问题，但最后一轮定向测试为 **158 通过、1 失败（共159项）**。R13 新源码尚未在模拟器重新加载、核对源码并复验。不能写成“全部通过”“R13完成”或“项目已完成”。

## 1. 接手一分钟摘要

1. 继续 R13，不要自行转去费用备份、实时音视频、远程执行或主界面精简。
2. 首先定位 `agent_loop_characterization_test.dart` 的 steering 完成边界测试失败，单独复现并核对原因；不要直接认定是既有问题、偶发失败或 R13 引入。
3. 保留所有既有未提交/未跟踪文件；项目本来就有大量改动，`git diff HEAD` 不能直接代表本轮工作。
4. 原有 RunEvents、工具计时及运行级 TTFT 已经存在。本轮复用这些设施，没有新增遥测 SDK、外部上报服务或第二套事件数据库。
5. 主机仅可运行明确列出的定向测试，禁止主机全量 `flutter test`。真机、真实模型调用、签名密钥操作等仍未获授权。
6. 模拟器必须先核验，只能使用获准的 `emulator-5554 / Nexus_Preview_API_36 / com.nexusagent.app.debug`。
7. 上一阶段的 99 项测试、24 项 UI、413 项契约是 **R13 修改前的历史证据**，不能用来证明当前 R13 源码已经通过模拟器验证。

## 2. 用户目标与执行边界

### 已确认的方向

- 原始任务是核验并改进 NEXUS 审计发现的问题，不是按审计假设盲目重写。
- 使用私有 APK、BYOK；保留执行能力，并维持逐动作审批。
- 用户此前选择完成本机费用闭环，之后明确选择“其他未完成的选项”，再选择 **R13**。
- 本次最新指令只要求写交接文档；因此已暂停扩展实现和新增验证。

### 持续有效的约束

- 使用中文；事实、推断和未验证内容分开说明，不编造证据。
- 每项任务先创建/更新可见 Bridge 任务卡，复杂任务维护步骤和状态。
- 终端使用 Bash；Windows 路径不能作为推断 shell 的依据。
- 禁止真机操作、真实模型调用、主机全量 Flutter 测试、签名密钥生成/替换/导出及破坏性 Git 操作。
- 不启用未经授权的付费服务或公网暴露；不改动其他运行中的预览进程。
- 不打印 VM-service 文件、认证地址、会话凭证或完整预览日志。
- 结束前继续项目交互问答，除非用户明确表示结束。

## 3. 环境、路径与工具

| 项目 | 位置/约定 |
|---|---|
| Windows 项目根目录 | `D:/AIIIIII/ai-agent/mobile_agent` |
| Bash 下项目路径 | `/d/AIIIIII/ai-agent/mobile_agent` |
| 远端命令 `cwd` | 必须使用原生路径 `D:/AIIIIII/ai-agent/mobile_agent`，不能传 `/d/...` |
| Dart | `/c/src/flutter/bin/cache/dart-sdk/bin/dart.exe` |
| Flutter | `/c/src/flutter/bin/flutter` |
| 本地 RPC helper | `/home/user/bridge_rpc.py` |
| RPC 调用 | `python /home/user/bridge_rpc.py TOOL '{JSON参数}'` |
| 查看单个工具 schema | `python /home/user/bridge_rpc.py list TOOL` |
| 任务卡 | `4bf4aeb2-b4aa-45aa-85c2-481ed86c19dc` |

任务卡在文档交付时为 **revision15，lifecycle=blocked**：交接步骤已完成，R13 指标复验及其他未完成项保留。续办必须使用最近一次回执的 revision，不能盲用旧值。`set_todos` 应采用 `mode:patch` 保留未列出的步骤，同时最多一个步骤为 `in_progress`。

Helper 使用已缓存的会话及任务卡所有权。不要打印 `/home/user/bridge_session.json`。不要重复尝试已失效的旧隧道或把 Bridge 当成尚未连接的普通应用连接器。

### 长期预览

此前明确保留的预览命令：

`cmd_06e08dafd6a979e7df2482350aa0b332466e5c4f34f2b0d4`

本次交接未停止、重启或读取它的完整日志；此处不声称重新确认了其存活状态。R13 期间**尚未发送热重启请求**，核查时 `local/android-preview/reload.request` 不存在。

## 4. R13 已实际落地的源码

### 4.1 链路基础

| 文件 | 已修改内容 |
|---|---|
| `lib/application/run_event_tracker.dart` | 复用既有异步队列；增加 trace/span、环境和本地请求关联；完成时保留起始元数据；使用 Stopwatch 单调计时；默认最多512个待写操作；增加写失败、队列丢弃与元数据丢失计数；flush 尽力写入 `telemetry_health`；保留分环境的进程内降级计数。 |
| `lib/application/traced_model_provider.dart` | 新增 `TracedModelProvider` 和 `withModelTrace`，按每次实际流订阅记录 `model_attempt`，覆盖重试和经同一 provider 的摘要；记录首个非空文本/推理事件、首个文本事件和已报告用量；区分成功、失败、取消、未完成。 |
| `lib/application/chat_controller.dart` | 导入包装器；这是 part 文件所依附的主库，不能只往 part 内加 import。 |
| `lib/application/chat_run_execution.dart` | 在构造 AgentExecutor 前包装已解析的 provider。 |
| `lib/application/headless_executor.dart` | 在 tracker 可用后，于 AgentExecutor 参数处包装 provider；没有持久化 tracker 的调用保持原 provider。 |

实现要点：

- `traceId` 使用已有持久化 `runId`；`spanId` 使用事件 ID；关联已有 `costRequestId`，不是供应商返回的请求 ID。
- 工具/文件操作 span 关联最近的模型尝试；不再额外给聊天路径加一套工具拦截记录，避免重复。
- 完成时不再丢弃起始关联元数据；调用方在 finish 中传入相同身份字段也不能覆盖既有身份。
- 保留既有脱敏机制，提前冻结待写元数据；编码失败或截断会披露降级，不使任务流因为日志失败而抛错。
- 模型包装器不采集提示词、生成正文、推理正文、工具参数或原始错误体；保存配置的模型标识等有限元数据，并复用既有脱敏规则。
- 收到 Completed 才能在无已知错误/取消时记成功。没有 Completed 的流关闭或消费者中断记为未知，不能盲记成功。
- ModelStep 外层 `.timeout` 可能只表现为消费者中断；包装器不假装知道外层超时原因。
- 进程计数用于披露连 health 行都无法落盘的错误；它不是持久化数据，重启后未落盘丢失不能追溯，也不能与落盘计数简单相加。

### 4.2 指标与诊断入口

| 文件 | 已修改内容 |
|---|---|
| `lib/application/operational_metrics.dart` | 新增本地聚合与 `ReferenceSlo`；按 debug/profile/release/fixture 分开；区分推理、摘要、其他模型尝试及工具端到端；最近邻秩 P50/P95；空值不按0；参考目标至少20样本；查询最多5000条并以 limit+1 检测截断；最多导出100条链路预览。 |
| `lib/presentation/diagnostics/operational_metrics_page.dart` | 新增“链路指标与参考SLO”页，含环境/窗口选择、仅本页参考目标、质量说明、计数、首事件耗时、链路标识和复制报告。默认不应用任何目标。 |
| `lib/presentation/diagnostics/run_analysis_page.dart` | 既有运行分析页增加入口；捕获当前作用域的数据库 Future，避免进入另一个全局库。 |
| `lib/debug/page_coverage_checks.dart` | 加入新指标页和明确标记 fixture 的合成行；加入不触发真实聊天初始化的 `_CoverageChatController` 作用域覆盖。 |
| `tool/verify_mobile_review.py` | 选定源码证明从21文件扩展到27文件；UI计划从24项改为32项，增加指标页与运行分析页的四态布局。**新计划尚未实际执行。** |

聚合的防误判规则：

- 既有 `model_request` 汇总不与 `model_attempt` 重复计数；未分类旧数据会提示覆盖不完整。
- 缺少逻辑请求关联、模型父链路不在窗口、未知/未完成、计时异常、遥测降级或查询截断，不得判参考目标达标。
- 已知取消单列，但计入“尝试成功占比”的分母；此指标不是 Agent 业务完成率。
- 工具 duration 含审批/等待，不是纯执行器延迟；未知 effect 或明确未完成的业务移交不能包装成业务成功。
- 模型 duration 是流订阅到结束，包含背压/本地处理；首文本或推理事件不是网络首字节。
- fixture 始终是 `fixture_only`，不会获得性能通过；报告明确 `notReleaseSignOff:true`、设备证据未核实。
- 构建环境不等于真实硬件环境；即使满足本页参考目标，也不构成 APK/真机/发布签收。
- 范围仅为已观测的持久化运行；不包括未落运行记录的后台调用及草稿，不能声称全应用链路覆盖完整。

### 4.3 新增测试文件

- `test/mobile_trace_test.dart`：13项，覆盖关联、每次订阅独立 span、未知结束/取消、隐私、单调时间、队列上限、SQLite 确定性拒写、元数据异常及未完成行。
- `test/mobile_operational_metrics_test.dart`：24项，覆盖分位数、空样本、最小样本、环境/摘要分组、不重复计数、父链路、未知/取消、持久化计数去重、进程丢失、截断和安全导出等。
- `test/mobile_metrics_widget_test.dart`：7项，覆盖四态布局、参考目标输入、退场生命周期、读取异常不伪装为0、数据库作用域导航。

上述文件数与测试定义用于说明覆盖面；最终是否通过必须以本节下方最新执行证据为准。

## 5. 最新验证结果：必须保留失败事实

### 5.1 最新一轮（当前源码）

命令 ID：`cmd_6a1a10283e98585d0121a340f72253bf4452473eb6190c15`

- 静态分析：`No issues found!`。
- 13个明确指定的测试文件：**158通过，1失败，总159项**。
- 整条命令退出码：**1**，不能描述为总体通过。
- 日志：`local/temp/mobile-r13-analyze.log`、`local/temp/mobile-r13-tests.log`。

**唯一报告的失败：**

```text
test/agent_loop_characterization_test.dart
steering steering queued at the completion boundary starts another step
位置：261行
Expected: an object with length of <2>
Actual: [Instance of 'UnifiedRequest']
Which: has length of <1>
```

当前未进行失败原因定位、单独重跑或有/无 R13 的对照。因此不能认定它是偶发、历史遗留或本轮引入；不要跳过测试、降低断言或覆盖已有代码以制造绿色结果。

最新执行包括以下13个文件：

```text
test/mobile_trace_test.dart
test/mobile_operational_metrics_test.dart
test/mobile_metrics_widget_test.dart
test/run_event_tracker_test.dart
test/run_event_interceptor_test.dart
test/privacy_and_cleanup_test.dart
test/mobile_cost_loop_test.dart
test/mobile_cost_ledger_widget_test.dart
test/mobile_review_regression_test.dart
test/agent_executor_test.dart
test/agent_executor_pipeline_injection_test.dart
test/agent_loop_characterization_test.dart
test/agent_loop_hardening_test.dart
```

### 5.2 本阶段较早证据与已修正问题

- 链路基础四文件定向测试 **27/27通过**：`cmd_68ef65a0bbc65c053304cf9f99dfdcaced56352df0d6246d`，日志 `local/temp/mobile-r13-core-tests.log`。
- 随后六文件测试曾为57通过、1失败；失败为 widget 测试误把 `find.byTooltip` 找到的 RawTooltip 转成 IconButton，不是页面运行故障。已改为按 IconButton 类型与 tooltip 属性定位。最新159项中已不再报告该失败。
- 最初用“关闭尚未打开的懒加载数据库”模拟拒写并不可靠；已改成 fixture SQLite trigger 确定性拒写，并验证进程计数。
- R13 新增代码曾有括号风格 info，已定向修正；最新静态分析无问题。
- 第一份核心补丁曾因无上下文 hunk 被拒绝；其后已按实际源码上下文成功应用。不要重跑旧生成脚本。

### 5.3 模拟器状态与证据边界

只读核验命令：`cmd_181b6fc11116d8c3f05794ba5aa70f06a22d799b21538d89`，退出0，确认了指定 serial、qemu=1、AVD 名和 debug 包。

**仅核验了目标身份；没有执行 R13 热重启、27文件 live-source 比对、32项 UI 或本轮413项契约。**

R13 修改前历史证据：99项定向 Dart、24项模拟器 UI、413项契约，以及 Python 发布门禁12、评分器5、源码守卫5。它们仍可用于历史追溯，不是当前 R13 源码的验收。

## 6. 接手续办顺序

### 第一步：保留现场、核对任务卡与失败

- 读取当前任务卡的最新回执；用 patch 恢复 R13 指标步骤为进行中。
- 检查最新源码和 `mobile-r13-tests.log`，不要重新应用 `/home/user/r13_*_patch.py`。
- 单独重跑失败用例，排查 steering 完成边界时事件/微任务顺序、请求生成次数及隔离差异；先读测试和相关执行代码再修改。
- 如需对照，只做非破坏性的隔离副本/fixture 对照，不能 reset、checkout 覆盖大量既有改动。

示例（远端 Bash，cwd 使用原生项目路径）：

```bash
/c/src/flutter/bin/flutter test test/agent_loop_characterization_test.dart \
  --plain-name 'steering queued at the completion boundary starts another step' \
  --no-pub --reporter expanded
```

注意测试名称可能有 group 前缀；若筛选不到，应先核对实际注册全名，不能把“0项执行”记为通过。

### 第二步：修复后重新做定向验证

- 运行上面列出的13文件测试及静态分析，保留新的明确日志和退出码。
- 仅修改经证实的原因，不为减少失败而删除断言或跳过用例。
- 检查相关 diff、源码守卫和已有发布门禁/评分器测试。最新 R13 之后这些 Python 项尚未复验。

### 第三步：只在获准模拟器上复验新源码

1. 再次只读核验指定模拟器身份，不枚举或操作真机。
2. 先备份 `local/temp/mobile-review-targeted.json`、`mobile-review-contracts.json` 为 `*-before-r13.json` 等历史文件。
3. 沿用原来受控预览的重启机制：`local/android-preview/reload.request` 写入 `R`；确认由原预览消费，不能另起重复预览或触碰其他进程。
4. 用更新后的 `tool/verify_mobile_review.py` 检查27个选定源码的 token/comment 等价性、32项 UI 以及 fixture 清理。
5. 用 `tool/verify_mobile_review_contracts.py` 重跑既有六套契约（最低计数36/69/228/28/12/40，总413），核对模型调用、平台/用户数据变更计数及前后源码稳定。

典型驱动环境：

```bash
export NEXUS_DART=C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe
python tool/verify_mobile_review.py
python tool/verify_mobile_review_contracts.py
```

不要把 formatter 导致的原始字节 hash 差异直接当成功/失败；当前驱动同时保留 raw hash，并使用 Dart token+comment 等价判断，不能退回简单去空白比较。

可考虑后续追加专门的模拟器模型 fixture/拒写可观测性契约，但**本次没有实现或运行任何新的专门 R13 契约扩展**。不要把此前讨论中的想法当成已落地代码。

### 第四步：更新交付证据与继续项目问答

- 当前 `docs/mobile-review-remediation.md`、`docs/mobile-cost-loop.md` 描述的是上一阶段，不包含本次最终 R13 状态；下一次应追加本阶段真实结果，区分历史/当前源码。
- 明确本地工程闭环与真实设备性能基线的差别，保留所有受限验收未完成项。
- 仅在失败解决、当前源码验证完成后再评价 R13 工程阶段；不能顺手把所有项目项标为完成。

## 7. 其他工作与遗留项

### 已完成的本机费用阶段

本地请求/尝试关联、reserved/pending/settled/reconciled 状态、保守预算占用、未知价格失败关闭、人工对账 CAS 与追加审计、作用域数据库导航、隐私清除等已实现并在当时验证。

相关文件：

- `lib/infrastructure/database/cost_budget_ledger.dart`
- `lib/infrastructure/providers/cost_budget_provider.dart`
- `lib/infrastructure/providers/cost_budget_policy.dart`
- `lib/presentation/dashboard/cost_ledger_page.dart`
- `docs/mobile-cost-loop.md`

局限：本地 ID 不是供应商账单 ID，保守估算不是账户账单硬上限；费用账本的完整跨机 vault 恢复尚未完成。

### 仍未完成/未授权的重点

- R05：实时音视频能力及全部入口/声明降级一致性；普通音频、图片能力不应被误删。
- R06：远程作业持久化状态、幂等、重连、取消及结果契约；并未部署真实远程设备闭环。
- R09：费用相关完整跨机备份/恢复。
- R14：先做信息架构/导航方案，未经批准不删除能力。
- R01/R02 等正式 APK、签名、ARM64/PRoot、ROM/进程/弱网、TalkBack、真实模型评测、外部业务结果与真实性能基线：未授权或未执行。
- 60条 Agent 评测语料存在不等于真实执行通过；仍须保留 `not_run` 的事实。

## 8. 交接操作说明

- 本次只新增交接文档并核对已有命令结果，没有继续修复 steering 测试、修改其他业务代码、运行新测试或重启预览。
- 没有 commit、push、签名密钥操作、真实模型调用或真机操作。
- 同名文档提供于本地工作区；项目内副本路径：`docs/mobile-r13-handoff-2026-10-20.md`。
- 本地 `/home/user/r13_core_patch.py`、`r13_health_patch.py`、`r13_metrics_patch.py`、`r13_tests_patch.py` 是历史生成脚本，不是可重复迁移；重跑可能冲突、重复添加或使用过时上下文。**项目源码才是事实依据。**

### 可直接给下一位执行者的开场指令

> 请先读本交接文档和项目当前源码，更新原 Bridge 任务卡。继续 R13，先单独定位最新159项定向测试中 steering 完成边界的唯一失败（158通过、1失败），不要声称已全通过。保留所有既有未提交改动，禁止全量主机 Flutter 测试、真机/真实模型和密钥操作。失败解决后再定向回归，并在获准模拟器上重启、核对27文件 live-source，执行32项UI及413项既有契约。旧24项UI/413项契约证据只能视作R13前历史证据。全程不打印认证地址或凭证，结束前继续项目问答。
