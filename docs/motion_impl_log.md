# 动效改造 · 阶段 4：实现日志

> 分支：`feat/harmony-motion`（从带 366 个未提交改动的 `main` 切出，改动原样带入）。不 push。
> 说明：`docs/*` 被 `.gitignore:109` 忽略，本目录文档只保存在本地。

## M0 公共基础：弹簧 Token + 动效性能分级（2026-09-24，已完成）

### Diff 计划（低风险，已按计划执行）

| 文件 | 动作 | 内容 |
| --- | --- | --- |
| `lib/presentation/motion/motion_tier.dart` | 新增 | `MotionTier`、`MotionTierController`（按帧耗时在会话内只降不升）、`MotionTierScope`（InheritedNotifier，支持 `cap` 上限）、`MotionBudget`（合并 MotionLevel × MotionTier，提供统一的装饰层预算） |
| `lib/presentation/motion/nexus_motion.dart` | 追加 | `springFollow` / `springRelease` / `springLively` 常量 + `NexusMotion.spring()` 工厂；未改动任何已有 Token |
| `lib/main.dart` | 追加 | 两行 import；`runApp` 之后调用 `MotionTierController.app.startMonitoring()`；`MaterialApp.builder` 外包一层 `MotionTierScope`（玻璃强度为 flat 时 cap = low） |
| `test/motion_tier_test.dart` | 新增 | 13 项：初始档、帧预算、预热、降档、只降不升、debugOverride、降级顺序、reduced/off、Scope/cap/系统移除动画、默认档、弹簧参数换算、弹簧收敛 |

没有改动路由、Provider 或原生代码，也没有新增依赖。

### 关键代码

```dart
// 装饰层只读这一个对象
final budget = MotionBudget.of(context);
if (budget.particleCount > 0) { /* 挂载粒子层 */ }

// 弹簧驱动
controller.animateWith(NexusMotion.spring(NexusMotion.springRelease));
```

档位预算：

| 能力 | high | mid | low | reduced | off |
| --- | --- | --- | --- | --- | --- |
| 粒子 | 28 | 14 | 0 | 0 | 0 |
| 光晕 | 漂移 + 呼吸 | 呼吸 | 静态 | 静态 | 无 |
| 流光 | 1.0× | 1.5× 周期 | 关 | 关 | 关 |
| 光随指动 / 发送光圈 / 转场视差 | 开 | 开 | 关 | 关 | 关 |

### 验证结果

| 步骤 | 命令 | 结果 |
| --- | --- | --- |
| Format | `dart format`（仅改动文件） | 通过 |
| Lint | `dart analyze --fatal-infos lib test` | **No issues found**（第一次有 2 条 unnecessary_import，已修复） |
| 定向测试 | motion_tier / nexus_motion_and_widgets / motion_ui_regression / route_transition_paint / code_quality_guard / liquid_glass | **57 项全部通过** |
| 全量测试 | `flutter test --no-pub` | **1404 项全部通过** |
| 构建 | `build-apk.bat --fast --no-pause --no-open` | **成功**，app-release.apk 25.9MB，85.3s |

日志：`artifacts/motion-logs/`（已被 gitignore）。

### 验收方式

- 目前没有可见的界面变化（M0 是基础设施，后续 M1–M10 才会读取 `MotionBudget`）。
- Debug 下可设 `MotionTierController.debugOverride = MotionTier.low` 验证降级路径。
- Profile 真机：DevTools 中 `MotionTierController.app.value` 初始值应与屏幕刷新率匹配（≥ 90Hz 为 high）。

### 性能注意

- 监测使用 `addTimingsCallback`，引擎本来就会批量上报帧耗时，额外开销是每帧 O(1)；降到 low 后自动注销回调。
- 前 90 帧（着色器编译、首屏光栅化）不计入统计，避免冷启动误降档。

### 回滚

- 尚未 commit（原因见下方「待确认」）。完整改动记录在 `artifacts/motion-logs/m0_changes.patch.txt`。
- 手动回滚：删除 `motion_tier.dart` 和 `motion_tier_test.dart`，撤销 `nexus_motion.dart` 中弹簧段落以及 `main.dart` 中的 4 处追加。

### 待确认

`lib/main.dart`、`nexus_motion.dart`、`motion_preferences.dart` 本身就有未提交改动，`motion_lifecycle.dart`、`nexus_haptics.dart` 仍是未跟踪文件，而 M0 依赖这些文件。此时单独 commit M0 会把你原有的未提交改动一起带进去，或者产生无法编译的提交。需要你决定基线怎么处理。

**更新**：你选择「先提交基线，再单独提交 M0」。执行 `git commit` 时遇到 `.git/index.lock` 已存在：该文件 0 字节，创建于 2026-09-24 04:16（约 19 小时前），当前没有 git.exe 在运行，判断为残留锁。按规则删除文件需要你确认，因此基线提交暂停；工作区已恢复到包含 M0 的完整状态（与测试通过时的文件完全一致）。

## M1 页面转场（整屏左右位移 + 下层视差暗化）：Diff 计划（高风险，等待确认，未写代码）

### 目标参数

| 项 | 进入（push） | 返回（pop / 系统返回手势） |
| --- | --- | --- |
| 上层页面 | translateX 100% → 0，由 `springRelease` 离散成曲线（约 350ms，过冲 ≤ 1.5%，并钳制不越过左缘） | 0 → 100%，250ms，`curveStandard` |
| 上层左缘 | 16dp 渐变投影，α 浅色 0.08 / 深色 0.20，随进度淡出 | 同步 |
| 下层页面 | translateX 0 → −30%（视差）+ 暗化遮罩 α 0 → 0.12 | 反向 |
| 下层绘制 | 转场期间用 `SnapshotWidget` 冻结成快照，只做 transform，不逐帧重录 | 同上 |
| 低端机（`routeParallax=false`） | 下层不视差，只暗化 | 同上 |
| reduced | 淡入 120ms，无位移 | 淡出 120ms |
| off | 0ms | 0ms |
| fade 档 | 保持不变 | 保持不变 |

### 实现路径

1. **下层动画用 `ModalRoute.delegatedTransition`**（本机 Flutter 3.47 SDK 已确认存在，routes.dart:1633）。由上层 `NexusPageRoute` 决定下层如何让位，因此首页（`MaterialApp.home` 生成的 MaterialPageRoute）和其他任意路由都能获得视差效果，**不需要改主题里的 `pageTransitionsTheme`，也不改路由结构**。
2. 删除进入方向的 `_keepUnderlyingRouteHidden`（下层停绘）逻辑，改为「下层快照参与绘制」。转场结束后恢复 Flutter 默认的 `opaque` 行为，稳态下下层仍然停止绘制。
3. 保留返回期上层快照（`_SnapshotOnExit`）。
4. 新增 `NexusSpringCurve`（把 SpringSimulation 归一化成 Curve），放在 `nexus_motion.dart`；新增 `AppTokens.durationPageSpring = 350ms`（沿用具名常量写法，不增加 code_quality_guard 的计数）。
5. 两处 `MaterialPageRoute` 改为 `NexusPageRoute`：`project_home_page.dart:518` 改为 `.detail`，`terminal_sheet.dart:198` 改为 `.workspace`。

### 文件清单

| 文件 | 改动 |
| --- | --- |
| `lib/presentation/motion/nexus_page_route_factory.dart` | 重写 `_buildTransition`；新增 `delegatedTransition`；移除进入方向停绘逻辑；左缘投影 |
| `lib/presentation/motion/nexus_motion.dart` | + `NexusSpringCurve` |
| `lib/presentation/theme/app_tokens.dart` | + `durationPageSpring` |
| `lib/presentation/projects/project_home_page.dart` | 1 处路由替换 |
| `lib/presentation/workspace/terminal_sheet.dart` | 1 处路由替换 |
| `test/route_transition_paint_test.dart` | **有意的行为变更**：「进入转场期间，下层页面不参与绘制」「返回转场期间，下层页面零绘制」两项断言改为「下层以快照参与绘制，重录 ≤ 1 次」；另外两项保持不变 |
| `test/route_parallax_test.dart`（新增） | 中间帧位移 / 视差 / 暗化数值；低档不视差；reduced 只淡入；off 为 0ms；fade 档不受影响 |

### 风险

- 下层快照在 push 的第一帧会多一次整页离屏拷贝（toImageSync），低端机上可能多 3–6ms，需要 profile 实测。如果超预算，退回方案是在低档下只暗化、不显示下层（`opaque`）。
- 聊天页的流式输出在被覆盖期间会被冻结在快照里（只在转场约 350ms 内），转场结束后恢复实时。
- 系统预测性返回（Android 14+ 边缘手势跟手预览）需要在 `AndroidManifest.xml` 加 `enableOnBackInvokedCallback`，属于原生配置改动（高风险）。**本次不包含**，只保证系统返回触发的是新的 pop 动画。

### 回滚

单独 commit；另外保留改动记录 `artifacts/motion-logs/m1_changes.patch.txt`。

---

## M1 整屏层级转场 — 已完成（commit 554131b）

### 改动文件
| 文件 | 改动 |
| --- | --- |
| `lib/presentation/motion/nexus_page_route_factory.dart` | 重写转场：上层整屏位移 + 左缘投影；`delegatedTransition` 驱动下层视差/暗化；`_SnapshotOnExit` 泛化为 `_SnapshotWhile`；移除 `_keepUnderlyingRouteHidden` |
| `lib/presentation/motion/nexus_motion.dart` | 新增 `pageSpring` 与 `NexusSpringCurve`（弹簧归一化定长曲线，钳制不越界） |
| `lib/presentation/theme/app_tokens.dart` | 新增 `durationPageSpring = 350ms`（具名常量，不增加 guard 计数） |
| `lib/presentation/projects/project_home_page.dart` | 全屏终端入口 `MaterialPageRoute` → `NexusPageRoute.detail` |
| `lib/presentation/workspace/terminal_sheet.dart` | 同上 → `NexusPageRoute.workspace`（+1 import） |
| `test/route_parallax_test.dart` | 新增 10 个用例：曲线端点/单调、进入/返回几何、嵌套 Nexus 路由、低档、reduced、off、fade、时长 |
| `test/route_transition_paint_test.dart` | 两个用例改为「下层以快照参与，转场内重录 ≤ 2、快照就绪后 0」；时长相关帧数同步 |
| `test/bugfix_regression_test.dart` | Bug3 两个用例从「下层 opaque 停绘」改为「下层快照参与 + 结束后解冻」，第三个（不透明画布底）保留 |
| `test/nexus_motion_and_widgets_test.dart` | 时长断言 250/180 → 350/250；改调 `buildTransitions` |

