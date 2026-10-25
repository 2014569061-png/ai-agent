# 移动端下一大版本：未完成任务交接文档

> **最新接手入口：** 用户再次要求暂停并交给DeepSeek，见 [DeepSeek最新交接](mobile-next-major-deepseek-handoff-2026-10-19.md)。本文是更早的历史交接；默认助手及单次页面文字等源码已由后续增量实现。最新最终APK为328项合同及外部输入UI通过，其他最终UI未齐，不具备发布资格。

> **后续恢复实施：** 用户已于同日要求继续未完成任务。本文保留交接时的历史快照；本地最新修改、验证证据和剩余状态请看 [恢复实施记录](mobile-next-major-resume-2026-10-19.md) 与 [默认系统助手契约](mobile-default-assistant-contract-2026-10-19.md)。原远端任务卡 MCP 当前会话不可用，未冒认远端卡已更新。

**交接日期：2026-10-19（Asia/Shanghai）**  
**项目：`D:/AIIIIII/ai-agent/mobile_agent`**  
**交接原因：用户中止继续实施，要求整理未完成任务。**

> **整版未完成，不具备发布资格。** 最新同一 x64 debug APK 的 **276/276 项模拟器合同检查，以及生产审批 UI、扩展语音/入口 UI 两条隔离链通过**。这些不是全部功能验收，也不是实际声学识别、真实 Linux 自动修复、跨进程恢复或 ARM64 发布证明。请勿将检查数量当作完成率。

## 1. 接手时先看这几项

1. 以最初方案 `docs/mobile-next-major-implementation-2026-10-18.md` 为总范围，必须保留 **W00–W21、F01–F22、A01–A28、S01–S12**；不能缩减为首页、语音或当前增量。
2. 本文是交接摘要。详细历史和各次证据在 `docs/mobile-next-major-progress-2026-10-18.md`；该文件前部工作包表是早期快照，**必须结合后续追加段落阅读**，例如“ASR待实现”“W20待实现”已不准确反映最新源码，但完整验收仍未完成。
3. 最新已完成证据为 **133 协议项 + 九套 143 项 = 276 项，同一 APK**，并通过两条 UI 链。没有待轮询构建或 UI 命令；本文所列最新命令均已结束。
4. 最近工作是：原执行循环验证/修复迁移、版本/审批/取消屏障，随后落实前台单句语音、四入口可见性、暖深链、失败重试和原 TTS 初始化竞争防护。
5. **系统默认助手三服务尚未实现；独立连续语音、实时多模态等仍未实现完整闭环。** 不得把单句录音循环称为连续会话，不得把普通深链称为默认助手接入。
6. 当前主任务卡：`9b084138-d144-4aad-95b9-eceee93be3bf`，交接前更新至 **rev24、blocked、2/12 完成**。`blocked` 是为用户要求交接而暂停，不是完成，也不表示已经穷尽所有可推进工作。

## 2. 不可违反的执行约束

| 项目 | 约束 |
| --- | --- |
| 工作方式 | 使用用户已提供 MCP；先任务卡后执行，复杂步骤持续更新；远端终端统一 Bash。此次用户要求交接，后续是否恢复实施以新指示为准。 |
| 既有改动 | 开始时已有 372 项工作区改动，Git 基线 `30e552e`、应用基线 `0.9.0+95`。只增量修改；不得 reset、clean、提交或推送。372 是初始值，不是当前状态数量。 |
| 设备 | 只操作 `emulator-5554`，核实 AVD 为 `Nexus_Preview_API_36`，Android16/x86_64。每个 ADB 命令显式指定序列号。 |
| 真机 | 本次排除真机验证；不得查询/安装/启动/转发/修改真机，不干扰用户接口；不得全局重启、断连 ADB。 |
| 测试 | 不运行宿主测试套件。宿主静态分析、构建允许；Python 驱动只作模拟器 RPC/UI 传输，业务合同在 Android Dart isolate 执行。历史宿主测试不抵作模拟器证据。 |
| 模型 | 真实低成本模型测试上限 3 次，**已全部用完**，不得追加、重置额度或暗中调用。后续离线 fixture 不算真实模型验收。 |
| 数据与账号 | 不破坏真实用户数据，不在真实库上做破坏性恢复测试；不得替用户登录、开通付费/托管；不得执行真实外部发送、删除。 |
| 权限 | 自用/私有 APK，不默认 Root、Shizuku、无障碍；保留已有受控专业入口。日历/联系人系统编辑器打开不等于创建或保存成功。 |
| 音频 | 本轮没有启动真实录音/发声，未启用或读取宿主麦克风。模拟器声学测试应保证不会采集宿主私密音频，不能直接打开 host microphone。 |
| 缓存与证据 | 下载、缓存、临时证据放项目 `local/`；覆盖安装用 `install -r`，不卸载、不清数据。 |
| 真实性 | 未覆盖/环境阻塞不算通过；不同 APK 的结果不得相加；x64 不替代 ARM64、Profile、功耗、多厂商或七天使用。 |

