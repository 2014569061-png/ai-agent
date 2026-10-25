# 移动端下一大版本：交给 DeepSeek 的最新交接

**时间：2026-10-19，用户明确要求先暂停，由 DeepSeek 完成后续。**

工作区：`D:/AIIIIII/ai-agent/mobile_agent`。本文是最新接手入口，覆盖同日旧交接的状态描述；旧交接及进度日志保留作历史，不要把其中“尚未实现”直接当当前源码状态。

> **最新晚间交接（F17 关联上下文 / F20 结果卡 + 合同 371/371）：** 见 [剩余未完成任务交接（晚间）](mobile-next-major-handoff-2026-10-19-evening.md)。F17/F20 已实现、接线（schema 32）并在模拟器实看；合同 332 → **371/371**（计划协议 **228/228**）；最终 APK `8ebe5948…` 上合同复验通过、**五条最终 UI 驱动 5/5 通过**（设备状态已复原）。下文第 9 节描述的是 `d2dab18f…`／`ce8ac684…` 那两轮的旧证据，不能与最新 APK 相加。

**整版未完成，不具备发布资格。** 已安装 APK 现为 `8ebe5948…`（含 F17/F20、1px 溢出修复与驱动掉线自愈），合同 **371/371** 通过、五条最终 UI 驱动 5/5 通过；连续语音会话、TaskService、F20 真实执行器、W/F 台账仍缺，`releaseReady:false`。不能写成整版完成。

## 1. 接手先做什么

1. 读本文、根 `AGENTS.md`、原方案 `docs/mobile-next-major-implementation-2026-10-18.md`。
2. 再读 `docs/mobile-next-major-resume-2026-10-19.md`、`docs/mobile-assistant-input-contract-2026-10-19.md`、`docs/mobile-default-assistant-contract-2026-10-19.md`。
3. 完整剩余台账在同日旧交接第5、6节；详细历史在 `docs/mobile-next-major-progress-2026-10-18.md`，页面台账在 `docs/mobile-next-major-page-coverage-2026-10-18.md`。旧文档前部是早期快照，以本文与后续追加为准。
4. 先查看当前文件和差异，保护工作区里其他 agent 的大量未提交改动。不要 reset、clean、提交、推送，不要重放旧 `core_work/*.py` 补丁。
5. 先修下文两个**验收驱动问题**，再补最终APK中断/未跑的UI；已有332项合同不必为了凑数反复重跑。发生业务源码变更或重构建后，需要重新建立同版证据（TTS 修复后已重建并重跑，见第 9.1 节）。

原总范围必须保留 **W00–W21、F01–F22、A01–A28、S01–S12**。不能把任务缩成语音、助手入口或本次新增检查；检查数量不是完成率。

## 2. 不可越过的既有约束

| 项目 | 约束 |
| --- | --- |
| 模拟器 | 只操作 `emulator-5554`，必须先确认 AVD=`Nexus_Preview_API_36`，Android16/x86_64；每个ADB命令显式 `-s emulator-5554` |
| 真机 | 不操作、查询、安装或转发真机；不全局重启/断连ADB。电脑上还有真机，不得因发现它就操作 |
| 模型 | 真实模型额度上限3次，**3/3已耗尽**；不得追加或用真实模型替代离线fixture，不替用户登录/开通托管 |
| 测试 | 不跑宿主 `flutter test`、pytest等测试套件。静态分析和构建允许；Python只作RPC/UI传输，业务检查在模拟器Dart isolate执行 |
| 数据 | 不清应用数据、不卸载；覆盖安装 `install -r`。不在真实用户库做破坏性恢复/删除，不执行真实外部发送 |
| 音频 | 不启用宿主麦克风，不启动真实录音/发声；当前声学测试未获追加授权。引擎存在不等于声学验收通过 |
| 下载/缓存 | 全部新增下载、缓存、临时文件在项目 `local/`；不要写默认用户缓存，不提交local目录 |
| 真实性 | x64不能替代ARM64/真实Linux/安全锁屏/多厂商/功耗/七天使用；不同APK结果不得相加 |
| 原任务卡 | `9b084138-d144-4aad-95b9-eceee93be3bf` 的rev24/blocked是旧交接历史。本会话无Arena/任务卡MCP，未更新远端卡，不可冒认已同步 |

