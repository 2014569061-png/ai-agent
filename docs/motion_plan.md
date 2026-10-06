# 动效改造 · 阶段 3：动效方案

> 依据：`docs/motion_scan.md`（现状）和 `docs/harmony_motion_research.md`（规范）。
> 原则：**接入现有 `NexusMotion` / `MotionPreferences` / `MotionLifecycle` 体系，不另起一套**；不新增依赖；不改路由结构和状态管理；`chat_page.dart` 只挂接、不重写。
> 标记 ★ 的是本方案新增的 Token 或组件。

## 0. 公共基础（M0，必须最先做）

### 0.1 弹簧 Token ★（`lib/presentation/motion/nexus_motion.dart`）

| Token | 对应 HarmonyOS 思路 | Flutter 参数（推断换算） | 用途 |
| --- | --- | --- | --- |
| `springFollow` | responsiveSpringMotion(0.15, 0.86) | mass 1, stiffness 1755, ratio 0.86 | 跟手、按压 |
| `springRelease` | springMotion(0.55, 0.825) | mass 1, stiffness 130, ratio 0.825 | 离手、回弹、气泡升起 |
| `springLively` | interpolatingSpring(128, 12) | mass 1, stiffness 128, damping 12 | 轻微过冲（发送按钮） |

不改动现有贝塞尔 Token。`curveAccelerate` 命名错误的问题（R2）只记录在文档里，是否修正等你决定。

### 0.2 动效性能分级 ★（`lib/presentation/motion/motion_tier.dart`，新文件）

`enum MotionTier { high, mid, low }`，和已有的 `MotionLevel`（用户意愿）是两个独立维度。最终生效档位 = min(用户设置, 设备能力)。

| 判定 | 规则 |
| --- | --- |
| 初始档 | `display.refreshRate ≥ 90` 判为 high 候选，否则 mid。玻璃强度为 flat 时，装饰层直接按 low 处理 |
| 运行时降档 | 用 `SchedulerBinding.addTimingsCallback` 统计最近 120 帧。若超过帧预算（按 refreshRate 计算）的帧占比 > 8%，降一档。**会话内只降不升**，避免档位来回抖动 |
| 覆盖 | Debug 下可通过常量强制指定档位，便于测试 |
| 注入 | 在 `main.dart` 的 `MaterialApp.builder` 里包一层 `MotionTierScope`（InheritedNotifier）。只增加一层 widget，不动路由和 Provider |

**各档能力**（粒子/光晕/模糊）：

| 能力 | high | mid | low | reduced（减少动效） | off |
| --- | --- | --- | --- | --- | --- |
| 粒子数量 | 28 | 14 | 0 | 0 | 0 |
| 粒子刷新 | 每帧 | 每帧 | — | — | — |
| 光晕 | 双层渐变 + 缓慢漂移 | 单层、静态缓慢呼吸 | 静态单层 | 静态 | 无 |
| 边缘流光 / 扫光 | 开 | 开（周期 ×1.5） | 关 | 关 | 关 |
| 模糊 | 沿用玻璃设置 | 沿用 | 强制 frosted→静态 | 沿用现有降级 | flat |
| 位移动画 | 全量 | 全量 | 全量（很便宜） | ≤120ms，只保留淡入 | 0ms |

## 1. 动效参数表（按优先级）

### M1 页面进入 / 切换（P1）

