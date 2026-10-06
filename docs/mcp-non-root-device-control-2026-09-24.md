# 设备控制免 Root 支持：交付说明（2026-09-24）

> 目标：没有 Root 的用户也尽量能使用 8 大类设备控制能力。
> 取代 `docs/mcp-non-root-device-control-handoff-2026-09-24.md`，那份接手文档里的待办已全部完成。
> 草稿目录 `docs/handoff/non-root-2026-09-24/` 已按约定删除，草稿已移到正式路径。

## 1. 执行顺序与原则

| 需要的特权 | 执行顺序 | 说明 |
|---|---|---|
| `shell`（系统命令） | Root → Shizuku（adb/uid 2000 或 uid 0）→ 系统 API → 打开系统设置页 | Wi-Fi、蓝牙、飞行模式、定位、勿扰、动画倍率、强行停止等 |
| `root_uid`（必须 uid 0） | Root → 以 Root 启动的 Shizuku → 专用降级（如有） | 清理缓存、hosts、端口防火墙、刷新 DNS、重启服务、结束进程、应用数据备份/恢复 |
| `storage`（共享存储文件） | **应用自身“所有文件访问”** → Root → Shizuku | 按你的决定走最小权限：/sdcard 优先用应用身份；/data/local/tmp 只能走 Root/Shizuku |

- 所有命令仍是**固定模板 + 参数校验**，Shizuku 只是换了执行身份，模型无法拼接任意命令。
- 特权命令执行失败时会继续尝试下一级降级。
- 原生结果统一带这些字段：`executedVia`（root / shizuku / app / api / settings / vpn / package_installer）、`applied`、`userActionRequired`、`partial`、`fallbackReason`。
- Dart 侧：只要 `userActionRequired=true`，结果就改写为“尚未直接生效，需要你在系统界面完成：…”，effect 设为 `unknown`。页面类动作（`open_*`、`request_shizuku_permission`、`choose_folder`）不改写，因为打开页面本身就是目的。

## 2. 各动作无 Root 时的行为

| 动作 | 无 Root、有 Shizuku | 两者都没有 |
|---|---|---|
| set_wifi | `svc wifi` | Android 9 及以下用 WifiManager；否则打开 Wi-Fi 面板 |
| set_bluetooth | `cmd bluetooth_manager` | 有“附近设备”权限且 Android 12 以下用系统 API；否则打开蓝牙设置页 |
| set_airplane_mode / set_location | `cmd connectivity` / `cmd location` | 打开对应设置页 |
| set_do_not_disturb | `cmd notification set_dnd` | 有勿扰权限时用 NotificationManager；否则打开勿扰授权页 |
| set_animation_scale | `settings put global` | 有 WRITE_SECURE_SETTINGS 时直接写；否则打开开发者选项 |
| set_brightness / auto_rotate / refresh_rate | 先用系统 API（WRITE_SETTINGS），再走特权 | 打开“修改系统设置”授权页 |
| stop_app / restart_app | `am force-stop` | killBackgroundProcesses 后打开应用详情页（`partial=true`） |
| clear_app_cache | uid 0 执行原脚本；adb 模式在 Android 14+ 用 `pm clear --cache-only` | 打开应用详情页 |
| kill_process / restart_service / refresh_dns | 需要 uid 0 | 返回 `ROOT_REQUIRED`，并给出替代建议（例如切换一次飞行模式来刷新 DNS） |
| set_hosts_block | 需要 uid 0 | **自动改用本地 VPN DNS 屏蔽**（`executedVia=vpn`） |
| set_firewall_port_rule | 需要 uid 0 | `ROOT_REQUIRED`；建议改用 set_app_network_block |
| running_processes / foreground_apps / recent_apps | `ps` / `dumpsys` | ActivityManager 和 UsageStats（需要“使用情况访问”） |
| logcat_tail / crash_logs | 完整 logcat | 本应用日志；授予 READ_LOGS 后可读完整日志 |
| read/list/write/delete/move/compress/extract/directory_size | /sdcard 路径优先用应用身份 | 需要“所有文件访问”；/data/local/tmp 只能走 Root/Shizuku |
| backup_app_data config/full、restore_app_data（数据） | 仅 uid 0 | `ROOT_REQUIRED`；建议改用 `scope=apk` |
| **backup_app_data scope=apk** | 不需要特权 | 复制 base 和拆分 APK，记录 SHA-256 与签名摘要 |
| **restore_app_data（apk-备份）** | 不需要特权 | 使用 PackageInstaller 会话，由系统安装确认界面决定是否安装；签名不一致时拦截 |
| backup_directory | /sdcard 路径优先用应用身份 | 需要“所有文件访问” |

