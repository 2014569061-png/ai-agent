# 移动端下一大版本执行记录（2026-10-18）

> **最新用户指令（2026-10-19 20:57）：暂停开发与测试，只整理交接。** 聊天/计划结果卡本轮为未完成增量：37/37 隔离合同及静态分析通过，UI 驱动在嵌套返回路由处失败，回归未跑。完整断点见 [暂停交接](mobile-chat-results-handoff-2026-10-19-2057.md)。下文历史自主推进指示不覆盖本次暂停。

> **2026-10-19 U04 接续**：已补个人上下文已知名称/旧称/别名/来源防回库、单次明确重添、原子历史和版本校验、授权过滤与清库范围。模拟器文件 SQLite/原合同 51/51，真实管理页 UI 通过；旧备份保留本机未纳入格式的 F17 并返回范围警告。细节见 `mobile-u04-personal-context-2026-10-19.md`。未关闭 W16/U04，未将热重载证据并入历史最终 APK 总数。

> **2026-10-19 U05 接续**：生产文件结果卡已接真实预览/系统分享，确认后可执行，取消不伪造成功且可显式重试；新成果原子发布文件卡，清库同步清卡与动作。增量合同 34/34、原成果回归 12/12、真实合成文件 UI 通过。详情及未完成范围见 `mobile-u05-file-actions-2026-10-19.md`。这是现有预览的热重载源码验证，不计入历史最终 APK 371/371，不关闭 W19/U05 或发布门禁。

> 最新状态：用户于2026-10-19再次要求暂停并交给DeepSeek。已完成两批源码增量；最终已安装APK328/328合同及外部输入UI通过，系统取文UI中断，其他最终UI未齐。先读 `mobile-next-major-deepseek-handoff-2026-10-19.md`。后文历史数字/未实现描述按追加时间理解，不与不同APK相加；整版未完成。

**整版状态：未完成，不具备发布资格。** 本记录不缩减原方案 W00–W21 / F01–F22 的范围，也不将局部导航或配置导入视为整个工作包完成。

## 用户执行边界

渠道已由用户确认：自用／私有 APK。决策及源码能力矩阵见 `docs/mobile-private-apk-decision-2026-10-18.md`。不默认申请 Root/Shizuku/无障碍，不擅自启用公共托管。

- 仅使用电脑上的 `Nexus_Preview_API_36`（Android 16 / x86_64）模拟器，当前序列号 `emulator-5554`，每次操作须重新核实设备。
- **禁止操作用户真机。** 约束提出前仅查询过真机型号/架构/系统版本，未安装、启动或修改其应用；之后不再向其发送命令。
- 最新用户范围：本次排除真机验证，仅模拟器验证；完成原方案全部改动前不再阶段性询问。不干扰真机接口，不执行全局 ADB 重启、断连或真机转发；不运行宿主测试套件。之前宿主结果仅为历史记录，不作为模拟器验证。
- 模型测试授权上限为 3 次：模拟器新会话已完成 3 次（固定标记两次、回忆首个标记一次），均返回预期内容；不再追加调用。界面显示耗时 1.5s/8.6s/1.5s，仅为小样本。截图 `local/temp/major-model-test-{1,2,3}-20261018.png`。
- 不覆盖其他工作的 372 项既有改动；没有执行 reset/clean/提交/推送。
- 下载、缓存和临时证据位于项目 `local/`；不在真实数据上执行破坏性恢复测试。

## 基线与本轮实际变更

- Git 基线：`30e552e`，应用 `0.9.0+95`。开始时 372 项工作区状态记录保存于 `local/temp/major-baseline-status-20261018.txt`。
- 新增 `lib/presentation/navigation/mobile_shell.dart`：四导航、惰性页面创建、独立子导航和保留状态、返回处理。Android/iOS 按平台选取，Windows 原布局保留。`lib/main.dart` 与引导完成入口已接入。
- 新增 `lib/domain/provider_template.dart` 和 `lib/presentation/settings/provider_template_import_page.dart`：严格无密钥 JSON、大小/版本/字段/协议/端点检查、接收方预览、确认失效、局域网/手机回环提示；解析无网络/存储副作用。模型服务商列表已接入现有编辑器。模板不具备可信签名，界面明确来源未经验证；没有宣称二维码已实现。
- 页面候选台账：`docs/mobile-next-major-page-coverage-2026-10-18.md`。47 个源码候选不等于 47 个页面已完成验收。

## 验证证据（仅当前增量）

后续动作安全增量：仅明确布尔 true 可声明恢复，未知恢复能力需要二次确认，替换预览批次重置勾选。设备动作相关选测 65 项通过，日志 `local/temp/major-device-safety-test-20261018.log`；全仓分析退出码 0，`No issues found!`（22.6 秒），日志 `local/temp/major-device-safety-analyze-20261018.log`。没有执行真实设备变更。这些是新增的选测记录，不代表完整 F04/F21 验收。

