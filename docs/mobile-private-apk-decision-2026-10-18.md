# ADR：私有 APK 分发与设备能力边界

日期：2026-10-18  
状态：用户已确认「自用／私有 APK」；其他待定项见下文。  
关联：W01/W03/W05/W13；F02/F03/F04/F14。

## 已确定的决策

- 本轮以自用/私有 APK 为交付渠道，不将 Google Play 上架当作当前发布门禁。若以后增加商店分发，必须重新审查权限/自动化路线，不能直接沿用此结论。
- 仅在电脑上的 Nexus_Preview_API_36 模拟器验证；禁止操作真机。当前已核实模拟器序列号 emulator-5554，后续命令应重新查询核实并显式指定。
- 私有分发不免除 Android 的系统权限、锁屏、后台、麦克风、投屏或用户授权限制，不代表用户同意默认启用 Root/Shizuku/无障碍。
- 保留既有签名体系，不生成、替换或导出签名密钥；当前 debug 预览不能作为正式安装包签名/更新验收。

## 现有源码能力矩阵（不是设备实测支持表）

| 层级 | 源码证据 | 现状与执行边界 | 本轮实测 |
| --- | --- | --- | --- |
| 普通 Android API | MainActivity.kt：launchApp/launchAppByName、SAF 选择、ACTION_SEND、系统设置跳转 | 已有桥接；同名应用返回 ambiguous；跳转/启动不等于下游动作完成。需逐动作验证 | 仅页面导航与配置模板；没有启动其他应用或发送内容 |
| 特殊权限 | AndroidManifest.xml、PrivilegedDeviceControl.kt | 已声明文件访问、通知/勿扰、VPN、用量等相关能力；应在系统授权后实时复查。打开授权页是 userActionRequired，不是授权成功 | 未新增或授予任何特殊权限 |
| Shizuku | PrivilegeManager.kt、PrivilegedShellService.kt | 已有安装/服务存活/权限状态探测与受控路由；不自动安装或申请，不作为普通问答必要条件 | 仅读取源码与 mock 测试；未在模拟器启用 |
| Root | PrivilegeManager.kt、AndroidDeviceTool | 已有 Root 探测与动作白名单/预览/票据；不得把 adb 能力冒充应用 Root 能力 | 未执行 adb root、su、权限授予或系统变更 |

路径基于 `android/app/src/main/kotlin/com/nexusagent/app/`、`lib/infrastructure/tools/android_device_tool.dart` 和 `lib/application/device_action_runner.dart`。源码位置会变化，引用方法名优先于行号。

## 尚未实现/待验证

本轮 Main 源集 Kotlin 文件发现和关键标识检索未见 SpeechRecognizer、VoiceInteractionService、AccessibilityService 实现；主清单也未登记相应助手/无障碍服务。该结论是当前检索范围下的缺口，不代表所有依赖或平台分支均已完整审查。

- ASR 与音频焦点/来电/生命周期、前台连续对话仍需实现和验证。
- 默认助手系统角色/手势/锁屏、悬浮入口、实时相机/屏幕采集仍需实现和验证。
- 通用 UI 自主执行没有因为选私有渠道就自动可用；若新增 AccessibilityService，仍需明确数据范围、版本支持、显式启用、撤权、超时和人工接管。
- 精确提醒、五个具体连接器、真实远端与同步没有在本 ADR 中被标记完成。
- ARM64、厂商行为、真实性能/耗电在禁止操作真机约束下保持未验证。

## 本轮补充的动作确认安全改动

- `PreparedDeviceAction.reversible` 仅在预览明确给出布尔 true 时成立；缺失、字符串或其他类型不再默认宣传「可恢复」。`recoveryKnown` 区分已知不可撤销和恢复能力未知。
- 确认界面对未知恢复能力显示「恢复能力未知」，保守要求二次确认；既有已知可恢复/不可撤销文案保持。
- 确认面板替换一批预览动作时清除原二次确认勾选。此 UI 改动不替代底层 planId/参数绑定/一次性票据校验，也不宣称已经完成运行中纠正的全部竞态处理。
- 真实设备动作仍复用 DeviceActionRunner → AndroidDeviceTool 的预览、授权、执行、审计链路，没有新增绕过审批的执行入口。

## 下一步需确定

- 语音/多模态采用的服务与成本预算；模拟器真实模型测试可否使用当前配置、允许的调用次数。
- 首个真实远程执行器宿主和部署方式。自托管与公共托管是不同决策；私有 APK 不意味着授权开通任何付费服务或将电脑端口暴露公网。