### 关键实现
- 上层：`SlideTransition(1,0 → 0)`，进入 `NexusSpringCurve(springRelease)` 350ms，返回 `curveStandard` 250ms；返回期间上层快照。
- 下层：`NexusPageRoute.buildSecondaryTransition` = `_SnapshotWhile(forward|reverse)` → `SlideTransition(0 → −0.3)`（`budget.routeParallax` 为真时）+ `FadeTransition` 黑色 α 0.12 遮罩。
- 下层是 `MaterialPageRoute`（home）时经 `delegatedTransition` 注入，其自身 secondary 转场被 Flutter 代理屏蔽；下层是 `NexusPageRoute` 时 Flutter 不传递相同的 builder，由 `didChangeNext` 记录 `_yieldsToNext` 后在自身 `buildTransitions` 里执行同一套。
- fade 档：`delegatedTransition == null`，下层不动；上层只做淡入。
- 分档：low → 只暗化；reduced → 120ms 淡入、下层不动；off → 0ms。

### 验收
- `dart analyze --fatal-infos lib test`：No issues
- 目标测试 52 通过；全量 `flutter test --no-pub`：**1414 通过**（首轮 2 个旧 Bug3 用例按旧契约失败，已按新契约改写，非实现缺陷）
- `build-apk.bat --fast`：成功，65.2s
- guard 计数：未新增 `Color(0x..)` / `fontSize:` / `Duration(milliseconds:)` 字面量

### 性能
- 转场期间两层均为「快照 + transform」，每帧 GPU 只合成两张纹理 + 一层 opacity 遮罩；下层整段重录 ≤ 2 次（测试守护）。
- 代价：转场期间多一张全屏快照纹理（约 1080×2400×4 ≈ 10MB，转场结束即释放）。
- 下层在转场期间内容冻结（350ms 内不可感知），稳态恢复实时绘制。

### 回滚
- `git revert 554131b`（只影响 M1；M0 与基线不受影响）。
- 补丁存档：`artifacts/motion-logs/m1_changes.patch.txt`。

### 已知边界
- 从终端 Sheet 内推入全屏终端时，被视差的是 Sheet 路由，Sheet 下方的页面不移动（仅被上层覆盖）；视觉可接受，如需可在后续把 Sheet 关闭后再推入。
- 不含预测性返回（按用户决定）。

### 下一步：M2 首屏入场编排（待出 diff 计划）

---

## M1 补充：终端 Sheet 先收起再推入（commit 0ce25e0）

- 用户决定（2026-09-24）：从终端 Sheet 打开全屏终端时先收起 Sheet 再推入，让整屏转场作用在 Sheet 下方的页面上。
- 改动：`terminal_sheet.dart` 的按钮回调改为 `navigator.pop()` 后 `navigator.push(NexusPageRoute.workspace(...))`（+5/−2）。
- 测试：`route_parallax_test.dart` 新增「先收起 Sheet 再推入：让位的是 Sheet 下方的页面」。
- 验收：analyze 无问题；全量 1415 通过；fast APK 构建成功（64.9s）。
- 回滚：`git revert 0ce25e0`。

---

## M2 首屏入场编排 — diff 计划（待确认）

### 触发与编排
| 元素 | 槽位 | 延迟 | 变化 | 播放次数 |
| --- | --- | --- | --- | --- |
| 顶部胶囊栏 `CapsuleTopBar` | 0 | 0ms | translateY −8dp → 0 | 每个进程 1 次（冷启动 / Onboarding 进入主界面） |
| 空状态主体 `ChatEmptyState` | 1 | 40ms | opacity 0 → 1 + scale 0.96 → 1 | 每次挂载（包括新建会话回到空状态） |
| 输入胶囊 `FloatingCapsuleInput` | 2 | 80ms | translateY 12dp → 0 | 每个进程 1 次 |

- 单元素 260ms，错开 40ms，总长 340ms（≤ 380ms），曲线 `curveEnter`。
- 两个玻璃外壳（顶栏、输入框）**只做位移、不做透明度**。项目里已有记录：`BackdropFilter` 放进 Opacity 临时缓冲区会闪烁。空状态没有玻璃，可以正常淡入。
- 返回页面、键盘开合、普通重建都不会重播：只在 `initState` 时播放。

### 分档
| 档位 | 行为 |
| --- | --- |
| full（所有 tier，含 low） | 如上 |
| reduced | 空状态 120ms 纯淡入；玻璃外壳不动 |
| off | 直接显示，不创建 ticker |

### 改动文件
| 文件 | 改动 | 规模 |
| --- | --- | --- |
| `lib/presentation/motion/nexus_entrance.dart`（新） | `NexusEntrance(slot, offset, scaleFrom, fade, onceId)`：单个 `AnimationController`，播放完成后停止；`onceId` 用进程内静态集合去重；提供 `debugReset()` 供测试使用 | 约 140 行 |
| `lib/presentation/theme/app_tokens.dart` | `durationEntrance = 260ms`、`entranceStagger = 40ms`，都用具名常量，不增加 guard 计数 | +6 |
| `lib/presentation/motion/nexus_motion.dart` | 两个别名 | +4 |
| `chat/widgets/chat_empty_state.dart` | 用 `NexusEntrance(slot: 1, scaleFrom: 0.96)` 包住根 `Center` 的内容 | +3 |
| `chat/widgets/capsule_top_bar.dart` | 用 `NexusEntrance(slot: 0, offset: Offset(0, -8), fade: false, onceId: 'top_bar')` 包住根节点 | +6 |
| `chat/widgets/floating_capsule_input.dart` | 用 `NexusEntrance(slot: 2, offset: Offset(0, 12), fade: false, onceId: 'composer')` 包住根节点 | +6 |
| `test/nexus_entrance_test.dart`（新） | 起点/中段/终点取值、错开顺序、onceId 不重播、reduced、off、完成后 `transientCallbackCount == 0`、`fade: false` 时子树中没有 Opacity/FadeTransition | 约 150 行 |

不改路由、状态管理、原生配置，也不新增依赖。业务回调全部透传。

### 风险
- 低。已有测试如果在 340ms 内断言可见性：finder 不受透明度影响，命中测试也不受位移影响，预计不会失败。全量测试会验证这一点。
- 回滚：单独提交，`git revert` 即可。

---

## M2 首屏入场编排 — 已完成（commit cb5eb86）

用户确认（2026-09-24）：按计划实现；玻璃外壳只做位移。

### 相对计划的调整（实现时发现）
- 空状态的场景分段栏和 2×2 卡片里也有玻璃（`LiquidSegmentedControl`、`GlassSurface`），所以把空状态拆成两块：
  - 主视觉（BrandMark + 标题 + 副标题）：淡入 + 缩放，槽位 1
  - 卡片区：只做 12dp 上移，槽位 2
- 输入框因此顺延到槽位 3。总时长 3×40 + 260 = 380ms，仍在上限内。
- 卡片区只在本次挂载时首次出现才入场；键盘开合导致的重新插入不会重播（`enabled` 只在挂载时读取）。
- 淡入使用 `Opacity(alwaysIncludeSemantics: true)`。首轮全量测试中 `a11y_compliance_test` 发现：透明度为 0 的首帧会把标题从读屏语义树里移除，这是真实的无障碍回归，已修复并补了测试。

### 改动文件
| 文件 | 改动 |
| --- | --- |
| `lib/presentation/motion/nexus_entrance.dart`（新） | `NexusEntrance(slot, offset, scaleFrom, fade, onceId, enabled)`，播放完成后不再有 ticker；包装结构在整个生命周期内保持稳定，不会重新挂载子树 |
| `lib/presentation/theme/app_tokens.dart` | `durationEntrance` 260ms、`entranceStagger` 40ms、`durationReducedEntrance` 120ms（具名常量） |
| `lib/presentation/motion/nexus_motion.dart` | 3 个别名 |
| `chat/widgets/capsule_top_bar.dart` | 用 `NexusEntrance` 包住根 `GlassSurface`（槽位 0，−8dp，不淡入，每进程一次） |
| `chat/widgets/chat_empty_state.dart` | 主视觉包装（槽位 1）、卡片区包装（槽位 2），新增 `_gridEntered`、`_maybeEntrance` |
| `chat/widgets/floating_capsule_input.dart` | 用 `NexusEntrance` 包住根 `Padding`（槽位 3，+12dp，不淡入，每进程一次） |
| `test/nexus_entrance_test.dart`（新） | 9 个用例：错开时序、玻璃不包 Opacity、onceId、重建时状态保留、enabled、reduced、off、语义、总时长 |

diff 行数偏大，主要是包装后 `dart format` 重新缩进造成的；`git show -w cb5eb86` 可以只看实际改动。

### 验收
- analyze 无问题；目标测试通过；全量测试 **1424 通过**；fast APK 构建成功（64.5s）。

### 性能
- 只在挂载时运行。每个元素一个 controller，最长 380ms，结束后 `transientCallbackCount == 0`（测试守护）。
- 稳态下保留恒等 `Transform` 和 `Opacity(1)`，不产生额外图层，开销可以忽略。
- 玻璃外壳不进入透明度缓冲区。

### 回滚
- `git revert cb5eb86`；补丁：`artifacts/motion-logs/m2_changes.patch.txt`。

### 下一步：M3 列表/卡片错开入场（≤ 8 项、30ms 错开），待出 diff 计划

---

## M3 列表/卡片错开入场 — diff 计划（待确认）

### 参数（沿用 `motion_plan.md` M3）
| 项 | 参数 |
| --- | --- |
| 触发 | 列表**挂载时**（历史、Agent、仪表盘三页都在数据就绪后才构建列表，因此挂载即等于「首次加载完成」）。下拉刷新、筛选切换、重建都不重播；滚动中新出现的 item 不加动画 |
| 时长 | 每项 220ms，错开 30ms，只对前 8 项生效，总长 7×30 + 220 = 430ms |
| 曲线 | `curveEnter` |
| 变化属性 | translateY 12dp → 0；**只有非玻璃模式**（`GlassIntensity.flat`）才叠加 opacity 0 → 1。玻璃卡片沿用 M2 的做法，只位移，避免 Opacity 缓冲区闪烁 |
| 实现 | `NexusStaggeredEntrance`（整个列表共用一个 `AnimationController`，通过 InheritedWidget 下发）+ `NexusStaggeredItem(index)`，每项用 `Interval` 切片 |
| 低端机 | 保留（整页只有 1 个 ticker，最长 430ms） |
| reduced / off | 直接显示，不创建 ticker |
| 滚动物理 | **不改**（弹性过界需要你确认，见问答） |