| 项 | 参数 |
| --- | --- |
| 触发 | `NexusPageRoute` push / pop，以及两处残留的 `MaterialPageRoute` |
| 时长 | 进入 250ms（保持）；退出 180ms（保持）；fade 档 220ms |
| 曲线 | 位移：`curveEnter`(0,0,0.2,1)；透明度：`Interval(0, 0.6, curveStandard)`；返回：`curveExit` |
| 变化属性 | 上层页面：translateX 16/10/8dp（保持），**新增 opacity 0→1（只在前 60% 时长内）**；**新增页面自带的遮罩层**：入场时上层左缘 24dp 渐变阴影 α 0.06→0（模拟「左右位移遮罩」） |
| 层级 | 上层 route 自身，不让下层重新绘制，保留「下层停绘」优化（R4） |
| 混合模式 | 普通 srcOver |
| 粒子 / 光效 | 无 |
| 低端机 | 保持不变（透明度 + 位移本身很便宜）；返回期快照继续保留 |
| 减少动效 | reduced：只淡入，120ms；off：直接切换（保持现有逻辑） |
| 可选升级（需确认） | 整屏左右位移 + 下层 30% 视差 + 暗化遮罩，最接近系统观感。但下层必须继续绘制，会破坏现有停绘优化和对应测试，属于**高风险** |

### M2 首屏入场编排（P1）

| 项 | 参数 |
| --- | --- |
| 触发 | 冷启动首帧后 / Onboarding → AppShell / 新建会话后回到空状态 |
| 时长 | 每个元素 260ms，错开 40ms，总长 ≤ 380ms |
| 曲线 | `curveEnter` |
| 变化属性 | 顶部胶囊栏：opacity + translateY −8dp→0；空状态主视觉：opacity + scale 0.96→1；输入框：opacity + translateY 12dp→0 |
| 层级 | 各自组件内部，不涉及路由 |
| 粒子 / 光效 | 光晕在主视觉之后 80ms 淡入（衔接 M7） |
| 低端机 | 同样执行 |
| 减少动效 | reduced：统一淡入 120ms；off：无 |

### M3 列表 / 卡片入场与滑动（P2）

| 项 | 参数 |
| --- | --- |
| 触发 | 历史、Agent、仪表盘、MCP、记忆等列表**首次加载完成**时。滚动过程中新出现的 item 不加动画 |
| 时长 | 每项 220ms，错开 30ms，只对前 8 项做，总长 ≤ 430ms |
| 曲线 | `curveEnter` |
| 变化属性 | opacity 0→1，translateY 12dp→0 |
| 实现 | ★ `NexusStaggeredEntrance`（整个列表共用一个 AnimationController，每项用 `Interval` 切片，避免每个 item 各开一个 controller） |
| 滚动物理 | 默认不改。可选（需确认）：仅非聊天列表使用弹性过界（`BouncingScrollPhysics`），聊天列表保持不变（R6） |
| 低端机 | 保留（成本很低） |
| 减少动效 | reduced / off：直接显示 |

### M4 卡片按压光感（光随指动）（P2）

| 项 | 参数 |
| --- | --- |
| 触发 | `NexusPressable`、`NexusListTile`、`SectionCard` 按下 |
| 时长 | 按下时光斑出现 100ms（`springFollow`）；抬起时淡出 220ms（`curveStandard`）；缩放 0.97 保持 |
| 变化属性 | 在触点位置叠加径向渐变高光：半径为卡片短边的 0.9 倍，中心 α 0.10（深色 0.14）→ 0；手指移动时光斑跟随 |
| 层级 | 卡片内部 `CustomPaint` 前景层，裁切到圆角 |
| 混合模式 | 浅色用 `BlendMode.softLight`，深色用 `BlendMode.plus`（对比度由 `contrast_guard_test` 把关） |
| 低端机 | 不画光斑，只保留缩放 |
| 减少动效 | reduced：不缩放，只做静态高亮 α 0.06；off：无 |

### M5 点击 / 发送消息（P3）

| 项 | 参数 |
| --- | --- |
| 触发 | 点击发送按钮 / 键盘回车发送 |
| 发送按钮 | 按下缩放 0.9（`springFollow`）；抬起用 `springLively` 回到 1.0，过冲约 4%；同时从按钮中心扩散一道光圈，半径 0→28dp，α 0.35→0，时长 280ms，曲线 `curveEnter` |
| 用户气泡 | 从右下方升起：translateY 16dp→0，scale 0.96→1（锚点右下），opacity 0→1（前 50% 时长），用 `springRelease`，约 320ms 收敛 |
| 助手占位 | 气泡升起 120ms 后，思考指示淡入（衔接 M9） |
| 触觉 | 沿用 `NexusHaptics.light` |
| 层级 | 光圈画在输入框玻璃**之上**（不在玻璃下方，避免触发玻璃重新采样） |
| 低端机 | 保留弹簧；不画光圈 |
| 减少动效 | reduced：气泡淡入 120ms，无位移；off：直接出现 |
| 实现 | 扩展现有 `_MessageEntrance`：新增「用户消息」变体参数，默认行为不变 |

