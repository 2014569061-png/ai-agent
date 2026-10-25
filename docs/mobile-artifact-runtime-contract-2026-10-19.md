# 成果副本与任务控制增量契约（2026-10-19）

整版未完成。本文仅覆盖成果中心、实体一致性及任务请求/控制持久化守卫；不是完整 F06/F07/F20/F21 验收。

## 成果保存与使用

沿用 `ProjectArtifact` 和 schema27 的 artifacts 表，不新增执行引擎。既有 projectId 字符串保留；空字符串表示非项目范围，不能伪称某项目成员。开发工作台允许非项目成果登记；登记失败有明确提示，不再只吞异常。

`ArtifactService.record`：校验便携相对路径，解析来源真实路径并限制在工作区；先复制到本次唯一私有目录，流式 SHA-256/长度校验，再入库。检查过期导致摘要/长度不一致、来源缺失或入库失败时抛错并清理本次目录，不删除工作区源文件或旧版本。新版本用新ID；后续工作区编辑不会自动修改保存副本。复制完整性不等于格式正确、APK签名安全、内容可信或任务成功。

`inspectPayload` 分 intact/missing/changed/unverified/invalid；缺少摘要的旧数据不伪装已校验。`verifiedPayload` 仅返回当前摘要和长度一致的副本。绝对路径、../、反斜线、盘符、非法记录ID、来源符号链接出界会被拦截。

工作区新增成果中心：数据库游标分页、真实来源任务/运行/项目、UTC时间、大小、摘要、文本或网页源码预览（最多128000字节且不执行网页脚本）、复制文本及系统分享/导出副本。动作前重新读取完整记录，并重新校验文件；重复点击有忙状态。系统分享返回不等同接收方已保存。全量搜索及任务详情可按真实成果ID进入详情；任务详情不再排除非项目成果。项目的复制路径/安装改用校验私有副本，不再直接打开可能已经变化的工作区文件。

限制：暂没有图片渲染、HTML可运行预览、独立“继续修改”入口、版本谱系、已验证的应用外导出回读和独立格式/安全验证展示；不可据此标记完整F07/F20通过。文件与数据库不是跨文件系统原子事务；进程在复制后入库前崩溃可能留下无索引目录，尚未实现孤儿回收。校验后到系统读取前也不承诺对同UID并发写入有OS级不可变保证。

## 任务请求与控制守卫

`TaskService.findByRequestId` 改为完整数据库参数绑定查询，json_valid保护损坏历史，不再只看最近400条。相同请求ID存在多个历史任务时拒绝歧义。enqueue查重与创建置于同一事务，跨会话/项目复用请求ID拒绝。

控制查重、查任务、分配序号、保存和请求态更新在同一事务。已完成/失败/取消的任务拒绝所有迟到控制，避免晚到cancel/pause把终态改回请求态。同一控制ID绑定task/kind/run/payload；变参或换任务的复用拒绝。控制ID不能为空或超过256字符，payload上限16384字符。

cancel仍为pending/cancel_requested，不等于执行端已停止；不会宣称撤销已发生动作。这些守卫尚未实现整个PlanRevision、跨进程旧回调隔离、人工完成证据或旧审批撤销；不能抵消F21剩余工作。

## 实际模拟器证据

只使用 `emulator-5554` / `Nexus_Preview_API_36`；未触碰真机、未新增模型调用、未运行宿主测试套件。