### 改动文件
| 文件 | 改动 | 规模 |
| --- | --- | --- |
| `lib/presentation/motion/nexus_staggered_entrance.dart`（新） | Scope 和 Item 两个组件。Item 在 `index ≥ 8`、没有 Scope、reduced/off 这几种情况下直接返回 child；包装结构保持稳定，不重挂子树；读屏语义始终保留 | 约 130 行 |
| `lib/presentation/theme/app_tokens.dart` / `nexus_motion.dart` | `durationListItem` 220ms、`listStagger` 30ms、`listStaggerMaxItems = 8` | +8 |
| `history/history_page.dart` | 用 Scope 包住 `ListView.builder`；分组头和会话卡片用 `NexusStaggeredItem(index: index)` 包装 | 约 +8 |
| `agents/agents_page.dart` | 用 Scope 包住 `ListView.separated`；首项入口卡片和每个 Agent 卡片用 Item 包装 | 约 +6 |
| `dashboard/dashboard_page.dart` | 用 Scope 包住 `ListView`；待办、性能详情/开发者区块、最近会话这几个顶层区块依次用 Item 包装（SizedBox 间距不包） | 约 +10 |
| `test/nexus_staggered_entrance_test.dart`（新） | 错开时序、整页只有 1 个 ticker、第 9 项起不动画、重建与刷新不重播、玻璃模式不包 Opacity、flat 模式淡入、reduced/off、语义 | 约 170 行 |

不改路由、状态管理、数据加载和业务回调，也不新增依赖。MCP/记忆页暂不纳入（计划文件表只列了三页），如需要可以在后续补充。

### 风险
- 低。已有测试里 finder 不受透明度影响，命中测试不受 12dp 位移影响；全量测试会验证。
- 回滚：单独提交，`git revert` 即可。

---

## M3 列表/卡片错开入场 + 弹性过界 — 已完成（commit 0653a0d）

用户确认（2026-09-24）：按计划实现，并把 MCP 页、记忆页也纳入；非聊天列表改为弹性过界。

### 改动文件
| 文件 | 改动 |
| --- | --- |
| `lib/presentation/motion/nexus_staggered_entrance.dart`（新） | `NexusStaggeredEntrance`：每个列表 1 个 controller，最长 430ms。`NexusStaggeredItem`：只在挂载时决定是否参与入场，结构保持稳定。`NexusStaggeredItem.wrap(itemBuilder)` 用来包装已有的 itemBuilder，不用改动其中的 item 代码 |
| `lib/presentation/theme/app_tokens.dart` | `durationListItem` 220ms、`listStagger` 30ms、`listStaggerMaxItems = 8` |
| `lib/presentation/motion/nexus_motion.dart` | 3 个别名；`listPhysics = BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())` |
| `history/history_page.dart` | 加 Scope、`physics`，itemBuilder 用 `wrap` 包装（分组头也按 index 参与） |
| `agents/agents_page.dart` | 同上（首项是「描述生成」入口卡片） |
| `mcp/mcp_servers_page.dart` | 同上 |
| `memory/memory_page.dart` | 加 Scope 和 `physics`；记忆卡片按 `filtered.indexed` 编号参与入场（搜索栏和统计卡片保持静止） |
| `dashboard/dashboard_page.dart` | 加 Scope 和 `physics`；待办 → 性能详情（开发者模式下为 4 个指标区块）→ 最近会话，依次编号 |
| `test/nexus_staggered_entrance_test.dart`（新） | 9 个用例：错开时序、整个列表只有 1 个 ticker、第 9 项起不动画、重建和滚动时不重播、玻璃模式不包 Opacity、reduced/off/没有 Scope 时直接显示、弹性过界回弹、弹性过界下下拉刷新仍能触发、总时长 430ms |

实际改动 +398/−25（`git diff -w`），其余是重新缩进。

### 验收
- analyze 无问题；目标测试 9 个通过；全量测试 **1433 通过**；fast APK 构建成功（64.5s）。

### 性能
- 每个列表 1 个 ticker，最长 430ms，结束后 `transientCallbackCount == 0`。
- 玻璃卡片只做 transform，不进入透明度缓冲区。
- 聊天列表不受影响。

### 行为变化
- 5 个列表页内容不足一屏时，也可以弹性下拉。仪表盘的下拉刷新已由测试确认仍能触发。

### 回滚
- `git revert 0653a0d`；补丁：`artifacts/motion-logs/m3_changes.patch.txt`。

### 下一步：M4 卡片按压光感（光随指动）——待出 diff 计划

---

## M4 卡片按压光感（光随指动）— diff 计划（待确认）

### 实现思路
项目中的卡片（`SectionCard`，79 处使用）本身不处理点击，点击来自卡片内部的 `ListTile` / `InkWell`。逐个改调用点风险大，所以换一种接入方式：
- **卡片与列表行**：新增自定义水波纹 `NexusTouchLight`（Flutter `InteractiveInkFeature`）。`SectionCard` 和 `NexusListTile` 在内部用 `Theme` 把 `splashFactory` 替换为它，卡片里所有 InkWell 自动获得光斑，调用点零改动。
- **`NexusPressable`**（输入框按钮、回到最新、附件面板，共 6 处）：没有 InkWell，改为在组件内部叠加前景 `CustomPaint`。按下时记录触点位置，手指移动时光斑跟随（`Listener.onPointerMove`），原有缩放 0.97 保留。
- 全局主题**不改**：卡片以外的按钮仍保持系统默认水波纹。

### 参数
| 项 | 参数 |
| --- | --- |
| 出现 | touch-down 立即出现，100ms 升到峰值（快速跟手） |
| 消失 | 抬起或取消后 220ms 淡出，`curveStandard` |
| 形状 | 以触点为中心的径向渐变，半径 = 卡片短边 × 0.9，裁切到卡片圆角 |
| 颜色 | 深色：白色，中心 α 0.14，`BlendMode.plus`。浅色：见下方问答（计划原定 `softLight`，但项目的浅色卡片是纯白底，softLight 叠在纯白上完全看不见） |
| 跟随 | `NexusPressable` 跟随手指；InkWell 类的光斑停在按下点（手指移动超过容差时 InkWell 本身会取消点击，行为与系统一致） |
| 低端机（tier low） | 不画光斑，保留系统高亮（highlight）和缩放 |
| reduced | 不画光斑、不缩放，只保留静态高亮 |
| off | 同 reduced（静态高亮属于反馈，不是动效，保留对无障碍更友好） |

### 改动文件
| 文件 | 改动 | 规模 |
| --- | --- | --- |
| `lib/presentation/widgets/nexus_touch_light.dart`（新） | `NexusTouchLight`（InkFeature + factory），`NexusTouchLightScope`（按 tier/level 选择 factory 的 Theme 包装），`NexusTouchLightPainter`（供 NexusPressable 使用）。按半径和颜色缓存 Shader | 约 200 行 |
| `lib/presentation/widgets/section_card.dart` | 玻璃 / 纯色 / NexusSurface 三个分支的 child 外包一层 `NexusTouchLightScope` | +6 |
| `lib/presentation/widgets/nexus_list_tile.dart` | InkWell 外包 `NexusTouchLightScope` | +3 |
| `lib/presentation/widgets/nexus_pressable.dart` | 改为 SingleTickerProvider，加入光斑 controller、触点跟随、前景 CustomPaint；缩放逻辑不变 | 约 +50 |
| `lib/presentation/theme/app_tokens.dart` / `nexus_motion.dart` | `durationTouchLightIn` 100ms、`durationTouchLightOut` 220ms | +6 |
| `test/nexus_touch_light_test.dart`（新） | SectionCard 内 InkWell 使用 NexusTouchLight；按下立即出现，抬起后淡出并释放；tier low、reduced、off 下不画光斑；NexusPressable 跟随手指；深浅色 α；卡片以外的 InkWell 不受影响 | 约 180 行 |

不改路由、状态管理和全局主题，也不新增依赖。点击回调、语义、Tooltip 全部保持不变。

### 风险
- 中低。影响面大（卡片里的所有 InkWell），但只改变按下时的视觉反馈。`contrast_guard_test` 和全量测试会把关。
- 回滚：单独提交，`git revert` 即可。

---

## M4 卡片按压光感（光随指动）— 已完成（commit 4b75c14）

用户确认（2026-09-24）：按计划实现；浅色模式使用品牌色淡光晕。

### 改动文件
| 文件 | 改动 |
| --- | --- |
| `lib/presentation/widgets/nexus_touch_light.dart`（新） | `NexusTouchLight`（参数与颜色、`enabled(context)`）；`NexusTouchLightScope`（按档位选择光斑或 `NoSplash`，替换后的主题按「原主题 × 工厂」缓存）；自定义 InkFeature；`NexusPressLightPainter` |
| `lib/presentation/widgets/section_card.dart` | 三个分支的 child 统一换成 `NexusTouchLightScope(child: child)`（+1 import，+2 行） |
| `lib/presentation/widgets/nexus_list_tile.dart` | InkWell 外包 `NexusTouchLightScope` |
| `lib/presentation/widgets/nexus_pressable.dart` | 新增光斑 controller、触点跟随（`Listener.onPointerMove`）、前景 CustomPaint；包装结构固定，档位降级时不会重挂子树；原缩放逻辑不变 |
| `test/nexus_touch_light_test.dart`（新） | 7 个用例：深浅色工厂、卡片以外保持系统默认、按下画出光斑并在抬起后移除、低端档/reduced/off 降级、Pressable 跟随手指、低端档仍保留缩放、颜色 α |

- 实际使用已有 token：进入 `NexusMotion.instant`（100ms），淡出 `NexusMotion.base`（220ms），没有新增时长 token。

### 验收
- analyze 无问题；目标测试 7 个通过（首轮 3 个失败都是测试本身的时序问题：InkWell 的 tap-down 要等 100ms 按压判定，主题切换有 200ms 过渡。已修正测试）。
- 全量测试 **1440 通过**，含 `contrast_guard_test`；fast APK 构建成功（64.8s）。

### 性能
- 只在按下到淡出的约 320ms 内逐帧绘制一个带径向渐变的圆，没有常驻 ticker。
- 卡片主题副本有缓存，重建时不会重复执行 `copyWith`。

### 回滚
- `git revert 4b75c14`；补丁：`artifacts/motion-logs/m4_changes.patch.txt`。

### 下一步：M5 发送按钮涟漪 + 用户气泡弹簧升起——待出 diff 计划

---

## M5 发送按钮涟漪 + 用户气泡弹簧升起 — diff 计划（待确认）

