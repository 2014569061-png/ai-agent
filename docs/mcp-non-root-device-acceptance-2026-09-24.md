# 免 Root 设备控制：真机验收脚本（2026-09-24）

> 配套文档：`docs/mcp-non-root-device-control-2026-09-24.md`（功能说明）。
> 本文按“准备 → 场景 A–H → 结果登记”组织。每一步都写了**操作**、**预期**和**adb 核对命令**。
> 在“结果”列填 ✅ / ❌ / ⚠️（部分通过），失败的步骤把工具返回的 JSON 贴到第 10 节。

## 0. 准备

| 项目 | 说明 |
|---|---|
| 安装包 | `build/app/outputs/flutter-apk/app-debug.apk`（包名 `com.nexusagent.app.debug`）。验证 R8 时用 `app-release.apk`（包名 `com.nexusagent.app`） |
| 设备 | 最好准备两台：一台 **Android 14+ 无 Root**（主测），一台有 Root（Magisk/KernelSU，用于回归）。只有一台无 Root 设备时，场景 G 跳过 |
| 电脑 | 已安装 adb，手机已开 USB 调试 |
| 测试应用 | 选一个可以随意卸载的普通应用，下文记为 `$APP`（例如 `com.example.testapp`）。另选一个**从 Google Play 安装、带拆分 APK** 的应用做场景 E |
| Shizuku | 从 https://shizuku.rikka.app/download/ 下载。场景 A 开始前**先不要安装** |

为方便复制命令，先在电脑终端设置变量：

```bash
PKG=com.nexusagent.app.debug
APP=com.example.testapp            # 换成你的测试应用
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb logcat -c
# 另开一个终端持续看日志：
adb logcat | grep -iE "nexus|shizuku|PrivilegedShell|NetworkFilter|PackageInstaller"
```

智能体会先调用 `android_device_preview`，审批后再执行。每次执行后，查看工具结果里的 `executedVia`、`userActionRequired` 和 `effect`。下文用 **说：** 标出要在聊天里输入的话。

---

## A. 无 Root、未安装 Shizuku（最差情况）

| # | 操作 | 预期 | adb 核对 | 结果 |
|---|---|---|---|---|
| A1 | 打开 设置 → 设备能力 | 页面没有弹出任何 Root 授权框。“免 Root 通道”显示 **未安装**，按钮为“打开”。“当前执行通道”显示 **仅降级** 和“（Root 未检查）” | — | |
| A2 | 点 Shizuku 行的“打开” | 浏览器打开 Shizuku 下载页 | — | |
| A3 | **说：**“查看一下设备的权限状态” | 调用 `privilege_status`（风险 safe，不需要审批），`routes.shell = null` | — | |
| A4 | **说：**“关闭 Wi-Fi” | 预览显示 `executionRoute.route = fallback`，fallback 写着“打开 Wi-Fi 面板”。审批后系统弹出 Wi-Fi 面板。工具结果以“尚未直接生效”开头，`effect = unknown`，`executedVia = settings` | `adb shell settings get global wifi_on`：在你手动切换前不变 | |
| A5 | **说：**“开启勿扰模式” | 未授予勿扰权限时，打开勿扰授权页，结果为“尚未直接生效” | `adb shell settings get global zen_mode`：保持 0 | |
| A6 | **说：**“强行停止 $APP” | 结果 `partial = true`，并打开应用详情页；消息以“部分生效”开头 | `adb shell pidof $APP`：后台进程已结束；前台进程可能还在 | |
| A7 | **说：**“清理 $APP 的缓存” | 打开应用详情页，结果为“尚未直接生效” | — | |
| A8 | **说：**“结束进程 xxx”（先说“列出运行中的进程”，再挑一个 PID） | 进程列表能返回（ActivityManager 或 UsageStats）；结束进程返回 **ROOT_REQUIRED**，并说明需要 uid 0 | — | |
| A9 | **说：**“刷新 DNS 缓存” | 返回 ROOT_REQUIRED，并建议切换一次飞行模式或 Wi-Fi | — | |
| A10 | **说：**“备份 $APP 的完整数据” | 返回 ROOT_REQUIRED，并建议改用 scope=apk | — | |
| A11 | **说：**“读取 /sdcard/Download 目录的大小”（此时尚未授予所有文件访问） | 返回 PERMISSION_REQUIRED，并提示去授予“所有文件访问” | — | |

