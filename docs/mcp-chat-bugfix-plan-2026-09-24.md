# 对话页 5 个问题：根因与修复方案（2026-09-24）

> 范围：`main@cfa11b5` 加上工作区里未提交的改动，只做了代码走查和调用链确认，**尚未修改代码**。
> 每个问题按"现象 → 根因（附文件和行号）→ 修复方案 → 验证"组织。

## 0. 总览

| # | 问题 | 根因（一句话） | 修复要点 | 优先级 | 预估 |
|---|---|---|---|---|---|
| 1 | 输入框上浮，底部一片白 | 键盘避让交给 Scaffold 默认的 `resizeToAvoidBottomInset`。IME 动画被打断时，平台的 inset 没归零，body 被多缩了一个键盘高度 | 页面自己处理键盘避让，按"是否有输入焦点"决定是否采用 inset，订阅 metrics 变化，并加残留看门狗 | P0 | 0.5 天 |
| 2 | 模型突然停止工作 | **不是手机限制**，是 App 单次执行预算（普通对话 16 轮）。预算暂停被显示成"未知错误"，而且没有继续入口；本例中 PRoot 没挂载共享存储，模型反复找文件把预算耗光了 | 预算暂停单独展示并提供「继续执行」；预算可配置并支持智能续跑；挂载共享存储；重复失败熔断 | P0/P1 | 1.5 天 |
| 3 | 改成 DeepSeek 风格 | AI 回复 = 头像 + 半透明卡片（描边、阴影、模型名页眉） | 新增「简洁」消息样式：AI 回复去掉卡片和头像，直接显示正文；操作行图标化；用户消息用浅色气泡 | P2 | 1 天 |
| 4 | 顶部任务面板最后一条滑不到 | 两层同方向滚动嵌套：内层已滚到底，但底部被外层视口裁掉；也不会自动跟随最新一条 | 只保留一个滚动容器；表头固定；自动跟随；只显示最近 3 条，其余用"查看全部"弹窗 | P0 | 0.5 天 |
| 5 | 暂停键点了没反应 | ① `pause()` 不更新 `state.paused` ② 只在检查点生效 ③ 工具循环里的检查点静默阻塞，不发暂停事件 | 立即反馈，分成三态；所有检查点都发事件；暂停时中断模型输出；「停止」入口放到明处 | P0 | 1 天 |

建议顺序：**第 1 天** #5、#2 的继续入口、#4 → **第 2 天** #1、#2 的预算与挂载 → **第 3 天** #3。每一步都跑 `flutter analyze`、相关测试，再用 adb 真机回归。

---

## 1. 输入框跑到中下部，底部一片白

### 现象
截图 1：输入胶囊连同"会话详情"条停在屏幕中下部，下面空出的高度大约等于一个键盘。输入框里正好是「编辑问题」回填的原问题。

### 根因
- `lib/presentation/chat/chat_page.dart:2385` 的 `Scaffold` 没有设置 `resizeToAvoidBottomInset`（默认 true），所以键盘避让完全由 Scaffold 按 `MediaQuery.viewInsets.bottom` 缩小 body。
- `lib/presentation/chat/widgets/floating_capsule_input.dart:128-134` 在 Scaffold body 内读取 `viewInsets`。按 `keyboard_insets.dart` 注释里的实测，这个值在 body 内恒为 0，所以只加了 safe-area。
- Android 上 IME 的显示/隐藏动画如果被打断，Flutter 最后拿到的 inset 可能不会归零。常见的打断场景：
  - 键盘弹出时出现审批底部弹窗或锁屏通知审批，或者切到文件管理器、切到后台；
  - `floating_capsule_input.dart:160` 的 `onTapOutside → unfocus()` 和「编辑问题」（`chat_page.dart:1418`）的回填 + `requestFocus()` 在一两帧内连续触发，形成"收起再弹出"的抖动。

  inset 残留后，body 仍被缩掉一个键盘高度，底部就露出背景色，也就是截图里的白色区域。
- 附带问题：`lib/presentation/utils/keyboard_insets.dart:19-22` 用 `View.of(context).viewInsets` 取值。`_ViewScope` 只在 view 对象本身变化时通知，**不会随 metrics 变化而重建**，所以读到的只是某一时刻的快照。