### 现状（扫描结果）
- 发送按钮是 `floating_capsule_input.dart` 里的 `_FilledCircleButton`（外层包 `NexusPressable`，按下缩放 0.97，回弹用 `easeOutBack` 150ms）。
- 输入框使用 `TextInputAction.newline`，回车只换行，**没有键盘回车发送**的路径，所以只处理按钮发送。
- 新消息入场是 `chat_message_list.dart` 的 `_MessageEntrance`：所有角色统一 220ms 淡入 + 上移 2.5%。reduced / off 下直接显示。

### 参数
| 项 | 参数 |
| --- | --- |
| 发送按钮按下 | 缩放 0.9（其他按钮保持 0.97） |
| 发送按钮抬起 | `springLively` 归一化曲线回到 1.0，允许轻微过冲（约 1.4% 缩放），时长 320ms |
| 发送光圈 | 从按钮中心扩散的描边圆环，半径 0 → 28dp，α 0.35 → 0，线宽 1.5dp，280ms，`curveEnter`，品牌色；画在输入框玻璃**之上**的前景层 |
| 用户气泡 | translateY 16dp → 0，scale 0.96 → 1（锚点右下），opacity 只在前 50% 时长内完成，`springRelease` 归一化曲线，320ms |
| 助手气泡 | **不变**（仍是现有的 220ms 淡入 + 上移） |
| 触觉 | 沿用 `NexusHaptics.light` |
| 低端机 | 保留缩放和气泡弹簧；不画光圈（`MotionBudget.sendRipple`） |
| reduced / off | 沿用现有行为：气泡直接出现、按钮不缩放、没有光圈。计划原本写的是「reduced 下 120ms 淡入」，但为了不改变现有默认行为，这里保持不变 |
| 助手占位 120ms 后淡入 | 放到 M9（思考指示）中处理 |

### 改动文件
| 文件 | 改动 | 规模 |
| --- | --- | --- |
| `lib/presentation/motion/nexus_motion.dart` | `NexusSpringCurve` 增加 `allowOvershoot` 参数（默认 false，M1 行为不变）；新增 3 个 token 别名 | +10 |
| `lib/presentation/theme/app_tokens.dart` | `durationSendRipple` 280ms、`durationBubbleRise` 320ms、`durationPressRelease` 320ms（具名常量） | +8 |
| `lib/presentation/widgets/nexus_pressable.dart` | 新增可选参数 `releaseCurve`、`releaseDuration`，默认值与现在一致 | +8 |
| `chat/widgets/floating_capsule_input.dart` | State 加 `SingleTickerProviderStateMixin` 和 `_sendPulse` controller；`_FilledCircleButton` 透传 `pressedScale`、`releaseCurve`、`releaseDuration`（只有发送按钮使用）；发送时启动光圈；按钮槽位外包一层前景 `CustomPaint`（`_SendRipplePainter`） | 约 +60 |
| `chat/widgets/chat_message_list.dart` | `_MessageEntrance` 增加 `isUser` 参数。为 true 时走用户气泡变体，调用处传入 `message.role == MessageRole.user`，默认分支代码不动 | 约 +30 |
| `test/send_motion_test.dart`（新） | 发送按钮缩放 0.9、其他按钮仍是 0.97；光圈的起点、终点与释放；低端档不画光圈；用户气泡起点（16dp / 0.96 / α）与到位；助手气泡保持原样；reduced 直接显示；`NexusSpringCurve(allowOvershoot)` 会过冲且终点为 1 | 约 170 行 |

不改路由、状态管理、发送逻辑和消息数据，也不新增依赖。

### 风险
- 中低。聊天页是核心页面，但只包装动画，发送回调与原来完全一致。
- 回滚：单独提交，`git revert` 即可。

### M5 实施记录（已提交 39406fe）
- 用户决定：reduced 下保持现状（直接出现）；光圈用 1.5dp 描边圆环。
- 改动：`app_tokens.dart`、`nexus_motion.dart`（`NexusSpringCurve.allowOvershoot`、`curveSendRelease`、`curveBubbleRise`）、`nexus_pressable.dart`（`releaseCurve` / `releaseDuration`）、`floating_capsule_input.dart`（`_sendPulse` 与 `_SendRipplePainter`）、`chat_message_list.dart`（`_MessageEntrance.isUser`），新增测试 `test/send_motion_test.dart`（9 个）。
- 检查：analyze 无问题；全量测试 1449 通过；fast APK 构建成功（64.3s）。
- 事故：`dart format` 误作用于整个目录，把与本项无关的约 90 个文件重新格式化了。已通过 `git checkout` 还原，提交中只有本项的 6 个文件。以后只格式化本次改动的文件。
- 性能：光圈只在发送后的 280ms 内重绘前景层，静止时不绘制；气泡升起只做 Transform 和 Opacity，不触发重新布局。
- 回滚：`git revert 39406fe`；补丁见 `artifacts/motion-logs/m5_changes.patch.txt`。

---

## M6 AI 流式回复出现 — diff 计划（待确认）

### 现状（扫描结果）
- 助手消息在运行中追加后，会先显示 `ReasoningCompactBlock`（思考 / 进度卡片）。首个 token 到达时，正文由 `message_bubble.dart` 里的 `if (hasText) body` 在一帧内直接出现，没有过渡。
- 答案开始后，进度卡片切换为 `condensedProgress`，进度时间线 `_buildProgressTimeline` 在一帧内消失，高度突变，下方正文会跳一下。
- 流式期间正文用 `StreamingMarkdown`（纯文本尾部），结束后换成完整 Markdown。这一步切换不在本项范围内。
- 与 motion_plan 的差异：plan 把改动文件写成 `chat_message_list.dart`，实际位置在 `message_bubble.dart`，按实际位置修改。

### 参数
| 项 | 参数 |
| --- | --- |
| 首 token 出现 | 正文区在流式中首次挂载时 opacity 0 → 1，180ms，`curveEnter`。只动画这一次，**不对逐个 token 做动画** |
| 历史消息 / 已完成消息 | 不动画（opacity 恒为 1，不创建 controller） |
| 进度时间线收起 | `AnimatedSize` 220ms，`curveStandard`，顶部对齐。时间线增删步骤时也会平滑变化高度 |
| 流式结束切换为 Markdown | 不做动画：对长 Markdown 做 AnimatedSize 代价高，还会干扰列表跟随滚动 |
| 低端机 | 保留（只有 opacity 和一次尺寸插值，开销很小） |
| reduced / off | 直接显示，时长 0 |

### 改动文件
| 文件 | 改动 | 规模 |
| --- | --- | --- |
| `theme/app_tokens.dart` / `motion/nexus_motion.dart` | `durationAnswerReveal` 180ms 与别名 `answerReveal` | +6 |
| `chat/widgets/message_bubble.dart` | 新增私有 `_AnswerReveal`（StatefulWidget）：`if (hasText) body` 改为 `if (hasText) _AnswerReveal(animate: lightweight, child: body)`。包装结构始终存在，不动画时 opacity 用常量 1，避免流式结束时子树被重新挂载 | 约 +50 |
| `chat/widgets/reasoning_block.dart` | 用 `AnimatedSize` 包住时间线的条件区，隐藏时给零高度占位；reduced 下时长为 0 | 约 +12 |
| `test/stream_reveal_test.dart`（新） | 首 token 淡入的起点、终点与只播放一次；历史消息不动画；reduced 下直接显示；时间线收起时有中间高度，并能 settle；settle 后没有残留 ticker | 约 150 行 |

不改流式逻辑、消息数据或滚动逻辑，也不新增依赖。

### 风险
- 中低。聊天气泡是高频组件，但新增的只是一层 FadeTransition（opacity 为 1 时不产生额外 layer）和一个局部 AnimatedSize。
- 回滚：单独提交，`git revert` 即可。

### M6 实施记录（已提交 a268389）
- 用户决定：流式结束切换为 Markdown 时不做动画。
- 改动：`message_bubble.dart` 新增私有 `_AnswerReveal`（首个 token 淡入 180ms，只在流式中首次挂载时播放）；`reasoning_block.dart` 新增 `_buildTimelineSlot`（时间线收起用 AnimatedSize 220ms）；新增 token `answerReveal`；新增测试 `test/stream_reveal_test.dart`（6 个）。
- 第一次全量测试失败 1 个：`motion_ui_regression_test` 的 “an active message entrance finishes when motion is reduced”。原因是淡入途中切换到 reduced 时 controller 没有停止。已修复（`didChangeDependencies` 中检测到 reduced 就立即完成），并补了对应测试。
- 另一个坑：零时长的 AnimatedSize 会在布局中重新标脏自身，触发断言。因此 reduced / off 下不包 AnimatedSize。
- 检查：analyze 无问题；全量测试 1455 通过；fast APK 构建成功（64.5s）。只格式化了本次改动的文件。
- 性能：opacity 为 1 时 FadeTransition 不产生额外 layer；历史消息不创建 controller；不对逐个 token 做动画。
- 回滚：`git revert a268389`；补丁见 `artifacts/motion-logs/m6_changes.patch.txt`。

---

## M7 背景光晕 — diff 计划（已确认，方案 A）

### 现状（扫描结果）
- `ChatEmptyState` 只在 `messages.isEmpty` 时挂载（`chat_page.dart` 中的 `Builder(builder: _emptyState)`），根结构是 `Center(SingleChildScrollView)`。
- `NexusBackground` 是中性渐变底，没有彩色光斑，按既有设计决策保持不变。
- `MotionLifecycle` mixin 已存在：会综合 App 前后台、`TickerMode`（页面被遮挡）和 `allowDecorativeMotion`（只有 full 档为 true）来决定装饰动效是否运行。
- `MotionBudget` 已有 `ambientGlow`、`ambientDrift`、`ambientBreathing` 三个开关：high 全开；mid 只有呼吸；low 静态；reduced 静态；off 不画。

### 与 motion_plan 的冲突（需要你决定）
motion_plan 写的是「思考中光晕提升到 1.3 倍」，同时又要求「只在空状态页挂载」。但思考时列表里已经有消息，空状态不可见，两条不能同时满足。
- 方案 A（推荐）：M7 只做空状态光晕；思考中的视觉交给 M9（思考流光）。
- 方案 B：在思考卡片周围画一圈局部小光晕。缺点是它在滚动列表里，会经过玻璃输入框下方，带来逐帧重新采样的风险。