## B. 系统特殊权限（无 Root、无 Shizuku）

| # | 操作 | 预期 | adb 核对 | 结果 |
|---|---|---|---|---|
| B1 | 设备能力 → 系统特殊权限 → “所有文件访问”点“去授权” | 跳到系统授权页；授权后返回，页面**自动刷新**为“已允许” | `adb shell appops get $PKG MANAGE_EXTERNAL_STORAGE` → allow | |
| B2 | 重做 A11 | 成功返回大小，`executedVia = app` | — | |
| B3 | **说：**“列出 /sdcard/Download 里的文件”，再说“把其中某个测试文件移动到 /sdcard/Documents” | 两次的 `executedVia` 都是 `app`；移动需要审批，预览列出源和目标 | `adb shell ls /sdcard/Documents` | |
| B4 | “勿扰权限”去授权，允许后重做 A5 | 直接生效，`executedVia = api` | `zen_mode` 变为非 0 | |
| B5 | “修改系统设置”去授权，然后**说：**“把亮度调到 30%” | 直接生效 | `adb shell settings get system screen_brightness` | |
| B6 | “使用情况访问”去授权，然后**说：**“现在前台是什么应用” | 能返回前台应用 | — | |
| B7 | 检查 WRITE_SECURE_SETTINGS 和 READ_LOGS 两行 | 显示“未允许”，**没有**“去授权”按钮 | — | |

## C. Shizuku ADB 模式（uid 2000）

先安装 Shizuku。Android 11+ 按 Shizuku 内的“无线调试”向导启动；也可以用电脑启动：
`adb shell sh /sdcard/Android/data/moe.shizuku.privileged.api/start.sh`（具体命令以 Shizuku 应用内显示的为准）。

| # | 操作 | 预期 | adb 核对 | 结果 |
|---|---|---|---|---|
| C1 | Shizuku 启动后回到设备能力页 | 自动刷新为 **待授权**，按钮为“授权” | — | |
| C2 | 点“授权” | Shizuku 弹窗出现；允许后显示 **可用 · ADB 模式**，“当前执行通道”里系统命令为 Shizuku | — | |
| C3 | 重做 A4（关闭 Wi-Fi） | 直接生效，`executedVia = shizuku`，`effect = applied`，**不再**打开面板 | `wifi_on` → 0 | |
| C4 | **说：**“打开蓝牙”，再说“关闭蓝牙” | 两次都是 `executedVia = shizuku` | `adb shell settings get global bluetooth_on` | |
| C5 | **说：**“打开飞行模式”，确认后再说“关闭飞行模式” | 两次都是 shizuku；预览里标注 dangerous | `adb shell settings get global airplane_mode_on` | |
| C6 | 重做 A6（强行停止） | 完整生效，`executedVia = shizuku`，不再有 partial | `adb shell pidof $APP` 为空 | |
| C7 | 重做 A7（清缓存，**Android 14+**） | `executedVia = shizuku`，使用 `pm clear --cache-only`。Android 13 及以下仍打开详情页 | 设置 → 应用 → 存储，缓存为 0 | |
| C8 | **说：**“看最近 100 行 logcat” | 返回完整系统日志（不只是本应用） | — | |
| C9 | 重做 A8 / A9 | 仍然返回 ROOT_REQUIRED，提示“ADB 模式的 Shizuku 无权执行” | — | |
| C10 | 设备能力页点“授予权限”（或**说：**“用 Shizuku 给自己授予系统权限”，这项为 dangerous，需要审批） | 提示已授予 N 项；WRITE_SECURE_SETTINGS 和 READ_LOGS 变为“已允许” | `adb shell dumpsys package $PKG \| grep -E "WRITE_SECURE_SETTINGS\|READ_LOGS"` → granted=true | |
| C11 | 在 Shizuku 里停止服务，然后**说：**“把动画倍率设为 0.5” | 因为 C10 已授予 WRITE_SECURE_SETTINGS，所以 Shizuku 停了也能直接生效（`executedVia = api`） | `adb shell settings get global window_animation_scale` → 0.5 | |
| C12 | Shizuku 停止状态下重做 C3 | 回到降级（打开面板）。前后两次预览的 `executionRoute` 不同（预览以最近一次状态为准，先刷新设备能力页） | — | |