## 3. 当前停在哪里

- 用户暂停后已定点结束本轮测试编排和系统取文UI驱动，未全局杀ADB/Java/Dart。
- 本轮隔离入口/核对路由已关闭；Google原默认助手、原识别器及secure settings已恢复并比较一致。
- 恢复角色后发现调试应用麦克风授权仍为true，已仅对本模拟器的 `com.nexusagent.app.debug` 撤回 `RECORD_AUDIO`，恢复到此前已知的false，并只读确认。**本轮没有实际录音**。
- 应用和模拟器保持运行。已重新attach现有应用，预览显示 **`[preview] Ready`**；暂停后没有再做功能验收或手动热重载。不要以此冒认最终UI补测完成。
- 当前预览监听的就是本工作区。先查现有预览进程，避免再开Flutter调试会话。另一个工具/IDE编辑 `lib/` 也会触发已有自动热重载。
- 暂停与恢复记录：`local/temp/major-deepseek-pause-20261019.json`。
- 最新冻结证据索引：`local/temp/major-deepseek-handoff-evidence-20261019.json`；原始JSON副本放在 `local/temp/deepseek-handoff-20261019/`，后续重跑不要覆盖这份归档。

### 当前APK与最终证据

APK：`build/app/outputs/flutter-apk/app-debug.apk`（TTS 归属隔离修复后重建，见第 9.1 节）。

SHA256：

```text
d2dab18f486ae12763db7a68610c4b5076bf22e9e917cd314310e90b39564f64
```

上一版 APK `d5d597973177e374f5de1450e4e9e1d245902442c70ca431c09f7c4b33cceb4f` 的 328 项合约与五条 UI 证据保留在历史索引中，不能与本版相加。

已只读校验**模拟器实际安装的base.apk**哈希与该文件一致；不是仅用磁盘构建文件冒认安装版本。

| 最终APK检查 | 结果 |
| --- | --- |
| 完整 `flutter analyze --no-pub` | 零问题，21.6秒 |
| Android x64 debug构建 | 成功，Gradle24.0秒；日志 `major-context-entry-build-20261019.log` |
| 协议/运行/语音/入口等 | **189/189**，其中外部输入/页面上下文31项、TTS归属隔离4项 |
| 知识范围 | 21/21 |
| 记忆工具范围 | 28/28 |
| 记忆/知识基础 | 12/12 |
| 任务运行 | 20/20 |
| 执行中纠正 | 12/12 |
| 成果 | 12/12 |
| 全量搜索 | 12/12 |
| 任务收件箱 | 14/14 |
| 连接器输入合同 | 12/12 |
| 合同合计 | **332/332，同一已安装APK**，没有模型调用 |
| `verify_assistant_entry_ui_emulator.py` | **通过**，含运行中审批导航、编辑确认、草稿保护、取消/重试/丢弃、过期及嵌套路由 |
| `verify_assistant_context_ui_emulator.py` | **通过**（含被暂停中断后的复跑，报告 `phase:"cancel"`） |
| `verify_approval_scope_ui_emulator.py` | **通过**，范围失效、覆盖路由、仅计划授权、无全局权限写入 |
| `verify_speech_capture_ui_emulator.py` | **通过**，可编辑确认、取消、覆盖路由、打字兜底，无真实麦克风/模型 |
| `verify_assistant_role_ui_emulator.py` | **通过**，role/session/assist key/撤销，设备设置与 runtime 权限复原 |

各合同报告为 `local/temp/major-*-emulator-contract-20261019.json`；冻结清单记录每份摘要哈希。最终完整复验开始时间在 `local/temp/major-context-entry-verify-start.txt`。

**历史边界：** 中间APK `562a935cbb8c22b56995de86ea2719951587dc2781c7949f49e99a3d194da140` 实际曾通过327项及五条UI链；其系统取文UI已经验证真实来源、密码过滤、FLAG_SECURE拒绝、8000字截断和编辑/丢弃。该中间构建不能与任何最终构建相加。

`d5d59797…`（328项）与当前 `d2dab18f…`（332项，+4 项 TTS 归属检查）也不能相加：前者不含 TTS 修复，后者是当前唯一同版证据。