> 具体是哪个平台时序触发的，只能靠推断（这类问题很难稳定复现）。下面的方案是防御性的，**不管哪种原因触发都能覆盖**。

### 修复（页面自己处理键盘避让 + 焦点门控）
1. 聊天页的 `Scaffold` 改为 `resizeToAvoidBottomInset: false`，不再依赖平台 inset 去缩 body。
2. 新增 `lib/presentation/utils/keyboard_avoider.dart`，作为本页唯一的键盘高度来源：

```dart
class KeyboardAvoider extends StatefulWidget {
  const KeyboardAvoider({super.key, required this.builder});
  final Widget Function(BuildContext context, double keyboard) builder;
  @override
  State<KeyboardAvoider> createState() => _KeyboardAvoiderState();
}

class _KeyboardAvoiderState extends State<KeyboardAvoider>
    with WidgetsBindingObserver {
  Timer? _staleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    _staleTimer?.cancel();
    FocusManager.instance.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _refresh(); // 订阅 inset 变化（View.of 做不到）

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  bool get _editing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx?.findAncestorStateOfType<EditableTextState>() != null;
  }

  double get _rawInset {
    final view = View.of(context);
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    // 看门狗：没有输入焦点却仍有 inset，说明 inset 残留，强制同步一次 IME 状态
    if (_rawInset > 0 && !_editing) {
      _staleTimer ??= Timer(const Duration(milliseconds: 400), () {
        _staleTimer = null;
        if (mounted && _rawInset > 0 && !_editing) {
          SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
          // 记录诊断事件 keyboard.stale_inset，方便真机统计触发频率
        }
      });
    } else {
      _staleTimer?.cancel();
      _staleTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) =>
      // 核心规则：没有输入焦点，就不可能有属于本页的键盘 → 残留 inset 一律当 0
      widget.builder(context, _editing ? _rawInset : 0);
}
```

3. 用 `KeyboardAvoider` 包住底部输入区（`SessionMetricsHud`、`ComposerSkillPromptSlot`、`FloatingCapsuleInput`、附件抽屉，即 `chat_page.dart:2841-2920`）：

```dart
KeyboardAvoider(
  builder: (context, keyboard) => Padding(
    padding: EdgeInsets.only(
      bottom: keyboard > 0
          ? keyboard + 8
          : MediaQuery.viewPaddingOf(context).bottom + 8,
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [/* 原有底部组件 */]),
  ),
)
```

   同时去掉 `floating_capsule_input.dart:128-134` 里自带的 bottom padding，避免重复计算。
4. 消除焦点抖动：用 `TapRegion(groupId: composerTapGroup)` 包住输入胶囊，`TextField` 设置相同的 `groupId`。点胶囊里的 +、…、发送不再触发失焦再聚焦。「编辑问题」改为先写入文本，再只调用一次 `requestFocus()`。
5. `keyboard_insets.dart` 改为读取 `KeyboardAvoider` 给出的值（通过 InheritedWidget 下发），空状态的 `keyboardVisible`（`chat_page.dart:2267`）也改用它。

### 验证
- 在 `test/keyboard_insets_test.dart` 新增用例：
  - `tester.view.viewInsets = FakeViewPadding(bottom: 900)` 且无焦点时，输入胶囊的底部 = 屏幕底部 − safe-area；
  - 有焦点时，胶囊位于键盘上方；
  - 焦点从有变无之后，下一帧立即回到底部。
- 真机按以下 4 个场景各测 10 次，都不应出现白屏：
  1. 键盘弹出时触发审批弹窗；
  2. 切到文件管理器再切回来；
  3. 连点「编辑问题」；
  4. 锁屏再解锁。

---

## 2. 模型突然停止工作（"已达到单次执行步数预算"）

### 直接回答：是不是手机的限制？
**不是。** 这是 App 自己的单次执行预算：
- 普通对话固定 **16 轮**（`lib/application/chat_controller.dart:739`）；
- 选了 Agent 时使用 Agent 的 `maxSteps`：默认 8（`database_tables.dart:67`），编辑器上限 32（`agent_editor_page.dart:74`）。