## D. 本地 VPN 过滤器

| # | 操作 | 预期 | adb 核对 | 结果 |
|---|---|---|---|---|
| D1 | **说：**“屏蔽域名 example.org” | 预览为 dangerous 且可逆；首次会弹出**系统 VPN 连接请求**，同意后结果 `executedVia = vpn` | `adb shell dumpsys connectivity \| grep -i "VPN"` 能看到 NEXUS 的 VPN | |
| D2 | 在手机浏览器打开 https://example.org | 无法解析 | `adb shell ping -c1 example.org` → unknown host | |
| D3 | 打开其它网站 | 正常访问（其余 DNS 正常转发） | `adb shell ping -c1 www.baidu.com` | |
| D4 | **说：**“给 $APP 断网” | 结果 `executedVia = vpn`，带 `undo`；该应用无法联网，其它应用正常 | — | |
| D5 | **说：**“恢复 $APP 的网络” | 恢复联网 | — | |
| D6 | 删除所有域名规则，只保留一个断网应用 | 状态里 `mode = app_full`；该应用**直连 IP 也不通** | `network_filter_status` 里 mode 的值 | |
| D7 | 设备能力页关闭 VPN 开关 | 所有规则立即失效，规则列表保留；重新打开后恢复 | — | |
| D8 | 保持开启状态，重启手机 | 开机后 VPN 自动恢复，规则仍然生效 | 重复 D2 | |
| D9 | 启用 VPN 时再开另一个 VPN 应用 | 系统只保留一个 VPN；NEXUS 的状态里 `running = false`，并记录 lastError 或提示 | — | |
| D10 | **说：**“禁止 NEXUS 自己联网” | 被拒绝（INVALID_ARGS：不能对 NEXUS 自身断网） | — | |
| D11 | 无 Root 时**说：**“用 hosts 屏蔽 example.net” | 自动改用本地 VPN；消息里写“无 Root，已改用本地 VPN DNS 屏蔽” | — | |

## E. APK 备份与安装恢复（无 Root）

| # | 操作 | 预期 | adb 核对 | 结果 |
|---|---|---|---|---|
| E1 | **说：**“备份 $SPLIT_APP 的安装包”（带拆分 APK 的应用） | 风险为 requiresConfirmation（不是 dangerous）；预览目标写“安装包（base + 拆分 APK）”，没有 su 命令。结果为“已备份安装包 apk-…（N 个 APK）”，N 应大于 1 | `adb shell ls /sdcard/Android/data/$PKG/files/backups/` 能看到 `apk-*` 目录 | |
| E2 | **说：**“查看这个备份的详情” | 返回 `kind = apk`、`signatureMatches = true`、installedVersion | — | |
| E3 | 卸载该应用：`adb uninstall $SPLIT_APP` | — | — | |
| E4 | **说：**“从刚才的备份恢复这个应用” | 预览写“通过系统安装器安装”，并列出文件和数量。未允许“安装未知应用”时，预览里有 installPermissionHint，执行时系统先要求授权 | — | |
| E5 | 在系统安装界面点“安装” | 安装成功。工具结果 `effect = unknown`，提示在系统界面确认；手机弹出 Toast“安装包恢复完成” | `adb shell pm list packages \| grep $SPLIT_APP` | |
| E6 | **说：**“再看一下备份详情” | `lastInstallResult.status = success` | — | |
| E7 | 重复 E4，在系统界面点“取消” | Toast 提示“用户取消了安装”；lastInstallResult 为 aborted | — | |
| E8 | 安装一个**签名不同**的同包名版本（例如 debug 签名和 release 签名对调），再恢复旧备份 | 预览的 compatibility 显示签名不一致，执行被拦截（RESTORE_BLOCKED），不会弹出安装界面 | — | |

