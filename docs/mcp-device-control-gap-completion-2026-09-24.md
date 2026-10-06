# Android 设备控制缺口补全（2026-09-24）

## 结论

对照 8 个能力域与架构要求复核后，1–6 域（应用、文件、系统状态、系统设置、进程服务、网络诊断）
与大部分架构约束（风险分级、Root 白名单、预览计划 + 一次性票据、能力探测页）此前已实现。
本次补齐三处缺口：

| 缺口 | 状态 |
| --- | --- |
| A. 审计未区分模型意图与实际执行、缺耗时 | 已完成 |
| B. 备份与恢复基本缺失 | 已完成 |
| C. 自动化只能定时跑 LLM 提示词，无条件触发、无设备动作、无撤销 | 已完成 |

## A. 审计

- `AuditService.logAndroidDeviceOperation` 新增 `intent`（来源、工具、操作、目标、参数）与
  `execution`（按已校验参数重建的白名单命令/执行流程，不采信模型给的命令文本）两段，
  以及 `timing.startedAt/completedAt/durationMs`。
- `intent.source` 区分 `model_tool_call`、`automation_rule`、`automation_undo`、`user_confirmed_ui`。
- 新增 `logDeviceAutomationEvent`（类型 `device_automation`）：规则创建/启用/暂停/删除、
  触发后执行/放弃；含 Root 动作的规则风险记为 `dangerous`。Agent 发起的规则变更会带上用户原话。
- 审计页展示意图、实际命令、执行计划、耗时，以及自动化事件。

## B. 备份与恢复

原生 `DeviceBackupManager.kt`（通道 `nexus/device_backup`）+ `android_backup_actions.dart`
接入 `android_device`，沿用预览 → 审批 → 一次性票据：

| action | 风险 | 说明 |
| --- | --- | --- |
| `backup_list` / `backup_inspect` | safe | 列表、完整性校验、归档前 20 项 |
| `backup_personal_data` | 需确认 | 通讯录 vCard、短信/通话记录 JSON；首次备份时才请求运行时权限 |
| `backup_app_data` | 危险（Root） | `config`（shared_prefs + databases）或 `full`；上限 2 GiB |
| `backup_directory` | 危险（Root） | 仅 /sdcard、/storage/emulated/0、/data/local/tmp 下的目录 |
| `restore_app_data` | 危险（Root） | 预览列出文件（前 20 个 + 剩余数）、大小、覆盖范围、版本兼容性；执行前自动生成恢复前快照（`undoBackupId`） |
| `restore_contacts` | 需确认 | 交给系统通讯录导入 |
| `backup_delete` | 危险、不可撤销 | 明确标注 |

- 不提供整机一键恢复；短信/通话记录只做只读备份。
- 原生错误码映射为明确的工具码：`SELINUX_DENIED`→`PERMISSION_REQUIRED`、
  `ROOT_UNAVAILABLE/ROOT_DENIED`→`ROOT_REQUIRED`、`TIMEOUT`→`TIMEOUT`（单步 180 秒）。
  `android_device` 工具超时调整为 420 秒。
- 设置页新增“备份与恢复”（`DeviceBackupsPage`）。

## C. 设备自动化

流程：**触发 → 通知 → 用户点开 → 逐项预览 → 确认 → 执行**，永不后台静默执行。

- 触发器（原生 `DeviceAutomation.kt`，通道 `nexus/device_automation`）：定时（可选星期）、
  连上指定 Wi-Fi（需定位权限，拿不到 SSID 时明确给出原因）、电量低于阈值且未充电。
  每条规则同时最多一个待确认触发，保留 12 小时。
- 动作白名单：打开应用/按名称打开/深链、停止应用、清缓存、Wi-Fi/蓝牙/勿扰/亮度/音量/自动旋转、
  清理已授权目录中的旧文件（每次最多 100 个，执行前列出清单、总大小和剩余数量）。
  不含任意文件写入、Root 文件操作、防火墙/hosts、飞行模式。每条规则最多 5 个动作。
- 每个动作仍经 `android_device` 的白名单校验、预览计划、一次性票据，并单独写审计。
  预览 2 分钟过期，过期后拒绝执行。
- 确认面板：展示目标、范围、影响、实际命令、执行流程、恢复方案；含 Root 或不可撤销动作时
  必须勾选二次确认。
- 撤销：设置类动作执行前读取系统设置，执行记录中可一键恢复原值（同样走预览确认）；
  停止应用的撤销为重新启动（标注无法完全还原）；清缓存、删文件标注为不可撤销。
- Agent 工具 `android_automation`：`list_rules`、`rule_history`、`trigger_status`、
  `pending_fires`、`create_rule`、`set_rule_enabled`、`delete_rule`。含 Root/不可撤销动作的
  规则创建、以及启用规则，均按危险操作审批；工具本身不执行任何设备动作。
- 设置页新增“设备自动化”（`DeviceAutomationPage`）：触发器状态与权限、待确认触发、规则开关、
  立即运行、执行记录与撤销、4 个模板（定时勿扰、连 Wi-Fi 开应用、低电量省电、定时清理目录）。
- 通知点击：冷启动由原生写入 launch fire、Dart 启动时消费；运行中通过 `automationFired`
  回调；两条路径都会投递 `automation:<fireId>` 意图，由 ChatPage 打开确认页。

## 主要文件

- `lib/application/audit_service.dart`、`chat_run_execution.dart`、`presentation/audit/audit_log_page.dart`
- `lib/infrastructure/tools/android_device_tool.dart`、`android_backup_actions.dart`
- `lib/domain/device_automation.dart`
- `lib/application/device_action_runner.dart`、`device_automation_service.dart`、
  `android_automation_tool.dart`、`device_backup_service.dart`
- `lib/presentation/settings/device_action_confirm_sheet.dart`、`device_automation_page.dart`、
  `device_backups_page.dart`、`settings_page.dart`
- `android/app/src/main/kotlin/com/nexusagent/app/DeviceBackupManager.kt`、`DeviceAutomation.kt`、
  `MainActivity.kt`、`AndroidManifest.xml`、`res/xml/file_paths.xml`

## 验证

- `flutter analyze lib`：无问题。
- 新增测试：`device_automation_test.dart`（10）、`android_backup_actions_test.dart`（6）、
  `audit_device_execution_test.dart`（3）、`device_action_confirm_sheet_test.dart`（5），全部通过。
- 全量 `flutter test`：1342 通过，1 失败——`layering_test.dart` 的
  “presentation infrastructure imports do not grow”（79 > 78）。多出的这一处来自本次之前已有的
  未提交改动，本次新增页面未引入 presentation → infrastructure 依赖。
- `flutter build apk --debug`：成功。

## 真机需验证

- Root 设备上的应用数据备份/恢复（含 SELinux 标签修正）、恢复前快照回滚。
- Android 13+ 通知权限、Android 10+ 后台定位对 Wi-Fi 触发的影响；厂商省电策略对闹钟/广播的限制。
- 各 ROM 对勿扰、Wi-Fi、蓝牙 Root 切换命令的兼容性。