"一轮"指一次模型请求，一轮里可以包含多个工具调用。所以底部显示"第 37 步"（工具调用次数）时，轮数可能已经到 16 了。两个"步"的含义不同，这本身就容易让人困惑。

### 根因（三层）
- **A. 显示错了**：`lib/application/chat_run_execution.dart:794` 把预算暂停的说明交给了 `formatErrorForMessage()`。`error_humanizer.dart:49-51` 匹配不到任何错误类型，就落到 unknown，显示成"错误：遇到未预期的错误…"，真正的原因被折叠进了技术细节。
- **B. 没有继续入口**：断点续跑其实已经实现了：
  - 续跑逻辑在 `chat_controller.dart:1589` 的 `resumeFromBudgetPause()`；
  - 上下文在 `chat_run_execution.dart:780-787` 保存，并写入了 checkpoint。

  但这个功能**只接到了计划面板**（`chat_page.dart:2537-2540`）。普通对话失败时只有「重试 / 编辑问题 / 切换模型」（`message_bubble.dart:559-579`），而「重试」会从原始 prompt 从头重跑，前面做过的步骤全部白做。另外，内存里的续跑上下文（`run_coordinator.dart:39`）在切换会话或重启后会丢失。
- **C. 预算被无效重试耗光（本例）**：`android/app/src/main/kotlin/com/nexusagent/app/BuiltinLinuxRunner.kt:317-343`（`:224` 处同理）的 PRoot 只绑定了 `/dev`、`/proc`、`/sys` 和 `workspace:/workspace`，**没有绑定 `/storage/emulated/0`（`/sdcard`）**。所以 `ls "/storage/emulated/0/测试/1/…zip"` 必然返回 No such file。模型不知道原因，只能换各种方式反复找，16 轮很快耗尽。

### 修复
**A + B（P0）：把预算暂停和错误区分开，并提供继续入口**
1. 新增运行暂停标记，替换 `chat_run_execution.dart:794` 的写法，和 `kErrorDetailMarker` 的机制保持一致：

```dart
const String kRunPauseMarker = '\n[运行暂停]\n';
// 旧：answer.write('\n\n${formatErrorForMessage(event.message)}');
answer.write('\n\n$kRunPauseMarker${jsonEncode({
  'kind': 'budget', 'maxSteps': event.maxSteps, 'runId': runId,
})}');
```

   兼容旧消息：技术细节里含"已达到单次执行步数预算"的历史消息，同样按暂停处理。
2. `message_bubble.dart` 识别到标记后，渲染一条"⏸ 已用完本轮 16 轮执行预算（不是错误）"提示条。主按钮是 **「继续执行」**，次按钮是「提高上限并继续」和「结束」。
3. 回调链：`ChatPage → ChatMessageList → MessageBubble` 增加 `onResumeBudget`，调用 `_chat.resumeFromBudgetPause(approveTool: _approveTool)`。只有最后一条消息显示这个按钮。
4. `resumeFromBudgetPause()` 在内存上下文为空时，按 `runId` 从持久化的 checkpoint 解码恢复（即 `encodeChatContextForPersistence` 的逆过程）。这样重启或切换会话之后也能继续。
5. 预算暂停时，顶部面板里的"1 项未完成"改为"已暂停（执行预算）"。

**预算策略（P1）**
1. 普通对话默认预算 16 → **40**，Agent 编辑器上限 32 → **100**（数据库默认值 8 不动，避免迁移）。
2. 会话配置里增加"单次执行上限：16 / 40 / 80 / 自定义"，存到 `chat.max_steps`。
3. **智能续跑**：预算耗尽时，如果最近几轮有进展（有成功的工具调用，且没有重复失败），就自动续跑。默认最多 2 次，可在设置里关闭。消息里标注"已自动续跑 1/2"。
4. 让进度可见：底部指标条改成"第 12/40 轮 · 37 次工具调用"，统一"轮"和"次"的叫法。

**让预算不被白白消耗（P1）**
1. PRoot 挂载共享存储，`BuiltinLinuxRunner.kt` 的两处启动参数都要改：