`local/temp/record-context-entry-evidence.py` 是未完成的中途汇总草稿；实际签收用 `local/temp/finalize_acceptance_20261019.py`（校验五份UI报告、已安装base.apk与磁盘APK一致、设备复原），不要改断言让它假通过。

## 4. 本次已经改了哪些生产能力

### 第一批已完成的增量

- `SpeechSubmissionGuard` 检查语音打开前及提交时无pending入口；即使后续被消费，旧语音也不会重新获得自动发送资格。草稿/附件/上下文/可见性变化仍限制提交。
- `TaskService.reconcileAppliedCheckpoint` 用新鲜任务revision、同runId、planVersion、当前终态head及真实回执进行单事务核对；不再把已应用旧断点无条件改成completed。failed/cancelled保持真实终态，缺证明只提示核实。
- 真实系统助手三服务、元数据、系统选择页、真实激活状态和“我的→默认系统助手”已落地。ASSISTANT角色不接受通用角色申请，生产走系统语音输入/助手设置页。
- `NexusRecognitionService` 是注册兼容端点，外部识别返回ERROR_CLIENT，不提供独立ASR、不录音、不委托自循环。前台识别显式排除自身服务。

### 第二批：统一外部输入与单次系统页面文字

| 源码 | 已实现内容 |
| --- | --- |
| `lib/infrastructure/share/deep_link_service.dart` | 分享批次/通知/页面文字有界队列；独占租约、精确ACK、失败暂停/明确重试、TTL、旧回调防护；legacyRevision与外部revision分开，不误重试失败深链 |
| `assistant_entry.dart`、`share_batch_intake.dart`、`sharing_service.dart` | 冷/暖分享按批次串行转换、容量限制、错误后继续；最多8批待转、每批最多12项，转换前也检查数量；绑定入口sink后不依赖ChatPage临时流订阅 |
| `lib/infrastructure/notifications/notification_intent.dart` | 通知统一入队，类型/ID校验及去重；只导航，不批准或执行动作 |
| `lib/application/assistant_entry_delivery.dart` | 交付协调器没有模型/工具/发送能力；核对后再检查可见/解锁/草稿/附件/会话身份/租约/角色/过期；追加当前草稿；纯助手导航与审批导航允许在运行中进入，分享仍须空闲 |
| `lib/presentation/chat/chat_page*.dart` | 去掉直接分享/通知消费；统一门禁，失败保留；数据库等待之后重查可见性；新会话/切会话/草稿恢复增加提交守卫 |
| `lib/application/chat_controller.dart` | newConversation/switchConversation接收可选canCommit，避免异步返回后覆盖已变化的上下文；并不等于所有restore/维护竞态已解决 |
| `lib/presentation/navigation/assistant_input_review_sheet.dart` | 可编辑核对、来源、附件数量、稍后/丢弃/加入草稿；过期清空并禁用；页面文字离开前台失效，不自动发送 |
| `lib/domain/assistant_page_context.dart` | 严格原生schema、来源/采集时间、两分钟上限与单调计时；确认后附来源说明并明确内容不授予操作权限 |
| `lib/application/assistant_context_intake.dart` | 前台读取进程内原生交接、入队后按IDACK；队列满时不丢原生所有权；接收查询期间的新native/lifecycle信号用revision保留并重查，不逐帧轮询 |
| `android/.../AssistantContextHandoff.kt` | 仅内存单槽，elapsedRealtime到期清理、精确ACK、不覆盖未处理内容、不把文字写URL/日志/偏好/文件 |
| `android/.../AssistTextExtractor.kt` | 仅主活动AssistStructure；真实组件来源；跳过blocked/隐藏/可识别输入控件；4窗口/256节点/16层/8000字上限，标明截断，不读截图或AssistContent extras |
| `NexusVoiceInteractionSessionService.kt` | 用户点“读取本页文字（仅本次）”才请求；仅该session一次、等8秒、请求后立即恢复采集禁用；重新核对角色/系统锁；关闭finish旧session，旧回调不能成为新请求 |
| `NexusVoiceInteractionService.kt`、`AssistantRoleBridge.kt` | 默认禁用structure+截图；停服清交接；原生交接桥及只读调试过滤检查；MainActivity新intent通知接收 |
| `lib/main.dart` | 插件初始化之前绑定分享/通知入口，初始化原生交接接收 |

