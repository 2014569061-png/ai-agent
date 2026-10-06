# NEXUS 移动端动效重构：最终交付说明（阶段 5）

- 分支：`feat/harmony-motion`（未推送，所有提交都只在本地）
- 时间：2026-09-24 至 2026-09-25
- 范围：在不改业务逻辑的前提下，给 Flutter 移动端 Agent App 加入参考鸿蒙风格的沉浸、光感、粒子、滑动与转场动效。**只借鉴思路，没有使用任何华为素材**（图形、音效、字体、代码都没有）。
- 相关文档：`docs/harmony_motion_research.md`（调研）、`docs/motion_scan.md`（现状扫描）、`docs/motion_plan.md`（规格）、`docs/motion_impl_log.md`（每一项的 diff 计划和实施记录）。

---

## 1. 结果总览

| # | 内容 | 提交 | 全量测试 |
| --- | --- | --- | --- |
| 基线 | — | — | 1404 |
| M0 | 公共基础：弹簧 token、性能分级 `MotionTier` / `MotionBudget` | 32a4f9a | 1404 |
| M1 | 整屏层级转场（上层弹簧推入，下层 −30% 视差 + 暗化） | 554131b | 1414 |
| M1 补充 | 从终端 Sheet 打开全屏终端时，先收起 Sheet 再推入 | 0ce25e0 | 1415 |
| M2 | 首屏入场编排（顶栏 → 主视觉 → 卡片 → 输入框，错开 40ms） | cb5eb86 | 1424 |
| M3 | 列表错开入场（最多 8 项、每项错开 30ms）+ 非聊天列表弹性过界 | 0653a0d | 1433 |
| M4 | 卡片按压光感（光斑跟随手指） | 4b75c14 | 1440 |
| M5 | 发送按钮 1.5dp 光圈 + 用户气泡弹簧升起 | 39406fe | 1449 |
| M6 | AI 回复首个 token 淡入，推理时间线平滑收起 | a268389 | 1455 |
| M7 | 空状态背景光晕（呼吸 + 漂移） | f54d59e | 1466 |
| M8 | 空状态光尘粒子 | a68c708 | 1474 |
| M9 | 「思考中」流光文字 + 执行状态光环 | 5b4b247 | 1484 |
| M10 | 朗读声波条（只在正在朗读的那条消息上显示） | 0d902de | 1494 |
| M10+ | 整轮运行成功时轻触感 | daff0ed | 1496 |
| M10 修正 | 切换会话时停止本页发起的朗读 | 329f90c | 1497 |

每一项都跑过：只格式化本次改动文件的 `dart format`、`flutter analyze lib test`（无问题）、全量 `flutter test`（全部通过）、`build-apk.bat --fast`（成功，约 62–65 秒，APK 约 26MB）。每项的补丁存档在 `artifacts/motion-logs/m*_changes.patch.txt`。

---

## 2. 架构与约定

### 2.1 性能分级（M0）

`lib/presentation/motion/motion_tier.dart`

- `MotionTierController` 通过 `addTimingsCallback` 统计帧耗时。前 90 帧不计入，避免冷启动误判。会话内**只降档、不升档**，降到 low 后注销回调。
- `MotionTierScope` 挂在 `MaterialApp.builder` 外层。玻璃强度为 flat 时，最高只到 low 档。
- `MotionBudget.of(context)` 合并「系统减弱动效 / 应用内动效开关（`MotionLevel`）」和「设备档位（`MotionTier`）」，是装饰层**唯一**读取的对象。

| 能力 | high | mid | low | reduced | off |
| --- | --- | --- | --- | --- | --- |
| 光尘粒子 | 28 | 14 | 0 | 0 | 0 |
| 背景光晕 | 漂移 + 呼吸 | 呼吸 | 静态 | 静态 | 无 |
| 流光 | 1.0× | 1.5× 周期 | 关 | 关 | 关 |
| 光随指动 / 发送光圈 / 转场视差 | 开 | 开 | 关 | 关 | 关 |
| 朗读声波条 | 伪波形 | 伪波形 | 静止 | 静态图标 | 静态图标 |

- 刷新率：120Hz 跟随系统设置，不强制开启高刷。
- 调试：`MotionTierController.debugOverride = MotionTier.low` 可以强制指定档位。

### 2.2 常驻循环的统一规则

M7–M10 的循环动效遵守同样的约束：

