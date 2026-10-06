# NEXUS Agent 真机验证交接（0.9.0 / PKX110）

校验对象：`docs/ui-improvement-handoff.md` 第 9 节「真机验证清单」。
日期：2026-09-22。设备：PKX110 `d29380b2`（adb `C:\Users\HJIE\AppData\Local\Android\Sdk\platform-tools\adb`）。
构建：release `com.nexusagent.app` 0.9.0（versionCode 94），入口 `com.nexusagent.app/.MainActivity`。截图帧 1216x2640。
证据目录：`device-check/`（本机未入库，见第 6 节）。

结论：11 项里 **5 项通过、1 项部分通过、5 项因 Provider 未配置无法执行**。设备系统设置与应用设置已复位。

---

## 1. 结果总表

| §9 条目 | 结论 | 证据 |
|---|---|---|
| 长会话滚动 / 「回到最新」按钮 | 通过（功能层，未做帧率采样） | `01-launch.png/.xml`、`02-after-jump.png/.xml`、`02.txt` |
| 指标面板「输出预留」不被当成空闲（A1） | 通过 | `07-metrics-sheet.png`、`07.txt`、`07-bounds.txt` |
| 工具卡片「已压缩」标记（A2） | 未验证（Provider 未配置，无法产生工具调用） | — |
| 指标面板点某一步定位消息（A3） | 未验证（会话只有 1 步，板上无可点步骤行） | `08-steps.png`、`08.txt` |
| 切无 Agent 老会话是否残留 Agent 名 | 未验证（抽屉里 3 个会话，未逐个切） | `drawer.txt`、`drawer-small.jpg` |
| 系统字体 1.3 溢出 | 通过（主列 + 指标面板概览/步骤均无溢出） | `03-font13`、`09-chat-13`、`10-metrics-13`、`11-metrics-13-steps` |
| 深色模式 + 指标面板可读性 | 部分通过（深色 + 磨砂 45% 已验；液态/纯扁平两档未验） | `04-night`、`12-chat-night`、`13-metrics-night`、`g6`、`g7` |
| 杀进程重进后保持 | 通过（会话层） | `05-after-kill.png/.xml`、`05.txt` |
| 网络断开 / 取消 / 重启恢复 | 未验证（Provider 未配置） | — |
| 超大工具结果 / 超长参数 / 多工具调用 | 未验证（Provider 未配置） | — |
| 原生库加载 logcat | 通过（818 行仅 1 条 `AndroidRuntime: Shutting down VM`） | `logcat.txt`、`logcat-hits.txt` |

---

## 2. 已通过项的硬证据

### 2.1 「回到最新」

- 首次启动（`01-launch`）：顶部会话条 `step-5-preview · 1 · 上下文 323 / 1.0M`，模式 `聊天` / `每次询问`，
  HUD `1 轮 · 0 步 · LLM 0ms · 工具 0ms`，助手气泡为错误文案
  `模型未返回可显示内容，请检查 Provider/模型配置后重试。`；蓝色 FAB 带角标 `2`，
  文案 `有 2 条新消息，点击回到底部`，bounds `[933,1833][1164,1976]`（`snip.py` 测得）。
- 点击 FAB（`input tap 1048 1904`）后（`02-after-jump`）：提示 chip 消失，列表回到最新一条，
  可见 `step-5-preview · 2.9s` 助手气泡与会话条 `gpt-5.6-luna · 1 · 上下文 17k / 256k`，
  HUD 变为 `1 轮 · 1 步 · LLM 2.9s · 工具 0ms · 缓存命中 0% · +2`。
- 未做：滚动帧率采样（`dumpsys gfxinfo ... framestats` 一类），因此「是否掉帧」仍无数据。

### 2.2 指标面板「输出预留」（A1，修复前会被当成空闲）

点 HUD 的「N 轮 · N 步」（`06-metrics.xml` 中该行 center `(608,2098)`）打开「会话指标」面板（`07-metrics-sheet`）：

- 面板标题 `会话指标 · 本次运行 311 tok`；`当前上下文 358 / 256k tok · 1%`
- 说明行（`07-bounds.txt` bounds `[208,1592][1093,1709]`）：
  `上下文使用低于 70% · 剩余 254k tok · 预留输出 2.0k tok · 组成估算`
- `主要占用：系统提示词 279 tok`；组成 chips `系统提示词 ≈279` / `注入内容 ≈34` / `用户消息 ≈16` / `助手消息 ≈29`
- `Token 构成：输入 298 tok / 输出 13 tok / 缓存命中 0`

即：输出预留（2.0k tok）单列展示且**未**被计入空闲额度，符合 A1 口径。

### 2.3 步骤页与字体 1.3