原生路径前缀为 `android/app/src/main/kotlin/com/nexusagent/app/`。Android生产页面已接线，没有把Android强制转入桌面布局。

新增debug活动 `android/app/src/debug/kotlin/com/nexusagent/app/AssistantContextFixtureActivity.kt` 仅含固定公开文字、密码测试框和可选长文/FLAG_SECURE，独立 `.contextfixture` taskAffinity；release manifest不包含它。新增Dart检查在 `lib/debug/assistant_entry_checks.dart`、`assistant_entry_ui_checks.dart`，不写用户库。

### 不要夸大的边界

- 页面核对默认警告敏感正文；只跳过可识别输入控件，不能保证识别所有第三方自绘敏感内容。
- 原始快照失效不撤回用户明确加入的普通草稿，普通草稿继续按原机制保存。
- 应用锁在入口UI夹具中是模拟状态，不是实际生物识别证明。
- 页面实际证据来自专用原生测试页，不代表任意Flutter/WebView/第三方应用都能被系统提供结构。
- 尚未证明完整系统分享插件冷热启动、通知实际投递、安全锁屏、多API/厂商、连续语音、真实ASR/TTS、实时相机/屏幕会话。
- 新入口不绕过原运行、预算、审批、取消和未知结果核实；不新建第二执行器。

## 5. 接手优先级与已发现的问题

### 先修验收驱动，再补最终UI

1. **角色恢复不保证权限恢复。** `snapshot()/restore()`目前只保存role holders和三个secure settings，不保存角色授予的runtime权限。暂停时角色已回Google，RECORD_AUDIO仍USER_SET/granted=true。已手动恢复已知false。下一轮先保存目标调试应用测试前权限基线，并在finally只恢复本轮改变、且有基线证明的权限；不要盲目撤销用户原先已有授权。不能只凭“原角色已恢复”声称权限全恢复。
2. **UI报告编码。** 两个新增Python UI驱动沿用旧模式 `Path.write_text(...ensure_ascii=False)`，未指定encoding，Windows当前默认GBK。含中文草稿的JSON用UTF-8读取会失败；应统一后续报告写UTF-8，历史文件用GB18030读取或保留原始字节/哈希，不要把解码失败冒认为业务失败。宿主不执行测试业务，修驱动不意味着跑宿主测试。
3. 补 `verify_assistant_context_ui_emulator.py` 最终同版整链，再跑 `verify_approval_scope_ui_emulator.py`、`verify_speech_capture_ui_emulator.py`、`verify_assistant_role_ui_emulator.py`。串行，不得并发争用前台UI/uiautomator。
4. 每份UI驱动通常只对磁盘APK求hash，未来构建与UI重叠可能造成标签不代表安装版本。最终签收应再次比较已安装base.apk哈希；不要在同版验收期间覆盖构建产物。
5. `launch_emulator_debug.py` 已增加启动日志等待、role撤权后PID变化重接及短暂稳定性检查；不输出调试端点。不要因为旧VM地址失效就清数据或重启ADB。

### 本轮取文驱动曾遇到的假失败，不要重踩

- 直接 `am start` 可能复用旧测试task根活动，新的secure/large extras不生效。驱动现用 `-f 0x10008000`（NEW_TASK|CLEAR_TASK），**只针对专用literal debug活动的独立task**；禁止套用到用户主任务。
- Android `am` 不支持 `--activity-new-task` 这个参数，已改正确flags。
- 单个超长TextView会先被Android裁剪，最初只拿到1871字，没有触发应用上限。debug长页现用75个小字静态节点，真实返回达到8000并truncated=true。
- 失败清理必须先关闭自己的原生面板并让MainActivity回前台，再关闭Dart fixture。后台等待endOfFrame可能超时并掩盖主失败。
- 不要让两个UI驱动同时执行；曾触发uiautomator注册冲突，失败回合未计入通过。

### 后续生产工作仍须推进