- 全仓分析 No issues found，22.2秒：`local/temp/major-runtime-analyze-20261019.log`。
- debug x64 APK构建20.6秒，install-r保数据：`local/temp/major-runtime-build-20261019.log`。
- 成果固定检查12/12：复制/非项目/独立版本/缺失/摘要不一致/路径与符号链接出界/篡改/旧数据/入库失败清理，`local/temp/major-artifact-emulator-contract-20261019.json`。
- 任务控制固定检查12/12：410条之后旧请求、字面ID、损坏JSON、并发入队、作用域、终态迟到控制、重复ID与变参/换任务拒绝、并发序号、取消请求态、无效输入，`local/temp/major-task-runtime-emulator-contract-20261019.json`。
- 成果真实页面隔离夹具：列表、完整副本文本预览、缺失文件提示通过，`local/temp/major-artifact-fixture-{list,good-capture,missing-capture}-20261019.png`。只读夹具禁用系统分享/复制，**不是已测试真实分享成功**。
- 同一最终APK复验搜索12/12、记忆12/12、任务14/14、系统连接器12/12。
- 360dp宽、字体1.6：搜索/展开筛选/输入法浮层、成果列表/详情采样断言与截图通过，`tool/verify_major_large_text_emulator.py`；截图 `local/temp/major-{search,artifact}*-font16-width360*-20261019.png`。设置及夹具已恢复。不是完整键盘、横屏、TalkBack或全应用无障碍验收。

## 后续本地纠正及 CAS 增量

新增 `AgentRunController.controlRevision`，接受非空纠正时递增；封存/取消后不接受纠正。AgentExecutor在模型请求开始前绑定代次，工具管线在审批前、审批返回后、暂停/事件背压之后且执行边界之前重查。旧工具/旧批准以 REVISION_CONFLICT、effect=none 拒绝，并撤销对应预览；已经提交的动作保留其真实effect，不声称撤回。此为本地turn代次，不冒充持久PlanRevision、跨进程拥有者或自动取消旧审批弹层/通知。

任务进度、完成、恢复计数、检查点读改写已事务化；新增updateTaskSnapshot按ID+stateRevision更新并递增，拒绝陈旧快照，不以upsert复活已删除任务；状态更新原子递增revision。初次创建/受控恢复导入的原始upsert仍保留，不把此增量宣称全数据库写入都已CAS。ChatController在异步持久化前同时捕获taskId/runId/本地代次，避免stop清空run后错绑空runId或新运行。

最终静态分析22.3秒通过：`local/temp/major-task-cas-analyze-20261019.log`；debug x64构建20.8秒及保数据安装：`local/temp/major-task-cas-build-20261019.log`。指定模拟器任务运行检查扩至20/20，新增CAS/拒绝陈旧与删除快照、并发进度/恢复计数、清理断点、重复ACK；本地纠正守卫12/12（合成工具计数器，零平台动作）见`local/temp/major-steering-guard-emulator-contract-20261019.json`。同APK成果12/12、搜索12/12、记忆12/12、任务14/14、连接器12/12。固定原生检查不代替真实模型任务、进程回收/断网、Windows或跨设备验收。

## 持久计划存储协议第一阶段（schema30，2026-10-19）
新增run_plan_heads/plan_revisions/run_dispatch_claims：运行身份、不可变修订、控制入箱同事务推进版本；派发claim与控制提交共享SQLite顺序；重复callId不重复占位；旧在途结果只结算原claim，不改新计划。删除任务清理关联表；保险箱保留计划/未知派发且恢复时不激活旧owner。DevelopmentExecutionService提交控制已接持久修订及显式旧run拒绝。
模拟器固定协议24/24，连同旧九套同APK167/167；analyze无问题23.0s、build21.6s，cmd_c91e0877e777a4190f0aa7f6d97770c7cf3fad013456448d，证据local/temp/major-plan-protocol-emulator-contract-20261019.json。含控制/完成顺序、去重、旧run、第二连接提交、重开和schema29升级、备份。
**仅存储协议通过：真实AgentExecutor/chat/headless派发尚未接新claim/consume，旧审批UI/通知仍未绑定持久版本，TaskService旧回调尚无完整run/plan屏障。不能宣称F21/A27闭环。下一步把该协议接回原执行器/审批，而不是新增引擎。**