### 参数
| 项 | 参数 |
| --- | --- |
| 形态 | 两团径向渐变：主色为品牌色，α 0.10；辅色为冷蓝，α 0.08；半径为宽度的 0.7；中心位于空状态区域上 1/3（左右错开） |
| high | 12s 周期 Lissajous 漂移（位移 ≤ 24dp）+ 亮度呼吸 ±15% |
| mid | 只呼吸 |
| low / reduced | 静态（reduced 只画主色一层） |
| off | 不绘制 |
| 刷新方式 | 用 **50ms 周期的 Timer（约 20fps）** 驱动重绘，不用逐帧 Ticker。光晕变化极慢，20fps 看不出台阶；同时，输入框和顶栏的玻璃模糊不会因此每帧重算，raster 开销约为逐帧方案的 1/3 到 1/6 |
| 测试兼容（修订） | 原计划说 Timer 能避免 `pumpAndSettle` 超时，这个说法**有误**：Timer 触发重绘同样会调度新帧，`pumpAndSettle` 仍会一直等下去。现有 5 个测试文件在空状态下调用了 `pumpAndSettle`。修订为：**只有在树上挂了 `MotionTierScope`（即真实 App，由 `main.dart` 注入）时光晕才循环**；没有 Scope 的独立 widget 测试一律画静态光晕。新增 `MotionTierScope.maybeOf`，不改变现有 `of` 的行为 |
| 生命周期 | 接入 `MotionLifecycle`：进入后台、页面被遮挡或非 full 档时停止 Timer |
| 绘制 | `CustomPainter` + `RadialGradient`，不使用 blur 滤镜；外包 `RepaintBoundary`、`IgnorePointer`、`ExcludeSemantics`；混合模式 srcOver |
| 对比度 | α 上限 0.12，测试中断言 |

### 改动文件
| 文件 | 改动 | 规模 |
| --- | --- | --- |
| `widgets/ambient_glow.dart`（新） | `AmbientGlow` 与 `_AmbientGlowPainter`，按 `MotionBudget` 分档 | 约 150 |
| `chat/widgets/chat_empty_state.dart` | 根结构改为 `Stack(fit: expand)`：底层 `Positioned.fill(AmbientGlow())`，上层是原来的 `Center(...)`，内容不变 | +8 |
| `motion/motion_tier.dart` | 新增 `MotionTierScope.maybeOf`（未挂 Scope 时返回 null） | +8 |
| `theme/app_tokens.dart` / `motion/nexus_motion.dart` | 光晕周期 12s、刷新间隔 50ms、漂移幅度 24dp 等具名常量 | +10 |
| `test/ambient_glow_test.dart`（新） | high 档会漂移且 `pumpAndSettle` 可结束；mid 只呼吸；low / reduced 静态，且不创建 Timer；off 不绘制；TickerMode 关闭时停止；α ≤ 0.12；空状态挂载了光晕 | 约 160 行 |

不改路由和 `chat_page.dart`，也不新增依赖。

### 风险
- 中（性能）。靠 20fps 刷新、RepaintBoundary 和生命周期停止来控制。真机上需要用 DevTools 看 raster 耗时（这一步我无法代劳，需要你在 profile 模式下验证）。
- 回滚：单独提交，`git revert` 即可。

### M7 实施记录（已提交 f54d59e）
- 用户决定：采用方案 A，M7 只做空状态光晕，思考中的视觉交给 M9；批准后，之后的低风险项不再逐项确认。
- 改动：新增 `widgets/ambient_glow.dart`（`AmbientGlow` 与 `AmbientGlowPainter`）；`chat_empty_state.dart` 的根结构改为 `Stack`，底层 `Positioned.fill(AmbientGlow())`，内容不变（`dart format` 让原有内容多缩进了一层，因此 diff 行数较多）；`motion_tier.dart` 新增 `MotionTierScope.maybeOf`；新增 token `ambientGlowPeriod` 12s、`ambientGlowTick` 50ms、`ambientGlowDrift` 24dp；新增测试 `test/ambient_glow_test.dart`（11 个）。
- 对比度：第一次运行时，对比度测试按「两层都取 α 上限 0.12 且完全重叠」计算，浅色模式次级文字对比度为 4.40，未达到 4.5。实际呼吸峰值为主色 0.115、辅色 0.092，重叠时为 4.54，达标。测试已改为使用真实峰值；单层 α 上限 0.12 不变，由另一个测试断言。
- 检查：`flutter analyze lib test` 无问题；全量测试 1466 通过；fast APK 构建成功（61.9s）。只格式化了本次改动的文件。
- 性能：只有挂了 `MotionTierScope` 且档位允许时才循环；Timer 约 20fps；`RepaintBoundary` 隔离重绘；后台或页面被遮挡时停止。raster 耗时需要在真机 profile 模式下用 DevTools 确认。
- 回滚：`git revert f54d59e`；补丁见 `artifacts/motion-logs/m7_changes.patch.txt`。

---

## M8 光尘粒子 — diff 计划（低风险项已获授权，写完直接实施）

### 现状（扫描结果）
- 空状态位于 `chat_page.dart` 的 Column 中：上面是顶栏占位（`capsuleTopBarHeight + 4`），中间 `Expanded` 是空状态，下面是 `FloatingCapsuleInput`。空状态区域与顶栏、输入框这两块玻璃**不重叠**，所以把粒子限制在空状态区域内，就满足了「不进入输入框和胶囊栏」。
- M7 的 `AmbientGlow` 已有一个 20fps Timer，并接入了 `MotionLifecycle`。

### 参数
| 项 | 参数 |
| --- | --- |
| 数量 | high 28 / mid 14；low、reduced、off 不挂载；没有 `MotionTierScope`（独立 widget 测试）时也不挂载 |
| 单个粒子 | 半径 0.8–2.2dp；α 0.15–0.45；寿命 4–7s；上浮 6–14dp/s；±4dp 正弦横摆；寿命首尾各 20% 淡入淡出 |
| 发射区 | 椭圆，中心 (0.5w, 0.34h)，半轴 (0.34w, 0.12h)，与光晕对齐 |
| 边界 | 画布 `clipRect` 限制在空状态区域内；距顶边 24dp 内渐隐；飘出顶边或寿命结束后在发射区重生 |
| 时钟 | **与 M7 光晕共用同一个 Timer**，不另开 Ticker。两个独立时钟交错会让实际刷新率翻倍（20fps → 40fps） |
| 混合模式 | 深色用 `plus`（颜色 #C9D4FF）；浅色用 `srcOver`（品牌色） |
| 降级 | 运行时降到 low 时粒子立即卸载，光晕保留；这与「先关粒子，再简化光晕」的顺序一致 |
| 状态存储 | `Float32List`，每个粒子 8 个 float；推进过程零分配 |

### 与 motion_plan 的差异
- plan 要求用 `drawPoints` / `drawVertices` 批量绘制。但 `drawPoints` 不支持给每个点单独设 α，而本方案每颗粒子的 α 都不同，所以改为逐个 `drawCircle`。最多 28 次，开销可以忽略。
- plan 的「思考态速度 ×1.4、向中心聚拢」按方案 A 不做：思考时空状态已经卸载。

### 改动文件
| 文件 | 改动 |
| --- | --- |
| `widgets/light_dust_field.dart`（新） | `LightDustSystem`（粒子状态与推进）和 `LightDustPainter`（绘制） |
| `widgets/ambient_glow.dart` | 持有 `LightDustSystem`，在同一次 tick 中推进；绘制改为 `Stack`（光晕在下、粒子在上），共用一个 `RepaintBoundary` |
| `test/light_dust_field_test.dart`（新） | 8 个测试：出生点在发射区内；长时间推进后粒子在区域内且 α、半径都在范围内；顶边渐隐；同一种子结果可复现；high 28 颗、mid 14 颗且随时钟推进；low / reduced / off / 无 Scope 时不挂载；运行时降档后卸载粒子；深色 / 浅色的混合模式 |

不改 `chat_empty_state.dart`、路由和状态管理，也不新增依赖。

### M8 实施记录（已提交 a68c708）
- 第一次 analyze 有 1 个错误：`material.dart` 不导出 `ValueListenable`，需要保留 `foundation.dart` 的导入；另有 1 条提示：`dart:typed_data` 的导入多余。两处都已修复。
- 第一次定向测试失败 1 个：`MaterialApp` 切换主题时有 200ms 过渡，测试读取得太早。改为等 300ms 后再读；实现代码本身没有问题。
- 检查：`flutter analyze lib test` 无问题；全量测试 1474 通过；fast APK 构建成功（63.3s）。只格式化了本次改动的文件。
- 性能：没有新增时钟，刷新率仍约 20fps；每帧最多 28 次 `drawCircle`，零分配。空状态里的玻璃卡片位于发射区下方，粒子向上飘，基本不会经过卡片。真机上仍建议用 profile 模式确认 raster 耗时。
- 回滚：`git revert a68c708`（M7 不受影响）；补丁见 `artifacts/motion-logs/m8_changes.patch.txt`。

---

## M9 思考中 / 执行中 — diff 计划（低风险，写完直接实施）

### 现状（扫描结果）
- 思考标题是 `reasoning_block.dart` 里的 `_label`（「正在思考…」、进度阶段文案或「响应较慢，仍在继续…」），没有动效。
- `NexusExecutionStatus` 已有 1400ms 呼吸（图标 opacity 0.68↔1），接入了 `MotionLifecycle`。它用在顶栏运行状态、工具活动、任务页、协作时间线等处。
- 聊天与工具区在运行结束时会**移除**状态组件，而不是切换到 succeeded。实际发生 running → succeeded 切换的只有任务协作时间线这类页面。

### 参数
| 项 | 参数 |
| --- | --- |
| 思考标题流光 | `ShimmerText`：`ShaderMask(srcATop)` 线性渐变，高光带宽 40%；扫过 1600ms（`curveStandard`）+ 间隔 400ms；mid 档周期 ×1.5；浅色高光为品牌色，深色为 90% 白 |
| 流光开关 | 只在思考中开启；进入「响应较慢」时关闭，避免在卡住时还显得很忙；high / mid 开，low / reduced / off 关；和 M7 一样，只有挂了 `MotionTierScope` 时才循环 |
| 执行外发光环 | 与现有呼吸同相：α 0→0.25，外扩 0→6dp；用径向渐变绘制，不用 blur；画在图标背后，允许溢出，不改变布局；跟随 `MotionBudget.shimmer` 分档 |
| 完成收拢 | running / preparing → succeeded 时，光环在 180ms 内收拢（`curveExit`），颜色取成功色 |
| 边缘弧光 | 不做（你选的是不含弧光的 M9） |
| 触感 | **本次不加**，原因见下 |