1. 原TTS无utteranceId的全局完成/错误回调隔离；当前只修初始化/stop/replacement竞争，**不能把该监听器用于自动开麦连续会话**。
2. 独立前台连续语音/实时多模态，必须独立设计采集生命周期、当前轮、音频焦点/插话/停止/预算；不能循环短句SpeechRecognizer冒充连续识别。真实模型额度不足的部分保留未验证，不擅自新增调用。
3. TaskService无runId兼容入口、跨restore/维护切换/独立进程的旧回调全仓审计，真实Linux验证修复/取消/未知结果/租约链；现有内存检查不是实际Linux或跨进程任务恢复证明。
4. 按原依赖图完成其余产品能力和全页验收，不能只继续堆合同而不补功能。

## 6. 全范围剩余台账摘要

| 工作包 | 尚未关闭 |
| --- | --- |
| W00 | 动态入口与A/S子用例逐条源码/证据/剩余映射 |
| W01 | 多平台助手/语音/实时/动作/远程/同步能力与成本ADR |
| W02 | 全页面复杂状态、主题、大字、横屏、键盘、TalkBack及性能；当前页面候选表不是完成表 |
| W03 | 运行/维护/迁移/审批全契约、兼容入口、跨isolate/进程/restore、压力与崩溃 |
| W04 / F01/F05 | 引导到有效配置首任务、诊断、全页面搜索导航、旧来源/失效/并发 |
| W05 / F02–F04 | 当前只关闭默认助手/单次文字/外部输入的具体增量；连续语音、ASR替代配置、悬浮入口、锁屏/撤权/设备动作矩阵及声学仍缺 |
| W06 / F06/F07 | 全分页/损坏终结审计、真实恢复/副作用核实、后台断网/进程重启、成果乱序 |
| W07 / F08 | 全项目开发链、终端/环境/实际Linux修复、ARM64 APK构建和制品验证 |
| W08 / F09 | 不保存模式、敏感提取、来源/项目隔离、遗忘/删除传播、真实回答引用 |
| W09 / F10 | 提醒独立模型、创建修改取消、通知插件投递、精确授权、时区/DST、重启强停和去重 |
| W10 / F11 | Agent创建模板、多Agent预算/整合、技能/MCP/市场生命周期及撤销 |
| W11 / F12 | 能力探测/模型推荐/切换、价格缺失、软硬预算与实际运营指标 |
| W12 / F13 | Windows原回环握手之外的配对/撤销、统一审批、作业租约、远端取消/未知、上传构建、同步冲突/删除传播 |
| W13 / F14 | 升级/迁移/恢复故障、签名/回退、隐私脱敏、Profile/性能/无障碍、发布手册及七天使用 |
| W14 / F15 | 真实相机/屏幕/音视频会话、frame/轮次/TTL、连续指代、撤权/插话、热流量延迟预算 |
| W15 / F16 | 五类具体连接器的账号/授权/版本/真实读写/未知提交；日历联系人编辑器交接不等于已保存 |
| W16 / F17 | 关联个人上下文、实体/指代、真实来源、更正/遗忘/来源删除传播 |
| W17 / F18 | 工作流编辑/输入输出/分支/检查点/不可变版本/试运行/重复执行/失败策略，编译到原执行层 |
| W18 / F19 | 研究证据、引用支持、矛盾/未知、更新和比较 |
| W19 / F20 | 六类真实资源结果卡、动作注册、权限复查/过期/冲突/重复点击幂等 |
| W20 / F21 | A27全链、真实副作用/人工接管/跨进程/压力/未知结果；原纠正守卫不代表整包完成 |
| W21 / F22 | 二维码配置、能力探测、用途引导、自主配置修复、托管额度/限流；运营付费托管需要独立决策 |

主验收A01–A28与专项S01–S12原文在原方案与旧交接第6节，全部保留。A15本次排除真机安装，不意味着ARM64构建自动通过或取消。账号、模型额度、真实音频和平台无法覆盖的部分必须写未验证，不能用别的场景成功抵消。

## 7. 构建与接回预览

PowerShell在项目根目录设置本地路径；每次新终端都显式设置，避免错用用户目录的debug签名：