- `08-steps`（步骤 Tab）：`上下文趋势` 图 + `1 估算 ≈358 实际 298`；`当前步骤 对话轮次 2 轮 / 模型步骤 / 估算上下文 ≈358 tok / 实际输入 298 / 工具调用 0 次 / 模型请求`。
- 字体：`settings put system font_scale 1.3` + `am start -S` 后，
  `03-font13`（旧会话，顶部条 `上下文 323 / 256k`）、`09-chat-13`（两轮会话）、
  `10-metrics-13`（概览）、`11-metrics-13-steps`（步骤）**均未出现黄黑溢出条纹**，指标面板卡片与 chips 排版正常。
- 注意：`03/04/05.txt` 三份 a11y 文本 hash 相同（`e1360134…`），**文本相同不能证明系统设置生效**，本次已改用 PNG 复核。

### 2.4 深色模式

- `cmd uimode night yes` 后无需重启，应用即时切换深色（`12-chat-night`、`13-metrics-night`、`04-night`）。
- 深色下聊天气泡、顶部会话条、HUD、指标面板正文与 `主要占用` 卡片对比度正常，可读；玻璃面板未盖住文字。
- 档位：这些截图都是 **磨砂 45%**（应用在 Android 上的默认档），不是液态档。

### 2.5 杀进程恢复 + 原生库 logcat

- `am force-stop com.nexusagent.app` 后 `am start`：仍是同一会话，两轮消息
  （`你是什么模型` / `你好` → `你好！有什么我可以帮你的吗？`）都在（`05-after-kill.png/.xml`、`05.txt`）。
- 会话跨多次重启（字体、深色、杀进程）保持；`am start -S` 不会清空会话。
- `logcat -d -t 800`：818 行，仅 1 处命中 `09-22 09:42:12.966 13015 13015 D AndroidRuntime: Shutting down VM`；
  无 `UnsatisfiedLinkError`、无 `dlopen`、无 `No implementation found`（过滤脚本 `filter_log.py`）。

---

## 3. 阻塞与未验证项

**根因：没有可用 Provider。** 所有模型调用都返回
`模型未返回可显示内容，请检查 Provider/模型配置后重试。`，因此无法产生真实的工具调用、压缩事件与长会话：

1. A2 工具卡片「已压缩」徽标 —— 未在真机见到（需要工具调用 + 批准压缩）。
2. 压缩标记 / 上下文快照 杀进程后是否保持 —— 未验证（本次屏幕上无压缩徽标可核对）。
3. 超大工具结果、超长参数、多工具调用 —— 未验证。
4. 网络断开 / 取消 / 重启后的任务恢复 —— 未验证。
5. A3 单步定位 —— 本次会话只有 1 步，步骤页没有可点步骤行，`onJumpToMessage` 未被真机触发
   （代码接在 `lib/presentation/chat/chat_page.dart:880`，单元测试 `test/session_metrics_sheet_test.dart:94` 覆盖）。
6. 老会话是否残留上一个 Agent 名称/系统提示词 —— 未验证；抽屉里可用老会话：
   `你是什么模型，知识库截止日期`、`你好，我想做一个安卓app`（见 `drawer.txt`）。
7. 液态玻璃 / 纯扁平两档的深色可读性 —— 未验证。

---

## 4. 证据可信度提醒

- `g6-chat-liquid-dark.png` / `g7-metrics-liquid-dark.png` **文件名有 liquid，但当时档位仍是 45% 磨砂**：
  那次点击落在小节标题「界面质感与液态玻璃」上（`glass_state.py` 显示该标题 center 与被点坐标 `(608,2438)` 相同），
  应用未切换。引用这两张时只能当作「深色 + 磨砂」证据。
- 「液态玻璃 (Liquid Glass)」磁贴实际 center 是 `(608,2582)` 一带，点击前应先用 `glass_state.py` 复核再点。
- `03/04/05.txt` 文本 hash 相同，不作为设置生效证据（见 2.3）。

---

## 5. 继续验证的最短路径

前置：在「设置 → 模型与模式」配好 Provider 与模型，先用一句「你好」确认能正常回复。

```bash
export MSYS_NO_PATHCONV=1
A="/c/Users/HJIE/AppData/Local/Android/Sdk/platform-tools/adb -s d29380b2"
cd /d/AIIIIII/"ai agent"/mobile_agent

# 复用脚本（都已在本机）
bash device-check/phaseG.sh        # 干净地走到「外观与主题」页（自带 HIT/MISS 校验）
bash device-check/restore_device.sh # 复位 font_scale=1.0 / night=no 并回到对话
```

建议顺序：