1. `flutter test --no-pub --reporter expanded`：凭证删除、调度结果、并行子代理分层、分层守护、预览、自动备份、维护服务与跨 isolate 选测，**68 项通过**。日志 `local/temp/major-baseline-regression-20261018.log`。
2. 导航/模板领域/模板界面/桌面导航/模型设置标签选测，**33 项通过**。日志 `local/temp/major-navigation-template-test-20261018.log`。初轮导航测试发现构建器重复调用，已缓存根页面并重测通过。
3. 全仓 `flutter analyze --no-pub` 首轮仅报两处多余 import，已移除；复测退出码 0，`No issues found!`（25.7 秒）。日志 `local/temp/major-analyze-20261018.log`。
4. 通过现有预览脚本完成模拟器 debug 构建/安装，日志确认 `[preview] Ready` 及源文件变更后 `[preview] Hot reload complete.`。debug 模式跳帧日志存在，不作为发布性能结论。
5. 模拟器已实际访问助手、任务、项目、设置四个根页、模型提供商列表与模板导入页，截图保存在 `local/temp/major-emulator-{start,tasks,workspace,mine,provider-list,template-import}-20261018.png`。尚未完成全部状态/页面/主题/大字/横屏/TalkBack 验证。截图可能含模拟器已有会话，不上传到外部报告。

## 全范围工作包台账

当前执行负责人：本会话助手；产品/运营决策和整版验收负责人尚待用户指定。下列未完成项不得由其他用例通过冲销。

| 包 | 范围 | 状态 | 证据或下一步 |
| --- | --- | --- | --- |
| W00 | 基线、审查复核、页面与任务清单 | 实施中 | 68 项可靠性选测通过；47 个页面候选已登记；完整路由和验收输入未冻结 |
| W01 | 系统助手、ASR、动作、渠道、远程/同步可行性 | 实施中 | 渠道为私有 APK、宿主为当前 Windows；模拟器真实握手通过。原生语音/助手待实现，真机专项最后另行许可 |
| W02 | 设计系统与全部页面原型 | 未完成 | 既有全局主题继续复用；逐页设计/复杂状态和无障碍矩阵待完成 |
| W03 | 任务状态、审批、事件、维护/迁移 | 待继续复核 | 现有维护隔离、调度结果、分层等选测通过；未覆盖所有进程/审批竞态 |
| W04 | 四导航、引导、配置、搜索 | 实施中 | 新增 MobileShell 接入主入口和引导完成入口；分页搜索已有基础，跨类型全量搜索未验收 |
| W05 | 语音、系统入口、上下文、手机动作 | 未完成 | ASR、连续语音、助手原生服务及生命周期仍需实现和验证 |
| W06 | 任务工作台、恢复、成果中心 | 实施中 | 待核实/部分完成投影、独立待处理和已读竞态保护落地；模拟器固定检查 14/14、四项已读后仍待处理链路通过；完整恢复/成果与状态矩阵待验收 |
| W07 | 项目开发页面、环境、终端、验证 | 未完成 | 项目页一级可达；完整创作链路和 ARM64 构建未验收 |
| W08 | 记忆、知识库、上下文来源 | 实施中 | 来源误标/本地与模型发送说明已修正；自动记忆注入过滤项目、知识片段附真实来源并可只读预览；模拟器固定12/12。显式工具隔离、完整遗忘/敏感控制及回答引用未完成 |
| W09 | 提醒、定时任务、通知、自动化 | 未完成 | 调度结果选测通过；提醒独立模型、时区/DST/精确授权未完成 |
| W10 | Agent、技能、MCP、模板、市场 | 未完成 | 保留原入口；安装/更新/撤销等整链路未验收 |
| W11 | 模型推荐、预算、用量 | 未完成 | 能力探测和成本/硬预算需完整实现/复核 |
| W12 | 远程执行器、同步、跨设备 | 实施中 | 真实回环执行器/持久作业/成果快照已实现，模拟器握手通过；统一审批提交、配对、同步、租约及完整远程构建链路待完成 |
| W13 | 数据、更新、性能、无障碍、发布 | 未完成 | 自动备份/维护选测通过；全量迁移、签名、Profile、七天使用未完成 |
| W14 | 实时音视频/屏幕会话 | 未完成 | 新增采集、帧有效期、取消隔离和预算未完成 |
| W15 | 首批五个具体连接器 | 实施中 | 五类严格输入契约及日历/联系人编辑器适配接原审批；模拟器固定输入检查 12/12 通过、联系人预填与拒绝已观察，日历账号准备阻塞；其余适配/完整读写/恢复专项待完成 |
| W16 | 关联上下文、指代消歧 | 实施中 | 2026-10-19：新增个人上下文实体/别名/关系模型、schema32 裸 SQL 仓储、消歧与纠正/遗忘演进、聊天注入块与手机管理页；22 条隔离合同随计划协议 228/228 通过。跨设备同步、实体图谱可视化、系统助手语音入口注入未完成 |
| W17 | 可复用工作流 | 未完成 | 不得将桌面工作流入口当成移动确定性流程引擎验收 |
| W18 | 可核查研究成果 | 未完成 | 证据结构、引用支持、更新和冲突待实现 |
| W19 | 六类可操作结果卡 | 实施中 | 2026-10-19：新增结果卡模型/仓储/服务/卡片组件与成果中心区块，9 个注册动作覆盖六类，含幂等键、并发共享执行、stale/conflict/unauthorized 判定与限时确认；17 条隔离合同随计划协议 228/228 通过。真实执行器、统一 ApprovalBridge、跨设备状态同步未接 |
| W20 | 执行中纠正和人工交接 | 未完成 | 计划版本持久事件、旧回调隔离、审批失效及竞态待实现 |
| W21 | 快速接入与托管适配 | 实施中 | JSON 无密钥导入/地址确认/编辑接线完成选测；二维码、能力探测、用途引导、托管决策未完成 |