```powershell
$env:ANDROID_HOME="$pwd/local/android-sdk"
$env:ANDROID_SDK_ROOT=$env:ANDROID_HOME
$env:ANDROID_USER_HOME="$pwd/local/android-user"
$env:ANDROID_AVD_HOME="$pwd/local/android-avd"
$env:GRADLE_USER_HOME="$pwd/local/gradle-cache"
$env:PUB_CACHE="$pwd/local/pub-cache"
$env:TEMP="$pwd/local/temp"
$env:TMP=$env:TEMP
& C:/src/flutter/bin/flutter.bat analyze --no-pub
& C:/src/flutter/bin/flutter.bat build apk --debug --no-pub --target-platform android-x64
./local/android-sdk/platform-tools/adb.exe -s emulator-5554 emu avd name
./local/android-sdk/platform-tools/adb.exe -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
python tool/launch_emulator_debug.py
```

失败则停下处理，不要在失败构建后继续安装旧包。原生Kotlin/manifest/依赖改变需要重构建；仅热重载不能验证原生修改。保持原签名，不删keystore，不用卸载解决签名冲突。

协议驱动现要求**189项**（原九套合计143项；页面上下文31项；TTS 归属隔离4项）。新增/修改合同必须同步数量并说明增量，不能改数字掩盖失败。驱动名称沿用旧交接第3节；本次新增 UI 驱动为：

```powershell
python tool/verify_assistant_entry_ui_emulator.py
python tool/verify_assistant_context_ui_emulator.py
python tool/verify_approval_scope_ui_emulator.py
python tool/verify_speech_capture_ui_emulator.py
python tool/verify_assistant_role_ui_emulator.py
python tool/verify_plan_protocol_emulator.py
```

上述是DeepSeek后续恢复时的操作说明；2026-10-19 已由接手的 DeepSeek 执行并存证，见第 9 节。

当前自动预览已attach且Ready。若进程失效，先确认app PID和设备，再从该PID的flutter日志解析**设备内**VM HTTP地址给 `tool/android_preview.dart ... --attach`，不要打印鉴权URL，也不要把已有宿主forward端口再当设备端口转发。未确认现有进程退出前不得开第二个预览。只看到模拟器窗口不代表热重载正常。

## 8. 可直接给 DeepSeek 的接手指令

> 阅读本最新交接与原总方案后继续未完成任务。保护已有未提交改动，保持完整W/F/A/S范围，不重复造执行器。先修UI驱动的权限基线恢复和UTF-8报告问题，再补最终APK中断/未跑UI，校验实际安装APK并更新本地台账。随后按依赖图推进剩余产品功能，明确区分源码已实现、离线合同、真实系统证据、环境缺口。不得追加已耗尽的模型调用，不操作真机、不跑宿主测试、不采集宿主麦克风、不清数据、不提交推送。当前版本未完成，不能把检查数当完成率或发布许可。

## 9. 接手进展：验收驱动修复、同版UI签收与TTS归属隔离（2026-10-19 16:2x–16:5x）

本节记录接手的 DeepSeek 在恢复会话后完成的部分。9.1 节修了一个生产缺陷并因此重建了 APK；**只关闭第3节的验收驱动/最终UI事项和这一处 TTS 缺陷；生产缺口（第5节“后续生产工作仍须推进”与第6节台账）不变，`releaseReady` 仍为 false。**

### 根因：权限恢复杀掉调试进程，下一驱动拿到死VM端口

15:58 的 `assistant-context` 中断不是业务失败：上一轮 `restore()` 的 `pm revoke` 会结束调试应用进程，`local/android-preview/vm-service.json` 记录的端口随之失效，驱动在写任何报告前就抛裸 `URLError`。

- `tool/emulator_driver_support.py` 新增 `apk_sha256()`、`app_pid()`、`ensure_debug_app(probe, attempts=3)`：PID 缺失或与VM元数据不一致即重新执行已批准的 `launch_emulator_debug.main()`，探针再失败重试，3次后抛 `RuntimeError('Debug app RPC unavailable: <type>')`。
- 五份UI驱动（entry/context/approval-scope/speech-capture/assistant-role）在触碰 RPC 前调用 `ensure_debug_app`，并在 `restore()` 之后再次调用以确认进程存活（报告记 `appAliveAfterRestore`）。
- approval-scope/role 驱动的报告改为**先构造后写入**：失败也在 `finally` 落盘并记 `failure`，不再出现“中断后无报告”。
- 报告统一走 `emulator_driver_support.write_json` 的 UTF-8 写入；历史 GBK 文件用容错 `read_json` 读取。

