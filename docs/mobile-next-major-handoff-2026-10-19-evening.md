# 移动端下一大版本：剩余未完成任务交接（2026-10-19 晚间）

> **最新状态：用户已于 2026-10-19 20:57 要求暂停开发、编写交接。** 聊天/计划结果卡已有接线与 37/37 合同，静态分析通过，但新 UI 验证失败、回归未跑，不能标完成。当前断点和恢复步骤见 [暂停交接](mobile-chat-results-handoff-2026-10-19-2057.md)。本文历史“继续执行”建议不能覆盖用户的暂停指令。

> **后续 U05 统一审批增量（2026-10-19）**：成果中心接入统一 sheet/ApprovalBridge，SQL 审批权威、事务 CAS 与最终交接校验已补齐；新增 27/27、回归 34/34 + 12/12 + 51/51、实际手机审批 4/4 场景通过。详见 [审批续做记录](mobile-u05-result-approval-2026-10-19.md)。验收期间共享预览重建，当前基包为 `3ac2ff38…`；本轮是实时源码核对后的热重载证据，不能沿用下文历史包的最终签收。通知 OS 端到端及整版仍未验收，`releaseReady=false`。

> **后续 U04 增量（2026-10-19）**：遗忘保护已扩展到已知旧称/别名/来源，重添改为单次明确放行；补事务版本检查、真实 SQLite 和手机管理页验收。51 项合同与未完成边界见 [U04 续做记录](mobile-u04-personal-context-2026-10-19.md)。这是热重载验证，不是新 APK 签收。个人上下文仍未进入备份格式，旧备份恢复保留本机该范围并明确警告；整版仍不可发布。

> **后续接手增量（2026-10-19）**：U05 文件预览/真实系统分享已接，确认后不执行的 UI 缺陷已修复，新成果自动生成文件卡；34 项增量合同、12 项成果回归和真实分享/取消/重试 UI 见 [U05 续做记录](mobile-u05-file-actions-2026-10-19.md)。本轮是已核对实时源码的热重载验证，**不是下文 `8ebe5948…` APK 的新增签收**；原历史证据保持不变，整版仍不可发布。

**交接时间：** 2026-10-19 18:4x（Asia/Shanghai）
**仓库：** `D:/AIIIIII/ai-agent/mobile_agent`
**Git 基线：** `30e552e chore(workspace): track docs/ and add local/ scratch directory`（工作区仍有 503 项未提交改动，本轮未 reset／未提交／未推送）
**应用版本：** `0.9.0+95`，数据库 schema **32**

> **一句话状态：** 今天下午到晚间完成了验收驱动修复、TTS 归属缺陷修复、F17 关联上下文、F20 可操作结果卡的实现与接线，合同 332 → **371/371**（计划协议 189 → **228/228**），并且在**同一枚 APK（`8ebe5948…`）上跑通了全部五条最终 UI 驱动**（entry／context／approval-scope／speech／role 全过，设备状态已复原）。**但整版仍不具备发布资格**：`releaseReady` 保持 `false`，W00–W21 无一关闭，A01–A28／S01–S12 未验收。
>
> **禁止把下列数字当完成率：** 371 是「同一 APK 内可复跑的隔离合同数」，不是功能验收通过数；五条 UI 驱动也只是一轮 fixture 级真机流程，不等于 §6 的完整验收。

---

## 1. 接手 60 秒速览