### M6 AI 流式回复出现（P3）

| 项 | 参数 |
| --- | --- |
| 触发 | 助手消息首个 token 到达；思考块折叠为答案 |
| 时长 | 首 token 淡入 180ms；思考→答案交叉淡入淡出 220ms（按研究 3.3，样式不同则错开：先淡出 80ms，再淡入） |
| 变化属性 | opacity；高度变化用 `AnimatedSize` 220ms `curveStandard` |
| 约束 | **不对逐个 token 做动画**（流式期间每帧都在追加内容，逐字动画会显著增加重建和光栅化开销） |
| 减少动效 | 直接显示 |

### M7 背景光晕（P4）

| 项 | 参数 |
| --- | --- |
| 触发 | 聊天空状态可见；Agent 思考中（光晕强度提升到 1.3 倍） |
| 形态 | 两团柔和环境光：主色为品牌色的 10%，辅色为冷蓝 8%，半径约屏宽 0.7，位于屏幕上 1/3 |
| 动画 | high：12s 周期的 Lissajous 缓慢漂移（位移 ≤ 24dp）加亮度呼吸 ±15%；mid：只做呼吸；low：静态 |
| 实现 | ★ `AmbientGlow`：`CustomPainter` + `RadialGradient`，不使用 blur 滤镜；外包 `RepaintBoundary`；循环接入 `MotionLifecycle`（后台 / 被遮挡时停止 ticker） |
| 层级 | `NexusBackground` 之上、页面内容之下，**只在空状态页挂载**。有消息的聊天列表背后不放光晕，因为胶囊栏和输入框是玻璃，会逐帧重新采样（R3） |
| 混合模式 | srcOver（先不用 screen / plus，保证浅色模式对比度） |
| 对比度 | 尊重 `NexusBackground` 已移除彩色光斑的设计决策：α 上限 0.12，由 `contrast_guard_test` 把关 |
| 减少动效 | reduced：静态单层；off：不绘制 |

### M8 光尘粒子（P4）

| 项 | 参数 |
| --- | --- |
| 触发 | 与 M7 相同的场景（空状态、思考中），且档位为 high 或 mid |
| 数量 | high 28 / mid 14 / low 0 |
| 单个粒子 | 半径 0.8–2.2dp；α 0.15–0.45；寿命 4–7s；向上漂移速度 6–14dp/s，叠加 ±4dp 正弦横摆；淡入淡出各占寿命的 20% |
| 发射区 | 光晕中心附近的椭圆区域（与 M7 对齐）；**不进入输入框和胶囊栏所在的矩形** |
| 实现 | ★ `LightDustField`：一个 Ticker，一个 `CustomPainter.drawPoints` / `drawVertices` 批量绘制；粒子状态存在 `Float32List` 里，零分配；外包 `RepaintBoundary` |
| 混合模式 | 深色 `plus`，浅色 `srcOver`，粒子颜色取主色的明度变体 |
| 思考态 | 速度 ×1.4，向光晕中心轻微聚拢（「引力」隐喻） |
| 低端机 / 降档 | 运行时检测到掉帧：先关粒子，再简化光晕（与 HarmonyOS 7 的降级顺序一致） |
| 减少动效 | reduced / off：不挂载 |

### M9 思考中 / 执行中（P5）