## 下一步执行顺序

2026-10-19 增量：用户确认五类系统连接器，优先编辑器交接。新增严格 DTO、日历/联系人公开接口、原审批接线与页面、仅模拟器启动/固定检查工具；说明和全部证据索引见 `docs/mobile-system-connectors-contract-2026-10-19.md`。最新全仓静态分析通过（23.4 秒），Android x64 debug 重建/保留数据更新成功，模拟器 Dart isolate 内固定输入检查 12/12 通过，无模型调用。联系人系统编辑器已观察到合成预填，另一次拒绝显示未交接；日历仅交接到账号准备，不能标记编辑/保存通过。没有读取真实联系人/日历数据、登录账号或点击保存。直接读写、地图/文件/媒体、任务人工交接与恢复等仍待完成。

当前远程增量文件：`tool/windows_remote_executor.py`、`tool/test_windows_remote_executor.py`、`lib/infrastructure/remote/remote_executor_client.dart`、`lib/application/remote_execution_probe.dart`、`lib/presentation/projects/remote_execution_page.dart`、`test/remote_executor_client_test.dart`；原占位测试已改为显式 fixture，未配置时不再返回虚假成功。说明见 `docs/mobile-windows-remote-executor-2026-10-18.md`。

模拟器新证据：在 emulator-5554 的实际远程页面认证访问当前 Windows 回环服务，显示「真实连接已通过」、nexus-remote/1、AMD64、python-3.12.7 及真实磁盘空间。截图 `local/temp/major-remote-handshake-20261018.png`。该验证只做握手，不上传项目、不发起模型调用、不提交有副作用任务；离开页面后令牌输入框随页面销毁，不保存配置。全仓静态分析复测通过（22.9 秒），`local/temp/major-remote-analyze-20261018.log`。最新测试约束前的 Windows 执行器 13 项、Flutter 传输及兼容 20 项通过，仅作为历史证据，不充当模拟器测试。

模拟器补充证据：已在模板导入页输入无密钥 `example.com` 示例并点击解析，正确显示接收方/协议/模型/预算，未勾选确认时「继续配置」禁用。截图 `local/temp/major-emulator-template-preview-20261018.png`；没有保存此示例服务商，没有点击网络连接测试。

1. 完成当前增量静态分析与模拟器导航/导入验收，补充已访问页面证据。
2. W00/W01：补动态入口、28 项 A 用例和 12 组 S 专项的具体输入、数据、可重复执行环境与验收人；缺失能力记为缺失而非通过。
3. W03/W20：复用现有运行/审批/维护基础，冻结统一状态、动作结果、参数绑定审批、持久事件、计划版本和恢复契约，先测试后接线。
4. W04/W05/W06/W21：在模拟器完成可测试的助手入口、语音前台状态、任务/成果和配置诊断；凡依赖厂商或 ARM64 的验证按用户禁用真机边界记录阻塞。
5. W07–W19：按原依赖图实现完整工作台、资料记忆、提醒、扩展、预算、远程、实时、连接器、工作流和研究/结果卡，不另建第二套授权/运行引擎。
6. W13：全部 A01–A28 / S01–S12、全页面、迁移、性能和发布门禁齐全后才可宣布整个大版本完成。

## 需要用户/环境提供的依赖（不是授权缩减范围）

- 目标分发渠道；语音/多模态服务配置和成本上限；至少五个连接器具体应用/账号/接口范围。
- 远程执行器宿主、部署方式、认证/同步方案；托管是否运营及负责人/预算。
- ARM64/多厂商/功耗/七天使用等验收在“不得操作真机”约束下保持阻塞；可以由用户另行提供独立测试结果，不能由 x86_64 模拟器替代。
- 人员、工时、交付/验收负责人以及 M0 冻结指标尚未确定，当前不编造发布日期。

## 2026-10-19 任务工作台增量（未完成整版）

用户指示先落地其他模块后，新增待核实/明确部分完成状态、独立待处理页签和异步快照/刷新代际保护；原“全部任务”改为诚实的“最近任务”。复用 Tasks/调度审计与原执行链路，不自动重试，不创建第二引擎。状态契约、兼容说明、列表上限与历史审计缺口见 `docs/mobile-jobs-contract-2026-10-19.md`。

- 全仓静态分析通过（22.1s），debug APK 重构建并保留数据覆盖安装到指定模拟器。
- 模拟器 Dart isolate 内固定检查 14/14；证据 `local/temp/major-jobs-emulator-contract-20261019.json`，不使用真实模型、真实数据库或宿主业务测试套件。
- 隔离 UI 夹具验证 4 项全部已读后，收件箱为空、独立待处理仍有 4 项；截图 `local/temp/major-jobs-fixture-{before,after,pending-after}-20261019.png`，夹具已关闭。
- 新 APK 上原连接器固定检查复验 12/12；日历账号准备/业务保存仍阻塞，联系人未保存，不提升为端到端通过。
- 完整分页、很早的损坏终结审计扫描、真实恢复/副作用核实、进程重启和 UI 请求乱序自动化仍未通过；W06/F13/W15/W20 和整版均不能据此宣布完成。三次模型额度仍已用尽；未查询或操作真机。

