# 灵动动效重构交付说明（L0–L8）

> 分支 `feat/harmony-motion`，2026-09-28。方向：**形变连续 + 弹簧物理**为主轴，微交互点缀；光效/粒子保留但收敛（默认强度「轻盈」）。
> 约束：不新增依赖、不改业务逻辑 / 路由表 / 状态管理；pubspec 版本保持 0.9.0+94。

## 1. 弹簧令牌（`lib/presentation/motion/nexus_spring.dart`）

质量 1；stiffness = (2π/response)²，damping = 2ζω。

| 令牌 | response | ζ | 回弹 | 收敛 | 用途 |
|---|---|---|---|---|---|
| snappy | 0.22 | 0.86 | ≈0.5% | ~0.2s | 按压、开关按住、切换 |
| bouncy | 0.28 | 0.69 | ≈5% | ~0.31s | 弹入、回弹、图标形变、开关滑块、数字滚动 |
| smooth | 0.30 | 0.92 | ≈0 | ~0.28s | 形变、尺寸、面板、页面 |
| release | 0.30 | 0.52 | 按压深度 ~15% | ~0.44s | 按压松手 |
| reduced | 0.18 | 1.0 | 0 | — | 减弱动效 |

**降级策略**（`NexusSpringPolicy.resolve`）：关闭动效 → `null`（直接到位）；减弱 → `reduced`（无回弹、无循环）；低性能档 → 临界阻尼（无回弹）。120Hz 跟随系统。

API：`SpringController(vsync:, value:)`、`.animateTo(target, spring:, velocity:)`、`.jumpTo`；`NexusSprings.settleOf / curveOf(allowOvershoot:)`；`NexusHaptics.light / selection / medium`。

## 2. 分阶段内容

| 阶段 | 提交 | 内容 | 关键文件 |
|---|---|---|---|
| L0 | ad8fd5a | 弹簧基座、令牌、降级策略；默认强度改为「轻盈」 | `motion/nexus_spring.dart` |
| L1 | 6aacd11 | 全局按压挤压（按钮 0.94 / 卡片 0.97 / 行 0.985，release 回弹）；发送/停止与代码块复制 MorphIcon；展开箭头 SpringTurns | `motion/morph_icon.dart` 等 |
| L2 | 3d12874, 06866dc | 输入胶囊弹簧尺寸与聚焦形变；发送时气泡从输入框「飞出」（整宽幽灵胶囊形变落位） | `motion/send_flight.dart` |
| L3 | c180b7a | 助手消息 bouncy 弹入（14px, 0.97）；流式输出高度弹簧跟随；工具卡/计划面板弹簧展开 | `motion/spring_follow_height.dart`、`widgets/nexus_disclosure.dart` |
| L4 | 38dddfd | 面板跟手拖拽（36px 橡皮筋、0.18 或 900px/s 关闭、过阈值 selection 触感、吸附 light 触感）；对话框/菜单从点击处长出 | `widgets/nexus_sheet.dart`、`motion/tap_origin.dart` |
| L5 | 52fdc4d, 80c0a9c | 列表卡片 → 详情页容器变换；返回手势跟手（预测性返回，Manifest 开启 `enableOnBackInvokedCallback`） | `motion/nexus_page_route_factory.dart` |
| L6 | 1cae861, 945605c | 分段/胶囊指示器滑动拉伸（NexusSegmentedButton、TabBar elastic）；19 处底部面板统一 showNexusSheet；**弹簧开关** NexusSwitch / NexusSwitchListTile 替换全部 16 处 | `widgets/nexus_segmented_button.dart`、`widgets/nexus_switch.dart` |
| L7 | 384d5b7 | 数字滚动（指标值）、状态徽章轻弹、消息复制 ✓；光效盘点（AmbientGlow 仅空状态、Shimmer 仅思考态） | `motion/micro_interactions.dart` |
| L8 | 本次 | 验收测试 + 本文档 + 最终包 | `test/lively_acceptance_test.dart` |

## 3. 触感映射

| 时机 | 触感 |
|---|---|
| 面板拖拽越过关闭阈值 | selection |
| 面板吸附/回弹到位 | light |
| 开关切换、分段切换 | selection |
| 复制 | light（原有） |

## 4. 验收

### 自动化（已通过）
- `test/lively_acceptance_test.dart`（7 例）：snappy/bouncy/smooth 收敛 ≤ 0.35s、release ≤ 0.5s；bouncy 峰值 1.03–1.07，smooth/reduced 无回弹；开关 full 档有回弹且 ≤ 0.42s 到位，reduced 档无越界，off 档下一帧到位；off 档数字不滚动、徽章不弹。
- 各阶段专项测试：send_flight(10) / spring_follow_height(6) / sheet_motion(10) / route_morph(5) / segmented_motion(2) / nexus_switch(3) / micro_interactions(3)。
- 全量：**1586 通过**，`flutter analyze` 无问题。

### 真机帧耗时（需手动，手机未连接）
使用 `flutter run --profile` + 性能浮层（或 DevTools Performance），在 120Hz 设备上逐项检查 UI/Raster 线程均 < 8.3ms（60Hz 设备 < 16.7ms），无连续掉帧：
1. 发送消息（气泡飞出 + 助手弹入 + 流式高度跟随）
2. 快速上下拖拽底部面板并甩动关闭
3. 列表卡片进入详情页、侧滑返回（跟手中途松开）
4. 连续快速拨动开关、切换分段控件
5. 仪表盘指标数字刷新
6. 空状态光效 + 思考态 Shimmer 同屏时滚动
7. 系统开启「移除动画」/ App 内动效设为减弱、关闭时重复 1–5：应无回弹、无循环、直接到位

## 5. 已知限制
- 页面内约 130 处原生 `ListTile` / `InkWell` 行未接入按压挤压（无全局钩子，需逐个包裹）。
- 其余 7 处复制按钮（审计、日志、终端等）仍为静态图标，可按需换成 `CopyFeedbackButton`。
- `RefreshIndicator`、过度滚动保持平台默认（Android stretch）；项目内无 `Dismissible` / `AnimatedList`，删除折叠未接入。
- 浅色模式下光效透明度已至对比度上限。
- 暂存区 `stash@{0}`（未跟踪）/ `stash@{1}`（已跟踪，含 AndroidManifest 改动，将与 80c0a9c 冲突）待重构完成后合回。