## 3. 新增 android_device 动作

| action | 风险 | 说明 |
|---|---|---|
| `privilege_status` | safe | 返回 Root、Shizuku、特殊权限、本地 VPN 的状态，以及 `routes`（shell / rootUid / storage / storageDataLocalTmp 的实际通道） |
| `network_filter_status` | safe | 返回 VPN 过滤器的规则、计数、最近拦截、限制说明 |
| `request_shizuku_permission` | requiresConfirmation | 弹出 Shizuku 授权框 |
| `open_shizuku` | requiresConfirmation | 打开 Shizuku；未安装时打开下载页 |
| `open_special_permission` | requiresConfirmation | `permissionKind`：all_files / usage / notification_policy / write_settings / install_packages / vpn / bluetooth |
| `open_app_details` | requiresConfirmation | 打开应用详情页 |
| `grant_privileged_permissions` | dangerous | 经 Root/Shizuku 给 NEXUS 自己授予 WRITE_SECURE_SETTINGS、READ_LOGS、使用情况访问、勿扰、所有文件访问等权限；授权后很多动作不再需要特权 |
| `set_network_filter` | dangerous | 启用或停用本地 VPN（规则保留） |
| `set_app_network_block` | dangerous，可逆 | 对某个应用断网，结果带 `undo` |
| `set_domain_block` | dangerous，可逆 | VPN DNS 屏蔽（NXDOMAIN） |

- 这些动作都走现有的“预览 → 审批 → 一次性票据”流程。预览工具的 enum 从动作集合自动生成。
- 预览新增 `executionRoute` 字段：`{requirement, route, label, fallback?, note?, statusAgeSeconds}`。
  - 预览**不访问原生层**，所以永远不会弹 Root 授权框。
  - 数据来自最近一次 `bridge.privilegeStatus()` 的快照，5 分钟内有效。设备能力页和 `privilege_status` 都会刷新快照。
  - 没有快照时显示 `route=unknown`，并提示先调用 `privilege_status`。
- 审计的“实际执行”记录新增 `privilegeRequirement` 和 `executionRoute`。
- 错误码映射：
  - `ROOT_REQUIRED` / `PRIVILEGE_REQUIRED` / `PRIVILEGE_UNAVAILABLE` → `ROOT_REQUIRED`
  - `STORAGE_PERMISSION_REQUIRED` / `PERMISSION_REQUIRED` → `PERMISSION_REQUIRED`
  - `UNAVAILABLE` → `CAPABILITY_UNAVAILABLE`
  - 原生 `details`（例如 Shizuku 是否安装）并入结果 data，同时附带 `nativeCode`。

## 4. 本地 VPN 过滤器（NetworkFilterVpnService）

- **dns 模式**（有屏蔽域名时）：只接管虚拟 DNS 10.111.222.1。
  - 屏蔽的域名，以及断网应用发出的查询（Android 10+ 按 uid 识别），返回 NXDOMAIN。
  - 其它查询转发到系统 DNS，失败时依次改用 223.5.5.5 / 119.29.29.29 / 1.1.1.1。
- **app_full 模式**（只有断网应用时）：只把这些应用路由进 VPN，丢弃它们的全部数据包，实现完整断网。
- 上限：500 个域名、100 个应用。开机后按已保存规则恢复。NEXUS 自身不能被断网。
- 限制（会在状态和能力页中如实展示）：
  - 应用自带 DoH/DoT、系统“私人 DNS”设为指定主机名、直连 IP 时，可以绕过域名屏蔽。
  - Android 同一时间只允许一个 VPN。
  - 端口级防火墙仍需要 Root。

## 5. 设备能力页（lib/presentation/settings/device_capabilities_page.dart）

新增三个分区：
- **免 Root 通道**：Shizuku 状态（未安装 / 未运行 / 待授权 / 可用 · ADB 或 Root 模式），并按状态提供“打开 / 授权 / 授予权限”按钮。下方是“当前执行通道”汇总。
- **系统特殊权限**：9 项权限的状态，每项说明用途。可以跳转的给出“去授权”按钮；WRITE_SECURE_SETTINGS 和 READ_LOGS 只能经特权授予，所以不提供入口。
- **本地 VPN 过滤器**：运行状态、规则摘要、限制说明，以及启用/停用开关（没有规则时不允许启用）。