### 触感为什么没加
plan 写的是「完成时 `NexusHaptics.success`」。但在组件层，running → succeeded 只会出现在按步骤展示的时间线里。如果在那里触发，每完成一步都会震动一次，太吵。真正代表「整次运行完成」的时机在 `chat_page` 的运行状态里，要在那里加就得改聊天页逻辑。这一项留作待你决定。

### 改动文件
| 文件 | 改动 |
| --- | --- |
| `widgets/shimmer_text.dart`（新） | `ShimmerText` 与 `shimmerGradient` |
| `widgets/nexus_execution_status.dart` | 改为 `TickerProviderStateMixin`；新增 `_finishController`（180ms）与 `ExecutionGlowRingPainter`；图标外层始终包一层 `CustomPaint`（painter 可为空），保持结构稳定 |
| `chat/widgets/reasoning_block.dart` | 用 `ShimmerText(enabled: thinking && !_isStalled)` 包住标题 |
| `theme/app_tokens.dart` / `motion/nexus_motion.dart` | 新增 `shimmerSweep`、`shimmerGap`、`glowRingSpread`、`glowRingCollapse` |
| `test/thinking_motion_test.dart`（新） | 10 个测试：high 档周期、mid 档 ×1.5、low / reduced / off / 无 Scope 时静态、关闭与遮挡时停止、高光在周期起止时位于文字之外、思考结束后停止流光、光环与呼吸同相、low / reduced 无光环、完成时收拢并结束、其他状态无光环 |

### M9 实施记录（已提交 5b4b247）
- analyze 有 1 个错误：测试中 `GradientTransform.transform` 的返回值可能为空，需要加 `!`，已修复。
- 检查：`flutter analyze lib test` 无问题；全量测试 1484 通过；相关的 6 个既有测试文件也都通过；fast APK 构建成功（62s）。只格式化了本次改动的文件。
- 性能：流光用 AnimationController 逐帧刷新，但只在思考中、只在一行文字上运行，外面还有 `RepaintBoundary` 包住的消息列表；光环复用现有的呼吸 controller，没有新增循环；收拢只持续 180ms。
- 回滚：`git revert 5b4b247`；补丁见 `artifacts/motion-logs/m9_changes.patch.txt`。

---

## M10 朗读声波条（per_message）

### 计划
- 新组件 `lib/presentation/widgets/speaking_wave.dart`：`SpeakingWave({color, level})` 有 4 根条，宽 2.5dp、间距 2dp、高 4–14dp。每根条周期 600/720/900/800ms，相位错开 120ms，一整轮循环 7200ms（token `speakingWaveLoop`），曲线 `curveBreathing`。
  - 传入 `level`（`ValueListenable<double>`）时进入真实电平模式，留给以后的语音输入复用。
  - reduced/off 档显示静态 `Icons.volume_up_rounded`。只有存在 `MotionTierScope`、`decorativeMotionActive` 为真且 `TickerMode` 开启时才循环。外层包 `ExcludeSemantics` 和 `RepaintBoundary`。
- 按消息显示：`_ChatPageState._speakingMessageIndex`（`ValueNotifier<int?>`）记录正在朗读的消息，TTS 的 `speakingListenable` 变为 false 时清空。`ChatMessageList` 新增可选参数 `speakingIndexListenable`，每个气泡拿到 `SpeakingAtIndex(源, index)`，按 (源, 索引) 判等，所以气泡缓存键保持稳定。
- `_ReplyActionRow`：正在朗读的那条消息，把停止按钮的图标换成声波条（tooltip 与读屏标签仍是「停止朗读」），其余消息显示「朗读」。
- 长按菜单的「停止朗读」只在被朗读的那条消息上出现。

### 实现记录
- 改动文件：`speaking_wave.dart`（新增）、`message_bubble.dart`、`chat_message_list.dart`、`chat_page.dart`（字段、监听、dispose、传参）、`chat_message_actions.dart`、`app_tokens.dart`、`nexus_motion.dart`、`test/speaking_wave_test.dart`（新增 10 个用例）。
- 行为变化：修复了原来所有回复一起显示「停止朗读」的问题。现在朗读中点另一条消息的「朗读」会切换到那一条，原来是直接停止。再点同一条仍是停止。
- `SpeakingAtIndex` 放在 `speaking_wave.dart` 里。原接口 `speakingListenable` 保留作兜底，旧测试不用改。
- 已知局限：索引对应的是朗读开始时的消息位置。朗读中切换会话后，TTS 不会自动停止，这点与原来一致；声波条可能出现在新会话同一位置的消息上，直到朗读结束。
- 中途问题：代码质量守卫限制硬编码 Duration ≤35 处，所以把 7200ms 改成了 token。
- 验证：analyze 通过；1494 个测试全部通过；fast 构建 OK。
- 性能：只有一个气泡运行 7200ms 的循环控制器，重绘范围限定在 RepaintBoundary 内，大约 20×14dp。
- 回滚：`git revert <M10 commit>`。

---

## M10+ 整轮成功触感（方案 A，用户已确认状态层改动）

### 计划 / 实现
- `ChatState` 新增 `successfulRunCount`（int，默认 0，只增不减）和对应的 copyWith 参数。只用于 UI 触感，不参与业务判断。
- 计数加 1 的位置：
  - `chat_run_execution.dart` 的最终收尾，两个 copyWith 分支，条件是 `runSucceeded = !runCancelled && runStatus == 'success'`；
  - `chat_controller.dart` 的任务续跑成功分支（`taskStatus == 'completed'`）。
- 失败、取消、暂停、异常分支都不计数。
- `chat_page.dart`：在已有的 `ref.listen` 里，当 `runSucceededBetween(prev, next)` 成立（计数增加）且 App 在前台时，调用 `NexusHaptics.success(context)`。动画 off 档时 NexusHaptics 会跳过。新会话重建状态导致计数归零时不会触发。
- 测试：新增 `test/run_success_haptic_test.dart`（2 个用例）；`chat_controller_test` 的 4 个现有用例补了断言：演示成功为 1，无输出、失败、停止都是 0。
- 验证：analyze 通过；1496 个测试全部通过；fast 构建 OK。
- 回滚：`git revert <本提交>`。

- 用户反馈后调整：成功触感改为 `NexusHaptics.light`（lightImpact），避免每轮都中等力度震动；已并入同一提交（amend）。

---

## M10 修正：切换会话时停止朗读（commit 329f90c）

- 用户选择 stop_tts：`chat_page` 已有的 `ref.listen` 检测到 conversationId 变化，且朗读是本页发起的（`_speakingMessageIndex != null`）时，调用 `TtsService.stop()`；停止后索引会随之清空。
- 新增 `@visibleForTesting shouldStopSpeakingOnSwitch`，并补 1 个测试。
- 验证：analyze 通过；全量测试 1497 个全部通过（分两半执行：761 + 736）；fast 构建 OK。
- 回滚：`git revert 329f90c`。

---

## 排查「UI 没有变化」+ 动效诊断（commit 62e36c8）

- 排查结论：构建脚本没有 bug。检查了 `dist/` 里各个 APK 的 libapp.so：
  - 09-18 与 09-24 22:36（c0c024e7）两个包**不含**任何动效代码；
  - 09-25 10:05 的 latest 包含 M0–M10 的全部内容。
  - 新旧包版本号都是 0.9.0+94、大小几乎一样，而且 latest 文件名每次都相同，所以手机上很容易装到旧包（例如聊天工具缓存了同名文件）。
- 本次改动：
  - `build-apk.bat`：通过 `--dart-define` 注入 `NEXUS_BUILD_SHA`（工作区 lib/pubspec 有未提交改动时带 `-dirty`）和 `NEXUS_BUILD_TIME`，构建时打印 `[info] Build stamp`。
  - 新增 `settings/motion_diagnostics.dart`，放在外观页「动效诊断」：显示构建标记、系统移除动画、App 动效设置、生效等级、设备档位与刷新率、玻璃限档，并给出结论。
  - `motion_tier.dart`：卡顿判定预算不低于 60Hz 的 16.7ms；运行时最低只降到 mid（low 只来自外部限档）。
  - 测试：新增 `test/motion_diagnostics_test.dart`（3 个），`motion_tier_test` 的降档断言相应调整。
- 验证：analyze 通过；全量测试 1500 个全部通过（761 + 739）；**正式 release 构建**成功，构建标记为 `62e36c8 20260925-1024`，已确认它在 APK 里。
- 保留策略自动删除了 09-24 那个不含动效的旧包。
- 回滚：`git revert 62e36c8`。

---

# 阶段 6：鸿蒙 7 风格加强（S1–S5）— diff 计划

背景：用户真机反馈「和之前看起来没区别」。已确认动效在运行（声波条可见），只是强度太弱。参照 HarmonyOS 7 的「空间美学 / 沉浸光感：光随指动、光线勾勒、非线性形变、更多粒子与光影」。
用户决定（2026-09-25）：S1–S4 全做；S5 同意新增 `sensors_plus`；强度预设默认「鲜明」。
执行顺序：S1 → S2 → S3 → S4 → S5，每项一个提交，都要跑 analyze / 全量测试 / release 构建。

## S1 动效强度预设（轻盈 / 标准 / 鲜明，默认鲜明）
- 新增 `motion/motion_intensity.dart`：`MotionIntensity { subtle, standard, vivid }`，增益 `gain` 分别为 1.0 / 1.5 / 2.0；工具函数 `amplify(base, gain, k) = base × (1 + (gain − 1) × k)`。
- `AppAppearanceController`：新增键 `settings.theme.motion_intensity`，默认 vivid。
- `MotionTierScope` 增加 `intensity` 参数，默认 subtle，保证现有测试不受影响；`main.dart` 从设置读取后传入。`MotionBudget` 增加 `gain`，粒子数同步放大。
- 各效果在鲜明档（gain = 2）下的取值：

| 效果 | 现在 | 鲜明 |
| --- | --- | --- |
| 粒子数（high / mid） | 28 / 14 | 48 / 24 |
| 粒子半径 | 0.8–2.2dp | 1.2–3.3dp |
| 粒子 α 上限 | 0.45 | 0.7 |
| 光晕 α | ×1 | 深色 ×1.8；浅色按对比度测试取最大可行值（目标 ×1.4） |
| 按压光斑 α（深 / 浅） | 0.14 / 0.08 | 0.28 / 0.16，半径 ×1.3 |
| 转场视差 / 暗化 | 30% / 0.12 | 45% / 0.22 |
| 发送光圈（半径 / 描边 / α） | 28dp / 1.5dp / 0.35 | 42dp / 2.5dp / 0.6 |
| 列表入场位移 | 12dp | 18dp |
| 流光带宽 | 0.4 | 0.5，高光更亮 |