| 项 | 当前值 |
| --- | --- |
| 设备 | `emulator-5554`，AVD `Nexus_Preview_API_36`（Android 16 / Google APIs / x86_64） |
| 包名 | `com.nexusagent.app.debug`（预览会话内进程存活，pid 每次重启变化） |
| 磁盘 APK | `build/app/outputs/flutter-apk/app-debug.apk` = `8ebe5948127987652c672c43b3ab611a412fb8f71a9f2ab0977f778c2ac1ddbc` |
| 设备已安装 APK | 同一哈希 `8ebe5948…`（已用 `pm path` + `run-as … sha256sum base.apk` 核对） |
| 合同 | **371/371**；其中计划协议 **228/228**（含 F17 22 条、F20 17 条），在本版 APK 上复跑通过 |
| 五条最终 UI 驱动 | **5/5 通过**（18:45 完成，设备状态已复原），报告见证据索引 `finalApkUiPassed` |
| 默认系统助手 | 已恢复为 `com.google.android.googlequicksearchbox/com.google.android.voiceinteraction.GsaVoiceInteractionService` |
| 预览进程 | **运行中**（分离进程 `Start-Process … ./tool/run-android-preview.ps1`，日志 `local/temp/preview-detached-20261019-2020.log`，已验证 touch 文件会出现 `[preview] Hot reload complete.`）；装 APK 会杀掉它，需重启 |
| 证据总索引 | `local/temp/major-deepseek-handoff-evidence-20261019.json`，`recordedAt`/`apkSha256` 已同步为 `8ebe5948…`，合同 371/371 |
| 模型真实调用额度 | 3/3 **已用尽**，后续只能离线 fixture |

---

## 2. 今天已完成（接手人不必重做，只做增量）

### 2.1 验收驱动的 RPC 自动重连（根因修复）

- 根因：`pm revoke` 会杀死 app 进程，`local/android-preview/vm-service.json` 随即陈旧，后续裸 `URLError` 让上一轮驱动在 15:58 中断。
- 方案：`tool/emulator_driver_support.py` 新增 `apk_sha256()`、`app_pid()`、`ensure_debug_app(probe, attempts=3)`；四条 UI 驱动在开始与 restore 之后各调一次，失败自动重新 `launch_emulator_debug.main()`。
- 文件：`tool/emulator_driver_support.py`、`tool/verify_approval_scope_ui_emulator.py`、`tool/verify_assistant_context_ui_emulator.py`、`tool/verify_speech_capture_ui_emulator.py`、`tool/verify_assistant_entry_ui_emulator.py`、`tool/verify_assistant_role_ui_emulator.py`。

### 2.2 TTS 归属缺陷修复

- 缺陷：`TtsService` 的全局 `completion/cancel/error` 回调不校验归属，旧 utterance 的迟到回调会误结束新 utterance。
- 修复：`lib/infrastructure/tts/tts_service.dart` 增加 `_startedSpeak` / `_awaitingStart`，新增 `_nativeStarted()` / `_nativeTerminated()`，`stopBeforeRecording()` 清空归属。
- 合同：`lib/debug/tts_lifecycle_checks.dart` 新增 4 条（共 189 → 当时 189/189）。
- 仍未覆盖：模拟器无 TTS 引擎，**真实发声与中断时序未验证**。

### 2.3 F17 关联个人上下文（新增）

| 文件 | 行数 | 作用 |
| --- | --- | --- |
| `lib/domain/personal_context.dart` | 1009 | 实体/关系/别名/来源/确认态/墓碑/消歧评分模型 |
| `lib/infrastructure/database/personal_context_store.dart` | 721 | 裸 SQL 仓储 + `ensurePersonalContextTables(AppDatabase)` |
| `lib/application/personal_context_service.dart` | 787 | 消歧、遗忘、更正、注入块、敏感动作校验 |
| `lib/presentation/settings/personal_context_page.dart` | 861 | 手机端管理页（增/改/确认/遗忘） |
| `lib/debug/personal_context_checks.dart` | 672 | 22 条隔离合同 |

- 接线：`lib/infrastructure/database/app_database.dart` `schemaVersion => 32`（`onCreate` line 101、`onUpgrade` `if (from < 32)` line 397）；`lib/application/chat_run_execution.dart` 在记忆/知识之后追加个人上下文注入块；入口在「我的 → 数据管理 → 个人上下文」。
- 已在模拟器实看：空态、新建条目、保存 toast、列表「人物 · 1 / 已确认」均正常。