### 权限基线恢复在 API 36 上的实测

scratch 探针 `local/temp/probe_permission_restore.py`：基线 RECORD_AUDIO `{granted:false,userSet:false}` → `pm grant` 后 `{true,false}` → `restore()` 返回 `permissionsRestoredCount:1`、`appProcessRestarted:true`，holders/settings/permissions 三项比对均相等，权限回到 `{false,false}`。结论：API 36 的 `pm revoke` 不留下 USER_SET；对“全 denied 且无 USER_SET”的原始基线，现有 restore 可忠实自证，代价是撤权会重启调试进程（已由 `ensure_debug_app` 覆盖）。

### 最终同版UI结果（APK `d5d597973177e374f5de1450e4e9e1d245902442c70ca431c09f7c4b33cceb4f`）

串行执行，全部 exit=0，无并发争用：

| 报告 | sha256 | 结果 |
| --- | --- | --- |
| `local/temp/major-assistant-entry-ui-20261019.json` | `7bb496c2eb59c3263c70eb08627bd518c0b69bad5c518191a84a0a25897f2ff7` | PASS（已有） |
| `local/temp/major-assistant-context-ui-20261019.json` | `19a5d39a7a5244842894ae132f88737abf45961ba8c82cb84cae9a5e63794fec` | PASS（补跑；secure页拒绝、取消不读取、正常页未裁剪、长页8000字truncated、草稿保留含 `_reviewed`） |
| `local/temp/major-approval-scope-ui-20261019.json` | `64d5446daab73bb713b0d6fcffa9325de862e497d3e5b51d702485bef25c4476` | PASS（范围失效、覆盖路由、计划级授权、无全局权限写） |
| `local/temp/major-speech-capture-ui-20261019.json` | `251c484e7f82915cf4b6209716196d7473975cc8c45e05705786456b1a57111c` | PASS（可编辑确认、取消、覆盖路由、键入回退；无真实麦克风/模型） |
| `local/temp/major-assistant-role-ui-20261019.json` | `b2e36261166dabf26dad88df53ec493df6c7f1cd030479fd6077d96895e84b36` | PASS（角色UI/会话/辅助键/撤权；设置与runtime权限按基线复原） |

签收输入 `local/temp/major-final-ui-rerun-summary-20261019.json`：已安装 `base.apk` 的 `sha256sum` 与磁盘APK一致（`installedMatchesDisk:true`）；设备复原为 role holders `[com.google.android.googlequicksearchbox]`、三条 secure settings 含 google、runtime 权限全 denied 且无 USER_SET、调试应用存活。证据总索引 `local/temp/major-deepseek-handoff-evidence-20261019.json` 已同步（`pausedAtUserRequest:false`，新增 `driverFix` 与 `finalApkUiSignOff`）。此段证据对应 APK `d5d59797…`，已被 9.1 节的新构建取代。

### 9.1 TTS 归属隔离修复与再次同版签收（APK `d2dab18f…`）

**缺陷：** `FlutterTts` 的 start/completion/cancel/error 回调是全局的，不带 utterance id。旧实现里 `setCompletionHandler/setCancelHandler/setErrorHandler` 都直接 `_nativeFinished()` → `_finish(_activeSpeak)`，于是被替换的旧 utterance 的迟到完成会结束新 utterance，把聊天页的朗读开关提前清掉。

**修复（`lib/infrastructure/tts/tts_service.dart`）：** 新增 `_startedSpeak` 与 `_awaitingStart`。`speak()` 置 `_startedSpeak=null; _awaitingStart=true`；`_nativeStarted()` 只在“当前 revision 正在等待 start”时接受并记下归属；`_nativeTerminated()` 只在 `active != null && _startedSpeak == active` 时结束，否则忽略；`_finish`/`stopBeforeRecording` 清空归属；逐句 `speak()` 返回的 future 仍是权威完成路径。类注释明确写出全局回调不足以驱动“自动开麦的连续会话”。

**新增合同（`lib/debug/tts_lifecycle_checks.dart`，`_FixtureTts` 加 `emitStart`）：**

