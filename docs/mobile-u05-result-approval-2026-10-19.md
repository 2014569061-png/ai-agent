# U05 增量：结果卡接入统一审批（2026-10-19）

## 本轮实现

- 成果中心不再用页面弹窗自行生成 `ui-confirm-*` 授权。前台复用 `ToolApprovalSheet`，后台复用 `ApprovalBridge` / `pending_approvals`，仅允许本次批准，不写会话、计划或永久信任。
- 审批绑定 action ID/准备版本、卡片 ID/版本、资源类型/ID/版本、动作类型、风险和当前 isolate 所有者；持久行与调用方 DTO 分离。伪造 DTO、重启后的旧授权、过期、撤回、改目标均不可执行。
- SQL 默认执行服务在确认、领取执行权和最终分享/预览边界检查审批。页面退出、资源校验期间发生变化或审批被移除时停止交接。
- 动作状态写入改为事务内 CAS；领取执行权同时检查当前卡片，审批校验也在该事务内进行。多个服务/SQLite 连接不可重复领取动作；SQLite busy/locked 的竞争失败方安全返回冲突，不重放。迟到结果不重新插入已被删除的动作。
- 等待期间资源变化或页面销毁会失效审批，只移除自己持有的 sheet 路由，不误弹出覆盖层；结束后清理握手行。审计只记动作类型/请求 ID/裁决，不记文件名。通知摘要不含目标名称。
- 既有运行审批通过 `ApprovalDecisionScope` 共用最小生命周期接口；原计划授权语义不扩大。数据库 schema 仍为 32。

## 本轮验证与口径

| 验证 | 结果 | 证据 |
| --- | --- | --- |
| 新增审批合同 | 27/27 | `local/temp/u05-result-approval-contract-20261019.json` |
| 原文件动作回归 | 34/34 | `local/temp/u05-result-approval-regressions-20261019.json` |
| 原成果合同回归 | 12/12 | 同上 |
| 个人上下文回归 | 51/51 | 同上 |
| 手机统一审批 UI | 4/4 场景 | `local/temp/u05-result-approval-ui-20261019.json` |
| 原计划审批 UI 回归 | 2/2 场景 | `local/temp/u05-approval-plan-ui-regression-20261019.json` |
| 静态分析 | 零问题 | `local/temp/u05-approval-analyze-20261019.log` |

新增合同在 Android isolate 内用自有临时 SQLite 文件运行，包括双连接竞争、首次裁决不可覆盖、超时/清数据/旧回调以及最终交接前的三类失效。通知测试是注入的通知传输 fixture，不发送 OS 通知。

实际 UI 覆盖：拒绝零执行；一次批准后打开真实 Android 系统分享并取消（无接收方，不能记成功）；审批被覆盖时更改资源只撤掉旧审批；页面销毁清理审批和根导航 sheet。截图：`local/temp/u05-result-approval-{sheet,sharesheet,stale}-20261019.png`。

驱动逐文件比较实时 VM 与磁盘源码并记录 SHA-256。模型调用为 0；未运行宿主业务测试；未操作真机、默认助手或运行时权限；未 reset/提交/推送。

最终串行复跑全部通过，证据索引为 `local/temp/u05-result-approval-evidence-20261019.json`：已断言四份报告的最终源码哈希一致、安装包与磁盘哈希一致、全部检查通过及静态分析零问题。预览保留运行中，隔离页面、审批和临时库均已关闭。

### APK 与预览特别说明

验收期间共享预览发生重建/重启（`local/temp/preview-detached-20261019-2020.log`）。本轮实测磁盘和设备安装包均为：

`3ac2ff383398b13c75f75768911b63cf262e1fd85d6bbb8aa6cffcba85066ed0`

其后仍使用自动热重载；报告标记 `runtime=existing_debug_preview_hot_reload`、`notFinalApkSignOff=true`。**不能把这次源码验证说成该 APK 完整签收，也不能说新增内容已在历史 `8ebe5948…` 包中签收。** 未覆盖原来的 371/371 或五条最终 APK UI 证据，新回归使用独立文件，不累加完成率。

## 仍未完成

- 除文件以外的提醒/日历/路线/工作流/差异操作真实执行器；聊天时间线结果卡；真正的跨设备资源版本同步。
- 本次通知接线尚无真实锁屏/通知动作端到端验收；fixture 不证明 OS 通知权限、投递或锁屏交互可用。
- 页面所属审批不可跨进程恢复；应用重启后必须重新发起。待执行列表/跨进程恢复不是本轮范围。
- U04 备份格式、U06 连续语音/多模态、U07 前台服务与恢复及全版设备矩阵等仍未闭环。

`releaseReady=false`；W00–W21 和完整 A/S 验收不因本轮增量关闭。

## 复跑

使用工作区已有预览，先核对设备 `emulator-5554` 属于 `Nexus_Preview_API_36`。等待预览显示 Hot reload complete，单独运行：

```powershell
$env:PUB_CACHE="$PWD/local/pub-cache"
$env:TEMP="$PWD/local/temp"; $env:TMP=$env:TEMP
$env:PYTHONIOENCODING='utf-8'; $env:PYTHONDONTWRITEBYTECODE='1'
python tool/verify_result_action_approval_emulator.py
python tool/verify_result_action_approval_ui_emulator.py
python tool/verify_result_action_approval_regressions.py
python tool/verify_result_approval_plan_ui_regression.py
flutter analyze --no-pub
```

不要并行运行 UI 驱动与 SQL 合同批次，也不要为复跑重新安装 APK。曾在并行 SQL 回归时遇到 sheet 动画掉帧，按钮坐标尚未稳定就点击导致驱动等待失败；驱动现先观察两次稳定坐标，再发出唯一一次点击，不自动重放批准动作。
