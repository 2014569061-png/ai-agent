# 移动端 Agent 初审整改与验收记录

## 范围与状态

本轮按私有 APK、自带 Key（BYOK）、逐次审批推进；仅允许模拟器隔离验证，不授权真机、真实模型调用、付费部署或公网暴露。保留原工作树改动，不提交、不推送、不替换签名。

**本记录不是整版上线签收。** 代码整改、单测通过、模拟器页面通过、真实模型任务成功、ARM64/厂商验收是不同层级，不相互替代。费用续办后最新定向回归99项、页面/弹窗24项通过；上一批结果保留历史含义，未完成事项不称“全部完成”。详见[本机费用闭环](mobile-cost-loop.md)。

## 对初审结论的更正

- 锁屏直接批准在当前源码已经禁用：`approval_bridge.dart` 后台入口仅接受拒绝，`notification_service.dart` 仅显示打开查看/拒绝；本轮未重复实现该能力。
- `run_recovery_safety.dart` 已有持久 dispatch、副作用未知及断点一致性检查；不能称为缺失。定向恢复测试纳入回归。
- 费用模型已有事务性持久预留及未知费用保留机制；首批补解释和显示，用户选择费用优先后继续扩展关联、pending状态和人工核对，不重复构造支付/计费服务。
- `android_system_editor_actions.dart` 已区分 `handoffRequested` 与 `businessCompleted=false`，并明确禁止盲目重试；保留该契约。
- 远程连接页只有诊断和本地状态，不能称为完成远端设备配对、续租或撤销。此次修正文案和切换目标清理旧状态。
- 既有最终验收 JSON 的六组契约通过，但总 `passed=false` 且 `errorType=TimeoutException`；不能复用为发布通过证据。

## 逐项处置

| 初审ID | 实际处置 | 状态与剩余边界 |
|---|---|---|
| R01 发布证据 | 新增 `tool/release_evidence_gate.py`，Release 上传前接入；核对 commit、APK/证书/源码/报告哈希、逐项门禁；缺失证据失败关闭 | 门禁代码已落地；正式候选包及完整证据未生成，发布仍阻塞 |
| R02 ARM64/进程/功耗 | 不用模拟器冒充真机门禁；列入必须通过的证据类别 | 受禁止真机约束阻塞，未完成 |
| R03 终端边界 | `ApprovalPolicy` 对真实工具名 terminal 强制逐次确认，即使 fullAccess/已有信任；管线传入工具名；前台认证守卫禁止会话/永久终端授权 | 代码已落地并有定向测试；不是 OS 沙箱，也未声称任意脚本安全 |
| R04 锁屏审批 | 核对已有后台拒绝、旧动作过滤、前台身份验证实现；终端纳入 fresh authentication；修正 README | 已有安全链保留并回归；原通知批准声明删除 |
| R05 实时多模态 | README 明确不作为当前交付能力 | 降级说明已更新；未实现 F15，也未把单句语音冒充实时会话；全入口可达性仍需复验 |
| R06 远程恢复 | 保留诊断范围；编辑地址/令牌清除旧 lease；本地延长/清除不再称远端续租/撤销 | 安全降级；持久远程作业完整审批/对账未实现，不标记全量完成 |
| R07 费用 | 保留原账本并新增运行/逻辑请求/尝试关联、pending、未知费用阻断、人工对账版本锁及审计；仪表盘已结算费用与预算采用同一账本；不自动释放未知费用 | 本机能力已实现并回归；本地请求ID不是供应商requestId，不具备自动云端账单匹配；费用跨机备份/共享预算和真实账单验收仍未完成 |
| R08 结果状态 | 核对现有系统编辑器真实交接字段及失败/未知语义，不重复更改 | 现有实现保留；真实外部应用取消/保存回执实测未完成 |
| R09 备份 | 核对个人上下文、结果卡、提醒/工作流/研究分区及遗忘保护实现；README 改为与当前代码一致；显式清除数据覆盖新费用明细及审计 | 费用账本尚未纳入跨机保险箱恢复，界面及README均提示；全部版本迁移矩阵未在本轮重新执行 |
| R10 研究 | supported wire值兼容旧备份，用户标签改为“来源近期核对，结论待复核”；无效来源/空摘录不得支持；HTTP核验复用私网策略与DNS地址固定 | 代码已落地；不是自动语义证明；不宣称自动识别所有矛盾或消除幻觉 |
| R11 提醒 | 新增只读当前系统能力查询；页面恢复前台复查；明确“上次登记结果”与“当前权限”不同，不自动重放旧通知 | 代码已落地；通知撤权/重启/厂商ROM完整矩阵未签收 |
| R12 评测 | 新增12类共60条隔离用例，默认not_run；新增记录评分器，缺结果/缺版本/危险误执行不能通过 | 用例与评分器已完成，不等于真实模型评测已运行 |
| R13 可观测/性能 | 保留既有trace，新增本机运行/逻辑请求/尝试与费用的关联和审计；不额外引入遥测SDK | 供应商requestId自动关联、设备p50/p95、内存/电量和SLO仍未完成 |
| R14 产品收敛 | 不凭初审假设大规模删除页面/工具/权限/依赖 | 目标用户3条核心任务未给出；产品导航重构和用户验证待确认 |