## F. 设备自动化的降级提示（本次新增）

| # | 操作 | 预期 | 结果 |
|---|---|---|---|
| F1 | 无 Root、无 Shizuku、未授予勿扰权限。**说：**“每天 23 点自动开启勿扰” | 审批后工具返回 `requiresAcknowledgement = true`，规则**没有创建**。智能体转述“勿扰动作触发时只能打开勿扰授权页”，并询问你是否同意 | |
| F2 | 回答“同意，仍然创建” | 智能体带 `acknowledgeFallback = true` 重新调用；审批详情里出现 fallbackNotice，规则创建成功 | |
| F3 | 设置 → 设备自动化 → 从模板创建“定时开启勿扰” | 弹窗列出降级动作，按钮为“创建”；点取消则不创建 | |
| F4 | 暂停一条含 Wi-Fi 动作的规则，再在页面上重新启用 | 弹出“启用规则”提示，按钮为“仍然启用” | |
| F5 | 授予勿扰权限（B4）后重做 F1 | 不再提示，直接创建 | |
| F6 | 连接 Shizuku（C2）后启用含 Wi-Fi 动作的规则 | 不再提示 | |

## G. Root 设备回归（有 Root 时执行）

| # | 操作 | 预期 | 结果 |
|---|---|---|---|
| G1 | 打开设备能力页 | **不弹** Root 授权框。点“检查 Root”后才弹出；授权后“当前执行通道”变为 Root | |
| G2 | 重做 A4、A6、A7、A8、A9、A10 | 全部直接生效，`executedVia = root` | |
| G3 | 同时安装 Shizuku 并授权 | 仍然优先使用 Root（`executedVia = root`） | |
| G4 | 应用数据备份（config），然后恢复 | 与第一期行为一致；恢复前会生成快照，结果里有 undoBackupId | |
| G5 | 在 Magisk 中拒绝 NEXUS 的 Root | 需要 shell 的动作自动改走 Shizuku 或降级；需要 uid 0 的动作返回 ROOT_DENIED 或 ROOT_REQUIRED | |
| G6 | 从未点过“检查 Root”的新安装，直接让智能体创建含 Wi-Fi 动作的自动化规则 | 因为设备上存在 su，会探测一次 Root（可能弹授权框，这是预期行为）；授权后不再有降级提示 | |

## H. release 包专项（R8）

| # | 操作 | 预期 | 结果 |
|---|---|---|---|
| H1 | 安装 `app-release.apk`，重做 C2、C3 | Shizuku UserService 正常绑定，没有 ClassNotFoundException | |
| H2 | 重做 D1 和 E5 | VPN 服务和安装回调在 release 包中都正常 | |

日志中出现以下内容即视为失败：`ClassNotFoundException`、`NoSuchMethodError`、`IPrivilegedShell`、`Unable to instantiate service`。

---

## 9. 结果登记

| 场景 | 通过 | 失败 | 部分 | 备注 |
|---|---|---|---|---|
| A 最差情况 | | | | |
| B 特殊权限 | | | | |
| C Shizuku ADB | | | | |
| D 本地 VPN | | | | |
| E APK 恢复 | | | | |
| F 自动化提示 | | | | |
| G Root 回归 | | | | |
| H release | | | | |

设备型号 / Android 版本 / ROM：______________________　Shizuku 版本：________

## 10. 失败记录模板

```
步骤编号：
你说的话 / 点击的按钮：
工具结果 JSON（code、message、data.executedVia、data.fallbackReason、data.nativeCode）：
logcat 片段（adb logcat -d | grep -iE "nexus|shizuku|NetworkFilter" | tail -50）：
```

把这些信息发给我，我就能按 `executedVia` 和 `fallbackReason` 定位问题出在哪一层降级。