## 持久计划第二阶段：原执行管线已接入（2026-10-19）
- `PersistedRunFence` 复用 `AgentRunController`、`AgentExecutor` 和既有 tool pipeline，没有第二套执行/模型引擎；chat/headless 入口已绑定。控制确认前等待本地提交，UI 收据失败保留纠正草稿；暂停检查点可消费持久恢复请求。
- 每轮捕获持久版本，审批前后及最终边界复核，授权前原子 claim，执行后按原版本 settle；重复 callId 不再次授权/执行，结算写入未确认保留 unknown。已派发旧结果保留事实，不推进新计划。异步完成屏障与控制共享存储顺序，不先封存后丢控制。
- TaskService 新增可选 runId/planVersion 写屏障；传入版本的旧状态/进度/完成回调被拒绝。完成状态必须已有持久计划 completed。保留无 runId 的 owner/admin 兼容入口，尚未声称所有旧调用均已迁移。
- `major-plan-fence-analyze-20261019.log` 无问题 22.5s；`major-plan-fence-build-20261019.log` debug x64 构建 21.8s。固定 Android isolate 合同从 24 扩至 41 项，新增原管线、审批等待期间纠正、事件背压、重复派发、在途结算、暂停恢复、完成竞争、提交等待、旧任务回调及数据库故障保守失败。模拟器实跑 41/41，同 APK 原九套 143/143，合计 184/184；均零真实模型调用、零平台动作。证据仍在 local/temp，非宿主测试。
- **仍未完成 F21/A27**：审批弹窗/通知的主动撤销和持久作用域、跨旧回调的全面版本迁移、运行后自动验证边界、崩溃恢复交互等仍待补齐。以上检查不替代进程崩溃、长期压力、ARM64/Profile/发布资格或原方案其他门禁；真机不在本次范围。


## 持久审批第三阶段（schema 31，2026-10-19）
- 新增临时 run_approval_scopes / run_plan_grants；框架 Zone 传递 run/plan/call 身份，不解析模型自报身份。通知动作在同一 SQLite 更新中校验当前 head、版本、无待消费控制、任务非终态与 TTL，仍保留首次裁决。
- 原 inline 审批等待器与共享 sheet 监听作用域失效；旧卡片须匹配原 ToolCall 实例，旧 callId 不指向新审批。后台通知等待也验证 scope，失效后收起；审批等待有超时与关闭信号。
- 持久运行中的「本计划允许」仅授予当前 plan，修改版本即清除缓存；不会由旧弹窗向全局信任写入。原无持久 scope 的 owner/高级入口保留原信任行为。临时握手与计划许可不进保险箱，不从恢复数据复活；clearAll 与任务删除清理。
- 同 APK 固定 Android isolate 检查 **61/61**（原 41 + 审批 20）；原九套 **143/143**，合计 **204/204**。静态分析无问题 22.1s；x64 debug 构建 19.3s。证据：major-approval-scope-analyze/build-20261019.log、major-plan-protocol-emulator-contract-20261019.json 与各原套报告。
- 新增超时检查真实捕获了审批 timeout Future 未加入竞争的缺陷；通过固定 debug 进度读口定位第 50 项后修复，重构建重跑 61/61。旧超时回合未计通过；debug 合同共享同一执行 Future，网络重试不重开 fixture。未运行宿主 tests、真实模型或真机。
- **仍不能核销 F21/A27**：主动 sheet 关闭/通知收起仍需模拟器 UI 证据；完整 AgentExecutor 多轮、后置自动验证、全部旧回调、崩溃恢复和原方案其余门禁继续实施。仅后台数据库裁决测试不能当作通知插件/系统行为验证。