## 2026-10-19 记忆与知识增量（未完成 W08/F09）

用户选择先推进其他模块后，落实记忆来源标签/记录 ID/来源会话、无项目自动注入不包含项目记忆、稳定含范围与来源的 revision、知识片段真实文档/分块标识及只读来源预览。修正“数据仅存本机”的误导：自动注入内容会发送给当前模型服务。删除说明不再暗示能撤回历史、已发送上下文、备份或原文件。

最终全仓分析通过 23.2s，debug APK 重构建并保留数据覆盖安装；模拟器固定记忆/知识检查 12/12、任务复验14/14、连接器复验12/12。内存 UI 夹具实际验证来源标签/发送说明和知识来源弹窗，关闭自有弹窗及路由。证据、兼容变化和剩余门禁见 `docs/mobile-memory-knowledge-contract-2026-10-19.md`。

这不是完整 per-run 不保存、敏感信息提取控制、工具 ACL、知识项目隔离、原子 CAS、所有历史上下文遗忘或真实回答引用验收；没有追加模型调用、没有运行宿主测试套件、没有查询/操作真机。整版仍未完成。

## 最新自主执行边界（覆盖此前阶段询问和真机安排）

用户最新明确要求：完成原方案全部内容，**本次排除真机验证，可使用模拟器验证；全部任务未完成前，不再停下来阶段性询问，后续按执行助手计划持续推进。** 原“真机最后另获许可”安排是历史约束，不再把真机专项排进本次执行。仍不查询/操作真机、不干扰其接口，不运行宿主测试套件；三次真实模型额度仍已用尽，不因自主推进而重置。环境/额度阻塞如实列出，不自动当作通过或缩减功能需求。

## 全量本地搜索增量（2026-10-19）

七类数据库分页搜索、类型/项目/时间筛选、旧消息正文与来源重新读取已实装。分析通过；debug x64保数据安装，模拟器固定检查12/12，真实搜索/来源/HistoryPage正文搜索UI通过，原记忆12/12、任务14/14、连接器12/12复验通过。详见 `docs/mobile-search-contract-2026-10-19.md`。仅搜索核心增量完成，整版与未覆盖状态不记通过。下一步成果实体一致性与恢复链路。

## 成果与任务控制守卫增量（2026-10-19）

已新增成果中心、校验副本后入库、缺失/变更拦截、非项目成果兼容、真实资源导航和工作台登记失败反馈；任务请求去掉最近400条查重限制，入队/控制事务化，终态迟到控制与控制ID变参/换任务拒绝。最终分析22.2秒通过、debug x64构建20.6秒、保数据安装；模拟器成果12/12、运行控制12/12，搜索12/12、记忆12/12、任务14/14、系统连接器12/12复验通过。360dp/1.6字体页面采样与输入法浮层截图完成并恢复设置。详见 `docs/mobile-artifact-runtime-contract-2026-10-19.md`；整版未完成，F07完整预览/导出回读/版本谱系及F21计划版本、旧审批和人工证据仍待做。

## 本地纠正与任务CAS增量（2026-10-19）

本地turn代次已接入原工具管线，目标纠正后旧调用/旧批准在执行前拦截；已提交动作不假装撤销。任务进度/完成/断点/恢复计数事务化并使用existing-record CAS，防止删除后晚到写入重新插入。控制持久化提前捕获run归属。最终分析22.3秒、构建20.8秒、模拟器任务运行20/20、本地纠正12/12，其余五组12/12、12/12、12/12、14/14、12/12复验通过。仍待完整持久计划版本、恢复/跨进程链路和六类结果卡，不能标记W03/W06/W19/W20整体通过。详见成果运行契约。继续补记忆显式工具隔离/并发与遗忘，再回收未完成集成项。

### 2026-10-19 记忆作用域与保草稿编辑增量（整版仍未完成）
- 工具共用应用固定 scope adapter，chat 在首次 await 前捕获项目/会话，headless 绑定已存在任务；项目工具只读全局及本项目，新增自动归本项目；模型参数不扩权。已有 id 写要求 revision；事务 CAS 防并写覆盖及删除后复活。owner/admin 无 scope API 仍保留。
- remember/memory_write 提升为敏感且需确认；既有 trusted/fullAccess 策略仍可自动批准，非所有模式逐次确认。注入使用含 id/来源/UTC 时间的 JSON，SQLite 秒精度对齐。未知写故障报告 effect=unknown。
- 编辑保存失败保留输入/错误/复制草稿；放弃需确认；删除使用逐条 expectedMemory。调试夹具仅用独立内存 DB，实际点击制造并发并确认旧草稿不覆盖新记录，再取消/放弃并关闭夹具。截图：local/temp/major-memory-scope-editor-conflict-20261019.png（已人工查看，草稿、冲突及复制入口可见；IME 侧栏略遮左侧文案，非完整键盘/TalkBack 验收）。
- 最新 analyze 无问题 22.4s；x64 debug build 19.5s，固定 Nexus_Preview_API_36 / emulator-5554 install-r，8 套模拟器契约 110/110；UI open→edit→draft→mutate→save→capture→inspect→cancel→discard→close 全链通过。命令 cmd_4cd70b15faf790844393ffad64e4695dad045d7062c59a81、cmd_d2c3d8d8b855b74893cba8106c2bb86f7eae76a314b3bf3f。未调用模型/宿主 tests/真机/外部发送。
- 未完成：遗忘 tombstone 与重学屏障、Knowledge 项目隔离及跨进程 generation。仅上述局部通过，不替代 F21/A23/整版门禁，也不构成 ARM64 或发布资格。

