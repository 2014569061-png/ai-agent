# 免 Root 设备控制：接手文档（2026-09-24）

> **状态（2026-09-24 更新）：已完成。** 本文档中的待办已全部实施，交付说明见 `docs/mcp-non-root-device-control-2026-09-24.md`；草稿目录 `docs/handoff/non-root-2026-09-24/` 已删除，草稿已移入正式源码路径。以下内容仅作历史记录。

> 状态：**进行中，已暂停交接**。第二阶段还没改动仓库里任何会被编译的代码。
> 草稿源码放在 `docs/handoff/non-root-2026-09-24/`，这个目录不参与构建，还没编译验证过。
> 上一阶段（审计、备份/恢复、自动化）已完成，见 `docs/mcp-device-control-gap-completion-2026-09-24.md`。

---

## 1. 目标与已确认的决策

用户要求：8 大类设备控制能力（应用控制、文件/存储、系统状态、系统设置、进程/服务、网络诊断、自动化、备份/恢复）要尽量让**没有 Root 的用户**也能用。

用户已确认以下方案：

| 决策点 | 结论 |
| --- | --- |
| 提权通道 | 集成 **Shizuku**。降级顺序：**Root → Shizuku → 普通系统 API → 打开系统设置页让用户手动完成** |
| 防火墙 / hosts | **现在就做**本地 `VpnService` 拦截器：免 Root 的域名屏蔽 + 按应用断网 |
| 应用备份 | 免 Root 时备份 **APK（含 split APK）**，通过系统安装器恢复 |
| 目录备份 | 使用“所有文件访问”（`MANAGE_EXTERNAL_STORAGE`，已声明） |

必须继续遵守的规则（沿用第一阶段）：

- 风险分级 safe / requiresConfirmation / dangerous 不因换了执行通道而降低。
- 高危操作要二次确认，并展示命令、路径、范围和能否撤销。
- 只允许白名单命令模板。**模型不能拼接 `su -c` 或 shell 命令。**
- 审计日志要同时记录意图和实际执行（新增实际执行通道 `executedVia`）。
- 必须有预览模式。批量操作预览只列前 20 项，并给出总大小和剩余数量。
- 没有权限时必须返回明确的失败状态，不能假装成功。
- 要支持超时和取消。
- 要有撤销或恢复方案，不可逆的操作要标出来。
- 不做整机一键恢复。恢复前要展示文件列表、大小和覆盖范围。
- 自动化只能“通知 → 点击 → 预览/确认 → 执行”，不能在后台静默执行。

---

## 2. 进度一览

| # | 工作项 | 状态 | 说明 |
| --- | --- | --- | --- |
| 1 | 梳理所有 Root 依赖点，设计免 Root 替代方案 | ✅ 完成 | 结果见 §4 的映射表 |
| 2 | Shizuku 提权层（AIDL + UserService + PrivilegeManager） | 🟡 有草稿，未接入构建 | 草稿 3 个文件，见 §3 |
| 3 | 本地 VPN 过滤服务 | 🟡 有草稿，未接入构建 | `NetworkFilterVpnService.kt`，见 §3 |
| 4 | 设备控制通道改走提权层（`PrivilegedDeviceControl.kt`） | ⬜ 未开始 | 最大的一块，见 §5.2 |
| 5 | Gradle / Manifest / ProGuard 接入 | ⬜ 未开始 | 见 §5.1 |
| 6 | APK 备份与安装恢复、目录备份免 Root | ⬜ 未开始 | 见 §5.4 |
| 7 | Dart：错误码、预览执行通道、新动作、能力页、自动化文案 | ⬜ 未开始 | 见 §5.5 |
| 8 | 测试、`flutter analyze`、APK 构建、交付文档 | ⬜ 未开始 | 见 §6 |

---

## 3. 草稿文件（`docs/handoff/non-root-2026-09-24/` 下，保持目标相对路径）

| 草稿文件 | 目标位置 | 内容 | 待确认点 |
| --- | --- | --- | --- |
| `android/app/src/main/aidl/com/nexusagent/app/IPrivilegedShell.aidl` | 同名路径 | UserService 接口，见下方说明 | 需要 `buildFeatures { aidl = true }` |
| `.../PrivilegedShellService.kt` | `android/app/src/main/kotlin/com/nexusagent/app/` | UserService 实现，见下方说明 | 需要 ProGuard keep（§5.1） |
| `.../PrivilegeManager.kt` | 同上 | 提权层核心，见下方说明 | 用 Shizuku 13.1.5 编译核对 API 名 |
| `.../NetworkFilterVpnService.kt` | 同上 | `NetworkFilterStore`（规则与统计）+ `NetworkFilterVpnService`，见下方说明 | 只处理 IPv4 DNS，纯 IPv6 网络见 §7 |