## 3. 最新可复核证据

### 3.1 同版验证结果

| 检查 | 数量/结果 | 驱动 |
| --- | --- | --- |
| 原运行、审批、验证、语音、入口、TTS 等合同 | 133/133 | `tool/verify_plan_protocol_emulator.py` |
| 知识范围 | 21/21 | `tool/verify_knowledge_scope_emulator.py` |
| 记忆工具范围 | 28/28 | `tool/verify_memory_scope_emulator.py` |
| 记忆/知识基础 | 12/12 | `tool/verify_memory_knowledge_emulator.py` |
| 任务运行 | 20/20 | `tool/verify_task_runtime_emulator.py` |
| 执行中纠正 | 12/12 | `tool/verify_steering_guard_emulator.py` |
| 成果 | 12/12 | `tool/verify_artifact_emulator.py` |
| 全量搜索 | 12/12 | `tool/verify_global_search_emulator.py` |
| 任务收件箱 | 14/14 | `tool/verify_job_board_emulator.py` |
| 系统连接器输入合同 | 12/12 | `tool/verify_system_connector_emulator.py` |
| 生产审批 UI 隔离链 | 通过 | `tool/verify_approval_scope_ui_emulator.py` |
| 生产语音/四入口隔离 UI 链 | 通过 | `tool/verify_speech_capture_ui_emulator.py` |

- 构建/安装/133/两 UI：`cmd_4409e64549f19491a601f3f33cf1e334e282379a44308062`，completed、exit0，约211秒。
- 同 APK 原九套143复验及只读能力提取：`cmd_96739f40374785805c934165e2a2666d90444cb94f792902`，completed、exit0。
- 分析：`local/temp/major-speech-sdk-guard-analyze-20261019.log`，零问题，22.6秒。
- 构建：`local/temp/major-speech-sdk-guard-build-20261019.log`。
- 协议原始结果：`local/temp/major-plan-protocol-emulator-contract-20261019.json`。
- UI 原始结果：`local/temp/major-approval-scope-ui-20261019.json`、`local/temp/major-speech-capture-ui-20261019.json`。
- UI 图片包括 `major-speech-ui-covered-20261019.png`、`major-speech-ui-edited-20261019.png`、`major-speech-ui-fallback-20261019.png`、`major-entry-ui-unsaved-preserved-20261019.png`，均在 `local/temp/`。

**实际只读识别能力快照：** `onDeviceAvailable=true`、`systemAvailable=true`、`permissionGranted=false`、`foreground=true`、`supportedSdk=true`、`minimumSdk=26`。这是指定模拟器报告的引擎存在性，不是中文/数字/日期准确率，也不保证所选语言模型已安装。不能把真实录音未测写成“引擎不存在”。

### 3.2 证据边界

- 大量合同使用内存 DB、固定脚本模型、受控 Future 或最底层计数适配器；不能冒充真实模型/系统动作/进程崩溃证明。
- 验证集成用原 finalizer/verifier/terminal/session/SQL guard；底层命令仍是 fixture，**没有执行真实 Linux 命令或真实 pytest**。
- 语音 UI 使用生产 Sheet、真实 MobileShell、真实 UI 点击和 IME，但识别 Source 与落地页为隔离内存实现；不写真实聊天草稿，不调用模型，不开真实麦克风。
- 本轮实际 API24/25 设备未运行；低 SDK 保护只是源码分支与当前 API36 重构建证据。

## 4. 最近已落地的源码与接线

### 4.1 原循环完成验证与修复（W03/W07/W20 增量）