| 项 | 参数 |
| --- | --- |
| 思考标题流光 | 「思考中…」文字上用 `ShaderMask` 线性渐变高光扫过：宽 40%，1600ms 一次，间隔 400ms，曲线 `curveStandard`；high / mid 开，low 关 |
| 执行状态光晕 | 现有 1400ms 呼吸（保留），加外发光环：α 0.0→0.25，扩散 0→6dp，与呼吸同相 |
| 边缘光线勾勒（可选） | 执行中时，输入框玻璃边缘有一段 60° 弧光绕行，周期 2400ms（对应光线勾勒 / 光随指动的思路）；只在 high 档 |
| 结束 | 完成时光环收拢 180ms，同时 `NexusHaptics.success` |
| 实现 | 改 `nexus_execution_status.dart` 和 `reasoning_block.dart`，全部接入 `MotionLifecycle` |
| 减少动效 | reduced：静态点加文字；off：无 |

### M10 语音（TTS 朗读中）（P5）

| 项 | 参数 |
| --- | --- |
| 触发 | 长按助手消息 →「朗读」，直到朗读结束或手动停止 |
| 形态 | 消息角标显示 4 根声波条，高度 4–14dp，相位依次错开 120ms，每根 600–900ms 往复，`curveBreathing` |
| 说明 | TTS 插件不提供音量电平，声波条是**伪波形**（节奏感提示，不代表真实音量） |
| 减少动效 | 静态喇叭图标 |
| 语音输入 | 仓库里**没有**语音输入功能；如果以后加入，可以复用同一组件接入真实音量电平 |

## 2. 需要修改的文件

| 动效 | 新增 | 修改 | 风险 |
| --- | --- | --- | --- |
| M0 | `motion/motion_tier.dart`、`test/motion_tier_test.dart` | `motion/nexus_motion.dart`（新增 Token）、`main.dart`（builder 包一层 Scope） | 低～中（main.dart 只加一层 widget） |
| M1 | — | `motion/nexus_page_route_factory.dart`、`projects/project_home_page.dart`、`workspace/terminal_sheet.dart` | 中（转场有专门的绘制测试） |
| M2 | `motion/nexus_entrance.dart` | `chat/widgets/chat_empty_state.dart`、`chat/widgets/capsule_top_bar.dart`、`chat/widgets/floating_capsule_input.dart`（只包装） | 低 |
| M3 | `motion/nexus_staggered_entrance.dart` | `history/history_page.dart`、`agents/agents_page.dart`、`dashboard/dashboard_page.dart` | 低 |
| M4 | `widgets/touch_light_overlay.dart` | `widgets/nexus_pressable.dart`、`widgets/nexus_list_tile.dart` | 低～中（组件全局复用） |
| M5 | `widgets/send_ripple.dart` | `chat/widgets/floating_capsule_input.dart`、`chat/widgets/chat_message_list.dart` | 中 |
| M6 | — | `chat/widgets/chat_message_list.dart`、`chat/widgets/reasoning_block.dart` | 中 |
| M7 / M8 | `widgets/ambient_glow.dart`、`widgets/light_dust_field.dart` | `chat/widgets/chat_empty_state.dart` | 中（性能） |
| M9 | `widgets/shimmer_text.dart` | `widgets/nexus_execution_status.dart`、`chat/widgets/reasoning_block.dart` | 低 |
| M10 | `widgets/speaking_wave.dart` | `chat/widgets/chat_message_list.dart` 或 `message_bubble.dart` | 低 |

每项都会新增或更新 widget 测试，覆盖三件事：reduced/off 下不创建循环 ticker、`pumpAndSettle` 可以结束、低档下不绘制粒子。

## 3. 依赖

**默认不新增任何依赖**，全部用 Flutter SDK 实现（CustomPainter、SpringSimulation、ShaderMask、SchedulerBinding.timings）。