```kotlin
val storageBinds =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
        Environment.isExternalStorageManager()
    ) listOf("-b", "/storage/emulated/0", "-b", "/storage/emulated/0:/sdcard")
    else emptyList()
// 插在 "-b", bind 之前：args += storageBinds
```

2. 把"共享存储是否已挂载"告诉模型。在 `agent_executor.dart:55-60` 的运行环境说明里追加一句：
   - 已挂载时："共享存储已挂载于 /sdcard 与 /storage/emulated/0"；
   - 未挂载时："未授予所有文件访问权限，无法访问 /storage/emulated/0；请提示用户授权，或使用文件导入"。
3. **重复失败熔断**（在 `agent_executor.dart` 的工具结果处）：
   - 同一个调用（工具名 + 规范化参数）失败 2 次 → 追加系统提示："已失败 2 次，请换一种方法，或向用户确认路径和权限"；
   - 连续 4 次工具失败 → 提前暂停，原因是"检测到连续失败"。这种暂停也显示为可继续的暂停提示条。为此把事件泛化成 `AgentRunPausedEvent{kind: budget | repeatedFailure}`。

### 验证
- `test/agent_executor_test.dart`：
  - 预算耗尽时，消息里是暂停标记，不含"错误："；
  - 同一调用失败 2 次后，上下文里出现系统提示；
  - 连续失败 4 次时提前暂停。
- 控制器测试：清空内存上下文后，`resumeFromBudgetPause()` 能从持久化的 checkpoint 继续。
- 真机：授予"所有文件访问"后，在 Alpine 里 `ls /sdcard/测试/1/` 能看到 zip；不授权时，模型能明确提示用户去授权，而不是一直重试。

---

## 3. 对话页改成 DeepSeek 风格（AI 回复去掉气泡，直接显示正文）

### 现状
- AI 回复（`message_bubble.dart:392-471`）= 36dp 头像（`MascotAvatar`）+ 60% 透明度的白色卡片（圆角 18、描边、阴影）+ 页眉（模型名 • 耗时，`:475-512`）；
- 用户消息（`:142-160`）= 品牌浅色气泡 + 描边。

### 方案
1. 新增 `ChatMessageStyle { plain, card }`，放在 `ChatLayoutController` 旁边，外观设置里可以切换。**默认 plain**，card 作为兜底保留。现有的 `quietReply` 分支（已去掉描边和阴影）可以直接作为改造起点。
2. **plain 模式下的 AI 回复**：
   - 去掉头像（`avatarSpace = 0`），去掉卡片（无背景、无描边、无阴影）；
   - 正文和页面左右 16dp 对齐，占满宽度；
   - 删掉页眉，模型名和耗时改为操作行右侧的浅色小字。
3. **思考块**：`ReasoningCompactBlock` 改成一行"已思考（用时 X 秒）›"，点击展开。展开后是左侧 2dp 竖线 + 灰色文字，和 DeepSeek 一致。
4. **操作行**：复制 / 👍 / 👎 / 朗读 / 分享，最右侧是重新生成。
   - 图标 18dp，间距 20dp；
   - 最后一条消息常驻显示，历史消息点击后才显示，避免满屏图标；
   - 👍 复用现有的"有帮助"标记。
5. **用户消息**：浅蓝填充（`lightBrandSoft`），去掉描边，圆角 20/20/20/6，最大宽度 78%（保持现状），右对齐。
6. **工具调用、错误、暂停提示**：改成行内轻提示（左侧 3dp 色条 + 文字 + 文字按钮），不再用卡片。
7. **背景图兼容**：用云朵或自定义背景时，纯文字的可读性会下降。plain 模式下给消息列表加一层 6–10% 的同色蒙层；或者检测到背景图时自动回退为 card，并在设置里说明。
8. （可选）空闲时把"会话详情"条收进顶栏，底部只留输入框，更接近 DeepSeek。

### 验证
在 `test/chat_visual_regression_test.dart` 和 `test/chat_visual_hierarchy_test.dart` 里增加 plain 样式的 golden，覆盖浅色、深色、大字号、宽屏（>700）四组。

---

## 4. 顶部执行任务显示不全，最后一条滑不下去