### 2.4 F20 可操作结果卡（新增）

| 文件 | 行数 | 作用 |
| --- | --- | --- |
| `lib/domain/result_card.dart` | 652 | 卡片/动作/风险/状态/错误码 + 9 个已注册动作规格 |
| `lib/infrastructure/database/result_action_store.dart` | 302 | 裸 SQL 仓储 + `ensureResultActionTables(AppDatabase)` + 幂等唯一索引 |
| `lib/application/result_action_service.dart` | 597 | prepare／validate／execute／confirm、幂等、in-flight 去重 |
| `lib/presentation/chat/widgets/result_card_view.dart` | 458 | 卡片渲染与动作按钮 |
| `lib/debug/result_card_checks.dart` | 496 | 17 条隔离合同 |
| `lib/presentation/artifacts/artifact_center_page.dart` | 299 → 654 | 成果中心追加结果卡区块与详情、本地确认弹窗 |

- 动作覆盖六类：`reminder.reschedule`／`reminder.cancel`／`calendar.adjust`／`file.preview`／`file.share`／`route.open`／`workflow.trial_run`／`diff.review`／`diff.restore`；模型伪造的 `actionType` 无法进 UI/prepare。
- 幂等键 `result-card:<cardId>:<actionType>:v<resourceVersion>`，并发点击共享同一 Future，执行器只调一次。
- 已在模拟器实看：用种子卡片看到「结果卡·1 张可操作结果」区块、详情、动作按钮、失败状态（无执行器时红底提示、不伪造成功）；期间发现并修掉紧凑卡横向列表 **1px 溢出**（`artifact_center_page.dart` 高 168 → 184）。

### 2.5 文档与证据

- `docs/mobile-next-major-implementation-audit-2026-10-19.md`：F17/F20 改「已实现（隔离合同）」，新增第六节落地记录（文件、行号、用例名、验证）。
- `docs/mobile-next-major-progress-2026-10-18.md`：W16/W19 改「实施中」并追加 F17/F20 增量段。
- `local/temp/update_evidence_8ebe5948_20261019.py` 已执行：证据索引写入 371/371、`f17PersonalContext`、`f20ResultCards`、五份新 UI 报告与 `livePreviewArtifact`（脚本带断言，报告不全过或哈希不一致会直接失败，不会写出假证据）。
- 本交接文档自身即本节产物：`docs/mobile-next-major-handoff-2026-10-19-evening.md`。

---

## 3. 已闭环（不要再重做）与真正剩余的任务

### U01 ✅ 已闭环（2026-10-19 18:45）五条最终 UI 驱动曾 1 过 4 败，根因是模拟器掉线 + 驱动误报

- 经过：先在 `e2bad66a…` 上 1 过 4 败（`local/temp/major-final-ui-rerun-after-f20-overflow-20261019.log`），重启设备后发现 `adb devices` 为空、无 `emulator`/`qemu` 进程，真实异常是
  `RuntimeError: Emulator ADB operation failed`，最内层帧为 `tool/launch_emulator_debug.py:19`——「driver line 19」是 `traceback.extract_tb(...)[-1].lineno`，不是驱动源码行号
  （见 `tool/verify_assistant_role_ui_emulator.py:152`），四份报告把「设备掉线」误报成了 UI 断言失败。
- 修复两处 `tool/emulator_driver_support.py`：新增 `device_online()`；`ensure_debug_app()` 入口在设备离线时直接抛
  `RuntimeError('Emulator offline: <serial> missing from adb devices')`；`app_pid()` 在 `pidof` 抛错时先区分「进程不在」与「设备掉线」。
- 复跑结果（`local/temp/major-final-ui-rerun-after-device-restart-20261019.log`，18:45 结束）**5/5 通过**：
  entry、context、approval-scope、speech、role 全部 `exit=0`，各自打印其通过句；`finalize_acceptance_20261019.py` 输出
  `FINAL-APK UI SIGN-OFF INPUTS OK`（`installedMatchesDisk=true`、默认助手复原为 Google、secure settings 复原、运行时权限全 denied 且无 USER_SET、app 存活）。