## 原执行器多轮与前台审批证据（2026-10-19）
- 同 APK `planProtocolContract` 已扩至 **72/72**，九套回归 **143/143**，共 **215/215**。分析无问题 21.6s，debug x64 构建21.1s。新增11项直接运行原 AgentExecutor：离线固定 Provider 严格无网络回退，覆盖首次请求前纠正、旧模型批次、在途事实/剩余调用、真实审批 Zone、旧最终草稿、请求背压以及异步完成竞争/继续/异常/取消/兼容控制器；这些是合成 Provider 请求，不是新增真实模型调用。
- 修正了旧最终草稿与新答案拼接的风险：AgentDraftSupersededEvent 仅清掉 superseded assistant 草稿，保留工具事实、调用结算与审计；chat/headless 均处理。请求发送前再核对持久版本，事件背压期间控制获胜则不发送旧请求。
- 原生产 promptToolApproval 的模拟器前台 UI fixture 已通过：纠正主动移除旧 sheet；上方另一个遮盖路由保留（不错误 pop）；旧裁决拒绝、握手/scope 清理；「本计划允许」只写当前计划、不写全局许可；再次纠正清除本计划缓存。证据 major-approval-scope-ui-20261019.json 及 before-correction/invalidated/plan-trust 三张 PNG；仅隔离内存任务/审计/许可数据，无工具执行或真实模型。
- 原循环已新增 awaitable beforeFinish 接点，并以5项 native 合同验证：不得提前 seal，控制获胜继续同一执行器；有限续跑不换 task owner，异常不标成功，取消释放等待。**实际后置 DevelopmentLoopFinalizer/自动验证修复尚未迁入该接点**，不能把 hook 合同等同运行时迁移完成。
- 待修复的重要整合风险：旧收尾自动修复会新建同 taskId 的 headless run，可能转移持久 head，使外层旧 run 的完成 ACK 被正确屏障拦截；旧 finalizer 又仍有不带 run/plan 的进度写入。下一步须把验证/有限修复迁入原 loop 的 beforeFinish（含每条验证命令 claim/settle 与写屏障），而非放宽旧 owner 保护或绕开持久协议。
- F21/A27 与整版主门禁仍未核销；通知真实插件收起、崩溃恢复、全部旧回调迁移等继续。真机仍排除，宿主 tests 未运行；特征测试源码仅补新 sealed-event 的穷尽映射以保持静态分析，不作为宿主测试通过证据。


## 恢复运行身份与验证中间件（2026-10-19）
- 修复 resume 先生成 executionRunId、Gateway/Headless 又另生成 runId 的错配：现在 caller/租约/Gateway/Headless/计划 head/日志与 ACK 复用同一显式身份。未传时 Gateway 生成一次。模型路由与模块 seam 也向原 Headless 转交；离线 native fixture 真实走这两层，不以 mock execute 替代。
- Finalizer 入口拒绝 foreign owner、待消费控制、显式旧版本、已删除/中断任务；两处任务进度写入均带捕获的 run/plan，返回前再核对。当前 caller 无版本的所有者/admin 兼容不等于放行旧执行回调。
- 原 DevelopmentVerificationService 新增可注入的 VerificationExecutionGuard，中间件包住原 session open/每条 command；SQL claim 先于动作，按原 token settle。控制先赢零动作、在途事实保留、异常 unknown 不重复派发、取消/DB 写失败不执行，均为固定模拟器计数 fixture，无真实验证命令。
- beforeFinish 已从 Gateway 转交 Headless 原循环；native 合同验证同 owner 下继续与替换草稿。多轮 fixture 显式给定离线预算；另有 totalTokenBudget=1 合同确认零 Provider 请求、paused、head interrupted，不为 hook 静默追加预算。
- 最新同 APK **86/86 + 原九套143/143 = 229/229**，生产审批 UI 隔离链通过。分析21.7s，构建19.4s，证据 major-verification-dispatch-analyze/build-20261019.log 与现有各模拟器 JSON/审批 PNG。77/78、84/85 的中间失败回合未记通过，分别真实捕获转交遗漏与 fixture 未显式提供足够多轮预算。
- **仍未完成迁移**：应用 chat/resume 的实际后置 finalizer 尚未搬进 beforeFinish，实际 caller 尚未注入验证中间件；有限修复仍走旧同 task 新 headless 链，owner 转移风险仍需移除。不能因中间件/接点合同通过宣称真实验证/自动修复闭环。通知插件、崩溃恢复、全旧回调及其他原方案门禁继续；模型3/3、无宿主 tests/真机访问。


