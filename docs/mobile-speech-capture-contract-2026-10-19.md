# 前台单句语音输入契约（W05/F02 增量）

> 2026-10-19 恢复实施新增提交屏障和真实默认助手入口。本文后面的255/266/275/276数字均为历史同版结果，最新同版证据单独记录在 `mobile-next-major-resume-2026-10-19.md`，不能跨APK累加。

**范围与状态：部分实现，F02/F03/F15、A02/A03/A21、S01未完成。** 单句 SpeechRecognizer 不能靠重复启动冒充连续识别或后台唤醒；本入口明确显示“前台单句”，连续会话仍按原方案独立实现。

## 实际接线
- Android ForegroundSpeechBridge 通过 nexus/speech 与带owner的事件通道接入 MainActivity，增加仅在用户发起时请求的 RECORD_AUDIO 与识别服务 package query；不增加后台麦克风服务、不申请Root/Shizuku/无障碍。
- 默认选择Android12+设备端识别；用户主动切换“系统服务（可能联网）”后才走系统配置识别服务，并明确音频可能交给该提供方服务器，不是聊天模型。不可用时可编辑文字；没有静默联网回退。
- 只在前台、有效事件owner、当前session及已授权麦克风时启动；先停止原TtsService，获取瞬时音频焦点。最多60秒单句，stop等待最终结果最多2.5秒；后台/销毁/焦点丢失/耳机拔出取消并destroy。音频不传给Dart、不在应用保存原始音频。
- owner/session代际隔离 Native监听、权限、音频焦点与结果；权限完成不自行开录音。Flutter等待事件通道connected后才请求/启动，取消先失效本地session，防止事件通道/权限/TTS等待结束后旧操作才开麦。
- SpeechCaptureSheet支持点击/按住录音、松开结束、编辑确认、取消与本次显式自动发送（缺省关）。根聊天只将文字交给原输入/发送流程，复用原模型/审批/预算；会话或controller变化不发送，已有/变化草稿或附件时只暂存，不借语音绕过原授权。长按朗读等旧功能保留。

## 状态契约
idle→checking→permission（需要时）→recording→transcribing→ready；任何阶段可取消，失败进入error。partial不提交模型；最终结果最多16000字符，可编辑后确认；未知/旧session、退出后的回调不能复活录音或文本。权限拒绝/撤销、无识别服务、网络/音频中断有分类提示。原TTS思考/自动播报与连续会话仍需独立整合，不将这些状态等同已经实现。

## 模拟器证据
最新同APK **112/112 + 原九套143/143 = 255/255 + 生产审批UI隔离链通过**。cmd_21500f5dc885185906306fc6a3b60886233ec669595b72d6 完成分析/原生重构建/保留数据安装/112/UI，cmd_a1c9802b8c027c39bf691d8e2cdce23994a1adc0ad2a2729 在同APK九套完成0。major-speech-capture-analyze/build-20261019.log、原协议JSON与审批PNG已更新。
新增11例：无引擎零授权/录音、拒绝权限、旧结果代际、权限等待取消、服务检查前松手、停止等最终结果及文本上限、权限撤销、dispose、最终结果早于start ACK、TTS停止等待期间松手、实际原生只读能力通道已注册。前10例使用内存Source，不实际录音/系统授权/TTS；第11例只查询指定模拟器能力。**没有打开真实录音或识别、没有声学中文/数字/日期/应用名/噪声/来电实测，原生取消/硬件释放未端到端验证。生产语音Sheet UI自动化仍待补，不能将审批UI冒认为语音UI。**

## 支持边界/后续
- Android8–11无设备端SpeechRecognizer API，默认设备端模式不可用；可由用户选择已安装系统识别服务。Android12+仍取决于设备端/所选语言引擎，不承诺所有设备可用。
- 当前模拟器为Android16 x86_64；不替代ARM64、多厂商、真实音频焦点/通话/耳机切换证据。其他平台保留文字/旧朗读，不显示本Android入口。
- 待补：生产Sheet隔离UI链、真实可用ASR及声学/权限中断矩阵、来电/全部音频路由、配置替代ASR、独立前台连续会话、默认助手角色/VoiceInteractionService、锁屏/分享/悬浮支持矩阵、实时多模态，以及原方案其他门禁。模型额度3/3耗尽，未追加；不运行宿主tests、不操作真机。


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
