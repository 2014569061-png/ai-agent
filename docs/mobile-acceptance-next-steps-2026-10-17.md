# 移动端验收后续工作单（Next Steps）

日期：2026-10-17 · 对应验收：`docs/mobile-acceptance-handoff-2026-10-17.md`
当前状态文档：`local/temp/mobile-acceptance-2026-10-17/final-report/FINAL-ADDENDUM.md`（权威）
完整报告：`local/temp/mobile-acceptance-2026-10-17/final-report/ACCEPTANCE-REPORT.md`
证据索引：`local/temp/mobile-acceptance-2026-10-17/final-report/EVIDENCE-INDEX.md`

> 结论现状：**有条件通过**（无未关闭 P0/P1）。本工作单只列「还没做完」的事，按优先级排序。

---

## 0. 开工前：30 秒环境自检

```powershell
cd D:\AIIIIII\ai-agent\mobile_agent

# 1) 设备在不在
./local/android-sdk/platform-tools/adb.exe devices          # 期望 emulator-5554  device

# 2) AVD 对不对
./local/android-sdk/platform-tools/adb.exe -s emulator-5554 emu avd name   # 期望 Nexus_Preview_API_36

# 3) 预览还在不在（本会话 PID 创建于 21:58 之后）
Get-Process | Where-Object { $_.ProcessName -match 'dart|flutter' } | Select-Object Id,StartTime
#    若为空 → 重新启动预览（会重新构建+安装）：
./tool/run-android-preview.ps1        # 后台常驻；等到输出 [preview] Ready

# 4) 设备设置是否仍是基线（必须 5 项都对）
& ./local/android-sdk/platform-tools/adb.exe -s emulator-5554 shell settings get system font_scale            # 1.0
& ./local/android-sdk/platform-tools/adb.exe -s emulator-5554 shell settings get system accelerometer_rotation # 1
& ./local/android-sdk/platform-tools/adb.exe -s emulator-5554 shell settings get system user_rotation          # 0
& ./local/android-sdk/platform-tools/adb.exe -s emulator-5554 shell cmd uimode night                          # Night mode: no
& ./local/android-sdk/platform-tools/adb.exe -s emulator-5554 shell wm density                                # Physical 420，无 Override
```

**红线（每轮都适用）**
- 不执行 `git reset / checkout / clean / stash`。工作区有 **316 条既有脏改动** 是别人的活，只做增量修改。
- 不并发跑两个 `flutter test`（Windows 编译缓存会互相覆盖）。
- 采样屏幕前必须先 `snapshot` 看清标签，不要盲传重复标签给探针 `tap`。
- 所有新证据只写 `local/temp/mobile-acceptance-<日期>/` 下；`local/` 已 gitignore。
- 结束前 `python tool/mobile_ui_probe.py --serial emulator-5554 restore`，并**从设备读回 5 项真值**（别信探针的 `restored` 标记）。

---

## 优先级 1：把 §1–§2 已产生的证据登记成判定（纯文案工作，1 小时内可完成）

**问题**：`section1-2/` 里已有 25 个实测日志 + 截图，但 `SECTION-1-2-EVIDENCE.md` 还停在「PAUSED、未执行任何清单项」，导致报告里 §1–§2 全是「待登记」。

**要做**：按清单顺序逐条回填 `local/temp/mobile-acceptance-2026-10-17/section1-2/SECTION-1-2-EVIDENCE.md`，每条写：
`场景 / 设备配置 / 操作步骤 / 预期 / 实际 / 结果(通过|失败|未覆盖) / 证据路径`

**素材对应表**（日志在 `section1-2/logs/`，截图+`json` 在 `local/temp/mcp-ui-5da85d5e/`）

| 清单条目 | 可用素材 |
| --- | --- |
| §1.1 聊天首页 亮/暗 411dp | `s1-01-chat-home-light-411dp.log`、`s1-08`/`s1-12` chat-home-dark |
| §1.1 360dp 窄屏 | `s1-18-chat-home-dark-360dp.log` + `narrow-seq.log`（density 480 ⇒ 360dp） |
| §1.5 抽屉导航 + 返回行为 | `s1-03`、`s1-09`、`s1-13`、`s1-19`、`drawer-cycles.log`（4 次开→返回）、`back-probe.log`、`tap-probe.log` |
| §1.4 暗色抽查 | `s1-10-appearance-page.log`、`s1-11-settings-dark`、`s1-14`/`s1-16` model-sheet-dark、`dark-seq.log` |
| §2 设置/模型入口 | `s1-07-settings-light`、`nav-settings.log`、`nav-model.log`、`s1-05-secondary-model-light` |
| 渲染健康（ANR 不复现） | `gfxinfo/after-drawer-tap-back-cycles-220545.txt` |

