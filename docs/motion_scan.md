# 动效改造 · 阶段 1：项目扫描

> 扫描日期：2026-09-24　范围：`lib/presentation/**`、`lib/main.dart`、`pubspec.yaml`、`analysis_options.yaml`、`.github/workflows/ci.yml`、`test/`
> 方式：ShunCode Bridge 只读工具（list_directory / read_files / run_command grep），未改动任何源码。

## 1. 技术栈结论

| 项 | 结论 | 证据 |
| --- | --- | --- |
| 框架 | **Flutter 3.47.2 / Dart**（stable，Impeller） | `flutter --version`、`pubspec.yaml` |
| 平台 | Android-only，arm64-v8a | `README.md` |
| 状态管理 | **Riverpod 3**（`flutter_riverpod ^3.0.0`）＋少量静态 `ValueNotifier`（主题/外观/语言） | `pubspec.yaml`、`app_appearance_controller.dart` |
| 路由 | **Navigator 1.0 命令式**，统一使用自研 `NexusPageRoute`（detail 34 / settingsPage 13 / workspace 10 / fade 1 / 裸构造 6），残留 `MaterialPageRoute` 2 处 | grep 统计 |
| 底部面板 | `showNexusSheet` 22 处、`showModalBottomSheet` 19 处 | grep 统计 |
| 持久化 | Drift / SQLite、SharedPreferences | `pubspec.yaml` |
| 着色器 | `shaders/liquid_glass.frag`（仅 Impeller，失败降级为高斯模糊） | `pubspec.yaml` |
| 动画依赖 | **无第三方动画库**（无 lottie / rive / flutter_animate） | `pubspec.yaml` |

## 2. 命令

| 用途 | 命令 |
| --- | --- |
| 依赖 | `flutter pub get` |
| Format | `dart format lib test`（CI 未强制，建议只格式化改动文件） |
| Lint | `flutter analyze --no-pub`（CI 门禁，`analysis_options.yaml` 启用 `prefer_const_*`、`unawaited_futures` 等） |
| Test | `flutter test`（CI 用 `--coverage`；约 200+ 测试文件） |
| 定向测试 | `flutter test test/route_transition_paint_test.dart test/motion_ui_regression_test.dart test/nexus_motion_and_widgets_test.dart test/liquid_glass_test.dart test/chat_visual_regression_test.dart` |
| Build | `build-apk.bat --fast --no-pause --no-open`（本地迭代）；正式：`flutter build apk --release --target-platform android-arm64` |
| 性能 | `flutter run --profile` + DevTools Performance（需真机） |

## 3. 现有动效基础设施（已相当成熟，改造应「接入」而不是「重写」）

| 文件 | 行数 | 作用 |
| --- | --- | --- |
| `lib/presentation/motion/nexus_motion.dart` | 134 | 时长/曲线 Token：instant 100、fast 150、base 220、expand 300、page 250、pageExit 180、sheet 300；曲线 standard(0.4,0,0.2,1)、enter(0,0,0.2,1)、sheetEnter(0.16,1,0.3,1)、responsive(0.2,0,0.2,1)、breathing |
| `lib/presentation/motion/motion_preferences.dart` | 51 | `MotionLevel { full, reduced, off }`；合并系统 `disableAnimations` 与 App 内设置；`allowDecorativeMotion` |
| `lib/presentation/motion/motion_lifecycle.dart` | 50 | 装饰性循环动画在后台/被遮挡/减少动效时**停止 Ticker** |
| `lib/presentation/motion/nexus_haptics.dart` | 49 | 统一触觉反馈 |
| `lib/presentation/motion/nexus_page_route_factory.dart` | 373 | `NexusPageRoute`：8~16dp 水平微位移、入 250 / 出 180ms、返回期快照、下层路由停绘优化（有回归测试） |
| `lib/presentation/theme/app_tokens.dart` | 139 | 设计 Token（含动效时长/曲线源头） |
| `lib/presentation/theme/app_appearance_controller.dart` | 70 | `effects: full/reduced/off`、玻璃强度 flat/frosted/liquid（移动端默认 frosted 0.45） |
| `lib/presentation/widgets/nexus_pressable.dart` | 66 | 按下即缩放 0.97（touch-down 响应） |
| `lib/presentation/widgets/liquid_glass.dart` | 481 | 液态玻璃（BackdropFilter + 折射 shader），随 MotionLevel 降级 |
| `lib/presentation/widgets/nexus_background.dart` | 52 | 根画布：中性微渐变；**注释明确已移除彩色光斑以保证对比度** |
| `lib/presentation/widgets/nexus_execution_status.dart` | 328 | 执行中呼吸脉冲（1400ms，接入 MotionLifecycle） |
| `lib/presentation/widgets/nexus_loading_skeleton.dart` | 286 | 骨架屏动画 |
| `lib/presentation/widgets/floating_toast.dart` / `nexus_sheet.dart` | 404 / 473 | Toast、底部 Sheet 动画 |

## 4. 动效相关业务文件清单

