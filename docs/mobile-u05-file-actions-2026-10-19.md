# U05 接手续做：真实文件结果卡动作（2026-10-19）

承接 `mobile-next-major-handoff-2026-10-19-evening.md`。本轮只推进 U05 的文件子集，**不关闭 U05/W19，也不改变 releaseReady=false**。

## 实施

- `lib/application/artifact_result_actions.dart`：接入文件预览/分享执行适配器。按真实成果 ID 读取记录，重新校验私有副本的 SHA-256、大小、路径和前台/只读状态；不使用卡片快照中的路径、URL、命令。其余动作拒绝执行。
- `lib/presentation/artifacts/artifact_center_page.dart`：生产默认服务使用该适配器。预览复用真实成果详情，文本/HTML 以文本展示（不运行脚本）；从结果卡打开时禁用详情内的分享，避免绕过确认。分享使用真实 SharePlus 系统接口。
- 修复确认后不继续执行：原 `pendingConfirmation` 只看 `pending_confirm` 状态，导致已有 approvalId 时页面仍提前 return。现在有审批凭据后进入执行，执行时仍检查审批期限、卡片修订、资源、权限。
- 分享被取消或平台无法确认结果时不记成功；成功也只表示系统交接，不声称接收方已保存或收到。
- 显式文件点击使用新的用户意图幂等键，同一意图在准备、确认、执行间沿用同一动作 ID；执行中重复点击被 UI 和服务去重。取消后用户可明确重试并重新确认，不自动重放旧分享。
- `ArtifactService.record()` 将成果索引与文件卡放在同一数据库事务发布。失败回滚新记录并移除本次独有副本，保留原工作区与历史成果。只对新成果自动生成卡，未批量回填旧成果。
- `AppDatabase.clearAllUserData()` 同步清除结果卡和动作记录，避免清库/恢复后残留文件名、旧审批和交付状态。
- 源码原本已有“返回关联任务”，保留其实现；交接中的“未回链任务”是旧快照，本轮没有重复实现。

未升级数据库 schema（仍为 32），未重新生成 Drift 文件；没有改依赖、原生权限或系统助手设置。

## 验证与口径

1. `tool/verify_artifact_actions_emulator.py`：**34/34**。其中 17 项使用模拟器内独有临时目录和真实文件 SQLite（含关库重开、发布失败回滚、清库），另 17 项复跑原结果卡服务合同。预览/分享平台边界在此套件中仍是计数回调，不能作为真实系统交付证据。
2. 原成果合同在同一运行时 **12/12**：复制完整性、源文件变化、缺失、篡改、路径/链接逃逸、发布失败等。
3. `tool/verify_artifact_actions_ui_emulator.py`：真实只读预览、返回后成功反馈、确认弹窗取消不派发、两次实际 Android 分享面板打开、两次系统取消不记成功、取消后显式重试均通过。仅使用合成 sample.txt，**未选择任何接收方**，未发送文件、未发起模型请求。
4. 修改后全仓静态分析通过；最终检查日志见下表。截图已实看，无本轮可见溢出。

**重要：本轮复用现有预览热重载，没有重建/安装 APK。** 驱动逐个读取 VM 的 live script source，与当前工作区源码逐字核对并记录 SHA-256。报告使用 `baseApkSha256`（原安装基包）和 `liveSourceSha256`（热重载代码），设置 `notFinalApkSignOff=true`。不得声称新增代码已包含在 `8ebe5948…` APK 中，也不得把这批数字加到历史 371/371 后冒充同一最终 APK 总数。

| 文件 | 用途 |
| --- | --- |
| `local/temp/u05-file-actions-contract-20261019.json` | 34 项检查，含实时源码摘要 |
| `local/temp/u05-artifact-regression-20261019.json` | 原成果 12 项回归 |
| `local/temp/u05-file-actions-ui-20261019.json` | 真实页面与系统分享/取消/重试报告 |
| `local/temp/u05-file-actions-final-analyze-20261019.log` | 最终静态分析 |
| `local/temp/u05-file-preview-20261019.png` | 已校验副本的实际文本预览 |
| `local/temp/u05-file-share-pending-20261019.png` | 待确认 |
| `local/temp/u05-file-sharesheet-{1,2}-20261019.png` | 两次实际系统分享面板 |
| `local/temp/u05-file-share-cancelled-{1,2}-20261019.png` | 取消后如实反馈 |

复跑（在项目根目录，先确认现有预览已完成热重载）：

```powershell
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONDONTWRITEBYTECODE = '1'
python tool/verify_artifact_actions_emulator.py
python tool/verify_artifact_actions_ui_emulator.py
```

## 未完成与下一步

- 结果卡确认仍使用页面内限时审批，**未接统一 ApprovalBridge/通知审批**。
- 提醒、日历、路线、工作流、代码差异等执行器未接；未以任意快照 URL 或伪成功补齐。
- 成果仍按不可变 ID 建模、版本 1。实际副本篡改现在会进入 conflict、缺失进入 stale，但没有建立同 ID 元数据修订/跨设备版本协议。
- 结果卡尚未纳入聊天时间线；历史成果未回填卡。结果卡与动作的备份/迁移语义仍待统一，本轮不增加备份恢复后的自动执行。
- 未验证真实接收方保存、ARM64 真机、后台/锁屏、全量移动 UI、全量测试及最终 APK。原五条最终 APK UI 报告仍只是旧制品证据。
- 下一优先级：U04 的个人上下文墓碑与真实 SQLite 集成合同；其后接统一审批与结果卡时间线。U06/U07 的连续语音恢复应基于已有 TaskService 扩展，不能按交接里的“无实现”重写现有任务服务。

没有操作真机、追加模型调用、提交、推送、重置或清理其他工作的改动。现有 Android 预览保持运行。