**仍然缺的（回填时会发现）**，需要补跑，命令模板：

```powershell
$S='emulator-5554'
# 字体 1.3 / 1.6（§1.3 清单原文要求；每次改完必须回读）
python tool/mobile_ui_probe.py --serial $S configure --font 1.3
& ./local/android-sdk/platform-tools/adb.exe -s $S shell settings get system font_scale     # 记下回读值
python tool/mobile_ui_probe.py --serial $S snapshot --name s1-21-font13-drawer
python tool/mobile_ui_probe.py --serial $S configure --font 1.6
& ./local/android-sdk/platform-tools/adb.exe -s $S shell settings get system font_scale
python tool/mobile_ui_probe.py --serial $S snapshot --name s1-22-font16-settings
# 横屏（§1.5 后半：横屏不得变成桌面导航）
python tool/mobile_ui_probe.py --serial $S configure --rotation 1
python tool/mobile_ui_probe.py --serial $S snapshot --name s1-23-landscape-chat
# 键盘态（§2 输入区）
python tool/mobile_ui_probe.py --serial $S snapshot --name s1-24-keyboard
python tool/mobile_ui_probe.py --serial $S restore
```

> 经验教训（本轮踩过）：`configure --font` 的参数顺序写错会 **exit 2 且静默失败**，截图文件名就会撒谎。**每次改状态后立刻回读并写进同一行证据。**

---

## 优先级 2：补做 §3–§5 未在设备验证的条目（本轮最大缺口）

先建 `local/temp/mobile-acceptance-2026-10-17/section3-5/SECTION-3-5-EVIDENCE.md`，逐条登记。计划与命令模板已在
`section3-5/SECTION-3-5-PLAN.md`（含无障碍标签与探针命令），驱动脚本 `section3-5/drive_section3_5.py`
（有 `HANDOFF_CONFIRMED` 闸门，需置 True 才允许驱动设备）。

| 编号 | 未验证项 | 建议做法 |
| --- | --- | --- |
| §3.1 | 项目列表：创建 / 导入 / 选择 / 空态 / 错误态、模板卡片、窄屏名称校验 | 用**项目空态 + 模板卡片 + 名称校验**，不实际创建（创建会写真实应用库，见下「不要做」） |
| §3.2 | 项目主页各标签：概览/文件/终端/任务/产物；路径可复制、长路径不撑破 | 每标签 `snapshot` + 点一次复制 |
| §3.3 | 文件树：空目录 / 深层目录 / 返回；编辑器顶部对齐 / 多行 / 跳行号 / 未保存确认 / 保存反馈 | 长路径与深层目录可直接用现有项目；「目录读取失败」需破坏夹具（本轮记为阻塞，附源码行号） |
| §3.4 | 开发工作台一条可重复的静态网页验证流程 | 优先做：夹具根有 `index.html` ⇒ 走静态网页分支、可反复重跑、零副作用 |
| §3.5 | 长任务进行时切页/回前台/等待完成 | 用夹具五态（`isolated-task-0..4`）作**替代覆盖**，报告里必须标注「替代覆盖，非真实长任务通过」 |
| §4.1/§4.2 | 项目命令/作业入口 vs 远程交互终端入口；输入、提交、清空/关闭、日志滚动、复制路径 | 探针 `tap` 前先 `snapshot` 确认标签 |
| §4.3 | 软键盘弹出后终端输入框/快捷操作/运行按钮均可见可点；收起后无多余空白 | 与 §2 键盘态一起做，省一轮配置 |
| §4.4 | 只读命令成功反馈；危险命令/工作区外路径的审批拦截 | 用 `pwd` / `ls` 验成功；`cat /etc/hosts`、`ls | grep` 只提交文本，**不点任何审批按钮** |
| §5.1 | 设置主目录 + 模型/服务商/工具/外观/语言/数据管理子页：可滚动、返回正确、当前值与修改反馈 | 语言子页与 P4 的本地化问题合并验 |
| §5.3 | 系统返回 + 软键盘 + 夜间 + 旋转 + 进后台/回前台的组合 | 用确定性命令表（`keyevent 111`、`configure --night`、`--rotation`、`keyevent 3`、`monkey ... LAUNCHER`），每状态单独截图、不叠加 |
| §5.4 | 已配置 provider 的**展示**状态 + 受控错误/超时/重试 | 只读；**不发真实模型调用**，证据里写「provider 已配置但未发起真实调用」 |

**不要做**：不实际创建项目（`ProjectService.createFromTemplate` 写真实应用库并落到应用自管理目录）、不点「清除本地凭证」、不装 APK、不执行覆盖恢复、不发真实 API 调用、不输出任何密钥/令牌到截图或日志。