- 教训（写进 §5）：设备掉线时驱动必须报「Emulator offline」，否则会被误读成业务回归。

### U02 ✅ 已闭环 证据索引已同步到 `8ebe5948…`（371/371）

- `local/temp/update_evidence_8ebe5948_20261019.py`（scratch 脚本，会**先断言**五份报告都 passed、且 `disk == installed == 报告里的 apkSha256` 才写）执行结果：
  `apk=8ebe5948…`、`contracts=371/371`、`ui=approvalScope:36d4a571…,assistantRole:85d2ff64…,context:60025f2e…,entry:d6c53e5e…,speechCapture:c0522272…`、`EVIDENCE-8EBE5948-OK`。
- 已更新字段：`apkSha256`／`installedApkSha256`／`finalApkUiPassed`（五份新报告 + sha256 + `apkSha256`）／`finalApkUiSignOff`（含 `summarySha256` 与新哈希）／`livePreviewArtifact`／`preview`／`recordedAt`；`contracts` 里计划协议项改为 228/228 并更新 sha256，`contractPassed/contractTotal` 重算为 371。
- **哈希口径**：能在本机复现的构建有两枚——`e2bad66a…`（`flutter build apk --debug --target-platform android-x64`，带工作区 env）与 `8ebe5948…`（`tool/run-android-preview.ps1` 的 `flutter run`）。
  两者源码相同、字节不同；**签收报告与当前安装/预览都是 `8ebe5948…`**，引用证据时一律用它，不要再写 `ce8ac684…`/`e2bad66a…`。

### U03 ✅ 已闭环 预览进程已恢复（20:25 复核热重载真的生效）

- 当前以**分离进程**运行：`Start-Process pwsh -Command "… ./tool/run-android-preview.ps1 *> local\temp\preview-detached-20261019-2020.log"`。日志有
  `[preview] Ready. Edits under lib/, assets/, shaders/ reload automatically.`；实测 touch `lib/main.dart` 后出现 `[preview] Hot reload complete.`，app pid 存活、界面正常（截图 `local/temp/preview-after-restart-20261019.png`）。
- **本轮新踩的坑（很重要）**：把 `run-android-preview.ps1` 放进**后台 job**（尤其 `| Tee-Object` 或管道）时，job 一结束管道就被拆，dart watcher 进程虽然还在，
  但 stdout 句柄已失效 → **热重载静默失效**（日志只剩 Ready，没有 reload），job 还会以 `exit code 1` 结束并抛 `Flutter preview exited with code 1`。
  判断"预览是否真的能热重载"必须 touch 一个文件看有没有 `[preview] Hot reload complete.`，不能只看窗口/进程存在。
- 修法：先 `Get-Process -Name dart | Stop-Process -Force` 清僵尸 watcher，再用 `Start-Process` 分离启动、输出重定向到文件。
- 注意：**任何 `adb install -r` 都会杀掉预览**，装完必须重启预览（它会重建 APK，哈希随之变成 `8ebe5948…` 这一枚）。

### 真正剩余的任务从 U04 开始

### U04（P1）F17 剩余缺口

| 缺口 | 说明 |
| --- | --- |
| 真实 SQLite 集成合同 | 22 条用例走内存仓储，`SqlPersonalContextRepository` 未在真机 DB 上跑过（schema 32 迁移只用合同间接覆盖） |
| 墓碑粒度 | `forget` 只按 `(normalized_key, project_id)` 拦截；实体改名/改限定词后新键不会被旧墓碑拦，可能「改个名就自动回库」 |
| 跨任务指代只到提示层 | 注入进 system prompt 的只是背景块，尚未验证「上次那份方案」在真实多轮对话中能定位到唯一对象 |
| 语音入口未接 | 默认助手语音链路的上下文摘要把个人上下文拼进去了，但语音侧未验证（受 U06 阻塞） |
| 未授权资料不召回 | 合同覆盖，但没有真实来源授权流程（无 OAuth/文件授权接入） |