- `lib/application/development_run_completion.dart`：chat/resume 共用的 beforeFinish helper，保持原 owner/head/token，逐动作 claim/settle；修复回到原循环 continuation，不另起同任务 Headless。
- `agent_loop/agent_loop_hooks.dart`：`TurnContinuation.allowedToolNames`、停止上下文局部可继续条件。
- `agent_executor.dart`：请求 manifest 和实际 dispatch 双层白名单；新纠正清除旧修复限制；beforeFinish 过期异常不能裁决新接受计划；仍用原步数/Token 预算。
- `development_loop_finalizer.dart`：deferred repair 保留失败事实，随后完整重验结算 completed/failed；owner/version/pending 屏障不放宽。
- `verification_execution_guard.dart`、`persisted_run_fence.dart`、`run_controller.dart` 等维持持久派发和取消边界。
- chat/resume 在释放租约前 join completion 清理；必需检查失败且不能修复时抛 `DevelopmentCompletionUnverified`，不 seal 成功。
- `headless_executor.dart`：`HeadlessRunResult.planVersion` 返回原 controller 捕获版本；chat/resume ACK 传版本，恢复 catch 不再无 run/version 走 admin 兼容写入。
- 原 `TerminalCommandService.run` 自身串行槽约100ms轮询 canContinue 并 stop；**closeSession 只删会话，不等于杀进程**。没有创建第二终端装饰器。

### 4.2 前台单句语音（W05/F02 增量）

- 原生：`ForegroundSpeechBridge.kt`、`SpeechCaptureLifecycle.kt`、`MainActivity.kt` 与 `AndroidManifest.xml`。
- Flutter：`lib/application/speech_capture.dart`、`lib/presentation/voice/speech_capture_sheet.dart`、`lib/presentation/chat/chat_page.dart`。
- 仅用户主动录音时请求麦克风；默认设备端识别，明确切换系统服务后才允许可能联网的服务；没有静默云回退、后台麦克风服务或唤醒词。
- owner/session 隔离事件、授权、取消与音频焦点；等待 connected 握手，取消先撤销本地代际，避免授权/初始化等待结束才晚开麦。
- 点击/按住录音、松开结束、编辑确认、取消、缺省关闭的本次自动发送；最大60秒单句，stop 最终结果等待有上限。原始音频不传给 Dart、不由应用保存。
- 文字交给原聊天发送流程；会话/controller、深链 revision、草稿、附件、忙碌条件变化会限制自动发送，不建立新执行器。
- API24–25 仅文字回退通道；API26 类型通过工厂隔离，未在旧系统实际运行。

### 4.3 四入口/深链/可见性

- `lib/presentation/navigation/mobile_shell.dart`、`assistant_entry_surface.dart`：同步 notifier 绑定 tab 和祖先 route；缓存但不可见页不能消费入口或自动发送语音。隐藏 Sheet 撤销捕获并关闭自动发送。
- `lib/infrastructure/share/deep_link_service.dart`：保留旧快捷方式，新增 `nexus://assistant` 纯导航、独立流、revision、参数和大小限制、待处理 slot 不被冲突入口覆盖。
- `chat_page_intents.dart`：仅可见且当前、非忙碌/恢复时消费；成功后 ACK，失败保留并按 revision 抑制，不逐帧重试；显式重试绑定失败 revision。
- 未保存嵌套路由不被暖深链或系统 Back 自动弹掉；用户明确离开后再消费。

### 4.4 原 TTS 防护

- `lib/infrastructure/tts/tts_service.dart`：仍是原 FlutterTts 单例，合并并发初始化；操作 revision 防止 stop 后旧初始化/替换播报晚启动。
- 保留旧 nonthrowing stop API；新增 `stopBeforeRecording`，只有明确接口 ACK 才允许语音开麦。
- 独立引擎 factory seam 用于原服务的内存接口检查，未替换生产全局平台通道。
- **原插件全局完成/错误回调没有 utterance ID，旧完成与新播报的全部交错仍未证明隔离。不要依赖此监听器实现自动开麦连续会话。**

## 5. 优先处理的未完成项

### P0：接手后先复核的风险

1. **语音自动发送与已有待处理外部入口：候选缺口，尚未补丁。** 当前已有深链 revision 检查，但若打开语音时就有 pending 入口，revision 可能保持不变。建议同时要求“打开时无 pending、提交时无 pending”，并核对当前上下文；否则只暂存并提示未发送。这个问题尚未做专门复现/合同，不能写成已修。最后中止前只停留在分析，未创建/应用对应自动提交 helper。
2. 原 TTS 无 utterance ID 的全局回调交错：本轮只解决晚绑定/替换晚启动和接口停止未确认开麦，不是所有真实声音/回调问题都已解决。
3. 原循环验证修复的真实 Linux 命令、实际文件修复、取消/暂停中止、未知结果核实与租约清理全链；内存底层适配器不能替代。
4. 跨 restore/维护切换/独立进程旧回调与 TaskService 无 runId 兼容入口的全量审计；最近修的是 chat/resume 关键路径，不是全仓都完成。
5. 所有有副作用动作仍须绑定参数/对象/计划版本审批，未知结果不得盲重放。新增入口不能绕过原审批和预算。