### 根因
- 外层：`chat_page.dart:2513-2556` 的顶部面板是 `Flexible(loose) → SingleChildScrollView → [PlanPanel, ToolActivityTimeline]`；
- 内层：`lib/presentation/chat/widgets/tool_activity_section.dart:86-101` 在时间线内部又套了 `ConstrainedBox(maxHeight: 280) → SingleChildScrollView`；
- 两层同方向滚动：顶部面板和消息列表按 flex 平分高度。当面板可用高度小于"表头 + 280"时，**内层列表的底部被外层视口裁掉**。手指在条目上拖动只会驱动内层（它认为自己已经到底了），外层不动，于是最后一条永远拉不出来；
- 新条目追加在底部，但没有自动跟随，而正在执行的那一条恰恰在最下面；
- 另外，`chat_run_execution.dart:914-916` 在**每次开始执行工具时**都往 `activityLog` 追加"等待确认"。顶栏下面那行小字（`chat_page.dart:2354-2356`、`:2498-2508`）因此一直显示"等待确认"，运行结束后也不清空，和实际状态不符（截图 1 和截图 4 左上角）。

### 修复
1. 只保留一个滚动容器：去掉顶部面板外层的 `SingleChildScrollView`，改为 `ConstrainedBox(maxHeight: min(可用高度 × 0.38, 320))`。
2. 时间线的紧凑模式改为下面的结构，并去掉内层的 `ConstrainedBox + SingleChildScrollView`：

```dart
Column(mainAxisSize: MainAxisSize.min, children: [
  _header(context, ...), // 固定表头，不随列表滚动，永远不会盖住条目
  Flexible(
    child: ListView.builder(
      controller: _scroll,
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: visible.length,
      itemBuilder: (context, i) => _row(context, visible[i]),
    ),
  ),
  if (hiddenCount > 0)
    TextButton(onPressed: _openAllSheet, child: Text('查看全部 $total 条')),
])
```

3. 自动跟随：条目数量或最后一条的状态变化时，在下一帧 `animateTo(maxScrollExtent)`。用户手动上滑后暂停跟随，并显示"回到当前"小按钮；滑回底部后恢复跟随。
4. 运行中默认只显示最近 3 条，完整列表通过"查看全部 N 条"在底部弹窗（`DraggableScrollableSheet`）里查看，小屏也不会挤。
5. 运行中 `PlanPanel` 折叠成一行摘要，点开再展开。
6. 修正"等待确认"误标：
   - `:915` 改为 `'执行中：${currentTool?.call.name ?? '工具'}'`；
   - 只有 `ApprovalRequiredEvent` 才写"等待确认"；
   - 运行结束时清空 `activityLog`，或者干脆删掉这行文字（表头已经显示了状态）。

### 验证
在 `test/tool_activity_timeline_test.dart` 里模拟 360×640 逻辑屏、12 条活动、最后一条为"执行中"：
- pump 之后，最后一条的 Rect 完全落在顶部面板视口内，且没有 overflow 异常；
- 手动上滑后，新增条目不会抢走滚动位置。

---

## 5. 暂停键点了没反应，模型还在工作

### 根因（三层叠加，外加一个可发现性问题）
1. `lib/application/chat_controller.dart:2341-2351` 的 `pause()` 只记了一条日志，**没有设置 `state.paused`**（而 `resume()` 会设置 `paused: false`）。按下后按钮不变，所以"点了没反应"。
2. `lib/application/run_controller.dart:49-55` 的设计是"在下一个检查点生效，不中断当前工具"。模型的流式输出、`apk add` 这类长命令都会继续跑完，所以"模型还在工作"。
3. `lib/application/agent_executor.dart:556` 在工具循环里调用 `checkpoint()` 时**静默阻塞**，只有 `:160` 的步首检查点才会发出 `RunStatus.paused`（UI 在 `chat_run_execution.dart:1125-1136` 才切换）。如果暂停正好落在两个工具之间：
   - 执行器已经停了，但 UI 永远进入不了暂停状态，也不会出现 ▶ 继续；
   - 再点暂停时，控制器已经处于暂停状态，`pause()` 返回 false。

   这时按钮就真成了摆设。