---

## 优先级 3：§6 剩余可做的备份恢复半步（约 30 分钟）

`section6/SECTION-6-EVIDENCE.md` 已有 R0 通过（host-side 回滚演练，tar 已验可恢复）。可做且非破坏：

- **R1** 立即备份 → 期望 toast「已生成新的数据快照」+「最近备份时间」有值
- **R2** 备份文件可识别 → `nexus-auto-*.nexusauto` 存在非空、staging 名消失（记录文件列表，不导出密钥）
- **R4** 打开恢复选择器，**停在**「覆盖恢复本地数据？」确认弹窗（截图），**不确认**
- **R6** 结束时 `restore` + 读回 5 项

**R5（完成覆盖恢复）保持不执行** —— 该路径会 `clearAllUserData()` 且不还原 `shared_prefs`，本 AVD 含真实会话与 provider 配置。想做端到端恢复验证，必须**另起一个一次性 AVD**。

---

## 优先级 4：两个仍未定的收尾判定

1. **设备复验 P2-1（环形溢出修复）**
   自动化已在 360dp × 2.3× 验证通过，但设备侧大字号重拍还没做。建议：
   ```powershell
   $S='emulator-5554'
   python tool/mobile_ui_probe.py --serial $S configure --font 2.0
   & ./local/android-sdk/platform-tools/adb.exe -s $S shell settings get system font_scale   # 必须回读到 2.0
   # 进设置把「字体大小」调到"特大"，再进仪表盘截图，看环形是否还有黄黑条纹
   python tool/mobile_ui_probe.py --serial $S restore
   ```
   注意：`configure` 只改 OS 字号；应用内字号要在设置页手动改，两者会**相乘**（≈2.05×）。若仍有条纹 → 新 P2，回来找我改 `token_usage_hero.dart`。

2. **静态审计剩余候选**（见 `local/temp/mobile-acceptance-2026-10-17/STATIC-AUDIT-FINDINGS.md`）
   逐条设备验证或明确记为未覆盖：`nexus_metric_tile.dart:70-99/101-127`（KPI 标签/数值 Row）、
   `file_tree_sheet.dart:244-249`（有 `ellipsis` 无 `maxLines`）、`message_bubble.dart:540-548`、
   `model_picker_sheet.dart:143,190`、`plan_panel.dart:131,576`；
   以及 `device_capabilities_page.dart:706-714` 的 **36dp 可见按钮**——要量**可点击节点**的 `bounds` 才能定 48dp
   （`AppTheme` 设了 `materialTapTargetSize: padded`，`app_theme.dart:285-286`，通常会扩到 48dp）。
   ⚠️ 更正：`file_tree_sheet.dart:244-249`（`Text(projectName, overflow: ellipsis)` 无 `maxLines`）**本轮没有被修改**，
   当前代码仍是原样（`git status --short -- lib` 只显示我改过的 3 个源文件）。所以它是**待验证/待修复**项，
   不是「已改过一轮」。若设备复验确认长目录名会换行撑高 sheet 头部，再加 `maxLines: 1` 并跑受影响测试。

---

## 优先级 5：最后才考虑的「提交」问题（现在别做）

工作区有 **316 条脏路径 + 本任务 5 个文件**。这轮验收只证明「当前工作树可通过测试并在模拟器上表现正常」，
它**不等于**这批改动可以提交。若要提交，先回答：

1. 那 316 条改动是哪些任务/谁的？（`git status --short` 逐目录归类）
2. 桌面端改动与移动端改动是否混在一起？是否需要拆分提交？
3. 提交前必须重跑：`flutter analyze` + 核心回归 9 条 + `dart format --set-exit-if-changed` + `git diff --check`
4. `artifacts/` 是测试输出目录（`.gitignore:137`），属正常 churn，不要清理、不要提交。

建议：把提交当作**独立的一次任务**，不要在本工作单里顺手做。

---

## 完成标准（本工作单做完后的验收口径）

- §1–§5 清单条目**全部有判定**（通过 / 失败已修复复验 / 阻塞未覆盖），且每条都有可复核的证据路径；
- 高优先级（P0/P1）无「未覆盖」；
- 所有复核改动跑过受影响测试 + 全套核心回归（当前是 9 条命令、153 个测试）；
- `flutter analyze`、`dart format --output=none --set-exit-if-changed <改动文件>`、`git diff --check` 全通过；
- 设备设置已 `restore` 并读回 5 项真值；预览进程保持运行；
- 最终 `git status --short` = 316 条基线 + 本任务新增文件，没有额外清理或覆盖。