**`IPrivilegedShell.aidl`** 定义以下方法：
- `start(cmd, stdin, stdout, stderr PFD)`
- `waitFor(handle, timeoutMs)`：超时返回 -1001，句柄未知返回 -1002
- `kill`
- `uid`
- `destroy = 16777114`

**`PrivilegedShellService.kt`**
- 继承 `IPrivilegedShell.Stub`，由 Shizuku 在 uid 2000 或 uid 0 的进程中加载。
- 用 `sh -c` 执行命令，三路流通过管道 `ParcelFileDescriptor` 转发。
- 同时提供空构造函数和带 `Context` 的构造函数。

**`PrivilegeManager.kt`**
- 执行通道 `PrivilegeBackend`：ROOT / SHIZUKU / APP。
- 权限要求 `PrivilegeRequirement`：
  - `ROOT_UID`：Root，或以 Root 模式运行的 Shizuku。
  - `SHELL`：Root 或任意模式的 Shizuku。
  - `STORAGE`：共享存储文件操作。已获“所有文件访问”时优先以应用自身身份执行，否则走 Root 或 Shizuku。
- Root 探测有缓存：已授权缓存 10 分钟，未授权缓存 60 秒。
- Shizuku 状态和授权请求：请求码 9301，回调在主线程执行。
- UserService 的绑定只能在后台线程发起，内部用 latch 等待，超时 8 秒。
- `start()` 返回统一的 `PrivilegedProcess`；`run()` 收集输出并处理超时。
- `permissionState()` 汇总特殊权限状态。
- `grantSelfPermissions()` 通过 Shizuku 或 Root 一键授予 `WRITE_SECURE_SETTINGS`、`READ_LOGS`、使用情况访问、`WRITE_SETTINGS`、勿扰权限、所有文件访问、安装未知应用。
- 统一的不可用错误码和提示：`ROOT_REQUIRED` / `PRIVILEGE_REQUIRED` / `STORAGE_PERMISSION_REQUIRED`，另附 details。

**`NetworkFilterVpnService.kt`** 有两种模式：

- **`dns` 模式**（有屏蔽域名时）：
  - 只路由虚拟 DNS 地址 10.111.222.1/32。
  - 命中屏蔽域名（含子域名）时返回 NXDOMAIN。
  - Android 10+ 用 `getConnectionOwnerUid` 识别查询来源，来自断网应用的查询一律返回 NXDOMAIN。
  - 其余查询转发到底层网络的 DNS，兜底上游为 223.5.5.5 / 119.29.29.29 / 1.1.1.1。
- **`app_full` 模式**（只有断网应用时）：
  - 用 `addAllowedApplication` 只把这些应用纳入 VPN，路由 0.0.0.0/0 和 ::/0，所有包直接丢弃，实现完整断网。
- 公共行为：
  - 本应用自身始终排除在 VPN 之外。
  - 系统收回 VPN（`onRevoke`）时自动关闭过滤。
  - 兼容系统的“始终开启的 VPN”。
  - `NetworkFilterStore.status()` 返回规则、统计、最近 30 条拦截和能力限制说明。

> 本地沙箱 `/home/user/work/android/...` 也有同样的草稿，内容一致。

---

## 4. Root 依赖点 → 免 Root 替代方案（设计已定）

来源是 `MainActivity.kt` 设备控制通道（`nexus/device_control`）。目前所有 Root 操作都经过 `runPrivilegedAppCommand()`，其中直接调用 `ProcessBuilder("su","-c",…)`。

⚠️ 这个函数目前**在主线程同步执行**，最长阻塞 5 秒。改造时必须移到后台线程，否则 Shizuku 绑定会死锁。

下表“权限要求”一列取值见 §3 的 `PrivilegeRequirement`。