### U05（P1）F20 剩余缺口

| 缺口 | 说明 |
| --- | --- |
| 真实执行器没接 | 9 个动作目前是**回调注入**的接口，没有真实 Intent／提醒／日历／文件分享实现；现在点按钮只会得到「没有可用的操作执行器，已停止（不会伪造成成功）」 |
| artifact 版本恒 1 | `lib/presentation/artifacts/artifact_center_page.dart` 的 `_ArtifactResultResourceReader` 因 `artifacts` 表无版本列而固定返回 version 1，导致 artifact 类卡片**只能 stale 不能 conflict**，「跨设备改了资源」这条验收拿不出来 |
| 审批未接统一链路 | 成果中心用本地 `AlertDialog` + `ResultActionService.approvalValidity`（5 分钟）生成 approval，没走统一 ApprovalBridge；`lib/application/result_action_service.dart` 的 `confirm(actionId, approval)` 是为接入留的口 |
| 卡片未进聊天时间线 | 只挂在成果中心；`lib/presentation/chat/widgets/tool_activity_section.dart` 的时间线条目、计划面板都还没挂结果卡 |
| 未回链任务 | 表里有 `task_id`，UI 没有「返回关联任务」跳转 |

### U06（P1，工作量大）连续语音会话 / 实时多模态

- `android/` 全仓 grep `MediaProjection` **零命中** → F15 实时多模态零实现。
- 原生侧只有单句 `SpeechRecognizer`（`NexusRecognitionService.kt`、`ForegroundSpeechBridge.kt`）；TTS 的全局回调也不能用于「自动开麦」的连续会话（`tts_service.dart` 的 doc 注释已写明）。
- 需要 `TaskService`／前台服务与跨进程恢复配合（U07）。

### U07（P1）TaskService／前台服务与恢复

- 连续语音、后台任务、跨进程恢复都依赖它；当前没有实现，W20 相关验收无法开始。

### U08（P1）W/F 台账与 A/S 验收

- `docs/mobile-next-major-progress-2026-10-18.md` 台账：**W00–W21 仍是 0/22 完成**（W00/W01/W04/W06/W08/W12/W15/W21 实施中，其余未完成）。
- F 功能：F17/F20 现已「机制已实现」；F10/F13/F15/F18/F19 基本未落地；F12 只有 token 预算没有费用预算；F16 只有五类 `prepare`（无读写、无 OAuth）。
- A01–A28、S01–S12 未验收；设备矩阵仍要求 ≥3 台 ARM64 真机。

### U09（P2）真机与发布门禁

- 需 ARM64 真机矩阵、Profile、功耗、七天使用；x64 模拟器不能替代（内置 Alpine/PRoot 仅 ARM64）。
- 这些没做完之前 `releaseReady` 必须保持 `false`。

### U10（P2）未提交/未推送

- 503 项未提交改动，本轮**没有** reset／commit／push。是否提交由用户决定。

### U11（P2）模型额度

- 真实模型调用 3/3 已用尽；后续模型相关验收需用户另行授权额度，离线 fixture 不算真实模型证据。

---

## 4. 命令速查（必须带工作区环境变量，否则签名对不上）