### schema29 遗忘与知识范围后续增量（2026-10-19，整版仍未完成）
- 前述“遗忘/Knowledge隔离尚未实现”是当时状态，已由本增量推进：schema28持久遗忘规则、删除/更正/停用事务保护、来源会话自动写屏障；schema29知识独立项目绑定、分scope缓存及SQLite触发器持久revision，第二连接和原始SQL提交后失效。跨来源任意语义改写、已发送上下文及完整独立进程压力测试不在本轮通过范围。
- 保险箱包含遗忘与范围：旧备份不会抹掉较新本机遗忘选择，跳过旧记忆并报告；项目文档恢复不悄悄全局化。无效规则/范围预验证、schema27/28升级与重新打开验证。
- 最新analyze无问题23.5s、build20.6s，同APK九套143/143（knowledge21+scope28+memory12+runtime20+steering12+artifact12+search12+jobs14+connectors12），cmd_d54520d7e0b5c3a2e0e8a7d000434d20a32dc7c347304ff2。知识合成入库失败保精确草稿、取消范围保草稿、重试项目保存与数据库/注入核实UI通过，cmd_47271156a7633a624228b266218c681e7cd96a795e6c628e；失败/成功截图已人工查看。最新APK记忆精确草稿冲突UI复验cmd_8604097d9ede4b1a200fe76b12d874ea2692c09142a34ce5通过。
- 不含新增模型、宿主tests、真机操作；不是ARM64/Profile/发布资格。详见mobile-memory-knowledge-contract-2026-10-19.md追加契约；关联歧义/使用记录、知识更正/范围管理和已组装上下文失效仍待补。当前转入持久计划、活动runId、旧审批取消及控制消费，不宣布W08/W20或全版完成。

### 持久计划存储协议第一阶段（schema30）
控制提交已原子记录不可变计划修订，持久run身份/派发claim、去重、旧claim结算、第二连接/重开、保险箱保留及恢复不激活已落地。固定协议24/24，同APK10套167/167，analyze23.0s无问题、build21.6s；cmd_c91e0877e777a4190f0aa7f6d97770c7cf3fad013456448d。实际执行器/后台消费/审批UI与通知/旧回调还未接新持久屏障，F21/A27仍未完成；继续同引擎集成。未增加模型/宿主tests/真机。


### 2026-10-19 持久计划原引擎接入
原执行器、chat/headless、控制收据和 TaskService 的运行/计划屏障已增量接入，无第二引擎。新同 APK 合同 41 + 原九套 143 = **184/184**；分析无问题 22.5s、构建 21.8s。F21/A27 仍未验收：主动审批撤销、持久审批 scope、其余旧回调/后置自动验证和崩溃恢复等继续实施。主卡保持 running，2/12；没有新增真实模型调用、宿主测试或真机访问。整版其余门禁不因局部合同通过而核销。


### 2026-10-19 schema31 审批作用域
已接原 inline/sheet/通知代码，按框架创建的 run/plan/call scope 约束裁决；本计划许可不扩散到全局。固定模拟器合同 61/61 + 同 APK 九套 143/143 = **204/204**，分析22.1s、构建19.3s。审批超时缺陷已被新 fixture 捕获并修复，不把失败回合记通过。F21/A27 保持未完成：主动 UI/通知、完整循环及后置验证/旧回调/崩溃恢复继续。模型预算仍3/3耗尽，未新增调用，未触碰真机或宿主测试。


### 2026-10-19 原循环多轮与审批 UI
同 APK 72 + 143 = **215/215**，原生产审批 sheet 的隔离模拟器 UI 链通过（覆盖其他路由时只撤旧审批、旧裁决拒绝、计划许可不扩散、再次纠正清缓存）。补原 AgentExecutor 离线合成 Provider 多轮合同及草稿替换事件；beforeFinish 异步接点通过竞争/续跑/异常/取消检查。分析21.6s、构建21.1s，真实模型预算仍3/3。**后置验证/自动修复仍需迁入 hook**；旧同 task headless 修复转移 owner 与无版本 finalizer 写入风险已记录，不放宽屏障假装成功。F21/A27 与整版仍未完成。


### 2026-10-19 恢复身份与验证中间件
Gateway/Headless 复用调用方 runId，修复恢复 ACK 与 head 所有权错配；finalizer 两处快照写入已加 run/plan 屏障。原验证服务可注入逐 session/命令持久 claim/settle，中间件 native 零动作/在途事实/unknown/取消/DB 失败检查通过。beforeFinish 转交 Gateway→原 Headless 已验证，严格小预算仍零请求暂停。最新 APK **229/229 + 审批 UI 链通过**，分析21.7s/构建19.4s。**真实应用 caller 尚未迁入 hook/注入中间件，旧自动修复 owner 转移未闭环**；F21/A27、整版任务保持未完成，继续推进，不追加真实模型、宿主 tests 或真机验证。


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