### 2026-10-19 实际调用方迁移中（未提升通过数）
源码 chat/resume 已使用 DevelopmentRunCompletion，在原 beforeFinish 内验证；有限修复返回原执行循环继续消息，删除旧另起同任务 Headless 修复方法。修复工具策略同时过滤模型请求 manifest 与实际派发，原步数/Token 预算不增加；修复开关仍需原文件/终端设置、自动验证/自动修复偏好与有效模型配置。finalizer 支持记录 deferred 修复，下一轮重跑全部原检查后才结算，不把请求修复等于修复成功。静态分析已零问题（22.0s）；90 例 APK 构建/模拟器链 `cmd_b52c1c3a63514ae30c024f65d2053861f4c3d037a079bc6d` 仍在进行，**本条不增加通过数，最新已完成证据仍229+UI**。
仍需补：取消时 join 原验证 Future 后再释放租约（原终端已有只在自身串行槽 100ms 检查 canContinue/stop，closeSession 本身不杀进程，不能误解为取消）；必需验证失败不可提前封 completed head；实际修复、命令/平台、崩溃恢复和全量门禁尚未验收。模型3/3耗尽，不宿主 tests，不访问真机。


### 2026-10-19 原循环验证迁移已构建并完成本轮模拟器检查
- chat/resume 实际 caller 已传 beforeFinish；旧 _repairVerification 新同任务 Headless 分支已删除。DevelopmentRunCompletion 捕获原 head token，原服务逐动作 claim/settle；修复返回受白名单限制的原循环 continuation，使用原剩余步数/Token 预算，不新建执行器或增加预算。
- TurnStoppingContext 提供捕获的本地取消/revision 边界，交给原命令 canContinue；沿用原终端串行槽100ms stop检查。正常及恢复入口都在释放其租约前 join completion 清理；不误将 closeSession 解释成终止命令。必需验证不通过且无法继续修复时抛出明确异常，阻止成功 seal；没有执行实际必需检查不得 verified。
- 同一最新APK **protocol91/91 + 九套143/143 = 234/234 + 生产审批 UI 隔离链通过**。新增5例为请求/派发白名单拒绝模型注入、真实空工作区 finalizer 在原循环 seal 前执行、foreign/pending 零 terminal factory、join 等待及本地 revision 撤销。后者是受控 Future 合同，不是实际 Linux 进程中止证据；空工作区没有验证命令，不代表真实自动修复通过。
- 分析24.1s/构建23.6s，日志 major-completion-cleanup-analyze/build-20261019.log；命令 cmd_787e821654656143c4c3b91d63fa46419cbd2cffff775482 完成构建/覆盖安装/91/UI，cmd_c207c94a9ec97db888ac14704fced059082f6a8f78e84157 在同APK复验143。各JSON/审批PNG已刷新。
- 中间90例APK在新终端误用默认构建用户环境，安装签名不兼容而停止，未运行后续检查/未计通过。恢复显式项目 local/gradle-cache、local/android-user，已验证已装APK与新APK公开签名摘要一致，install -r成功；没有卸载、清数据或替换签名私钥。以后每个构建显式设置这两个环境，不依赖已退出终端的 export。
- **F21/A27及整版仍未完成**：真实命令/修复全链、通知插件、恢复错误分支和跨restore旧回调、独立进程崩溃/长期压力、原方案其他页面/功能/发布门禁仍未覆盖。真实模型3/3耗尽；无宿主tests/真机操作。ADR见 mobile-original-loop-verification-adr-2026-10-19.md。


