# 默认系统助手入口契约与验证边界

2026-10-19。W05/F03 增量，F02/F03/A02/A03/A04/S01/S07 及整版仍未全部验收。

## 生产实现

- `NexusVoiceInteractionService`、`NexusVoiceInteractionSessionService`、`NexusRecognitionService` 与完整 `android.voice_interaction` 元数据已接线。前两服务需要系统签名权限 `BIND_VOICE_INTERACTION`；识别适配端点需要 `BIND_SPEECH_RECOGNITION_SERVICE`。不新增另一套聊天、执行或审批引擎。
- “我的 → 默认系统助手”打开生产引导页，查询真实 RoleManager 持有状态、被选服务、系统 active 状态及本进程 onReady 状态。只有这些条件都成立才显示“系统助手已激活”；打开设置、角色存在、应用注册服务本身都不等于激活。
- AOSP 的 ASSISTANT 角色标记 `requestable=false`，不能用通用 `createRequestRoleIntent` 冒认打开选择器。模拟器验证发现该请求会直接取消，已改为公开 `ACTION_VOICE_INPUT_SETTINGS` 系统页面。用户自行选择、更换或撤销，返回时刷新；旧 Android 使用被选服务与激活状态，没有伪造 RoleManager 持有事实。
- 原生系统会话显示真实面板，显式点击“打开助手”后投递 `nexus://assistant` 纯导航，继续使用原四入口和可见性屏障，不弹掉已有嵌套编辑页、不预填或自动发送。系统面板关闭和返回不发起任务。
- 每次打开动作重新核对角色/激活/锁屏状态；不设置 showWhenLocked、不解除系统锁屏，锁屏出现时隐藏面板。元数据明确禁用从 keyguard 启动，不声明唤醒词能力。
- 系统角色可能由 Android 自动授予相应权限；应用不会因角色被选择而开始录音或发起权限请求。语音仍需用户在原前台 SpeechCaptureSheet 主动操作，沿用设备端默认模式及显式系统服务选择。
- 识别适配端点仅满足系统助手注册兼容性，不提供独立 ASR。外部识别请求返回 ERROR_CLIENT，既不录音，也不把请求再次委托给系统默认识别器。不能把这个端点称作新的识别引擎或连续会话。
- 原 `ForegroundSpeechBridge` 查询系统当前指定的外部识别组件，排除本应用，检查服务可用性并显式绑定该组件。自己的兼容端点不能让 `systemAvailable` 假阳性，也不能因成为默认识别器而委托自循环；不会静默改用另一个音频接收方。设备端入口仍走 Android 的设备端识别 API。
- 服务在 onReady 默认禁用 assist structure 和 screenshot，异常截图回调直接丢弃。第二批已接入用户点击后的单次文字请求、来源和有效期、编辑核对及只加入草稿；发出请求即恢复禁用标记。生产队列与隐私边界见 [外部输入契约](mobile-assistant-input-contract-2026-10-19.md)，实际证据以恢复实施记录为准，完整支持矩阵仍未关闭。

## 当前已验证与剩余

生产 UI 驱动为 `tool/verify_assistant_role_ui_emulator.py`，通过只读 debug 扩展开生产引导页，再用模拟器真实 UI 选择默认助手、检查激活、展示系统 session、使用 KEYCODE_ASSIST、点击进入、撤销角色。撤销角色所授权限可能结束应用进程；驱动重新启动原 debug 包、更新本地 VM 元数据，在新进程检查撤销后的真实状态，最后恢复原助手与识别器配置。

| 项目 | 边界 |
| --- | --- |
| API36/x86_64 角色/面板/系统助手键/撤销 | 实际模拟器链；最终同 APK 证据见恢复实施记录 |
| 状态真值/不完整状态/打开设置不授权 | Android Dart isolate 内运行生产状态解析类；另有原生只读注册查询 |
| 录音、ASR、TTS、实际音频焦点 | 本轮不启动；不能以角色测试冒认为声学验收 |
| 冷启动 | 覆盖撤权导致的真实进程重启后状态；未证明角色仍持有时全部系统冷唤起路径 |
| 锁屏 | 有生产门禁与禁用元数据；尚未完成带安全锁屏的实际场景验收 |
| 多厂商/API24–35/ARM64 | 未实测，不以 API36 模拟器代替 |
| 单次系统页面文字 | 第二批已实现；API36专用测试页的实际取文/过滤/保护/截断结果见恢复实施记录，不推广为所有应用支持 |
| 连续语音、后台唤醒、实时多模态 | 未完成；不以单次文字采集或单句识别替代 |

## 依据

- [Android VoiceInteractionService](https://developer.android.com/reference/android/service/voice/VoiceInteractionService)：onReady、isActiveService、setDisabledShowContext。
- [Android VoiceInteractionSession](https://developer.android.com/reference/android/service/voice/VoiceInteractionSession)：系统 session 生命周期与可选上下文。
- [AOSP Android16 助手角色定义](https://android.googlesource.com/platform/packages/modules/Permission/+/refs/heads/android16-qpr2-release/PermissionController/res/xml/roles.xml)：ASSISTANT 的 requestable=false。

这些是实现依据，不是额外平台实测证据。