| 原生方法 | 现有命令 | 权限要求 | 无特权时的降级（按顺序） |
| --- | --- | --- | --- |
| `setWifi` | `svc wifi enable/disable` | SHELL | API ≤28 用 `WifiManager.setWifiEnabled`（需补 `CHANGE_WIFI_STATE`）→ API 29+ 打开 `Settings.Panel.ACTION_WIFI` |
| `setBluetooth` | `cmd bluetooth_manager enable/disable` | SHELL | API ≤32 且有权限时用 `BluetoothAdapter.enable/disable` → 开启：有 `BLUETOOTH_CONNECT` 或 API <31 时用 `ACTION_REQUEST_ENABLE` → 否则打开蓝牙设置页 |
| `setAirplaneMode` | `cmd connectivity airplane-mode …` | SHELL | 打开 `ACTION_AIRPLANE_MODE_SETTINGS` |
| `setLocationEnabled` | `cmd location set-location-enabled …` | SHELL | 打开 `ACTION_LOCATION_SOURCE_SETTINGS` |
| `setDoNotDisturb` | `cmd notification set_dnd on/off` | SHELL | 有勿扰访问权限时用 `NotificationManager.setInterruptionFilter` → 打开 `ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS` |
| `setAnimationScale` | `settings put global *_scale` | SHELL | 已有 `WRITE_SECURE_SETTINGS`（可由 Shizuku 一次性授予）时用 `Settings.Global.putFloat` → 打开开发者选项 |
| `setFontScale` | 现为 `WRITE_SETTINGS` 优先、失败再走 su | SHELL | 顺序保持；最后打开 `ACTION_MANAGE_WRITE_SETTINGS` |
| `stopApp` | `am force-stop <pkg>` | SHELL | `killBackgroundProcesses`（部分效果，需补 `KILL_BACKGROUND_PROCESSES`）+ 打开应用详情页让用户点“强制停止”，返回 `partial` 和 `userActionRequired` |
| `restartApp` | `am force-stop` 后再启动 | SHELL | `killBackgroundProcesses` 后重新启动；如果目标有前台服务可能不会真正重启，返回 `partial` |
| `clearAppCache` | Root 脚本清理 `/data/user/0/<pkg>/{cache,code_cache}` | ROOT_UID | Shizuku 且 API 34+ 用 `pm clear --cache-only <pkg>`（**需真机确认**）→ 打开应用详情页（存储 → 清除缓存） |
| `killProcess` | 校验 `/proc/<pid>/cmdline` 后 `kill -TERM` | ROOT_UID | shell uid 杀不了其它应用的进程，返回 `ROOT_REQUIRED`，并建议改用 `stop_app` |
| `restartService` | `setprop ctl.restart logd/statsd` | ROOT_UID | 无降级，明确失败 |
| `refreshDns` | `ndc resolver flushdefaultif` | ROOT_UID | 无降级，提示切换飞行模式或 Wi-Fi |
| `setFirewallPortRule` | iptables REJECT | ROOT_UID | 本地 VPN 不做逐包转发，**明确不支持**，建议改用按应用断网或域名屏蔽 |
| `setHostsBlock` | 改写 `/system/etc/hosts` | ROOT_UID | 本地 VPN：`NetworkFilterStore.setDomain` + `NetworkFilterVpnService.sync`，`executedVia=vpn` |
| `runningProcesses` | 仅本应用进程 | 可选 SHELL | 有 SHELL 时用 `ps -A -o PID,UID,RSS,NAME` 解析全部进程，否则保持现状并注明范围 |
| `foregroundApps` / `recentApps` | 返回空或仅本应用 | — | 有使用情况访问时用 `UsageStatsManager`（`queryEvents` / `queryUsageStats`），可由 Shizuku 用 `appops set … GET_USAGE_STATS allow` 授予 |
| `logcatTail` / `crashLogs` | 本进程 logcat | 可选 SHELL | 有 SHELL 时通过 `PrivilegeManager.run` 执行 logcat 读取全量日志，否则保持只读本应用并注明 |
| `directorySize`、`read/list/write/delete/moveRootFile`、`compressRootFiles`、`extractRootArchive` | `su -c` 执行 du/cat/ls/printf/rm/mv/tar | STORAGE（传入 paths） | 路径在 `/sdcard` 或 `/storage/emulated/0` 且已获所有文件访问时，用应用自身 `sh -c` 执行同样的命令；`/data/local/tmp` 只能走 Root 或 Shizuku。`read` 改用 `head -c 65537` 限长 |
| `inspectAppPrivateData` | Root 只读 `/data/data` | ROOT_UID | 不改，保持 Root 专属 |