## 验证方式

已执行的分批验证：
- 12项发布门禁 Python 单测通过。
- 5项记录评分器单测通过；全为合成fixture，不能计入Agent任务成功率。
- 第一批3个 Dart 测试文件27项通过（审批、前台认证、研究和预算/SQLite）。
- 第二批4个 Dart 测试文件45项通过（恢复、远端客户端和工具管线）。
- 两轮定向静态分析均通过。

费用续办前的上一批固定源码验证（不能冒充本批源码证明）：
- 固定源码7个文件共72项测试通过，另有4项研究URL边界测试通过。
- 全部 `lib/` 与新增边界测试最终静态分析通过（`mobile-review-analyze-final.log`）；发现的一处debug流程大括号info已修正。
- 发布门禁12项、评分器5项单测复跑通过。
- 运行时源码一致性守卫5项自测通过：仅格式空白变化可等价，代码、普通/原始字符串内容和注释变化不能蒙混通过；守卫Dart静态分析通过。
- 4个页面（仪表盘、提醒、远程诊断、研究）加预算弹窗的4态检查20/20通过，fixture已关闭且源码证明前后一致。
- 模拟器6组契约复验413/413通过：artifactActions 36、personalContextSql 69、planProtocol 228、memoryScope 28、memoryKnowledge 12、conversationResults 40；命令退出码0，源码前后证明通过。这些是fixture断言，不是413个真实Agent任务。

输出位置：
- `local/temp/mobile-review-analyze.log`
- `local/temp/mobile-review-analyze-final.log`
- `local/temp/mobile-review-source-boundary-tests.jsonl`
- `local/temp/mobile-review-contracts.json`
- `local/temp/mobile-review-tests.jsonl`
- `local/temp/mobile-review-release-tests.log`
- `local/temp/mobile-review-eval-tests.log`
- `local/temp/mobile-review-targeted.json`（模拟器源码匹配及4页面/预算弹窗四态；失败也保留）

模拟器第一次检查失败，因为 `emulator-5554` 不在线，并非页面检查通过。已使用现有预览脚本启动已授权AVD，预览日志写入 `local/temp/mobile-review-preview.log`；其中可能含VM鉴权地址，不应公开或提交。

随后严格文本比对发现VM缓存的是格式化前源码。排查证明差异为格式空白，而非逻辑回退；没有简单忽略所有空白。新增Dart analyzer token+注释比较，分别保存live/disk原始哈希，字符串内容不被归一化，前后证明一致后才进行UI验收。该证明不等于基础APK包含热重载后的源码，故仍标记notFinalApkSignOff。