- 外观页「动效偏好」下新增「动效强度」分段控件。
- 风险：浅色模式对比度 ≥ 4.5 由 contrast 测试守护；粒子增多后绘制开销约 ×1.7，仍在每帧 50 次 drawCircle 以内。

## S2 光线勾勒
- AI 运行中：输入胶囊的边框上有一段 90° 的高光弧沿圆角矩形循环流动，周期 2.4s，线宽 1.5dp（鲜明档 2dp），颜色为品牌色 → 透明。实现为 `EdgeTracePainter`（SweepGradient + 路径描边），只在 running 期间循环。
- 卡片按压：在 M4 光斑的基础上，离手指最近的边缘描出一段亮边（α 0.35），跟随手指移动。
- 分档：只有 high / mid 档开启，reduced / off 关闭。

## S3 非线性形变
- `NexusPressable`：按下缩放 0.96（原为 0.98），松手用 `springLively` 弹回并带 3% 过冲；发送按钮做「果冻」效果（X/Y 非等比缩放 1.08 / 0.92 → 1）。
- 列表过界：Android 上用 `StretchingOverscrollIndicator` 风格的拉伸代替回弹（iOS 保持回弹）。
- 分档：reduced / off 只保留缩放，不做过冲。

## S4 空间层次
- 转场时下层页面加缩放 1 → 0.94；high 档再加 4px 模糊（快照上的 ImageFilter，只在转场期间生效）。
- 侧边抽屉打开时，主页面缩放到 0.92、右移，加圆角 24dp，带深度感。
- 分档：low 档只保留暗化。

## S5 陀螺仪视差（新增依赖 sensors_plus，用户已确认）
- 空状态的光晕和粒子层随手机倾斜做 ±12dp 位移（低通滤波），前景卡片反向 ±4dp，形成层次。
- 只在空状态可见、high / mid 档、App 在前台时订阅传感器，采样约 30Hz；离开空状态或切到后台时取消订阅。
- 风险：新增原生插件，需要确认 Gradle 构建正常，不需要额外权限。

### S1 动效强度（鲜明默认）— 实施记录

**变更文件**（12 个 lib + 1 个新测试）
- 新增 `lib/presentation/motion/motion_intensity.dart`：`MotionIntensity { subtle 1.0 / standard 1.5 / vivid 2.0 }`、`amplify(base, gain, k)`
- `motion_tier.dart`：`MotionTierController.intensity`（变化即 notify）、`MotionTierScope.gainOf`、`MotionBudget.gain` + 粒子数放大（high 28→48 / mid 14→24）
- `app_appearance_controller.dart`：`settings.theme.motion_intensity`，默认 vivid
- `main.dart`：偏好 → `MotionTierController.app.intensity` 同步（+5 行）
- `ambient_glow.dart`：painter `alphaGain/radiusGain/driftGain`；深色 α×1.8，浅色 α 不变；半径 ×1.25、漂移 ×1.5
- `light_dust_field.dart`：`sizeGain/alphaGain`，α 上限 0.72（鲜明：半径 ×1.5、α ×1.6）
- `nexus_touch_light.dart` / `nexus_pressable.dart`：α ×gain（上限 0.3）、半径 ×1.3，工厂按（深浅, 增益）缓存
- `shimmer_text.dart`：高光带 0.4→0.5，深色高光 0.9→1.0
- `nexus_page_route_factory.dart`：视差 30%→45%，暗化 0.12→0.22
- `nexus_staggered_entrance.dart`：入场位移 12→18dp
- `floating_capsule_input.dart`：发送光圈 28dp/0.35/1.5dp → 42dp/0.6/2.5dp
- `appearance_theme_page.dart`：「动效偏好」卡片新增「动效强度」分段（轻盈/标准/鲜明）
- 新增 `test/motion_intensity_test.dart`（8 个用例）

**护栏**：强度只放大「量」，开关仍由分档决定——reduced / off / low 下粒子、漂移、流光依旧关闭；未挂 Scope 时增益 = 1（原有测试数值不变）。
**对比度**：浅色模式 α 上限约 ×1.05（lightTextMuted 在白底 4.5 红线附近），因此浅色只放大尺寸/漂移/粒子；深色 ×1.8 已有测试覆盖（≥ 4.5）。
**回滚**：设置里选「轻盈」即完全等于 S1 之前；代码回滚 `git revert <S1>`。

## 阶段 7：灵动大改（L 系列）

> Plan: `docs/motion_lively_plan.md`. Baseline b51a48b. WIP is in stash@{1} (40 modified files) and stash@{0} (18 untracked new files); merge back after the redesign.

### L0 灵动动效基础 v2
- Added `lib/presentation/motion/nexus_spring.dart`:
  - `NexusSprings.snappy / bouncy / smooth / reduced`, defined by response + ratio:
    - snappy: 0.5% overshoot, settles in 0.17–0.22s
    - bouncy: 5% overshoot, 0.31s
    - smooth: no overshoot, 0.28s
  - `critical()` removes overshoot. `curveOf / settleOf` cache the spring as a fixed-duration curve.
  - `NexusSpringPolicy.resolve/resolveFor`: off → null (instant); reduced → critically damped short spring; low tier → no overshoot.
  - `SpringController`: unbounded controller; each retarget starts from the current value and velocity, and drag release velocity can be passed in.
  - `SpringValue`: implicit spring number, keeps velocity when interrupted. `SpringAnimatedSize`: AnimatedSize using spring duration and curve.
- Default intensity changed to 轻盈 (`MotionIntensity.parse` fallback and `AppAppearanceController` default): decorative light is toned down, and the emphasis moves to motion.
- Tests: new `test/nexus_spring_test.dart` (13); `motion_intensity_test` updated for the new default. Full suite **1533** passing. analyze clean.
- Rollback: `git revert <L0>`. The new module isn't used by business code yet, so there is no risk.

### L1 触感：按压回弹 + 图标形变
- Added `motion/press_squash.dart`:
  - `PressSquash`: gesture-neutral. It only listens to the pointer and stays out of the gesture arena. It cancels once the finger moves past the touch slop (scrolling).
  - `PressScale`: squash driven by external state.
  - `NexusPressStyle`: global button style.
  - `NexusPressScale` levels: button 0.94 / card 0.97 / row 0.985.
  - Press uses snappy; release uses the new `NexusSprings.release` (response 0.30, ζ 0.52): overshoot about 15% of the squash depth.
  - The spring controller is created lazily on first press, so idle elements don't hold a Ticker. No scaling under reduced / off.
- Added `motion/morph_icon.dart`:
  - `NexusMorph.transition/duration/layout` and `MorphIcon`: bouncy scale from 0.5 to 1 plus a −0.08-turn rotation; reduced gets a fade only, off switches instantly.
  - `SpringTurns` replaces AnimatedRotation.
- **Global rollout:**
  - Theme: Filled / Elevated / Outlined / Text buttons get `NexusPressStyle.apply`, IconButton gets `IconButtonThemeData(style: squash)`. That's about 290 buttons with no call-site changes.
  - GlassSurface interactive: the 120ms AnimatedScale becomes a spring PressScale (card level). Covers all glass cards and chips.
  - Shared components: NexusListTile / SettingsTile / NexusDisclosure (row), GlassChip (button), NexusMetricTile (card).
- **Morphs:**
  - Send↔stop button (floating_capsule_input AnimatedSwitcher now uses NexusMorph).
  - Code block copy→✓ (MorphIcon).
  - Expand arrows in plan_panel ×2 / reasoning_block / tool_activity_section (SpringTurns).
- **Not covered:** raw `ListTile` / `InkWell` inside pages (about 130). Material has no global hook for these; they'll be picked up page by page in L3 / L6.
- Tests: new `test/press_morph_test.dart` (8); `glass_surface_test` updated for PressScale. Full suite **1541** passing, analyze clean.
- Rollback: `git revert <L1>`. To remove it locally, drop the `NexusPressStyle.apply` / `iconButtonTheme` lines from the theme.

### L1 触感：按压回弹 + 图标形变
- Added `motion/press_squash.dart`:
  - `PressSquash`: gesture-neutral. It only listens to the pointer and stays out of the gesture arena. It cancels once the finger moves past the touch slop (scrolling).
  - `PressScale`: squash driven by external state.
  - `NexusPressStyle`: global button style.
  - `NexusPressScale` levels: button 0.94 / card 0.97 / row 0.985.
  - Press uses snappy; release uses the new `NexusSprings.release` (response 0.30, ζ 0.52): overshoot about 15% of the squash depth.
  - The spring controller is created lazily on first press, so idle elements don't hold a Ticker. No scaling under reduced / off.
- Added `motion/morph_icon.dart`:
  - `NexusMorph.transition/duration/layout` and `MorphIcon`: bouncy scale from 0.5 to 1 plus a −0.08-turn rotation; reduced gets a fade only, off switches instantly.
  - `SpringTurns` replaces AnimatedRotation.
- **Global rollout:**
  - Theme: Filled / Elevated / Outlined / Text buttons get `NexusPressStyle.apply`, IconButton gets `IconButtonThemeData(style: squash)`. That's about 290 buttons with no call-site changes.
  - GlassSurface interactive: the 120ms AnimatedScale becomes a spring PressScale (card level). Covers all glass cards and chips.
  - Shared components: NexusListTile / SettingsTile / NexusDisclosure (row), GlassChip (button), NexusMetricTile (card).
- **Morphs:**
  - Send↔stop button (floating_capsule_input AnimatedSwitcher now uses NexusMorph).
  - Code block copy→✓ (MorphIcon).
  - Expand arrows in plan_panel ×2 / reasoning_block / tool_activity_section (SpringTurns).
- **Not covered:** raw `ListTile` / `InkWell` inside pages (about 130). Material has no global hook for these; they'll be picked up page by page in L3 / L6.
- Tests: new `test/press_morph_test.dart` (8); `glass_surface_test` updated for PressScale. Full suite **1541** passing, analyze clean.
- Rollback: `git revert <L1>`. To remove it locally, drop the `NexusPressStyle.apply` / `iconButtonTheme` lines from the theme.

### L1 触感：按压回弹 + 图标形变
- Added `motion/press_squash.dart`:
  - `PressSquash`: gesture-neutral. It only listens to the pointer and stays out of the gesture arena. It cancels once the finger moves past the touch slop (scrolling).
  - `PressScale`: squash driven by external state.
  - `NexusPressStyle`: global button style.
  - `NexusPressScale` levels: button 0.94 / card 0.97 / row 0.985.
  - Press uses snappy; release uses the new `NexusSprings.release` (response 0.30, ζ 0.52): overshoot about 15% of the squash depth.
  - The spring controller is created lazily on first press, so idle elements don't hold a Ticker. No scaling under reduced / off.