**关于降级顺序的说明（需要写进最终文档）**：共享存储文件操作刻意采用“应用自身权限优先”，也就是最小权限，这与用户要求的“Root 优先”不同。原因是两者结果相同，但应用自身权限风险更低，也不会产生 Root 属主的文件。其余操作严格按 Root → Shizuku → API → 设置页。

---

## 5. 剩余工作分解

### 5.1 构建接入

编辑 `android/app/build.gradle.kts`：

```kotlin
android {
    buildFeatures { aidl = true }
}
dependencies {
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
}
```

补充说明：
- `settings.gradle.kts` 已配置 `mavenCentral()`。远端主机已确认能访问 Maven Central，13.1.5 是最新版。
- AGP 8.13.0、Kotlin 2.2.20、compileSdk 37、Java 17。

新建 `android/app/proguard-rules.pro`。Flutter Gradle 插件会自动引用这个文件，release 构建开了 R8：

```
-keep class com.nexusagent.app.PrivilegedShellService { *; }
-keep class com.nexusagent.app.IPrivilegedShell { *; }
-keep class com.nexusagent.app.IPrivilegedShell$Stub { *; }
```

`AndroidManifest.xml` 需要补充以下内容。

**权限：**
- `KILL_BACKGROUND_PROCESSES`、`ACCESS_NOTIFICATION_POLICY`、`CHANGE_WIFI_STATE`、`BLUETOOTH_CONNECT`
- `BLUETOOTH` 和 `BLUETOOTH_ADMIN`，都加 `maxSdkVersion="30"`
- `PACKAGE_USAGE_STATS`、`WRITE_SECURE_SETTINGS`、`READ_LOGS`，这三个都要加 `tools:ignore="ProtectedPermissions"`

**Shizuku Provider：**

```xml
<provider android:name="rikka.shizuku.ShizukuProvider"
    android:authorities="${applicationId}.shizuku"
    android:multiprocess="false" android:enabled="true" android:exported="true"
    android:permission="android.permission.INTERACT_ACROSS_USERS_FULL" />
```

**VPN 服务：**

```xml
<service android:name=".NetworkFilterVpnService"
    android:permission="android.permission.BIND_VPN_SERVICE" android:exported="false">
    <intent-filter><action android:name="android.net.VpnService"/></intent-filter>
</service>
```

**`<queries>`：** 加 `<package android:name="moe.shizuku.privileged.api"/>`，用于判断 Shizuku 是否已安装。

### 5.2 `PrivilegedDeviceControl.kt`（新建，最大的一块）

建议结构，目的是避免在 3048 行的 `MainActivity.kt` 里到处改：

1. 新建 `class PrivilegedDeviceControl(activity: Activity)`：
   - 提供 `handles(method)`、`handle(call, result)`、`onActivityResult(requestCode, resultCode): Boolean`、`shutdown()`。
   - 内部使用 `Executors.newFixedThreadPool(2)`，所有结果通过 `mainHandler.post` 回到主线程。
2. 在 `MainActivity` 中接入：
   - `configureFlutterEngine` 里调用 `PrivilegeManager.init(this)`。
   - `nexus/device_control` 的 handler 开头加一句：如果 `privilegedControl.handles(call.method)`，就交给 `privilegedControl.handle(call, result)` 处理并返回。
   - 在 `onActivityResult` 和 `onDestroy` 中转发给 `privilegedControl`。
   - **然后删除 MainActivity 中对应的旧分支和旧函数**，列表见 §4。建议用按括号配对的脚本删除，删完 grep 确认没有残留的 `"su"`，`inspectAppPrivateData` 除外。
   - 参数校验函数（`isAllowedRootFilePath`、`isValidPackageName`、`isValidHostsDomain`、`isRestartableAndroidService` 等）要复制到新类中，保持规则完全一致。
3. 统一的返回结构：

   ```
   {
     applied: Bool,
     executedVia: "root|shizuku|app|api|settings|vpn",
     userActionRequired: Bool,
     partial: Bool,
     output: String,
     message: String,
     fallbackReason: String?   // 特权通道为什么没用上
   }
   ```

4. 错误码：
   - 通道不可用：`ROOT_REQUIRED` / `PRIVILEGE_REQUIRED` / `STORAGE_PERMISSION_REQUIRED`，details 使用 `PrivilegeManager.unavailableDetails`。
   - 超时：`TIMEOUT`。
   - Root 被拒：`ROOT_DENIED`。
   - SELinux：`SELINUX_DENIED`（stderr 含 `avc:` 或 `SELinux`）。
   - 权限拒绝：`PERMISSION_DENIED`。
   - 其他非零退出：Root 通道返回 `ROOT_COMMAND_FAILED`（兼容旧逻辑），其他通道返回 `PRIVILEGED_COMMAND_FAILED`。