### P1：当前 W05/F02/F03 尚缺的功能

- 系统默认助手：真正的 `VoiceInteractionService`、session service、元数据、识别服务适配、角色选择/引导、冷热启动与锁屏行为；目前没有这些三服务实现。
- 系统提供上下文的来源/同意/敏感内容/受保护页面边界；分享、通知、深链在四导航和隐藏/嵌套路由下的**全入口**复核，当前只完成部分深链与语音场景。
- 独立前台连续语音会话：思考、播报、插话、结束会话、取消、音频焦点、预算和状态闭环；不得反复调用短句 SpeechRecognizer 冒充持续识别。
- 可配置替代 ASR、数据去向说明与能力/语言诊断；不追加现有真实模型测试额度。
- 后台唤醒、悬浮入口及撤权按真实支持矩阵实现/验证，不能默认开启或承诺全机型。
- 普通话、数字/日期/应用名、噪声、权限拒绝/撤销、来电、耳机切换、后台/退出资源释放与实际 TTS/ASR 验证。
- 真机排除仍生效；现有模拟器有引擎，但没有录音授权，也没有声学测试。

## 6. 全范围未完成工作包台账

下表是**剩余工作清单，不是从零重做清单**。已有实现请先读对应契约和源码，不重复造轮子；未列入最近增量的能力也不能默认完成。

| 包/功能 | 尚需完成或验收 |
| --- | --- |
| W00 基线/总台账 | 冻结全部动态入口、页面/任务清单和 A/S 子用例；给每条要求建立源码、证据、剩余状态映射；不能以47页候选当47页验收。 |
| W01 架构/可行性 | 系统助手/真实ASR/多模态/动作支持矩阵；远程与同步真实架构验证；平台/成本边界与 ADR 完整化。 |
| W02 设计系统 | 全页面路由覆盖、复杂状态、离线/错误/空/加载/权限/大字/横屏/主题/TalkBack/键盘与性能；保留原高级页面。 |
| W03 运行与维护 | 全部任务/审批/事件/维护/迁移契约，跨 isolate/进程/restore 屏障，崩溃/压力与兼容 admin 入口审计。 |
| W04/F01/F05 导航/配置/搜索 | 引导与有效配置首任务全流程；完整诊断、全页面搜索导航和旧数据/失效来源/并发状态覆盖；真实模型场景不可再擅自调用。 |
| W05/F02–F04 | 见上一节；受控设备动作/参数重审/人工接管/锁屏等支持矩阵和真实接口验证仍缺。 |
| W06/F06/F07 | 完整分页、很早/损坏终结审计扫描、真实恢复与副作用核实、后台/断网/进程重启、成果状态和 UI 乱序；已有收件箱/成果增量不抵完整链。 |
| W07/F08 | 全项目开发页面/环境/终端/创建、修改、验证、成果链；实际 Linux 修复与 ARM64 APK 构建/制品验证，不用x64抵替。 |
| W08/F09 | 完整不保存模式、敏感提取控制、权限/项目/来源隔离、完整遗忘/删除传播、回答引用；已有范围合同不能替代真实回答行为。 |
| W09/F10 | 提醒独立模型、创建/修改/取消、通知插件实际投递、精确授权、时区/DST、重启/强停/重新打开、失败恢复与无重复。 |
| W10/F11 | Agent 对话创建、模板、多Agent预算/结果整合、技能/MCP、市场安装/更新/卸载/撤销及全链验收。 |
| W11/F12 | 能力探测/模型推荐/服务商切换、缺价格时不伪造费用、软硬预算/停止、用量与运营指标。 |
| W12/F13 | 当前Windows真实执行器已有回环握手增量；统一审批提交、配对/撤销、作业/租约、远端取消/未知结果、项目上传构建、双端同步、冲突/删除传播和跨设备连续性未完成。不得把回环当公网服务。 |
| W13/F14 | 全量升级/迁移/备份恢复故障注入、签名/更新校验/回退、隐私脱敏、Profile/性能/无障碍、支持矩阵、恢复与发布手册、七天使用。 |
| W14/F15 | 实时相机/屏幕/音视频会话、帧来源/有效期/过期、连续指代、插话取消、采集撤权、热/流量/延迟预算；尚非完整实现。 |
| W15/F16 | 五类连接器逐项真实能力矩阵、账号/授权/版本/恢复/未知提交；现有日历/联系人编辑器交接不等于保存，日历账号准备未解决；不替用户登录。 |
| W16/F17 | 关联个人上下文、实体/真实来源、指代消歧、更正/遗忘/来源删除传播及行为验证。 |
| W17/F18 | 移动工作流定义/编辑/步骤/输入输出/分支/检查点/不可变版本、试运行、重复执行和失败策略；编译到原执行层，不新增第二引擎。 |
| W18/F19 | 可核查研究的证据结构、引用支撑、矛盾/未知、持续更新和比较，不以有文字输出代替研究验收。 |
| W19/F20 | 六类结果卡的真实资源/版本、动作注册、修改/分享、权限重查、冲突、过期、重复点击与幂等全整合。 |
| W20/F21 | 已有较多运行/审批/版本/取消防护，但 A27 全链、真实副作用、人工接管、跨进程恢复/压力与未知结果仍未验收。 |
| W21/F22 | 已有无密钥JSON导入、地址确认和原编辑器接线；二维码、能力探测、用途引导、自主配置修复、托管适配/额度/限流仍未完成。是否实际运营付费托管是独立决策。 |

