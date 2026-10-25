# 第一批安全修复交接（2026-10-20）

## 状态与边界

- 获准范围：W0 基线、W1 高风险通知审批、W2 中断开发任务/未知副作用恢复。
- 分发场景：私人、自用 APK；不以商店发布为当前门禁。
- 未调用真实模型；未操作真机；未修改模拟器的服务商、模型或密钥配置。
- 未安装/启动 APK。ADB 基线与构建前复核均未列出设备；未发现正在运行的模拟器或 Flutter 预览进程，未停止他人的会话。
- 源码、定向回归与 Android x64 Debug APK 构建已通过。模拟器设备级验收尚未完成，不能宣称第一批最终验收通过。

## W0 基线

- 项目：`D:/AIIIIII/ai-agent/mobile_agent`，Bash 路径 `/d/AIIIIII/ai-agent/mobile_agent`。
- HEAD：`30e552e`。开始时已有 233 个 tracked 改动（207 modified、26 added）；未 reset、checkout、clean 或批量覆盖既有工作。
- `pubspec.lock` 起始 SHA-256：`85720a75543cd749602dafcaa7c707c63450725fc9e111c1120b6e504a5f4734`。
- 既有文件的补丁均带 SHA-256 乐观并发校验；未改依赖、数据库 schema 或模型配置。

## W1：通知不再是批准凭证

- `lib/domain/approval_action_codec.dart`：新增只允许 deny 的后台动作解析器。
- `lib/application/approval_bridge.dart`：后台入口先过滤动作；旧版/伪造的 approve 动作在插件初始化和打开数据库前即被忽略。后台写入仅为拒绝。
- `lib/infrastructure/notifications/notification_service.dart`：按钮改为“打开查看/拒绝”；前者打开 UI 但不授权，后者可后台处理；锁屏可见性改为 private。
- `lib/application/foreground_approval_guard.dart`：危险、sensitive、远端命名的待审批操作验证身份；验证前后检查前台及作用域；异常、取消、失效均拒绝；高风险授权收敛到仅本次。
- `lib/presentation/widgets/tool_approval_helper.dart`：工具/结果卡审批接入 guard，远端或高风险审批不创建会话/永久信任。
- `lib/presentation/chat/chat_page_tool_approvals.dart`：高风险快捷批准转到详细审批路径，避免绕过身份验证。
- 普通 safe 自动放行策略未改；持久化脱敏名单没有被错误用来升级工具审批等级。
- 既有一次性决定、TTL、计划版本和执行前校验继续生效，未用 UI 检查替代数据库/执行边界。

## W2：恢复不是重放

- `lib/application/run_recovery_safety.dart`：根据持久化 dispatch 和 checkpoint 判断恢复是否安全。
- dispatched / unknown / 不认识的 effect：拒绝直接恢复，保留原记录；不将 unknown 写成 none。
- 已生效操作：要求匹配 runId、受支持版本以及保留 assistant tool call + applied tool result 的完整上下文。缺失或不匹配时禁止回退为原 prompt 重放。
- `lib/infrastructure/database/run_plan_store.dart`：换新 runId 也不能绕过该任务旧的未知 dispatch。
- `lib/application/chat_controller.dart`：恢复在清理 UI、切换任务状态/分配新 run 前检查；重新生成/编辑重发在删除历史前检查；预算续跑保留上下文并增加会话切换后的再校验。
- `lib/application/background_execution_gateway.dart` 与 `headless_executor.dart`：通用后台入口与直接调用入口均检查，不能仅绕过 UI 重试按钮来执行。
- 聊天重试、冷启动恢复及任务详情提供核实说明；“重新核实执行记录”只重新读取记录，不代表已经核实文件/外部目标，更不会授权重放。
- 结果未知时的安全路径是：先只读检查文件、Git diff/日志与外部目标状态，保留证据，再以明确的新请求只执行尚未完成的步骤。

## 验证证据

- 最终定向命令：`flutter test --no-pub --reporter expanded`，只列出以下 9 个文件，未跑宿主全量测试：
  - `test/foreground_approval_guard_test.dart`
  - `test/approval_policy_test.dart`
  - `test/tool_approval_background_test.dart`
  - `test/run_recovery_safety_test.dart`
  - `test/chat_resume_test.dart`
  - `test/approval_bridge_test.dart`
  - `test/agent_pause_interrupt_test.dart`
  - `test/run_coordinator_test.dart`
  - `test/task_details_page_test.dart`
- 最终结果：82 passed、0 failed，命令 exit 0；日志 `local/temp/batch1-targeted-tests.log`。
- 生产改动及新增测试的 17 路径静态分析：No issues found；最后修改的两个测试文件另外静态分析：No issues found。
- 测试使用内存数据库、注入的身份验证回调及回环假上游；费用硬停未关闭，假模型明确声明零费用且账本绑定同一个测试内存库，避免默认数据库单例。
- 测试关闭数据库前等待真实 runtime lease drain，不删除/伪造 barrier；未知结果 UI 用 paused 断点样例，避免对永续 running 动画调用 pumpAndSettle。

### 旧测试失败的对照

- 首次扩展旧 `chat_resume_test.dart` 有 8 项失败，未作为通过处理。
- 在 `local/batch1-baseline-20261020` 独立副本中，将 4 个恢复后端文件及该旧测试恢复至修改前精确 SHA-256（包括原 CRLF），复现相同 8 项失败；不是将 Git HEAD 当作当前基线，也未回退主工作区。
- 哈希证据：`local/batch1-baseline-20261020/baseline-source-hashes.json`；对照日志：`local/temp/batch1-baseline-chat.log`。
- 仅补齐假模型单价、内存账本、终态证据及异步夹具清理；另增“仅有 applied receipt 不能清断点/重放”负例，没有为通过测试而放宽生产安全门。

## 构建与剩余验收

- 构建：`flutter build apk --debug --target-platform android-x64 --no-pub`，SDK/Gradle/pub/temp 均使用工作区 local 路径；没有构建 ARM64 release 或签发私人发布候选。
- 构建结果：exit 0；APK 为 `build/app/outputs/flutter-apk/app-debug.apk`，147,846,211 字节。日志：`local/temp/batch1-android-debug-build.log`。
- APK SHA-256：`508c02478c21ec14567badd484049e116b1a2ce8b3e8b926315cef520f1bf180`。
- ZIP 中还有插件/运行时自带的 arm64-v8a 与 armeabi-v7a 原生库；本包只按 android-x64 Flutter Debug 目标构建，不能据此当作已验证的 ARM/真机安装包。
- 构建发现既有 Gradle/AGP/Kotlin 后续支持告警；未绕过检查，也未在本批擅自升级工具链。
- APK 含整个当前工作区，包括其他 agent 的既有改动，不是仅含本批补丁的独立候选。
- 尚未验证：Android 原生通知按钮/锁屏、设备身份验证成功/失败/取消、实际进程被杀后的 UI 恢复与在模拟器上的点击路径。
- 未提供“我已检查”即直接解除 unknown 的按钮。压缩/不完整旧断点可能被保守拦截；这比静默重放安全，但后续需要带证据的核实闭环。
- 不宣称跨 run 的任意语义等价命令具有全局 exactly-once，也不把模拟器当作 ARM64 PRoot 或多 ROM 验证。

## 下一步

先确定不会触发真实模型任务的隔离模拟器验收启动方式，再说明安装/替换影响并执行设备级验证；保留现有模型配置与用户数据。当前第一批未完成最终设备级验收，不应直接扩大到 W3–W7 或发布。