```powershell
$repo = 'D:\AIIIIII\ai-agent\mobile_agent'
$env:ANDROID_HOME      = "$repo\local\android-sdk"
$env:ANDROID_SDK_ROOT  = $env:ANDROID_HOME
$env:ANDROID_USER_HOME = "$repo\local\android-user"   # debug.keystore 在这里
$env:PUB_CACHE         = "$repo\local\pub-cache"
$env:GRADLE_USER_HOME  = "$repo\local\gradle-cache"
$env:TEMP              = "$repo\local\temp"
$env:TMP               = $env:TEMP
Set-Location $repo

# 静态检查与构建
flutter analyze --no-pub
flutter build apk --debug --no-pub --target-platform android-x64
"{(Get-FileHash build\app\outputs\flutter-apk\app-debug.apk -Algorithm SHA256).Hash.ToLower()}"

# 安装并拉起调试 app（会杀掉预览）
.\local\android-sdk\platform-tools\adb.exe -s emulator-5554 install -r build\app\outputs\flutter-apk\app-debug.apk
python tool\launch_emulator_debug.py

# 合同（期望 228/228，只有全过才 exit 0）
python tool\verify_plan_protocol_emulator.py

# 五条最终 UI 驱动（应串行跑；会临时改默认助手并复原）
python tool\verify_assistant_entry_ui_emulator.py
python tool\verify_assistant_context_ui_emulator.py
python tool\verify_approval_scope_ui_emulator.py
python tool\verify_speech_capture_ui_emulator.py
python tool\verify_assistant_role_ui_emulator.py

# 预览
.\tool\run-android-preview.ps1     # 或根目录 android-preview.bat
```

---

## 5. 已知陷阱（都是本轮踩过的）