源码守卫自测已加入发布工作流。模拟器预览保留运行；未执行真实模型调用、真机操作、完整宿主Flutter测试、正式发布、提交推送或签名密钥操作。

## 发布证据契约

运行：

```bash
python tool/release_evidence_gate.py --apk build/app/outputs/flutter-apk/app-release.apk --evidence release/mobile-evidence.json --output artifacts/project-review/mobile-release-gate.json
```

证据顶层必含：`schema:1`、`channel:private-apk`、`gitCommit`、`apkSha256`、`certificateSha256`、完整 `sourceSha256` 映射、`blockers:[]`、`gates`。

`gates` 必含 `static_analysis`、`agent_regression`、`approval_security`、`arm64_runtime`、`background_recovery`、`accessibility`、`performance`。各项有 `status:passed`、同一 `apkSha256`、`reviewedBy`、`verifiedAt`、仓库内 `report` 路径及 `reportSha256`。JSON报告必须真实通过；运行中、超时、清理失败或源码变化均不能通过。

签名证书由工具调用 apksigner 从APK读取，不凭JSON自报；APK/源码/报告实际重新算hash。源码覆盖Dart、Android主源集及构建版本清单。证据仍是需人工复核的本地声明，不是自动证明业务正确、可复现构建或第三方可信签章。不要为放行手填“passed”或复用其他APK的报告。

**有意的行为变化：** 没有 `release/mobile-evidence.json` 或证据不匹配，Release工作流会停止上传；本轮不会制造一份假通过文件。

## 60条评测的使用

`test/fixtures/mobile_agent_review_cases.json` 是任务集，不执行任何网络或模型调用。先在隔离回放/获授权模型环境执行，再提交人工复核的结果数组给 `tool/score_mobile_agent_eval.py`。每条结果包含id、status、requiredChecks对应的checks、modelVersion、promptVersion、toolVersion、traceId、reviewedBy、evidence、tokens和dangerousMisexecution。

```bash
python tool/score_mobile_agent_eval.py --results <reviewed-results.json> --output local/temp/mobile-agent-evaluation.json
```

评分器要求全部用例有有效记录、成功率至少90%、危险误执行为0；缺失不得算成功。此阈值只是首轮建议，不是外部模型效果保证，评分器也不代替语义审查或真实执行。

## 费用续办后的当前源码复验

- 7个定向Dart测试文件99项通过，全部lib与两份新增费用测试静态分析No issues found；其中费用20项、费用界面11项、原回归6项，另外62项为Agent预算/执行器/草稿/加固测试。
- 模拟器5个页面加预算弹窗的4态检查24/24通过；6组契约413/413复跑通过，命令退出码均0。前后21个选定Dart源码token/注释证明一致，不是正式APK源码认证。
- 发布门禁12项、评分器5项、源码守卫5项复跑通过；定向diff检查通过，只有行尾转换提醒。
- 当前输出：`mobile-cost-analyze.log`、`mobile-cost-tests.log`、`mobile-review-targeted.json`、`mobile-review-contracts.json`，均位于`local/temp/`。早先模拟器报告保存为`*-before-cost.json`。
- 契约入口已保存为`tool/verify_mobile_review_contracts.py`，检查隔离属性、0模型调用/平台及用户数据变更声明、最低断言数量、全通过及源码前后一致。
- 弹窗保存曾被新增widget测试检出controller销毁过早，已改为弹窗State持有并在卸载时销毁，交互回归通过；测试常量/语法错误也已修复，不用失败轮次充当通过证据。
- 费用跨机保险箱恢复、供应商requestId/账单自动关联及真实收费验收仍未完成，不能称完整云端账单闭环。其余R02/R05/R06/R08/R11/R12/R13/R14边界不变。

## 仍待授权或继续工程

真机ARM64/PRoot、多厂商ROM、真实耗电/进程恢复、TalkBack实机、真实模型任务评测、正式签名候选包、外部系统业务结果及用户核心流程验证仍需相应授权/环境/材料。未提交、未推送、未发布APK，未读取或导出签名密钥。