页面行为：
- 页面加载使用 `privilegeStatus(probeRoot:false)`，**不执行 su**。Root 仍只在你点“检查 Root”时探测，检查结果会并入通道汇总。
- 从系统授权页或 Shizuku 返回（resumed）时自动刷新。
- 没有新增 presentation → infrastructure 的 import。

## 6. 文件清单

**新增（Android）**
- `android/app/src/main/aidl/com/nexusagent/app/IPrivilegedShell.aidl`
- `android/app/src/main/kotlin/com/nexusagent/app/PrivilegedShellService.kt`：Shizuku UserService，以 uid 2000 或 0 执行命令，支持流式 stdin/stdout
- `.../PrivilegeManager.kt`：通道选择、Shizuku 绑定与授权、特殊权限状态、自授权
- `.../PrivilegedDeviceControl.kt`：原 MainActivity 中 29 个 device_control 分支的降级实现，运行在 2 线程后台池，不再在主线程执行 su
- `.../NetworkFilterVpnService.kt`：NetworkFilterStore 和 VPN 服务
- `.../ApkInstallResultReceiver.kt`：PackageInstaller 状态回调；待确认时拉起系统界面，结果写入 lastInstallResult
- `android/app/proguard-rules.pro`：保留 UserService 和 AIDL 类名

**修改（Android）**
- `android/app/build.gradle.kts`：aidl、Shizuku api/provider 13.1.5、release 使用 proguardFiles
- `AndroidManifest.xml`：ShizukuProvider、VPN 服务、安装回调接收器、相关权限
- `MainActivity.kt`：3048 → 2324 行，改为委托 PrivilegedDeviceControl
- `DeviceBackupManager.kt`：APK 备份与安装恢复；目录备份和应用数据流式打包改走 PrivilegeManager

**修改（Dart）**
- `lib/infrastructure/tools/android_device_tool.dart`：新桥接方法、10 个新动作、executionRoute、结果解读、错误码
- `lib/infrastructure/tools/android_backup_actions.dart`：scope=apk、`apk-` 备份 ID、APK 预览与结果、错误码
- `lib/domain/device_automation.dart`：自动化动作标签改为“（Root/Shizuku）”；补齐两处 if 花括号
- `lib/presentation/settings/device_capabilities_page.dart`：见第 5 节

**新增测试**
- `test/android_device_non_root_test.dart`（9 个）：预览不访问原生层；通道快照；降级为设置页时 effect=unknown；PRIVILEGE_REQUIRED 映射；风险分级；VPN 断网；hosts 改走 VPN；权限页校验；APK 备份与安装恢复
- `test/device_capabilities_non_root_test.dart`（2 个）：加载时不探测 su；去授权；Shizuku 通道展示；VPN 开关

## 7. 验证结果

- `flutter analyze`：只剩 `test/motion_ui_regression_test.dart` 的 2 条 info（该文件不是本次修改）。
- `flutter test`：**1353 通过 / 1 失败**。失败项是既有的 `layering_test`（presentation→infrastructure import 数为 79，阈值 78；本次没有增加）。
- `flutter build apk --debug`：成功。
- `flutter build apk --release`：成功（21.1 MB）。
  - R8 mapping 确认 `PrivilegedShellService`、`IPrivilegedShell(+$Stub)`、`NetworkFilterVpnService`、`ApkInstallResultReceiver` 保留原类名，rikka.shizuku 的 11 个类都在。
  - 第一次构建因 Windows 锁住第三方插件 package_info_plus 的 Kotlin 缓存而失败；执行 `gradlew --stop` 后重试成功，与本次代码无关。

## 8. 尚未在真机验证（建议验收清单）