| 可选能力 | 依赖方案 | 替代方案 | 建议 |
| --- | --- | --- | --- |
| 120Hz 强制高刷 | `flutter_displaymode`（新依赖，高风险） | 在已有的 `MainActivity` MethodChannel 里设置 `preferredDisplayModeId`（原生改动，高风险）；或不处理，跟随系统 | 先不处理。多数 Android 高刷机在 Flutter 3.2x 以后已按系统刷新率渲染，建议先实测 |
| 复杂设计稿动画 | `lottie` / `rive` | 本方案全部用代码绘制 | 不需要 |

## 4. 风险与对策

| 风险 | 对策 |
| --- | --- |
| R1 `main` 上有 366 个未提交改动 | 开始写代码前新建分支 `feat/harmony-motion`；**不自动 push** |
| R3 玻璃下方有动画会导致逐帧重新采样 | 粒子和光晕只挂在空状态页，并避开玻璃所在的矩形；每项都用 DevTools 检查 raster 耗时 |
| R4 转场停绘优化 | M1 默认方案不让下层重新绘制；「整屏视差」作为可选项，需要你确认 |
| R6 滚动物理 | 聊天列表不改 |
| 测试护栏 | 每项完成后跑 analyze、定向测试、全量 `flutter test`、`build-apk.bat --fast`；连续失败两次就停下来问你 |
| 回滚 | 每个动效单独 commit，可以按 commit 回滚；另外所有装饰性效果都受 `MotionTier` 和 `effects` 设置控制，可在运行时关闭 |

## 5. 实施顺序

M0 → M1 → M2 → M3 → M4 → M5 → M6 → M7 → M8 → M9 → M10。每项开始前先给出 diff 计划；高风险项等你确认后再动手。

## 6. 验收指标

- Profile 模式真机测试：转场、列表首屏、发送、空状态粒子四个场景，UI 与 Raster 线程的 P90 < 8ms（120Hz）/ < 16ms（60Hz），掉帧率 < 1%。
- 系统开启「移除动画」或 App 设置为 off 时，没有任何 ticker 持续运行（用测试断言 `SchedulerBinding.transientCallbackCount`）。
- 浅色和深色模式下对比度测试通过。

## 7. 已确认决策（2026-09-24）

| 问题 | 决策 | 对方案的影响 |
| --- | --- | --- |
| Q1 Git | 已执行 `git switch -c feat/harmony-motion`，未提交改动原样带入；每个动效单独 commit，不 push | 回滚粒度为单个 commit |
| Q2 转场 | **整屏左右位移 + 下层视差暗化（高风险，已确认）** | M1 改为：上层 translateX 100%→0；下层 0→−30% 视差，并叠加 α 0→0.12 暗化遮罩；弹簧 `springRelease`（约 350ms 收敛），返回 250ms；转场期间下层必须继续绘制，因此要重新设计 `_keepUnderlyingRouteHidden` 优化，并更新 `route_transition_paint_test.dart` 的基线；侧滑返回手势跟手使用 `springFollow`，离手继承手速；低端机降为「下层不视差、只暗化」；reduced 只淡入 120ms |
| Q3 粒子/光晕 | 只放在空状态页和思考中 | 与 M7/M8 默认方案一致 |
| Q4 语音 | 预留语音输入：组件带真实音量电平接口 | M10 的 `SpeakingWave` 暴露 `ValueListenable<double>? level`；TTS 场景传 null，走伪波形 |
| Q5 120Hz | 跟随系统，先用 profile 实测 | 不做原生改动，不新增依赖 |

### M1（整屏方案）专项风险与对策

- 返回过程中下层要继续绘制，聊天页的玻璃和背景图会带来 raster 压力。对策：下层在转场期间用 `SnapshotWidget` 冻结为快照（下层内容在转场中不需要实时更新），这样在恢复下层绘制的同时控制成本。
- 玻璃面板在位移过程中会重新采样背景。对策：沿用现有返回期快照；进入方向在前 2 帧完成首帧光栅化后再开始位移。
- 回归：`route_transition_paint_test.dart` 的「下层零绘制」断言会失效，需要改写为「下层快照期间零重录」。这是有意的行为变更，会在 diff 计划中单独列出，等你确认。