5. 特权命令执行失败（比如旧系统没有 `cmd bluetooth_manager`）时，**继续尝试下一级降级**，并把失败原因写入 `fallbackReason`。
6. 新增原生方法：

   | 方法 | 作用 |
   | --- | --- |
   | `privilegeStatus` | 放到后台线程执行，因为会探测 su。返回 `{root: rootState(true), shizuku: shizukuState(), permissions: permissionState(), networkFilter: NetworkFilterStore.status()}` |
   | `requestShizukuPermission` | 请求 Shizuku 授权 |
   | `openShizuku` | 已安装则启动 Shizuku，否则打开 `SHIZUKU_DOWNLOAD_URL` |
   | `grantPermissionsViaPrivilege` | 调用 `grantSelfPermissions()` |
   | `openSpecialPermission(kind)` | 打开对应的特殊权限设置页，见下方 |
   | `openAppDetails(packageName)` | 打开应用详情页 |
   | `networkFilterStatus` | 返回 VPN 过滤状态 |
   | `setNetworkFilterEnabled(enabled)` | 开关 VPN 过滤 |
   | `setAppNetworkBlock(packageName, enabled)` | 按应用断网 |
   | `setDomainBlock(domain, enabled)` | 屏蔽域名 |

   `openSpecialPermission(kind)` 支持的 kind 如下：
   - `all_files`：`ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`
   - `usage`：`ACTION_USAGE_ACCESS_SETTINGS`
   - `notification_policy`：勿扰访问设置
   - `write_settings`：`ACTION_MANAGE_WRITE_SETTINGS`
   - `install_packages`：`ACTION_MANAGE_UNKNOWN_APP_SOURCES`
   - `vpn`：VPN 授权

### 5.3 VPN 授权流程

1. 调用 `VpnService.prepare(activity)`：
   - 返回 `null`：已授权，写入 `NetworkFilterStore.setEnabled(true)`，然后调用 `NetworkFilterVpnService.sync(ctx)`。
   - 返回 Intent：先暂存 `pendingVpnResult`，再用请求码 **9310** 调用 `startActivityForResult`。
2. 在 `onActivityResult(9310)` 中处理结果：
   - 用户允许：开启过滤并同步，然后回复 pending 的 result。
   - 用户拒绝：返回 `PERMISSION_DENIED`。
3. 一次只允许一个 pending 请求，其它请求直接返回 `BUSY`。
4. `setAppNetworkBlock` 和 `setDomainBlock`：先修改规则，再同步 VPN。返回值带 `previouslyBlocked` 用于撤销，同时带上 `mode` 和 `limitations`。
5. 规则全部清空后，`sync` 会自动停止 VPN。
6. 服务启动失败时，错误在 `lastError` 里，调用方需要轮询 `networkFilterStatus`（建议在启动后约 500ms 读一次再回复）。

### 5.4 备份（`DeviceBackupManager.kt`）

**APK 备份：**
- 新动作 `backupApk(packageName)`，或者给 `backupAppData` 增加 `scope=apk`。**建议用 scope=apk**，对模型更直观。
- 拷贝 `applicationInfo.sourceDir` 和 `splitSourceDirs` 下的所有文件，写 manifest，字段为：
  - `kind=apk`
  - `files`，每个文件带 sha256
  - `versionCode`、`versionName`
  - `restoreMethod=package_installer`
  - `restorable=true`
- 备份 ID 前缀用 `apk`。**同步修改 Kotlin 和 Dart 两边的 ID 正则**：`^(personal|app|prerestore|dir|apk)-\d{8}-\d{6}-[a-z0-9]{4}$`。

**APK 恢复：**
- 对 `apk-` 开头的 ID 执行 `restoreAppData` 时，走 `PackageInstaller` 会话：写入全部 APK 后 commit，commit 时带 `PendingIntent` 指向一个内部 BroadcastReceiver。
- 收到 `STATUS_PENDING_USER_ACTION` 时，启动 `EXTRA_INTENT` 让用户确认安装。
- 如果还没有“安装未知应用”权限，先返回 `PERMISSION_REQUIRED`，并提供 `openSpecialPermission(install_packages)`。
- 要说明限制：
  - 只恢复 APK，不恢复数据。
  - 签名不一致时系统会拒绝。
  - 版本比已安装的更低时通常会失败（需要先卸载，这属于不可逆操作，要提示用户）。