以下项目只能在真机上确认：
1. 未安装 Shizuku：能力页显示“未安装”，“打开”跳到下载页；set_wifi 降级为打开 Wi-Fi 面板，工具结果显示“尚未直接生效”。
2. Shizuku ADB 模式：授权弹窗出现；set_wifi / set_bluetooth / stop_app 的 `executedVia=shizuku`；clear_app_cache 在 Android 14+ 走 `pm clear --cache-only`；“授予权限”之后，动画倍率和勿扰改走系统 API。
3. Shizuku Root 模式：kill_process、应用数据备份走 uid 0。
4. 本地 VPN：
   - 首次弹出 VPN 授权；set_domain_block 后浏览器访问该域名失败。
   - set_app_network_block 后该应用断网，反转 enabled 后恢复；停用过滤器后全部恢复。
   - 重启手机后规则仍然生效。
5. APK 备份与恢复：
   - 备份含拆分包的应用（如 Google Play 安装的应用）。
   - 卸载后恢复，系统安装界面出现，backup_inspect 的 lastInstallResult=success。
   - 签名不同的备份被拦截。
6. 授予“所有文件访问”后，read_root_file / directory_size 读取 /sdcard 路径时 `executedVia=app`。

## 9. 已知限制

- ADB 模式的 Shizuku 不是 uid 0：hosts、iptables、/data/data 私有数据、重启 init 服务都做不到，会明确返回 `ROOT_REQUIRED` 并给出替代方案。
- 无 Root 时应用数据只能备份 APK，不包含数据。Android 已不允许普通应用读取其它应用的私有数据。
- 降级为“打开设置页”时，工具无法确认你是否真的完成了操作，所以 effect 为 `unknown`，模型需要重新读取状态确认。
- 预览里的执行通道来自最近一次状态快照（5 分钟内有效）；实际执行时会重新按顺序选择通道。

## 10. 自动化规则在无特权通道时的提示（2026-09-26 补充）

原则：没有 Root / Shizuku 时，规则动作可能只能“打开设置页”。创建或启用这类规则前必须先告诉你，但只审批一次。

流程：
1. 模型先调用 `android_automation` 的 `trigger_status`，结果里带 `privilegeRoutes`（当前可用通道）和 `fallbackPreview`（逐条列出会降级的动作）。这一步同时刷新 5 分钟内有效的通道快照。
2. `create_rule`，或 `set_rule_enabled` 且 `enabled=true`：如果快照显示有动作会降级，风险升为 `dangerous`，因此必须弹审批。审批卡片列出 `fallbackActions`，并注明“批准即表示知悉”。
3. 批准后，`authorizeAfterApproval` 自动写入 `acknowledgeFallback:true` 和 `acknowledgedFallbackActions`，不再二次确认。
4. 执行前 `_fallbackGate` 再检查一次：只有审批时没列出的新降级项（例如审批后 Shizuku 断开）才会被拦下，要求重新审批。
5. 没有快照时（未调用 `trigger_status`，或原生通道不可用），审批卡片提示“未检查特权通道”（`privilegeCheck`），不推断你已知悉。

各动作的降级判断（`lib/domain/device_automation.dart` 中的 `automationFallbackFor`，与原生降级顺序一致）：

| 动作 | 不降级的条件 | 降级后的行为 |
| --- | --- | --- |
| set_wifi | 有 shell 通道，或 Android 9 及以下 | 打开 Wi-Fi 面板，手动切换 |
| set_bluetooth | 有 shell 通道，或 Android 12 及以下且已授予蓝牙连接权限 | 打开蓝牙设置页或系统确认框 |
| set_do_not_disturb | 有 shell 通道，或已授予勿扰权限 | 打开勿扰授权页 |
| set_brightness / set_auto_rotate | 有 shell 通道，或已允许“修改系统设置” | 打开授权页 |
| stop_app | 有 shell 通道 | 结束后台进程并打开应用详情页，需要手动“强行停止” |
| clear_app_cache | 有 uid 0，或有 shell 通道且 Android 14 及以上 | 打开应用详情页，手动清除缓存 |

规则触发后仍是“通知 → 点按 → 预览确认 → 执行”，不会在后台静默执行。

改动文件：`lib/domain/device_automation.dart`、`lib/application/device_automation_service.dart`、`lib/application/android_automation_tool.dart`、`lib/infrastructure/tools/android_device_tool.dart`（`recentPrivilegeStatus`）、`lib/presentation/settings/device_automation_page.dart`、`test/automation_fallback_test.dart`。

验证（2026-09-26）：`automation_fallback_test.dart`、`device_automation_test.dart`、`android_device_non_root_test.dart` 共 28 个测试全部通过，`flutter analyze` 无问题。