- Added `motion/morph_icon.dart`:
  - `NexusMorph.transition/duration/layout` and `MorphIcon`: bouncy scale from 0.5 to 1 plus a −0.08-turn rotation; reduced gets a fade only, off switches instantly.
  - `SpringTurns` replaces AnimatedRotation.
- **Global rollout:**
  - Theme: Filled / Elevated / Outlined / Text buttons get `NexusPressStyle.apply`, IconButton gets `IconButtonThemeData(style: squash)`. That's about 290 buttons with no call-site changes.
  - GlassSurface interactive: the 120ms AnimatedScale becomes a spring PressScale (card level). Covers all glass cards and chips.
  - Shared components: NexusListTile / SettingsTile / NexusDisclosure (row), GlassChip (button), NexusMetricTile (card).
- **Morphs:**
  - Send↔stop button (floating_capsule_input AnimatedSwitcher now uses NexusMorph).
  - Code block copy→✓ (MorphIcon).
  - Expand arrows in plan_panel ×2 / reasoning_block / tool_activity_section (SpringTurns).
- **Not covered:** raw `ListTile` / `InkWell` inside pages (about 130). Material has no global hook for these; they'll be picked up page by page in L3 / L6.
- Tests: new `test/press_morph_test.dart` (8); `glass_surface_test` updated for PressScale. Full suite **1541** passing, analyze clean.
- Rollback: `git revert <L1>`. To remove it locally, drop the `NexusPressStyle.apply` / `iconButtonTheme` lines from the theme.

### L2 输入胶囊形变 + 发送气泡飞出（2026-09-28）
- 新增 `lib/presentation/motion/send_flight.dart`：`SendFlightBus`（900ms 认领窗、一次性认领、胶囊 dispose 时作废）+ `SendFlightLanding`（FLIP：首帧透明测量，自输入框底边以 bouncy 弹簧竖直飞入，0.94→1 右下锚点缩放；异常位移/降级直接显示）。
- `floating_capsule_input`：输入区 `SpringAnimatedSize`（多行增高弹簧过渡，挂 `_fieldKey` 作飞出起点）；外边距 `_FocusMorphMargin` 聚焦 12→8 舒展；状态行 `SpringAnimatedSize`；＋↔× 改用 `NexusMorph` 形变；仅 full 级发起飞出。
- `chat_message_list._MessageEntrance`：用户消息认领飞行后以 `SendFlightLanding` 替代上浮入场。
- 两文件工作区 CRLF→LF（与索引一致）；移除未用 import。
- 测试：新增 `test/send_flight_test.dart` 7 例；全量 1548 通过；analyze 无问题。
- L2 追加（用户选"完整宽度形变"）：`SendFlightAnchor` 标记用户气泡（message_bubble 外包一层，无落地动画时透传）；落地改为"幽灵胶囊"——底色/圆角同气泡的矩形自输入框矩形以 bouncy 弹簧收缩到气泡矩形（圆角胶囊→20/20/20/6），气泡内容按最终宽度排版、随底边竖直飞入并于后半程淡入接棒，不重排文字；Stack passthrough 保持布局、落地前后元素树一致。测试 +3（共 10 例），全量 1550 通过。

### L3 消息与流式（2026-09-28）
- 新增 `lib/presentation/motion/spring_follow_height.dart`：`SpringFollowHeight` / `RenderSpringFollowHeight`——布局测内容高度，变化后帧后以 smooth 弹簧追随；动画中再次变化从当前值+速度重定目标（逐 token 不重新起步）；显示高度不足时裁底；enabled=false / 动效关闭即时。
- `chat_message_list`：助手消息外包 `SpringFollowHeight(enabled: 正在流式那条)`；助手入场改为 bouncy 弹簧（上移 14 + 0.97→1 左上锚点，透明度前 40%）。
- `NexusExpandSection`（工具卡、计划面板紧凑↔展开、思考过程、技术细节、NexusDisclosure 共用）改为 `SpringAnimatedSize`；reduced 直接切换（零时长 AnimatedSize 会自我标脏）。
- 思考点：应用内无跳动点（思考态为流光文字，M9 已有），该项不适用。
- 测试：新增 `test/spring_follow_height_test.dart` 6 例；`send_motion_test` 助手入场用例改为断言新行为；全量 1556 通过；analyze 无问题。

### L4 抽屉跟手 + 对话框自点击处长出（2026-09-28）
- `nexus_sheet._NexusSheetMotionState` 重写拖动：`SpringController` 驱动位移；下拉 1:1 跟手，上推越过静止位走橡皮筋（极限 36px）；过关闭阈值（0.18 屏高）时 selection 触感；松手未关闭则带手指速度以 bouncy 弹簧弹回（light 触感）；内容滚到顶后继续下拉由抽屉接管、抽屉下移时上滑先收回；入场曲线改 bouncy（allowOvershoot）轻回弹。
- 新增 `lib/presentation/motion/tap_origin.dart`：`NexusTapOrigin` 全局指针路由被动记录按下位置（1.5s 新鲜度 = kLongPressTimeout×3）；`app_presentation_preferences` 构建时 `ensureInstalled()`。
- `showNexusDialog`：`_NexusDialogMotion` 自点击点 0.72→1 bouncy 放大 + 前 45% 淡入（selfContained）；玻璃外壳分支不淡入、0.92 起；无新鲜点击时居中。
- 修正 L3：助手入场 `curveOf(pop, allowOvershoot: true)`（此前被夹掉过冲）。
- 未覆盖：19 处原生 `showModalBottomSheet`（Material 自带跟手/甩动，无法注入橡皮筋与弹簧，如需统一需逐个改用 showNexusSheet）；原生 PopupMenu。
- 测试：新增 `test/sheet_motion_test.dart` 10 例；全量 1566 通过；analyze 无问题。

### L5 容器变换 + 返回手势跟手（2026-09-28）
- `NexusPageRoute`（68 处调用零改动）：detail 路由构造时 `captureOrigin()`——取 L4 `NexusTapOrigin` 的新鲜按下点，在当前布局命中测试，选最内层「像卡片/行」的盒子（高≥44、宽≥96、面积≤半屏），否则 48×48 小方块；构建/布局阶段或异常时返回 null。
- 有起点时 `_ContainerMorph`：页面全屏布局、按矩形宽度缩放绘制并裁到矩形高度，矩形/圆角（radiusCard→0）以 smooth 弹簧曲线插值到全屏，前 35% 表面色面纱淡出（不用 Opacity，避免玻璃闪烁）；落定后结构不变不重建；下层改为只暗化（`_delegatedDimTransition`），不视差；返回沿原路收回卡片。无新鲜点击 / settings / workspace / fade / reduced 保持原行为。
- 返回手势：`_FollowGesture` 在 `navigator.userGestureInProgress` 期间直接用控制器线性进度（位移与容器变换均跟手）。系统级预测性返回需在 AndroidManifest 开启 `android:enableOnBackInvokedCallback`（原生配置，待用户确认，未改）。
- 测试：新增 `test/route_morph_test.dart` 5 例；全量 1571 通过；analyze 无问题。

### L6 分段拉伸 + Tab 弹性 + 抽屉统一（2026-09-28）
- 新增 `lib/presentation/widgets/nexus_segmented_button.dart`：`NexusSegmentedButton<T>`（SegmentedButton 同名参数、单选）；指示器两边各一根弹簧，运动方向前沿 snappy、后沿 smooth → 滑动中拉伸、到位收回；切换 selection 触感。替换 4 处（mcp_servers / device_backups / provider_detail / collaboration_plan_sheet）。
- `app_theme` tabBarTheme：`indicatorAnimation: TabIndicatorAnimation.elastic`。
- 19 处原生 `showModalBottomSheet` → `showNexusSheet`（丢弃 backgroundColor/shape；自行按 viewInsets 垫底的 5 处传 `removeInnerViewInsets: true`）；`showNexusSheet` 新增该参数，并在玻璃面内包透明 Material（修复 ListTile 墨水波纹被遮挡）。mcp_servers 移除随之无用的局部变量。
- AndroidManifest 开启 `enableOnBackInvokedCallback`（单独提交 80c0a9c，用户已确认）。
- 未做（说明）：Switch / RefreshIndicator 为 Material 内部动画、无法主题注入弹簧；应用无 Dismissible/AnimatedList，删除收拢无挂点；过度滚动已是 Android 拉伸效果。
- 测试：新增 `test/segmented_motion_test.dart` 2 例；全量 1573 通过；analyze 无问题。
- L6 追加（用户要求弹簧开关）：新增 `lib/presentation/widgets/nexus_switch.dart`——`NexusSwitch`（bouncy 弹簧滑块带轻回弹、直径 16→24、按住横向拉伸、轨道色插值、selection 触感、可横拖）与 `NexusSwitchListTile`；替换全部 10 处 Switch / Switch.adaptive 与 6 处 SwitchListTile；settings_page_test / device_capabilities_non_root_test 的类型查找改为 NexusSwitch。新增 `test/nexus_switch_test.dart` 3 例；全量 1576 通过。

## L7 微交互与光效收敛
- 新增 `lib/presentation/motion/micro_interactions.dart`：`RollingText`（数字滚动：只滚变化的字符，增大向上/减小向下，bouncy；静止为普通 Text）、`PopOnChange`（触发值变化 0.86→1 轻弹）、`CopyFeedbackButton`（复制后图标形变为 ✓，约 2s 恢复）。
- 接入：`NexusMetricTile` 数值（17 处使用）→ RollingText；`NexusStatusBadge` 状态/文案变化 → PopOnChange；消息气泡操作行复制 → CopyFeedbackButton（保留原 Toast 与触感）。代码块复制 ✓ 已于 L1 完成。
- 光效：盘点确认 AmbientGlow 仅在聊天空状态、Shimmer 仅在思考态，符合"只在空状态和思考态"约定，无需清理。
- 降级：off/reduced 下 RollingText 直接换值、PopOnChange 不弹。
- 测试：`test/micro_interactions_test.dart` 3 例；全量 1579 通过，analyze 无问题。

## L8 验收与交付
- 新增 `test/lively_acceptance_test.dart`（7 例）：令牌节奏/回弹幅度、开关 full/reduced/off 三档、off 档微交互不播放。全量 1586 通过，analyze 无问题。
- 新增交付文档 `docs/motion_lively.md`（令牌、分阶段内容、触感映射、验收与真机帧耗时清单、已知限制）。
- 真机帧耗时需用户手动按清单验收（手机未连接）。