### 2026-10-19 完成回执版本与旧异常隔离
HeadlessRunResult 新增可选 planVersion，返回原 controller 捕获的版本；恢复正常 ACK 与普通 chat 完成写入均传入版本，恢复 catch 不再走无 run/version 的 admin 兼容通道。尚未取得执行回执的失败不会擅自标记当前任务失败。原 beforeFinish 异常先核对取消/新 revision：过期异常不裁决已经接受的纠正，仍在原循环继续；当前版本异常仍抛出，不能伪完成。
最新APK **94/94 + 九套143/143 = 237/237 + 审批UI通过**；新增旧异常与纠正竞态、同owner旧版本ACK拒绝/新版本成功、新纠正恢复普通工具策略3例，原真实Headless/Gateway两例现在也断言回执版本来自原head。分析21.9s/构建20.4s；major-completion-receipts-analyze/build-20261019.log、原JSON/PNG已刷新。cmd_4bc7a12a44ac2952bc291c5ff6993b88dbcbdcba3068ece6 构建/安装/94/UI成功；cmd_7ada1b133b7bcd95a98a5ac6d0945dc0deb14ac693efd67a 九套均打印通过，末尾只读grep查找不存在的测试文件使整条命令退出2，不把该退出码写成成功。无宿主tests或实际模型/终端命令；真实命令、跨restore、通知/崩溃/全版门禁仍未完成。


### 2026-10-19 原验证/会话服务与持久派发集成合同
最新同APK **98/98 + 九套143/143 = 241/241 + 生产审批UI通过**。cmd_563b8d8e4c14bce61cad04b4642d2670803ed78eee4ea475 分析/构建/保留数据安装/98/UI完成0；cmd_38bcf93d1a19c454d9b01660970e5e021bd5ce9f1d33e635 同APK九套完成0。日志 major-verification-runtime-analyze/build-20261019.log，各JSON/PNG已刷新。
新增4例现在真正走原 DevelopmentVerificationService、原 TerminalCommandService 的 session/open/execute/close、原SQL guard：session和每条命令分别claim、pending控制零session、在途命令事实结算且下一条被阻止、原100ms取消检查调用本次运行时stop并清理会话。仅最底层 LinuxRuntimeAdapter 为计数/受控Future，daemon持久层为空内存、工作目录为自有临时目录并清理；没有开启默认PRoot/Termux、恢复用户daemon或执行真实命令。这比单独中间件计数更完整，但**仍不是真实Linux进程/构建/自动修复/崩溃证据**。F21/A27及整版未完成，其他门禁不变；模型3/3，无宿主tests/真机。


### 2026-10-19 原循环组合链集成合同
最新同APK **101/101 + 原九套143/143 = 244/244 + 生产审批UI通过**；cmd_4a19779f6502bbd90b2a00dca1610f95ca0219d368f14737 分析/构建/保留数据安装/101/UI完成0，cmd_27caf93f96063f224291381451d9e725293131317d51c11b 在同APK九套完成0。日志 major-completion-integration-analyze/build-20261019.log 与既有JSON/PNG已更新。
新增3例把自有临时Python工作区的真实快照/文件差异、原finalizer、原verifier、原terminal/session、SQL guard、原AgentExecutor及completion整体连起来：首个合成检查失败后原循环继续、再次检查通过且持久attempt completed/仍单head；禁用修复时必需检查失败不seal成功；重复失败遵守原持久一次修复限额，attempt failed、不追加Provider请求/新head。模型与最底层命令适配器仍为离线固定脚本/计数适配器，内存daemon与DB，不运行Python/pytest或真实模型；不声称模型实际修改了代码、真实检查通过或已完成Linux全链。真实命令/通知/跨restore/崩溃/全版其他门禁仍未完成，F21/A27保持未完成。没有扩大3次模型额度，无宿主tests/真机。