1. **签名不一致**：裸 `flutter build` 会用 `C:\Users\<user>\.android\debug.keystore`，装到模拟器报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE: … signatures do not match`。必须像上面那样显式设 `ANDROID_USER_HOME`。
2. **覆盖安装会杀掉预览**：`adb install -r` 之后 `flutter run` 会话一定结束，要重新启动预览；装完先 `python tool\launch_emulator_debug.py` 再跑驱动。
3. **`pm revoke` 杀进程**：权限驱动 restore 后 `vm-service.json` 陈旧，必须走 `ensure_debug_app`；手写脚本也要先 `pidof` 校验。
4. **合同总数是硬编码**：`tool/verify_plan_protocol_emulator.py:45` 的 `len(cases) != 228` 要随新增用例同步改，否则报「意外数量」。
5. **报告 JSON 编码**：`local/temp/major-*.json` 有的是 GBK，直接 `json.load(open(..., encoding='utf-8'))` 会 `UnicodeDecodeError`；统一用 `tool/emulator_driver_support.read_json/write_json`。
6. **数据库迁移的裸 SQL 先例**：新表都走 `customStatement('CREATE TABLE IF NOT EXISTS …')`（见 `app_database.dart` 的 `ensureRunPlanProtocol`/`ensureRunApprovalScopes`/`ensurePersonalContextTables`/`ensureResultActionTables`），**不要**重新生成 `app_database.g.dart`。
7. **驱动对设备助手角色状态敏感**：五条 UI 驱动依赖「默认助手」可切换且能复原；跑之前确认 `settings get secure voice_interaction_service` 是 Google 而不是残留的 NEXUS。
8. **1px 溢出**：结果卡紧凑卡标题两行 + 摘要两行时 168 高度差 1px，已改 184（`lib/presentation/artifacts/artifact_center_page.dart`）；以后改卡片内边距要重看 render 溢出日志。
9. **设备掉线会伪装成业务失败**：模拟器整机退出时，驱动报的是 `RuntimeError at driver line 19`，19 是最内层帧（`tool/launch_emulator_debug.py:19`）而不是驱动行号。本轮已在 `tool/emulator_driver_support.py` 加 `device_online()` 与 `Emulator offline:` 明确报错；看到这类报错先 `adb devices`。
10. **驱动里不要用未定义的常量**：修 `ensure_debug_app` 时曾写 `DEVICE_SERIAL`（该名字只存在于 `tool/run-android-preview.ps1` 语境），导致五条驱动全部 `NameError`。序列号常量在 `tool/emulator_driver_support.py` 里叫 `SERIAL`。
11. **`run-as` 写不了 `/sdcard`**：往设备里灌种子数据只能走 `/data/local/tmp` + `run-as cp`，以及 `adb exec-out run-as <pkg> cat <db>` 拉库；拉库要连 `-wal`/`-shm` 一起拉并 checkpoint，否则会误判「新表没建」。
12. **后台 job + 管道会"假预览"**：把 `run-android-preview.ps1` 塞进后台 job（尤其 `| Tee-Object`）时，job 结束后 watcher 还活着但 stdout 已废，热重载**静默失效**、job 报 `exit code 1`。要用 `Start-Process` 分离启动并把输出重定向到文件，并用 touch 文件验证出现 `[preview] Hot reload complete.`。

---

## 6. 建议接手顺序

> U01（五条 UI 驱动回到全过）、U02（证据索引同步）、U03（预览恢复）已在 18:2x–18:45 全部闭环，见第 3 节。剩下的按下面顺序做。

1. **U05 的真实执行器（最推荐）**：F20 现在承诺「可操作」，但点按钮只会失败（实拍证据：点「预览文件」→ 卡片转「失败」+「没有可用的操作执行器」）。
   先接 2–3 个最安全的——`file.preview`、`route.open`、`reminder.reschedule`（系统 Intent + `ResultActionApproval`），把「准备中/待确认/成功/失败」四态真正跑出来。
   这是把「机制已实现」变成「用户能用」的最短路径，也是审计文档里唯一能立刻抬升分数的一项。
2. **U04 的墓碑粒度 + 真实 DB 集成合同**：F17 的遗忘防回库是安全底线，成本小（改 `personal_context_store.dart` 的墓碑匹配 + 加一份真机 DB 合同）。
3. **U06/U07 连续语音与 TaskService**：工作量大、受 ARM64 真机阻塞，建议单独开一轮，先写真机验证计划。
4. **U08 的 ARM64 真机与 W/F 台账收尾**：属于门禁，不是功能，放在功能稳定后统一做。

如果只做一件事：做第 1 项。

---

## 7. 证据文件清单

| 路径 | 内容 |
| --- | --- |
| `local/temp/major-deepseek-handoff-evidence-20261019.json` | 证据总索引（371/371、合同明细、F17/F20、driverFix、TTS 修复、预览制品） |
| `local/temp/major-plan-protocol-emulator-contract-20261019.json` | 计划协议合同报告（228 项，含 F17/F20） |
| `local/temp/major-final-ui-rerun-after-device-restart-20261019.log` | **最新一轮**五条 UI 驱动（5/5 通过，`8ebe5948…`） |
| `local/temp/major-final-ui-rerun-after-f20-overflow-20261019.log` | 设备掉线那轮（1 过 4 败，仅作误报证据，不要当业务结论） |
| `local/temp/major-final-ui-rerun-after-f17-f20-20261019.log` | 更早一轮五条 UI 全过（`ce8ac684…`） |
| `local/temp/major-assistant-*-ui-20261019.json` | 五条 UI 驱动的结构化报告（最新一轮均为 passed=true） |
| `local/temp/major-approval-scope-before-20261019.json`、`major-speech-capture-before-20261019.json`、`major-assistant-role-before-20261019.json` 等 | 每轮设备基线快照与还原报告 |
| `local/temp/update_evidence_8ebe5948_20261019.py` | 证据索引写入脚本（幂等，带「报告必须 passed 且哈希一致」断言，可改参数复跑） |
| `local/temp/seed_result_card.py`、`ui_dump.py`、`db_probe.py` | F20 实看用 scratch 脚本（不属于验收套件） |
| `local/temp/f20-*.png`、`f17-*.png` | 模拟器实看截图 |
| `local/temp/build-apk-f17-f20-ws-20261019.log` | 带工作区签名的构建日志（`ce8ac684`）；`e2bad66a` 为修 1px 溢出后重建 |
| `docs/mobile-next-major-implementation-audit-2026-10-19.md` | 实现方案落地审计 + F17/F20 落地记录 |
| `docs/mobile-next-major-progress-2026-10-18.md` | W/F 台账与逐次增量记录 |