### 2026-10-19 W05前台单句语音增量
新增原生SpeechRecognizer owner/session桥、原TTS互斥、显式权限/设备端或可能联网系统服务选择、编辑确认/取消/可选自动发送，接原聊天而非新引擎。最新同APK255/255+审批UI通过，11个新语音合同中10个内存Source、1个实际原生只读能力查询；没有真实录音/ASR或语音Sheet UI证据。契约与支持/未完边界见 mobile-speech-capture-contract-2026-10-19.md。**连续会话不靠循环短句伪造，W05/F02/F03与整版仍未完成**，继续推进。模型3/3、不宿主tests/不真机。


## 2026-10-19 生产语音Sheet隔离UI链已通过
- 新增 speech_capture_ui_checks.dart 与 verify_speech_capture_ui_emulator.py，运行生产 SpeechCaptureSheet、注入内存Source，不触发真实ASR/麦克风/系统授权/TTS/模型，也不写用户聊天草稿。
- 模拟器真实UI点击/IME验证：录音状态、遮盖层使捕获撤销且不弹掉遮盖层、取消不提交、旧session转写拒绝、最终转写等待确认、在可编辑输入中追加_edited并确认、仅记录显式自动发送意图、无引擎时纯文字回退且零录音/授权。3PNG与 major-speech-capture-ui-20261019.json 保存于local/temp。
- 为该链补齐生产路由边界：隐藏语音Sheet取消当前捕获并关闭本次自动发送；自动发送再次核对本Sheet是current route；取消/关闭只操作捕获的owned route，不会误弹后来遮盖层。停止提示不再提前宣称硬件录音已经结束。
- **最新同APK255/255 + 生产审批UI + 生产语音UI隔离链通过**。cmd_756c0b1f698f722d6494e8da806bee4bf8dae28745ce1eb5 完成分析21.9s/构建21.1s/保留数据安装/112/两UI，cmd_d650ed5c5e8eea5bf963695f789aaee50e8f752d9b6e291e 同APK复验143完成0；major-speech-ui-analyze/build-20261019.log与JSON/PNG已更新。
- 这仍不是实际ASR准确率/声学/硬件取消、前台连续会话、后台唤醒或系统助手验收；F02/F03/A02/A03/S01与整版保持未完成。模型3/3耗尽、不宿主tests/不访问真机，继续后续原方案能力。


## 2026-10-19 四入口与暖链/语音可见性
- MobileShell 监听原DeepLinkService，暖入口切回助手但不自动弹掉嵌套编辑页；新的 AssistantEntrySurface 使用同步可见性notifier并绑定祖先route，阻止缓存/隐藏页消费入口，也阻止隐藏语音Sheet自动发送。切换tab或全局遮盖会取消捕获，旧结果不能复活。普通chat页仍走原流程，繁忙/恢复时保留入口，预填成功才ACK；nexus://assistant只导航、不替换草稿/发模型。
- DeepLinkService保留原快捷方式API，增加独立embedding流、revision与明确拒绝反馈。拒绝未知host、凭据/端口/片段/路径、重复/未知参数、超过20000 URI/16000预填；待处理内容不被新冲突入口悄悄覆盖。新接受入口revision也撤销旧语音的自动发送资格。
- **同一最新APK123/123+九套143/143=266/266 + 生产审批UI + 扩展语音/入口UI链通过**。cmd_77af2baf2fc9ad0208c196433d095f0689617c0aa5d75790 分析/构建/保留数据安装/123/两UI完成0，cmd_d6d18567259d64630bf1e2ca8bca89541732e3e50e88aac9 同APK143完成0。major-entry-surface-analyze/build-20261019.log、原JSON/PNG已刷新；新增 major-entry-ui-unsaved-preserved-20261019.png。
- 新11合同为原URI解析/边界/旧slot保留/revision/纯消费门禁；UI现在嵌入真实MobileShell和生产SpeechSheet、使用独立深链流与内存落地页/ASR Source。实际点击验证tab隐藏停止捕获、暖入口回助手、繁忙保留、未保存嵌套路由不被深链或系统Back弹掉、明确离开后才消费。没有在真实用户聊天/DB执行这些入口，也没有真实录音/模型，不能冒认生产ChatController数据库/声学/崩溃全验。
- **F02/F03/A02/A03/S01及整版仍未完成**：默认助手三服务/角色、上下文/分享/通知路由全覆盖、独立连续会话、真实ASR与平台矩阵仍待落实；另需补数据库失败后的重试屏障，避免保留入口在持续失败时按帧重试，并审计原TTS初始化等待期间stop后旧播报晚启动的竞争。模型3/3，不宿主tests/不真机。