**目录备份：**
- 把 `runRootStreaming` 改成基于 `PrivilegeManager.start(STORAGE, script, paths=[path])` 的通用流式实现。
- APP 和 ROOT 通道是本地 Process。Shizuku 通道通过管道传 stdout，stdin 需要传 `acceptsStdin=true`。
- 已获所有文件访问时，即使没有 Root 也能执行 `tar -czf -`。

**应用数据备份和恢复：** 改用 `ROOT_UID`，这样 Root 模式的 Shizuku 也能用。ADB 模式的 Shizuku 读不了 `/data/data`，要明确报错。

### 5.5 Dart 侧

以下文件都在 `lib/` 下。

**`infrastructure/tools/android_device_tool.dart`**

- 错误映射（约 1617 行）：新增三个错误码并映射到 `ToolCodes.permissionRequired` 或 `rootRequired`：
  - `PRIVILEGE_REQUIRED`
  - `STORAGE_PERMISSION_REQUIRED`
  - `ROOT_REQUIRED`（主 switch 目前没有这个分支，会落到 `AndroidBackupActions.codeForPlatformError`）

  另外把 `PRIVILEGED_COMMAND_FAILED` 映射到 toolError。
- 成功结果中：
  - `userActionRequired == true` 时，使用 `ToolEffect.unknown`，提示语写成“已打开系统设置页，请手动完成”。
  - `partial == true` 时，要把部分生效说明清楚。
- `executedVia` 写入 `ToolResult.data`，审计层已经记录 data，需要确认 intent/execution 字段也带上这个值。
- `_rootAndroidActions`（约 444 行）从语义上改名为“需特权”：
  - 风险等级不变。
  - 预览文案把“需要 Root”改成“需要 Root 或 Shizuku；没有时 → <降级方式>”。
  - 在 `AndroidDevicePreviewTool` 中调用 `privilegeStatus`，预览里加上 `executionRoute`（预计走哪个通道）和 `fallback`。
- 新增动作：

  | 动作 | 风险等级 |
  | --- | --- |
  | `privilege_status` | safe |
  | `network_filter_status` | safe |
  | `set_app_network_block`（packageName, enabled） | dangerous，可撤销 |
  | `set_domain_block`（domain, enabled；也可以沿用 `set_hosts_block` 并自动降级到 VPN） | dangerous，可撤销 |
  | `grant_privileged_permissions` | dangerous，需说明授予了哪些权限 |

  这些动作都要登记到 `_mutatingAndroidActions` 和 schema 的 enum 中。
- Bridge 的 `rootStatus()` 保持兼容，另外新增 `privilegeStatus()`。

**`infrastructure/tools/android_backup_actions.dart`**
- `_appDataScopes` 增加 `apk`。
- `backup_app_data` 在 `scope=apk` 时，以及 `restore_app_data` 的 backupId 以 `apk-` 开头时，都**不算 Root 动作**。风险判断需要看参数，不能只看动作名。
- 预览中的 command、executionPlan 要写成 APK 拷贝和系统安装器，rollback 写“卸载或安装原版本 APK”。

**`domain/device_automation.dart`**
- `automationRootActions` 的文案从“（Root）”改成“（Root/Shizuku，或打开设置页）”。
- `set_do_not_disturb` 在有勿扰访问权限时不需要特权。
- 自动化执行结果里如果出现 `userActionRequired`，应记为 `partial`，并提示用户手动完成。

**`presentation/settings/device_capabilities_page.dart`**（未跟踪文件，归用户所有，改之前先 pull）

新增以下区块：
- **Shizuku**：已安装 / 运行中 / 已授权 / 模式（adb 或 root）/ 版本，以及“授权”“打开 Shizuku”两个按钮。
- **特殊权限清单**：每项有状态和“去开启”按钮，另有“通过 Shizuku 一键授予”按钮。
- **网络过滤**：开关、域名列表、断网应用列表、拦截统计、限制说明。
- **能力矩阵**：每类能力当前实际会走哪个通道。

**层级测试约束（`test/layering_test.dart`）：**
- infrastructure 不能 import application。
- presentation 对 infrastructure 的 import 已经是 79 条，超过阈值 78。这是用户未提交的改动造成的，**不要再增加**。新页面应通过已有的 bridge 或 service 访问。