### 必须逐项对照的主验收

- A01–A06：首任务、语音问答、打断/取消、系统冷启动、文章分享/摘要导出、截图来源与识别。
- A07–A12：记忆增删改、提醒增删改、应用/分享、敏感动作、定时失败恢复、长任务后台/断网。
- A13–A20：静态网页、脚本差异、ARM64 APK、MCP/技能撤销、历史全量搜索、远程跨端、升级备份恢复、预算停止。
- A21–A28：实时多模态、五连接器、关联召回、重复工作流、研究更新、六类结果卡、纠正接管、配置模板首任务。
- 原方案 A15 的真机安装部分本次排除；**ARM64 构建与制品检查不因此自动通过或取消**。

### 必须逐项对照的专项

S01 语音/入口/撤权；S02 Agent/市场；S03 模型/费用；S04 全页面/性能/可访问性；S05 同步/撤配/远端未知；S06 更新/恢复/脱敏；S07 注入/深链/锁屏/权限快照；S08 精确提醒/时区/强停；S09 实时采集/延迟/预算；S10 连接器账号/版本/未知提交；S11 工作流/纠正竞态；S12 来源删除/证据失效/卡片冲突/配置导入/托管条件验收。

## 7. 建议的接手执行顺序

1. **恢复上下文而不是重跑脚本。** 读根 AGENTS、原方案、本文、最近契约；查看当前源码和任务卡，保护现有修改。不要重跑已 apply 的 `core_work/*.py`。
2. 复核第5节自动发送/pending候选缺口和恢复回调风险；若修改，先补模拟器合同，再重建、同APK复验，更新证据。
3. 完成 W05 原生默认助手与上下文/全入口；与原语音/审批/导航整合，禁止角色未持有时显示已接入。系统设置页打开不等于角色已选择。
4. 独立设计并实现连续语音/实时会话，不以单句识别循环替代；补采集撤销、音频焦点、过期画面、预算和当前轮隔离。
5. 按原依赖图补 W06–W19/W21 的完整功能，不因当前基础合同多而只继续堆合同、不补产品能力。
6. 最后逐条关闭 A01–A28/S01–S12 与文档/性能/发布门禁；真实模型额度/账号/费用和平台无法覆盖的项目明确未通过，不擅自补授权。

## 8. 操作与构建复现

### 8.1 构建环境务必显式设置