## 2026-10-19 失败入口重试与原TTS初始化竞争
- DeepLinkService新增按revision的失败抑制；chat预填失败保留内容但不按帧重试。显式“重试”绑定失败revision，旧Snackbar不可重试另一条已改变入口；新接受的同一入口可重试，旧失败回调不能压制新revision。
- 原TtsService继续作为生产单例并复用FlutterTts：合并并发初始化，用操作revision在每次await后核对owner；stop也撤销等待中的初始化/替换播报，防止麦克风打开后旧speak才晚启动。保留旧stop不抛错API；新stopBeforeRecording只对停止接口明确ACK返回true，未确认时语音Controller不启动录音。仅注入独立FlutterTts接口实现作为测试seam，不替换生产全局平台通道。
- **同一最新APK132/132+九套143/143=275/275 + 生产审批UI + 扩展语音/入口UI链通过**。cmd_0c4be35b221f27d61eab38f97910c9327c9847eb5decc8af 完成分析/构建/保留数据安装/132/两UI，cmd_e5439754d8878324790df3db9503f3eedee0f098a2a7350b 同APK143完成0。major-entry-tts-fence-analyze/build-20261019.log、原JSON/PNG已刷新。
- 新9例为3个失败/显式重试revision合同、5个实际TtsService异步生命周期（接口假实现，不构造插件/设备引擎、不发声音）、1个停止未确认时零录音/授权。证明晚绑定/旧替换不能启动播报，不冒称真实声音/设备取消。
- **仍有边界未验**：FlutterTts原生全局完成/错误回调没有utterance ID，旧完成事件与新播报的全部交错不能由这些fixture宣称完全隔离；尚不使用它驱动“播报完自动开麦”的连续会话。真实ASR/TTS/通话/耳机、默认助手三服务/角色及上下文、分享/通知全路由、API24–25启动保护、独立连续会话、跨restore/真实Linux/崩溃/全版门禁仍未完成。模型3/3，不宿主tests、不真机。


## 2026-10-19 SDK隔离与实际只读识别能力
- 新增 SpeechCaptureLifecycle/Factory，把API26 AudioFocusRequest类型从MainActivity字段隔离；API24–25分支只注册“不可用/文字回退”通道，不构造识别器、请求权限或加载API26实现。旧系统录音入口禁用；API26+仍用原ForegroundSpeechBridge。**这只是源码分支与当前API36构建证据，不是已在API24/25运行通过。**
- 语音页离开前台也清除本次自动发送；预填异步结束后若页面已销毁不ACK待处理入口。
- 最新同APK **133/133+九套143/143=276/276 + 审批UI + 扩展语音/入口UI链通过**；cmd_4409e64549f19491a601f3f33cf1e334e282379a44308062 分析零问题22.6s/构建/保留数据安装/133/两UI完成0，cmd_96739f40374785805c934165e2a2666d90444cb94f792902 在同APK143完成0。major-speech-sdk-guard-analyze/build-20261019.log与原JSON/PNG更新。
- 新合同验证不支持SDK时即使Source宣称有引擎也零授权/零启动；实际只读原生能力快照写入协议JSON：**onDeviceAvailable=true、systemAvailable=true、permissionGranted=false、foreground=true、supportedSdk=true、minimumSdk=26**。这是Nexus_Preview_API_36 / emulator-5554报告的引擎存在性，不是普通话/数字/日期/应用名准确率或语言模型可用性证明。
- 本次仍没有实际录音、系统授权或声音，不启用/读取宿主麦克风，也不以“引擎不存在”伪称环境阻塞。真实声学/硬件中断及独立连续会话、默认助手角色/上下文、分享/通知/恢复/发布等门禁仍未完成。模型3/3，不宿主tests/不真机。


## 2026-10-19 用户中止实施：交接

用户最新要求改为“把未完成的任务，写一份交接文档”，覆盖此前持续自主实施的安排。此后未继续修改业务源码或运行功能测试；已创建 `docs/mobile-next-major-handoff-2026-10-19.md`，列明完整剩余范围、证据、约束和接手顺序。

主卡 `9b084138-d144-4aad-95b9-eceee93be3bf` 已确认更新 rev24、blocked、2/12，因用户要求交接而暂停；不能设置整版 completed。最新原生构建仍是同APK133+143=276及双UI通过；没有真实录音/声音/真机动作，模型3/3额度已耗尽。语音自动发送未检查打开前及返回时已有 pending 入口的候选缺口仅分析，尚未补丁/验收；下一任先复核，勿误认已完成。

## 2026-10-19 用户要求恢复实施：两处P0与默认助手入口

用户明确要求阅读交接并继续，已恢复本地实施。原Arena桥接/任务卡MCP在当前会话不可用，未冒认主卡已更新。完整范围和约束沿用，不操作真机、不追加3/3已耗尽的模型额度、不运行宿主测试、不采集宿主麦克风、不提交/推送。

- 修复既有pending入口不改变revision时的语音自动发送缺口：生产提交屏障同时检查打开前与返回时无pending；后续被消费也不能给旧语音重新授权；补页面可见性、恢复状态检查与暂存提示。6条新增Android合同及生产Sheet隔离UI两个新增场景通过。
- 审计发现resumeTask原已应用断点分支会无run身份清断点并无条件写completed。改为TaskService单事务比较新鲜快照revision、同run/version终态head和已应用终态回执；失败/取消保持原终态，缺证明不改写/不重放并给UI提示。回执持久化planVersion，不继承缺版本证明；10条新合同通过。其余兼容调用/跨restore审计仍未完成。
- 新增真实VoiceInteractionService、session service、识别注册兼容端点及元数据、默认系统助手设置引导和真实角色/激活状态。AOSP的助手角色不接受通用角色申请，实际UI捕获后改用系统助手选择页。原生session与系统助手键可打开纯导航入口，复用原聊天/语音/审批；识别端点不提供独立ASR、不委托自循环，原前台识别明确排除自身外部服务。无自动录音、后台唤醒或页面/截图采集。5条新状态/原生只读合同通过。