1. 只有祖先中存在 `MotionTierScope`（即真实 App 环境），且 `decorativeMotionActive` 为真时才循环。没有 Scope 的测试环境里保持静态，`pumpAndSettle` 可以正常结束。
2. 通过 `MotionLifecycle` 和 `TickerMode` 管理：App 进入后台或页面被遮挡时停止。
3. 外层包 `RepaintBoundary` 限定重绘范围；纯装饰内容包 `ExcludeSemantics`。
4. reduced / off 档给出静态版本，不产生 ticker。

### 2.3 Token

所有时长、曲线和尺寸都定义在 `lib/presentation/theme/app_tokens.dart`，并在 `lib/presentation/motion/nexus_motion.dart` 中提供别名。代码里不新增 `Duration(milliseconds: 数字)` 字面量，由 `code_quality_guard_test` 的计数门槛守护（本轮 M10 的 7200ms 就是因为这条规则才改成了 token）。

| Token | 值 | 用途 |
| --- | --- | --- |
| `springFollow` / `springRelease` / `springLively` | 弹簧参数 | 跟手、松手、活泼回弹 |
| `durationPageSpring` | 350ms | M1 推入（返回为 250ms `curveStandard`） |
| `durationEntrance` / `entranceStagger` / `durationReducedEntrance` | 260 / 40 / 120ms | M2 |
| `durationListItem` / `listStagger` / `listStaggerMaxItems` | 220ms / 30ms / 8 | M3 |
| `curveSendRelease` / `curveBubbleRise` | 弹簧曲线（允许过冲） | M5 |
| `answerReveal` | 180ms | M6 |
| `ambientGlowPeriod` / `ambientGlowTick` / `ambientGlowDrift` | 12s / 50ms / 24dp | M7、M8 |
| `shimmerSweep` / `shimmerGap` | 1600 / 400ms | M9 流光 |
| `glowRingSpread` / `glowRingCollapse` | 6dp / 180ms | M9 光环 |
| `speakingWaveLoop` | 7200ms | M10（600/720/900/800ms 四个周期的最小公倍数） |

---

## 3. 各项要点

### M1 整屏转场

- 文件：`nexus_page_route_factory.dart`。上层做 `SlideTransition(1→0)`，使用弹簧曲线 350ms；下层通过 `delegatedTransition` 位移到 −0.3，并叠加 α 0.12 的黑色遮罩。转场期间两层都是快照，下层最多重录 2 次（有测试守护）。
- 降级：low 档只暗化；reduced 档 120ms 淡入；off 档 0ms。没有做预测性返回（按用户决定）。

### M2 首屏入场

- 新增 `nexus_entrance.dart`，共 4 个槽位，总时长 380ms。玻璃外壳只做位移，不套 Opacity。
- 淡入使用 `alwaysIncludeSemantics`。修复了透明度为 0 的首帧会让读屏丢失标题的问题。

### M3 列表入场与弹性过界

- 新增 `nexus_staggered_entrance.dart`，每个列表只有 1 个 ticker，最长 430ms。
- 覆盖页面：历史、Agent、MCP、记忆、仪表盘。这 5 页改用 `BouncingScrollPhysics`，下拉刷新仍然可用。聊天列表不变。

### M4 按压光感

- 新增 `nexus_touch_light.dart`。深色模式用白光，浅色模式用品牌色淡光。只在按下到淡出的约 320ms 内绘制。
- 接入 `SectionCard`、`NexusListTile`、`NexusPressable`。

### M5 发送与气泡

- 发送后显示 1.5dp 圆环光圈，持续 280ms；用户气泡做弹簧升起。reduced 档下直接出现。

### M6 流式回复

- 首个 token 淡入 180ms，只在流式中首次挂载时播放。推理时间线收起用 AnimatedSize 220ms。
- 流式结束切换为 Markdown 时不做动画（按用户决定）。

### M7 / M8 空状态光晕与光尘

- `ambient_glow.dart`、`light_dust_field.dart`：共用一个 50ms Timer（约 20fps）。粒子数据存在 `Float32List` 里，每帧零分配，最多 28 次 `drawCircle`（每个粒子需要独立透明度，所以没用 `drawPoints`）。
- 对比度：光晕峰值 α 为 0.115 / 0.092。两层重叠时，浅色模式次级文字对比度为 4.54，满足 ≥ 4.5（`contrast_guard_test`）。

### M9 思考中 / 执行中

- `shimmer_text.dart`：推理标题在思考中显示流光，停滞时停止。
- `nexus_execution_status.dart`：执行光环复用已有的呼吸 controller，完成时收拢 180ms。没有做输入框边缘弧光（按用户决定）。