| 优先级 | 场景 | 文件 | 现状 |
| --- | --- | --- | --- |
| P1 页面进入/切换 | 路由 | `motion/nexus_page_route_factory.dart`；残留 `projects/project_home_page.dart`、`workspace/terminal_sheet.dart` 的 `MaterialPageRoute` | 只有位移、无透明度/遮罩层次；两处未统一 |
| P1 | 启动 | `main.dart`（`StartupGate` → `AppShell` → `ChatPage`）、`onboarding/onboarding_page.dart` | 首屏无入场编排 |
| P2 卡片/列表 | 历史、Agent、仪表盘 | `history/history_page.dart`、`agents/agents_page.dart`、`dashboard/dashboard_page.dart`、`dashboard/widgets/*.dart`、`widgets/nexus_list_tile.dart`、`widgets/section_card.dart` | 无首屏交错入场；按压仅缩放、无光感反馈 |
| P2 | 聊天列表 | `chat/widgets/chat_message_list.dart`（498）、`chat/chat_scroll_coordinator.dart` | 新消息 `_MessageEntrance`：fade + 2.5% 上移，220ms |
| P3 点击/发送 | 输入框 | `chat/widgets/floating_capsule_input.dart`（780） | 发送按钮 `AnimatedSwitcher` + 触觉；无「发出」动势 |
| P3 | 气泡 | `chat/widgets/message_bubble.dart`（877） | 无自身动画 |
| P4 背景粒子/光晕 | 背景 | `widgets/nexus_background.dart`、`chat/widgets/chat_empty_state.dart`（503）、`main.dart` builder | 无粒子/光晕 |
| P5 语音/思考中 | 思考 | `chat/widgets/reasoning_block.dart`（561）、`widgets/nexus_execution_status.dart`、`chat/widgets/chat_execution_stage.dart` | 呼吸脉冲；无流光 |
| P5 | 语音 | `chat/chat_message_actions.dart`（TTS 朗读） | **只有 TTS 朗读，没有语音输入/麦克风 UI** |
| 核心大文件 | 聊天页 | `chat/chat_page.dart`（3287 行） | 高耦合，尽量不动 |

## 5. 已有测试护栏（改动必须保持绿）

`route_transition_paint_test.dart`、`motion_ui_regression_test.dart`、`nexus_motion_and_widgets_test.dart`、`liquid_glass_test.dart`、`liquid_glass_multi_page_test.dart`、`glass_surface_test.dart`、`chat_visual_regression_test.dart`、`chat_visual_hierarchy_test.dart`、`history_page_performance_test.dart`、`a11y_compliance_test.dart`、`contrast_guard_test.dart`、`code_quality_guard_test.dart`。

## 6. 可加动效点（按用户优先级）

1. **页面转场**：在现有微位移上叠加进场透明度（前 60% 时长 0→1）＋下层页面轻微变暗；两处 `MaterialPageRoute` 收编进 `NexusPageRoute`；首页冷启动入场编排。
2. **卡片/列表**：列表首屏交错入场（最多 8 项）；卡片按下「光随指动」高光；非聊天列表可选弹性过界。
3. **点击/发送**：发送按钮按压 + 光圈扩散；用户气泡从输入框方向升起（弹簧）；助手首 token 淡入。
4. **背景粒子/光晕**：空状态/思考态的低密度光尘粒子＋柔和环境光晕（遵循「已移除彩色光斑」的对比度约束，默认克制）。
5. **语音/思考中**：思考标题流光扫过、执行中光晕呼吸；TTS 朗读中的声波条。

## 7. 发现的问题与风险

| # | 类型 | 描述 | 等级 |
| --- | --- | --- | --- |
| R1 | 仓库状态 | `main` 分支有 **366 个未提交改动**（含 android/ 原生与 CI 配置）。直接在其上开发会混淆 diff、难以回滚 | 高：先建分支/确认 |
| R2 | Token 命名 | `AppTokens.curveAccelerate = Cubic(0,0,0,1)` 实际是强减速曲线，与「加速/退场」语义不符；`NexusMotion.curveExit` 引用它 | 中：修改会影响所有退场观感与快照测试 |
| R3 | 性能 | 玻璃面板（BackdropFilter + shader）会实时采样背后内容；**任何放在玻璃下方的粒子/光晕都会迫使玻璃逐帧重算**（华为沉浸光感功耗指南同样警告） | 高：粒子必须避开玻璃覆盖区或降帧 |
| R4 | 性能 | 路由有「下层停绘」优化（`entry.opaque`），做「下层变暗/视差」遮罩必须让下层继续绘制，会与该优化冲突 | 中：遮罩只能画在上层页面自身 |
| R5 | 设备分级 | 仓库**没有设备性能分级**；120Hz 需原生 `preferredDisplayModeId` 或新依赖 | 中/高：新增依赖/原生属高风险 |
| R6 | 滚动 | 修改全局 `ScrollBehavior`/physics 会影响 `chat_scroll_coordinator` 的尾随与定位逻辑 | 高：只在非聊天列表局部应用 |
| R7 | 大文件 | `chat_page.dart` 3287 行，改动易引发回归 | 中：以包装组件方式接入 |
| R8 | 语音 | 无语音输入功能，「语音动效」只能落在 TTS 朗读态，或需新功能（超出动效范围） | 待确认 |
