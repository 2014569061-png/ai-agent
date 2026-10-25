# 任务工作台增量契约与验收边界（2026-10-19）

**本文件仅记录 W06 相关增量，不表示 W06、F13、W20 或整版完成。**

## 状态投影（只读）

继续使用 Tasks、scheduled_task_run 审计、原执行与审批链路；不新增任务引擎，不自动重试，不调用模型。

| 来源状态 | 工作台投影 | 说明 |
| --- | --- | --- |
| task waiting_approval / awaiting_approval | 待审批 | 已读不是批准，也不改变执行状态 |
| task paused / scheduled paused | 已暂停 | 不自动恢复 |
| partial / partially_completed / completed_with_errors | 部分完成 | 必须是明确结构化状态，不从输出文本猜测 |
| scheduled timeout、未知状态、损坏/过大 JSON、decision 与 detail.status 冲突 | 待核实 | 不当作确定失败或成功；不表示可安全重试 |
| scheduled success，且存在 error、非 completed 的 executionStatus、businessCompleted=false 或 needsUserCompletion=true | 待核实 | 兼容旧记录缺少 executionStatus，不把交接视为业务保存 |
| 明确 failed / error | 失败 | 显示副作用未必已撤销的提示 |
| cancelled | 已取消 | 不宣称回滚完成 |
| 合法且不矛盾的 success | 已完成 | 表示调度运行完成，不新增对外部业务资源的确认能力 |

未知 task 状态保守投影待核实；原始状态保留在 JobSummary.rawStatus。定时运行详情展示状态和安全提示，而非仅展示输出。

## 三个入口与有界查询

- **最近任务**：最近 100 个 Tasks/定时审计的合并投影，不再命名为“全部任务”。
- **待处理**：独立筛选待审批、暂停、待核实、部分完成；不受已读标记和七天时间窗口影响。普通成功历史不会挤掉旧 Tasks 待审批。默认最多 100 项，接口允许 1–1000。
- **收件箱**：合并最近任务和待处理，按来源与 ID 去重；终结结果维持七天窗口，未解决候选豁免年龄限制。两个来源各有上限，因此收件箱可能超过 100 项；不是完整历史分页。
- 当前 SQL 对非终结 Tasks、非明确终结定时审计先筛选，再补充最近审计中识别到的损坏/冲突记录。**很早且 decision 声称 success/failed/cancelled、但详细元数据损坏/冲突的审计，仍可能不在有界候选中。全历史索引/分页/迁移扫描未交付。** 不把这个增量当成无遗漏待办承诺。
- 失败和取消属于终结历史，不在待处理列表永久保留。后续仍需明确解决/归档策略。

## 已读与并发

- 每次刷新分配递增代际，只有最新请求可更新加载、错误和列表状态。
- 全部已读捕获不可变条目快照；持久化后只移除快照中的精确键，保留新条目和同 ID 的新版本；写入期间禁止重复全部已读。
- 写入完成后发起新读取，使此前启动的过期读取失效。单项已读也使用精确键和新的读取。
- 持久化返回 false / 抛异常时不把条目直接清空；界面提示未保存。读取失败保留已有内容并显示错误。
- 已读键保留现有来源/ID/rawStatus/时间，增加正数 stateRevision 与高风险投影阶段后缀。已有正版本任务或新识别的待核实/部分完成记录在升级后可能重新提示一次；旧已读偏好不删除、不更改数据库 schema。
- Prefs 仍最多保存 500 个已读键：超过容量的旧键可再次成为未读；不是永久处理/归档状态。

## 验证方式

`lib/debug/job_board_checks.dart` 通过 debug-only service extension 在模拟器 Dart isolate 内执行固定检查，数据库为 NativeDatabase.memory，已读使用内存存储。宿主 Python 仅做传输和结果记录，未运行宿主测试套件。

固定检查涉及：未知状态、超时、明确部分完成、失败、旧 success 兼容、冲突元数据、损坏审计、保留原状态、110 个成功历史不挤掉 40 天前审批、已读不解除待处理、同时间新 revision 再提示、异步快照保留新事项/版本、有界筛选、安全提示。

另提供 debug-only 隔离页面夹具：仅内存合成数据，覆盖四种旧待办，覆盖 jobBoardProvider；任务点击回调为空，禁止进入真实执行/审批详情。关闭只移除自有路由并关闭自有内存库。发布模式不注册扩展。

实际验证（本批增量）：

- 全仓 `flutter analyze --no-pub`：No issues found，22.1 秒；`local/temp/major-jobs-analyze-20261019.log`。
- 原签名环境 debug x64 APK 构建成功，指定模拟器 `install -r` 成功，未卸载/清数据；`local/temp/major-jobs-build-20261019.log`。Gradle/AGP/Kotlin 未来版本支持警告仍存在，没有借此升级构建链。
- 固定模拟器检查 **14/14**；`local/temp/major-jobs-emulator-contract-20261019.json`。仅隔离内存数据库变更，modelCalls=0、platformMutations=0、persistentDataMutations=0。
- 实际页面链路通过：收件箱 4 项 → 点击全部标为已读 → 收件箱空态 → 点击待处理 → 四项仍在（old-approval、partial、unknown、paused）。`tool/verify_job_board_ui_emulator.py` 验证模拟器 UI 节点并截图，截图亦已查看：`local/temp/major-jobs-fixture-{before,after,pending-after}-20261019.png`。
- 首次 UI 断言因 Windows 默认编码误解码 ADB 的 UTF-8 中文而失败；已明确指定 UTF-8 后重跑整条链路通过，未把失败当成通过。隔离路由已关闭、内存库已释放。
- 同一新 APK 上连接器固定检查复验 **12/12**，不是日历保存/联系人保存的端到端验收。

Flutter widget 测试源码随标签/状态调整，但没有运行宿主测试。真正的 UI 请求乱序自动化、全状态/大字/横屏/TalkBack、全部运行态契约和恢复/成果整链路仍待验收。真机、ARM64 和七天专项仍须最后另获许可。