---

## 6. 验证清单

1. `flutter analyze lib`：必须无问题。
2. 单元测试（新增）：
   - VPN：`NetworkFilterStore.matchesDomain`，可以抽成纯 Kotlin，也可以在 Dart 侧做同等的域名校验测试。
   - Dart：错误码映射，`scope=apk` 和 `apk-` ID 不算 Root，预览里带 `executionRoute`，新动作的风险等级。
   - 自动化：`userActionRequired` 结果记为 partial。
3. 全量 `flutter test`：已知的预存失败只有 1 个（layering_test 的 79>78），不能出现新的失败。
4. `flutter build apk --debug`：确认 AIDL 生成和 Shizuku 依赖能解析。建议再跑一次 `--release -PallowDebugSigning=true`，验证 R8 keep 规则。
5. **真机矩阵**（至少覆盖前两种环境）：

   | 环境 | 重点验证 |
   | --- | --- |
   | 无 Root、无 Shizuku | 每个设置类动作都能降级到 API 或设置页；文件操作在授予所有文件访问后可用；VPN 域名屏蔽和按应用断网；APK 备份和恢复 |
   | Shizuku（ADB 模式） | Wi-Fi、蓝牙、飞行模式、定位、勿扰、force-stop；`pm clear --cache-only`；ps / logcat；一键授权；ROOT_UID 类操作要明确报错 |
   | Shizuku（Root 模式） | ROOT_UID 类操作可用 |
   | Magisk / KernelSU Root | 行为与第一阶段一致 |

6. 交付文档：`docs/mcp-non-root-device-control-<日期>.md`，用 UTF-8 编码、LF 换行、行尾无空格。完成后在 set_todos 中把 lifecycle 设为 completed。

---

## 7. 风险与需要真机确认的点

- `pm clear --cache-only`：推测 Android 14+ 才有，需要真机确认；没有时降级到应用详情页。
- `cmd bluetooth_manager`：推测 Android 13+ 才有。旧系统可以尝试 `svc bluetooth enable/disable`（Android 11+），建议作为第二条命令模板。
- 特权命令失败要继续降级，不能直接报错（见 §5.2 第 5 点）。
- VPN 的已知限制：
  - 应用自带 DoH/DoT、系统“私人 DNS”指定了主机名、或直接用 IP 连接时，都可以绕过域名屏蔽。
  - 纯 IPv6 DNS 网络目前不拦截，因为虚拟 DNS 只有 IPv4。
  - 同时只能有一个 VPN。
  - Android 9 及以下无法按应用识别 DNS 来源，只能用 `app_full` 模式。
- Shizuku 服务在 ADB 模式下重启手机后会失效，需要用户重新启动 Shizuku。能力页要提示这一点。
- Android 13+ 应用读取 logcat 时，每次可能弹出系统授权框（READ_LOGS 的限制）。建议优先走 Shizuku 通道执行 logcat。
- `killBackgroundProcesses` 对前台服务无效，结果必须标 `partial`。
- Magisk 的 su 授权弹窗最长等待 10 秒，Root 探测超时就是 10 秒，所以探测必须放在后台线程。

---

## 8. 环境与工具备忘（给使用 ShunCode Bridge MCP 的接手者）

- 远端：Windows 上的 PortableGit bash，仓库在 `/d/AIIIIII/ai-agent/mobile_agent`。Flutter 3.47.2 位于 `/c/src/flutter/bin/flutter`，Dart 3.13.2。
- 仓库有大量未提交的改动，**不要覆盖或还原**。
- Gradle 输出是 GBK 编码，读取前先用 iconv 转码。
- 长时间构建用 nohup 放到后台跑，避免共享终端里批处理的 Y/N 提示中断进程。
- `apply_patch` 的锚点必须唯一；打补丁前先拉取最新文件；输出看起来异常时也要用 grep 或 analyze 再核实一次。
- Kotlin 代码中，Java 11+ 和 API 33+ 独有的 API（如 `OutputStream.nullOutputStream`、`readNBytes`）必须加版本判断。
- Flutter 3.47 中 `RadioListTile.groupValue` 已弃用，改用 `SegmentedButton`。
- `chat_run_execution.dart` 是 `part of 'chat_controller.dart'`，它需要的 import 要加到 `chat_controller.dart`。