- `tts_global_completion_without_matching_start_is_not_trusted`
- `tts_foreign_completion_while_replacement_awaits_start_is_ignored`
- `tts_error_callback_before_start_keeps_correlated_owner`
- `tts_stop_drops_start_ownership_so_late_callbacks_are_ignored`

**重建与复验：** `flutter analyze --no-pub` 零问题；`flutter build apk --debug --no-pub --target-platform android-x64` 成功（日志 `local/temp/build-apk-tts-isolation-20261019.log`）；`adb -s emulator-5554 install -r` 成功；新 SHA256 `d2dab18f486ae12763db7a68610c4b5076bf22e9e917cd314310e90b39564f64`。协议驱动计数从 185 改为 189，模拟器实跑 **189/189**，十套合计 **332/332**（`local/temp/major-plan-protocol-emulator-contract-20261019.json`，sha256 `ca93fd39…`）。

五条 UI 驱动在新 APK 上串行复跑，全部 exit=0（日志 `local/temp/major-final-ui-rerun-after-tts-20261019.log`）：

| 报告 | sha256 |
| --- | --- |
| `local/temp/major-assistant-entry-ui-20261019.json` | `873f146463f3a40fd493de4b03f61f21ec98cc7fc544b45cadaeb1c54739fb59` |
| `local/temp/major-assistant-context-ui-20261019.json` | `4c9d4826f76604444877322dc93abb5891d5720d3da9a549c646d8e4de24bb73` |
| `local/temp/major-approval-scope-ui-20261019.json` | `798dcd80b44429751ebd771036751187f7a8813dc3874ed2825897f99eab832c` |
| `local/temp/major-speech-capture-ui-20261019.json` | `fa40850295e1bc483ca07d1d904f8bd5cf60e5237e1193556ed6ee5831f5308f` |
| `local/temp/major-assistant-role-ui-20261019.json` | `a37b0fdc4f47f926db06ada9ec19ed281d88952cfaa5b3c1f9385f5deae7b4fa` |

`local/temp/finalize_acceptance_20261019.py` 复跑后仍为 `installedMatchesDisk:true`、role/settings/runtime 权限/app 存活全部复原；索引已更新为 332/332、新 APK 哈希、`ttsUtteranceIsolation` 块。**未证明：** 模拟器无 TTS 引擎，真实设备连续语音/自动开麦仍未验证（见第5节缺口）。

**预览会话与哈希口径：** 收尾时按 `AGENTS.md` 恢复了预览会话（`tool/run-android-preview.ps1`），`flutter run` 用同一工作区源码重建并覆盖安装了调试APK，当前设备运行的是 `babb05de…`（`livePreviewArtifact` 已记入索引，含两个改动文件的源码哈希）。`flutter run` 与 `flutter build` 产出的 APK 字节不同，所以本轮所有 APK 哈希只标识“哪一个制品”，不代表源码版本；判源码版本请用索引里的 `sourceIdentity` 文件哈希或 `git diff`。预览终端已到 `[preview] Ready`，改 `lib/` 会自动热重载。

### 复跑方式

按第7节设置本地路径后，串行执行，勿并发：

```powershell
python tool/verify_assistant_entry_ui_emulator.py
python tool/verify_assistant_context_ui_emulator.py
python tool/verify_approval_scope_ui_emulator.py
python tool/verify_speech_capture_ui_emulator.py
python tool/verify_assistant_role_ui_emulator.py
```

驱动现在会自行重连死端点；若仍报 `Debug app RPC unavailable`，先 `adb -s emulator-5554 shell pidof com.nexusagent.app.debug` 再 `python tool/launch_emulator_debug.py`，不要清数据或重启ADB。

### 仍未完成（保持原判断）

- 生产缺口不变：连续语音/实时多模态生命周期（第5节1–2）、TaskService旧回调与真实Linux跨进程恢复（第5节3）、其余W/F/A/S条目与全页验收（第6节）。
- `releaseReady:false`；ARM64构建、真机、真实模型与真实音频仍未验证。
- 本轮改了业务代码一处：`lib/infrastructure/tts/tts_service.dart` 的TTS归属隔离（见9.1），并因此重建/重装调试APK，合同计数由328变为332；没有新增模型调用、没有提交或推送。若后续要求，可单独回滚这一处而不影响验收驱动的修复。