1. 造长会话（≥10 轮）+ 触发一次工具调用 → 观察 A2「已压缩」徽标；批准压缩后 `am force-stop` 再进，核对压缩标记与上下文快照是否保持。
2. 指标面板「步骤」Tab 点某一步 → 验证 A3 定位；顺带核对没有锚点时是否退化为滚到底部（先造 2 步以上再点）。
3. `会话列表` → 切到 `你是什么模型，知识库截止日期` 等老会话 → 看顶部是否残留上一个 Agent 名称 / 系统提示词。
4. 飞行模式发消息 → 取消 → 关飞行模式重试 → 杀进程重进，观察任务恢复与错误提示文案。
5. 超大工具结果（单次 >100KB）+ 超长参数 + 多工具并发，看渲染与滚动。
6. 深色 + 「外观与主题」三档（液态玻璃 0.85 / 经典磨砂 0.45 / 纯扁平 0.0）逐个截图对比指标面板可读性；
   点「液态玻璃」前先 `python device-check/glass_state.py device-check/<dump>.xml out.txt` 确认坐标。
7. 长会话滚到底部时采帧：`$A shell dumpsys gfxinfo com.nexusagent.app framestats`（或 `--jank` 旧接口），补上「是否掉帧」的数据。

---

## 6. 仓库 / 工作区变更

- 新增（**未入库**，`git status` 显示 `?? device-check/`）：`device-check/` 下全部截图、`*.xml` a11y dump、
  `*.txt` 文本标签与报告，以及本轮写的脚本：
  `bounds.py`（按文案取 bounds/center，第 4 参 `prefer` 做二级过滤）、`labels.py`（dump → 去重文本）、
  `glass_state.py`（玻璃档位与选中态）、`filter_log.py`（logcat 过滤）、
  `phaseA/B/C/D/F/G/H/I/J.sh`、`explore_drawer.sh`、`explore_settings.sh`、`probe_settings.sh`、
  `restore_device.sh`、`shrink.ps1`/`shrink_all.ps1`/`shrink_one.ps1`。
  这些脚本按「本机验证工具」对待即可；要清理就直接删 `device-check/`（其中 PNG 是唯一真机证据，删前先确认）。
- `docs/_device_probe.txt` 是临时中转文件（base64/命令回显），**属 `docs/` 本地笔记**，可删。
- 本文件 `docs/mcp-device-verification-handoff.md`：`.gitignore:109 /docs/*`（只放行 `index.html`、`qrcode.png`），
  所以它同 `mcp-code-review.md` 等一样是**本地工程笔记、不会进 git**；要入库需 `git add -f`。
- 本轮**没有**改任何 `lib/`、`android/` 源码，没有提交、没有 `git clean`/`reset`。

---

## 7. 设备当下状态（已复位，可直接交还）

| 项 | 值 | 来源 |
|---|---|---|
| `font_scale` | `1.0` | `restored-font2.txt`、`_restore.txt` |
| `cmd uimode night` | `Night mode: no` | `restored-night2.txt`、`_restore.txt` |
| 玻璃档位 | 45%（磨砂，应用 Android 默认值，未被改动） | `glass-before-restore.txt` |
| 前台 | `com.nexusagent.app/.MainActivity`（对话页） | `_restore.txt` |

会话内容保留：两轮消息仍在（`你是什么模型` 的报错轮 + `你好` / `你好！有什么我可以帮你的吗？`）。

---

## 8. 踩坑记录（下一位接手请先看）

1. `run_command` 是 pty，**回显可能整段丢失**（`next_offset: 0`）。所有结果写进文件，再用 `read_files` 读。
2. 文件必须是 **UTF-8**：PowerShell 重定向（`>`）产生的半 UTF-16 文件会让 `read_files` 报 `UNSUPPORTED_ENCODING`；
   需要落盘就用 Python `write_text(..., encoding='utf-8')`。
3. 别在 bash 里内联 PowerShell 引号；用 `shrink_one.ps1 -name <basename>`（420px JPEG，约 40KB，可直接读图）。
4. 原文案匹配会串台：系统「设置」App 里也有「设置」，抽屉项与系统项都用「设置」。用 `bounds.py ... "设置" "打开设置"` 限定。
   同理「外观」要先确认在 NEXUS 自己的设置页（页面上要有「外观与主题」）。
5. 每次点击前**重新 dump**：用旧 XML 算坐标会点空（本次 phaseI 就因此整链失败），脚本里已加 `HIT:` 断言。
6. Flutter 的 a11y dump 只给语义节点；`text`/`content-desc` 内容一样不等于渲染一致 —— 视觉结论一律以 PNG 为准。
7. 读完即删的临时文件统一叫 `_xxx.txt` / `_reportN.txt`，别和证据文件混。