**最终同一x64 debug APK154+原九套143=297/297，生产审批、扩展语音/入口隔离UI、真实默认助手UI三条链通过。** 完整分析零问题149.3秒，最后异常提示增量三文件分析零问题12.2秒，最终构建6.8秒并保留数据覆盖安装。真实默认助手UI覆盖选择/取消/激活、session、KEYCODE_ASSIST、遮盖路由保护、撤权导致进程结束后新进程状态核实，最后恢复原Google助手/识别器；随后实际“我的→默认系统助手”菜单访问通过，麦克风权限仍false。

源码、APK哈希、JSON/截图及完整剩余状态见 `docs/mobile-next-major-resume-2026-10-19.md`、`docs/mobile-default-assistant-contract-2026-10-19.md` 与 `local/temp/major-resume-evidence-20261019.json`。本轮仍不证明真实声学/连续会话、系统上下文、安全锁屏/厂商、真实Linux修复、跨进程任务恢复、ARM64或整版发布；W00–W21/F01–F22、A01–A28/S01–S12未完成门禁继续保留。

## 2026-10-19 F17 关联上下文与 F20 结果卡（W16/W19）

用户明确指令：先做 F17 关联上下文 + F20 结果卡。详单见 `docs/mobile-next-major-implementation-audit-2026-10-19.md` 第六节。

- F17（W16）：新增 `lib/domain/personal_context.dart`、`lib/infrastructure/database/personal_context_store.dart`、`lib/application/personal_context_service.dart`、`lib/presentation/settings/personal_context_page.dart`、`lib/debug/personal_context_checks.dart`；schema 升 32，四张 `nexus_pctx_*` 表（裸 SQL，不跑 build_runner）；聊天动态上下文段注入（记忆/知识之后）；22 条合同覆盖来源三态、推测不自动确认、有效期、项目隔离、同名消歧、歧义不自动选、敏感动作拒绝推测对象、纠正保历史并递增 revision、遗忘级联+tombstone、注入预算截断。
- F20（W19）：新增 `lib/domain/result_card.dart`、`lib/infrastructure/database/result_action_store.dart`、`lib/application/result_action_service.dart`、`lib/presentation/chat/widgets/result_card_view.dart`、`lib/debug/result_card_checks.dart`，成果中心追加结果卡区块；`result_cards`/`result_actions` 两表；9 个注册动作覆盖六类，幂等键 `result-card:<cardId>:<actionType>:v<version>`，并发点击共享同一执行，失效判定 stale/conflict/unauthorized 且失败不写 succeeded；17 条合同。
- 验证（最终，2026-10-19 18:45）：`flutter analyze --no-pub` 零问题；合同 332 → **371/371**（计划协议 189 → **228/228**，报告 `local/temp/major-plan-protocol-emulator-contract-20261019.json`）；最终同版 APK `sha256 8ebe5948127987652c672c43b3ab611a412fb8f71a9f2ab0977f778c2ac1ddbc`（磁盘与设备已安装 `base.apk` 一致），该 APK 上**五条最终 UI 驱动 5/5 通过**（`local/temp/major-final-ui-rerun-after-device-restart-20261019.log`，设备默认助手/secure settings/运行时权限均已复原）。
- 模拟器实看（`local/temp/f17-context-*.png`、`local/temp/f20-*.png`）：F17 管理页可建实体并显示来源/确认/有效期；F20 成果中心出现「结果卡 1 张可操作结果」、卡片显示 `资源 artifact/… · 版本 v1 · 卡片 r1` 与「预览文件 / 分享文件」。实看发现结果卡横向列表 168px 固定高度在摘要两行时溢出 1px，改为 184px（`lib/presentation/artifacts/artifact_center_page.dart`）。无执行器时点动作如实显示「没有可用的操作执行器，已停止（不会伪造成成功）」并转「失败」，未伪造成功态。历史哈希 `ce8ac684…`/`e2bad66a…` 已被最终构建覆盖，不再引用。
- 未完成：六类真实执行器（Intent/系统能力）、统一 ApprovalBridge 接线、跨设备状态同步、实体图谱可视化、系统助手语音入口注入；仍不关闭 §6 完整验收门禁。

## 2026-10-19 U05 统一审批增量

- 成果结果卡已接统一前台 sheet / 后台 ApprovalBridge；仅本次、持久审批权威与资源/动作版本绑定，执行前重校验；事务 CAS 阻止多实例/双连接重复执行，迟到结果不恢复已删除动作。
- 新增审批合同 27/27；文件动作 34/34、成果 12/12、个人上下文 51/51 回归；实际结果审批 UI 4/4、原计划审批 UI 2/2。独立证据和复跑入口见 [U05 审批记录](mobile-u05-result-approval-2026-10-19.md)。不与历史 371/371 累加。
- 共享预览在验收期间重建为 `3ac2ff38…`，安装包/磁盘哈希一致；本轮仍是实时源码核对后的热重载检查，不是新最终 APK 签收。历史最终五条 UI 证据未覆盖。
- 仍未完成：非文件执行器、聊天结果时间线、真实跨设备版本同步、OS 锁屏通知端到端，以及其他 U04/U06/U07/发布矩阵门禁。`releaseReady=false`，W/A/S 未关闭。