4. 「停止」只能长按（`floating_capsule_input.dart:446-461`），用户几乎不可能发现。

### 修复
1. **立即反馈，分成三态**。`ChatState` 增加 `pausePending`：

```dart
bool pause() {
  final controller = _runs.runController;
  if (controller == null || !controller.pause()) return false;
  unawaited(_persistControl(TaskControlKind.pause));
  if (_runs.isVisible(state.conversationId)) {
    state = state.copyWith(
      paused: true,        // 按钮立刻变成 ▶
      pausePending: true,  // 状态行："正在暂停：当前命令结束后停下"
      activityLog: [...state.activityLog, '正在暂停'],
    );
  }
  return true;
}
```

   收到 `RunStatus.paused` 事件时（`chat_run_execution.dart:1134`），把 `pausePending` 置为 false，状态行显示"已暂停"。
2. **所有检查点都发事件**。在 `run()` 里定义一个局部生成器，替换 `:160-163` 和 `:556` 两处：

```dart
Stream<AgentEvent> pausePoint(RunStatus resumeAs) async* {
  if (runController?.isPaused ?? false) {
    yield const AgentStatusEvent(RunStatus.paused);
    await checkpoint();
    if (!isCancelled()) yield AgentStatusEvent(resumeAs); // 恢复后 UI 自动切回
  }
}
// 用法：yield* pausePoint(RunStatus.executingTool);
```

3. **按暂停立即停下模型输出**：
   - 每次模型请求使用独立的 `CancelToken`，并和运行级 token 联动（停止时两者都取消）；
   - `AgentRunController` 增加 `onPauseInterrupt`，在等待模型或流式输出阶段调用 `pause()` 时，取消本次请求；
   - 执行器捕获"因暂停而取消"的异常（`isPaused && !isCancelled`），跳过重试逻辑，丢弃本轮半截输出，**这一轮不计入步数**，然后回到 `pausePoint` 等待；继续之后重发本轮请求。
   - 工具正在执行时，**等当前命令结束再停**（强杀 `apk add` 可能损坏环境），状态行额外提供「停止当前命令」。
4. **「停止」放到明处**：暂停后按钮区显示 [■ 停止][▶ 继续]；运行中保留长按停止，同时在首次使用时给出提示。
5. **后台开发任务**：如果 `_runs.runController` 为 null（任务绑定在后台执行器上），`pause()` 目前会直接返回 false，也就是没有任何反应。现在只会写入 `pause_requested`（`development_execution_service.dart:185-186`），**需要确认**后台执行器会在检查点读取它。如果不支持，就把暂停按钮置灰，并提示"后台任务仅支持停止"。

### 验证
- `test/run_controller_test.dart` 和 `test/agent_executor_test.dart`：
  - 在工具批次中间暂停，能立即收到 `RunStatus.paused`；
  - 流式输出中暂停，本次请求被取消、步数不增加，继续后会重发；
  - 连续点两次暂停，状态保持一致。
- widget 测试：点击暂停后，按钮的 key 立即变为 `trailing_action_resume`。
- 真机：执行长时间的 `apk add` 时点暂停，按钮立刻变化，命令结束后显示"已暂停"，点继续能从断点恢复。

---

## 6. 风险与注意
- `resizeToAvoidBottomInset: false` 只影响聊天页 body。弹层都是独立的 route，`nexus_sheet.dart:41` 已经自行处理 inset。抽屉里如果有搜索框，需要回归测试一下。
- 暂停时中断模型输出会浪费本轮已生成的 token（半截输出被丢弃），可以接受。
- 挂载 `/storage` 会扩大终端的可访问范围。只在用户已授予"所有文件访问"时才挂载，并沿用现有的审批策略。
- 简洁样式在背景图上的可读性，按第 3 节第 7 条处理。

## 7. 统一验收
```bash
flutter analyze
flutter test test/keyboard_insets_test.dart test/tool_activity_timeline_test.dart \
  test/run_controller_test.dart test/agent_executor_test.dart \
  test/chat_visual_regression_test.dart
flutter build apk --release   # 然后 adb install -r，按各节的真机步骤回归
```