曾有一次新终端丢失环境，用默认 debug keystore 构建导致 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`。未卸载/清数据；随后验证原已装APK与项目本地key签名一致并恢复覆盖安装。不要再依赖前一个终端的 export，也不要删除/替换签名私钥。

```bash
cd D:/AIIIIII/ai-agent/mobile_agent
export GRADLE_USER_HOME="$(cygpath -w "$PWD/local/gradle-cache")"
export ANDROID_USER_HOME="$(cygpath -w "$PWD/local/android-user")"
flutter analyze --no-pub
flutter build apk --debug --no-pub --target-platform android-x64
ADB=local/android-sdk/platform-tools/adb.exe
test "$($ADB -s emulator-5554 emu avd name | head -1 | tr -d '\r')" = Nexus_Preview_API_36
$ADB -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
python tool/launch_emulator_debug.py
python tool/verify_plan_protocol_emulator.py
python tool/verify_approval_scope_ui_emulator.py
python tool/verify_speech_capture_ui_emulator.py
```

- 然后顺序执行第3节九个驱动，在同APK补143；不要并发争用Flutter/前台UI。
- 原生 Kotlin/manifest 修改必须重构建，不能热重载冒认原生已更新。
- 当前协议驱动要求133例。加/删合同需同步 driver 数量，但不能改数字掩盖失败。
- 命令返回 running 时用其 command_id/offset 继续读取，不重跑同命令；不要全局杀 Java/Dart/ADB。
- 不执行 `flutter test`、宿主 pytest 等套件。检查命令文档中的历史示例，不能直接照抄早期宿主测试段落。

### 8.2 MCP 与桥接

- 权威源码在 Windows 项目；Arena `/home/user` 是桥接/脚本工作区，不是另一份权威工程。
- Arena 有 `bridge_client.py`、`bridge_text.py`、`bridge_schemas.json`、`core_work/`。通过用户原 MCP 连接调用 `read_files`、`apply_patch`、`run_command`、`get_command_output`、`set_todos`。
- 连接地址/会话信息在现有桥接配置，不在本文复制，以免传播可调用端点或凭据。失效时应如实报告连接阻塞，不编造执行成功。
- 修改前 fresh read，使用 expected_versions；format 后 hash 会变，不能用旧 snapshot 覆盖新源码。
- `exec(open('core_work/refine_artifact.py').read().split("p='lib/presentation/artifacts")[0])` 只用于加载 call/get/versions/changes 等助手；**不要直接执行整个 refine_artifact.py**，其后部有旧业务补丁。
- 已 apply 脚本不可重复执行；`*.snapshot`、早期草稿不是远端权威源码。

## 9. 文档与接手文件索引

优先读取：

- `docs/mobile-next-major-implementation-2026-10-18.md`：原总方案及验收原文。
- `docs/mobile-next-major-progress-2026-10-18.md`：全部历史进度、当前追加证据。
- `docs/mobile-speech-capture-contract-2026-10-19.md`：单句语音、入口、TTS、SDK边界与未完成项。
- `docs/mobile-artifact-runtime-contract-2026-10-19.md`：成果/运行/审批/验证契约。
- `docs/mobile-original-loop-verification-adr-2026-10-19.md`：回到原循环的验证/修复决策；其局部证据数字可能早于最新进度，读追加记录。
- `docs/mobile-next-major-page-coverage-2026-10-18.md`：页面候选台账，不是验收表。
- `docs/mobile-private-apk-decision-2026-10-18.md`。
- `docs/mobile-windows-remote-executor-2026-10-18.md`。
- `docs/mobile-system-connectors-contract-2026-10-19.md`。
- `docs/mobile-jobs-contract-2026-10-19.md`。
- `docs/mobile-memory-knowledge-contract-2026-10-19.md`。
- `docs/mobile-search-contract-2026-10-19.md`。

最近新增调试模块：
`lib/debug/plan_protocol_checks.dart`、`speech_capture_checks.dart`、`speech_capture_ui_checks.dart`、`entry_intent_checks.dart`、`tts_lifecycle_checks.dart`。这些是debug隔离夹具，不是产品功能完成的替代品。

### 默认助手后续研究参考（尚未实施）

已查 AOSP `VoiceInteractionServiceInfo.java`：元数据解析要求 sessionService 和 recognitionService，且服务要求 BIND_VOICE_INTERACTION。不要只加一个设置跳转或遗漏元数据就宣称支持默认助手。

- https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/service/voice/VoiceInteractionServiceInfo.java
- https://source.android.com/docs/automotive/voice/voice_interaction_guide/app_development （生命周期/清单参考，**不能直接把汽车平台能力当手机验收**）
- 添加自有 RecognitionService 后要防系统 ASR 可用性探测把自己算作可用外部引擎、默认识别器委托自循环、静默更换音频接收方。系统选择/实际持有角色/服务激活要分别记录；不得自动录音、读取受保护页面或执行锁屏高风险动作。

## 10. 交接结论

**当前可移交的是已修改源码、最新276项同版合同与两条UI隔离链证据，以及明确的剩余清单；不是可发布的整版。**

目前没有待轮询的命令，没有新增真实模型授权，没有进行真机操作、登录、外部发送/删除或 Git 提交/推送。交接后应先恢复范围与约束，再按依赖图实施，持续维护真实证据，不得把历史局部成功升级为整版完成。