### M10 朗读声波条

- `speaking_wave.dart`：4 根条，宽 2.5dp、间距 2dp、高 4–14dp，各条相位错开。
  - 传入 `level`（`ValueListenable<double>`）即切换到真实电平模式，可以直接给以后的语音输入复用。
- 按消息显示：`_ChatPageState._speakingMessageIndex` 记录正在朗读的消息，`SpeakingAtIndex(源, 索引)` 为每个气泡派生是否在朗读。它按 (源, 索引) 判等，所以气泡缓存不会失效。
- 顺带修复：以前朗读任意一条时，所有回复都会显示「停止朗读」。
- 行为变化（用户已确认保留）：朗读中点另一条消息的「朗读」会切换去读那一条；再点同一条仍是停止。

### M10+ 整轮成功触感

- `ChatState.successfulRunCount` 只增不减，只在正常完成且结果为 success（包括任务续跑成功）时加 1。
- `chat_page` 在计数增加且 App 在前台时调用 `NexusHaptics.light`。动画 off 档会跳过；失败、取消、暂停都不震动。
- 这是本轮唯一改到状态层的地方（新增 1 个字段），用户已确认。

---

## 4. 验收清单（真机）

- [ ] 进入任意二级页：上层弹簧推入，下层左移并变暗；返回时反向。
- [ ] 冷启动首屏：顶栏、主视觉、卡片、输入框依次出现，总时长约 0.4 秒。
- [ ] 历史 / Agent / MCP / 记忆 / 仪表盘列表：前 8 项错开入场，滚动时不重播；内容不足一屏时也能弹性下拉。
- [ ] 按住卡片：光斑跟随手指移动，松手后淡出。
- [ ] 发送：出现一圈光圈，气泡带轻微弹性升起。
- [ ] AI 回复：首字淡入；思考中标题有流光；执行中有光环呼吸。
- [ ] 空状态：背景光晕缓慢呼吸和漂移，光尘上浮；切到后台再回来仍然正常。
- [ ] 朗读：只有被朗读的那条显示声波条；读完、再点一次或点另一条时状态正确；切换会话后朗读停止。
- [ ] 一轮任务成功结束时有一次轻震；点停止或出错时不震。
- [ ] 系统开启「移除动画」或应用内关闭动效：以上全部变为直接出现或静态，且没有震动。
- [ ] 低端机或 flat 玻璃模式：粒子、视差、光随指动关闭，其余正常。
- [ ] Profile 模式下用 DevTools 查看空状态和转场的 raster 耗时：目标 60Hz 设备 < 16ms，120Hz 设备 < 8ms。

---

## 5. 性能说明

- 转场期间多占一张全屏快照纹理（约 10MB），转场结束即释放。
- 常驻循环只有：空状态光晕/光尘（约 20fps，仅空状态可见时运行）、思考流光（仅思考中、一行文字）、朗读声波条（仅一个气泡、约 20×14dp）。它们都在 `RepaintBoundary` 内，并在后台或页面被遮挡时停止。
- 一次性动画（入场、按压、发送、淡入）结束后 `transientCallbackCount == 0`，有测试守护。
- 沙盒环境无法做真机 profile；raster 耗时需要按第 4 节最后一项在真机上确认。

---

## 6. 回滚

- 单项回滚：`git revert <提交>`，各项之间基本独立。
  - 注意 M8 依赖 M7（粒子由光晕的 Timer 驱动），回滚 M7 前需先回滚 M8。
  - M10+ 与 M10 互不依赖。
- 全部回滚：丢弃 `feat/harmony-motion` 分支即可，主分支从未改动。
- 补丁存档：`artifacts/motion-logs/`。

---

## 7. 已知局限与后续建议

1. M10 按消息索引记录朗读目标。~~切换会话后声波条可能错位~~：已修正，切换会话时会停止本页发起的朗读（用户选择），索引随之清空。
2. 声波条目前是伪波形。接入语音输入时，把麦克风电平（0–1）通过 `level` 传入即可，不需要改组件。
3. 没有做预测性返回手势，也没有做输入框边缘弧光（均按用户决定）。
4. 本轮新增 93 个测试（1404 → 1497），但动效的主观观感仍需要真机验收。
5. `docs/` 目录被 gitignore 忽略，本文档和实施日志不在提交里；如需归档，请手动复制或调整 `.gitignore`。
