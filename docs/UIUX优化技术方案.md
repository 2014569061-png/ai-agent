# NEXUS Agent UI/UX 优化技术方案

> 对应《docs/UIUX优化计划.md》的可执行技术设计。每项给出：现状（文件:行号）→ 技术设计（API 签名/代码骨架）→ 改动清单 → 测试 → 工作量。
> 基线：v0.6.0，Drift schemaVersion 11，`flutter analyze` 0 问题、104 测试全绿。
> 原则：不新造设计系统，一切复用 `ImmersiveSurface`（材质）/ `ImmersiveMotion`（动效）/ `AppTokens`（节奏）/ `AppSemanticColors`（颜色）。

---

## 全局新增组件清单（先行，供各项复用）

| 组件/模块 | 路径 | 职责 |
|---|---|---|
| `ImmersiveDropdown<T>` | `presentation/widgets/immersive_dropdown.dart`（新） | 玻璃化下拉选择，替代 DropdownButtonFormField |
| `SkeletonBox` / `SkeletonList` | `presentation/widgets/skeleton.dart`（新） | 玻璃质感骨架屏 |
| `AppHaptics` | `presentation/widgets/app_haptics.dart`（新） | 触觉反馈唯一入口 |
| `errorHumanizer` | `application/error_humanizer.dart`（新） | 底层错误 → 人话 + 技术细节折叠 |
| `DraftStore` | `application/draft_store.dart`（新） | 按会话的输入草稿存取 |
| `CatalogPanel` | 从 `chat_catalog_drawer.dart` 抽出（重构） | 抽屉内容与宽屏常驻左栏共用 |

---

## P0 一致性收尾

### P0.1 玻璃化下拉 `ImmersiveDropdown<T>`

**现状**：3 处 `DropdownButtonFormField` —— settings_page.dart:869（MCP 连接方式，2 项）、scheduled_tasks_page.dart:104（时，24 项）、:116（分，12 项）。菜单走 Flutter 内部 `_DropdownRoute`，无法附加 BackdropFilter，`popupMenuTheme` 管不到它。

**设计**：不做"给系统菜单加模糊"（不可行），改为同 look 的 FormField，点开后走 `showImmersiveSheet` 选单：

```dart
/// 与 DropdownButtonFormField 迁移成本对齐：直接复用现有 items 构造。
class ImmersiveDropdown<T> extends FormField<T> {
  ImmersiveDropdown({
    super.key,
    required String labelText,
    required List<DropdownMenuItem<T>> items,
    T? initialValue,
    ValueChanged<T?>? onChanged,
    bool enabled = true,
  }) : super(
    initialValue: initialValue,
    builder: (state) {
      // 渲染层：复用全局 InputDecorationTheme（胶囊+浮层底），
      // suffixIcon: Icons.expand_circle_down_rounded，
      // 整体 InkWell → showImmersiveSheet<ListTile 列表>
      //   每项 leading 选中勾、trailing 无，onTap: Navigator.pop(sheetCtx, value)
      //   sheet 返回后 state.didChange(value); onChanged?.call(value);
    },
  );
}
```

要点：
- 当前值显示用 `items` 中匹配项的 `child`（迁移时零改动）；
- 24 项的"时"列表在 sheet 内 `ListView` 滚动即可，sheet 已限高 82%；
- 键盘可达性：InkWell 外包 `Semantics(button: true, label: labelText)`。

**改动清单**：新建 1 文件；settings_page.dart:869、scheduled_tasks_page.dart:104/:116 替换（各 ~4 行）；无 DB/控制器改动。
**测试**：widget 测试——点开出现 sheet、选择后回调携带值、FormField 校验态透传。
**工作量**：0.5 天。

### P0.2 theme 层过时配置清理

**现状**：app_theme.dart:159-168 `dialogTheme`（backgroundColor: surface 不透明）、:169-178 `bottomSheetTheme`、:179-189 `popupMenuTheme`。grep 确认全 lib 已无 `showModalBottomSheet`/`PopupMenuButton`/裸 `showDialog` 调用方，三块仅剩兜底作用且会误导后续开发。

**设计**：
- `dialogTheme` 保留 `titleTextStyle`（showImmersiveDialog 内 AlertDialog 的标题样式仍来自它），`backgroundColor: Colors.transparent`、`elevation: 0`——与 showImmersiveDialog 的 Theme 覆盖（immersive_sheet.dart:96-102）双保险；
- `bottomSheetTheme`、`popupMenuTheme` 整块删除；
- 删除前 grep 断言：`grep -rn "showModalBottomSheet\|PopupMenuButton\|DropdownButtonFormField(" lib`（第三项在 P0.1 完成后应为 0）。

**改动清单**：app_theme.dart 1 处删 2 块、1 处改 1 块。
**测试**：`flutter analyze` + 全量 `flutter test`（主题变更跑全量兜底）。
**工作量**：0.5 小时。

### P0.3 语义色收敛（第一批：chat/ + widgets/）

**现状**：硬编码 `Color(0x…)` 约 120+ 处。第一批范围（grep 实测）：plan_panel(20)、message_bubble(10)、floating_capsule_input(9)、tool_call_card(8)、chat_catalog_drawer(7)、chat_page(7)、chat_empty_state(6)、message_metrics_sheet/message_status_pill、reasoning_block、mascot_avatar。

**设计**：`AppSemanticColors`（app_theme.dart:251-321）扩容，明暗两套 const 同步补齐：

```dart
// 新增字段（6 个）
brandAccent,        // 亮 0xFF1677FF / 暗 0xFF4C8DFF —— plan_panel、抽屉图标等品牌蓝
userBubbleStart,    // 亮 0xB3FFFFFF / 暗 0x8C4C8DFF —— 用户气泡渐变起（带 alpha）
userBubbleEnd,      // 亮 0x80C7D7FE / 暗 0x8C9333EA
userBubbleGlow,     // 暗 0x4D9333EA / 亮透明 —— 气泡光晕
onGlass,            // 亮 0xFF1E293B / 暗 Colors.white —— 彩色玻璃上的文字
mutedOnGlass,       // 亮 0xFF627D98 / 暗 0xFF8A94A6 —— plan_panel 署名、副标题
```

映射规则（替换时执行）：
| 现硬编码 | 归宿 |
|---|---|
| 0xFF1677FF / 0xFF4C8DFF（品牌蓝）| `brandAccent` |
| 0xFF627D98 / 0xFF8A94A6 / 0xFF94A3B8 | `mutedOnGlass` 或既有 `textMuted` |
| 0xFFEDF1F8 / 0xFF243B53 | `textPrimary`（值已一致） |
| 0xFFEF4444 / 0xFFF59E0B / 0xFF10B981（HUD 三态）| 既有 `danger` / `warning` / `success`（色相微移需目测验收） |
| 0xFF2563EB（新建对话按钮 dark 分支）| `brandAccent`（同 source 合并） |
| 0xFF9333EA / 渐变对 | `userBubble*` 系列 |

**改动清单**：app_theme.dart 扩容（+6 字段 ×2 const）；第一批 11 个文件机械替换（预计 70 处）。第二批（P1 期间）：markdown/code_block、workspace/。
**测试**：替换是纯视觉 diff——`flutter analyze` + 深浅色双主题真机过一遍聊天页/计划卡片/抽屉/HUD。
**工作量**：1 天。

### P0.4 双层玻璃、手写表面与计划模式状态分叉

**现状**：
- model_picker_sheet.dart:291-294 `_ModelTile` 又包一层 ImmersiveSurface（选中 ultraThin / 未选 ultraThick），叠在外壳 ultraThick 上发浑；
- plan_panel.dart:66-75 手写 `Container(decoration: surface+border+floatingShadow)`；
- 计划模式状态双源：聊天页走 `ChatController.planMode`，设置页走 SharedPreferences `'plan_mode'`（历史遗留待办）。

**设计**：
- `_ModelTile` 去掉 ImmersiveSurface，改透明行 + 选中态着色：
  ```dart
  Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(AppTokens.smallControlRadius),
      color: selected ? colors.focusGlow : Colors.transparent,
      border: selected ? Border.all(color: colors.brandAccent) : null,
    ),
    child: ListTile(...),
  )
  ```
  外层 showImmersiveSheet 的 ultraThick 是唯一玻璃面，层级立刻干净。
- plan_panel 外壳换 `ImmersiveSurface(level: ultraThick, showGlow: true, borderRadius: radiusCard)`，内层保留 `Material(transparent)` 供 InkWell 水波。
- 计划模式单一数据源：设置页改读写 ChatController（Riverpod provider），SharedPreferences `'plan_mode'` 保留只读迁移（首次启动读旧值 → 写入控制器 → 删 key）。若设置页在聊天页外无法拿 controller 实例，则把 planMode 提升为独立 `StateNotifier<bool>`（`plan_mode_provider.dart`），两处共同订阅——推荐后者，30 行内完成。

**改动清单**：model_picker_sheet.dart（-6 行）、plan_panel.dart（外壳 ~10 行）、新增 plan_mode_provider.dart、chat_page/settings_page 各改一处读写。
**测试**：手动双向同步验证；既有 104 测试全绿。
**工作量**：0.5 天。

---

## P1 手感与动效

### P1.5 骨架屏

**现状**：全部加载态是 `CircularProgressIndicator`。集中点：async_state_view.dart:19-21、chat_catalog_drawer.dart:336-345（_loadingHistory）、history/knowledge/memory/agents/mcp 列表首屏、file_tree_sheet.dart:186。

**设计**：

```dart
/// 玻璃质感骨架块：半透明圆角块 + 光扫，尊重系统减少动效。
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});
}
// 实现：AnimationController(repeat, 1.4s) 驱动 LinearGradient(-1→2 平移)，
// 色 stop: Colors.white .04→.12（暗）/ black .04→.08（亮），ClipRRect 裁切；
// MediaQuery.disableAnimations → 静态纯色块。

/// 列表骨架预设：头像圆 + 两行条，随机微差更自然。
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.itemCount = 6, this.tileHeight = 64});
}
```

- `AsyncStateView` 增加可选参数 `Widget? loadingBuilder`，缺省仍为转圈；列表页传 `SkeletonList()`。这样 history/knowledge/memory/agents 一次改一行；AsyncStateView 本身不动默认行为，测试零回归。
- 抽屉 `_loadingHistory` 与文件树单独替换为 3 行小骨架。

**改动清单**：新建 skeleton.dart（~90 行）；async_state_view.dart +4 行；7 个调用点各 1 行。
**测试**：widget 测试——loading 态渲染 SkeletonList、disableAnimations 时无 AnimationController 循环。
**工作量**：1 天。

### P1.6 列表手势与下拉刷新

**现状**：history_page.dart:192-253 `_conversationTile` 只有 trailing 菜单；knowledge/memory 删除藏在 trailing 图标；所有数据库列表无下拉刷新（数据层 `_reload()` 均已是 `Future<void>`，可直接喂 RefreshIndicator）。

**设计**：
- `_conversationTile` 包 `Dismissible(key: ValueKey(conversation.id))`：
  - `startToEnd`（右滑）→ 置顶切换：直接 `db.saveConversation(copyWith(isPinned: !…))` + `_reload()`，背景层置钉图标 + `colors.focusGlow` 底；
  - `endToStart`（左滑）→ 删除：`confirmDismiss` 内走 `showConfirmAction`（复用现有玻璃确认），返回 true 后删除；
  - Dismissible 背景层用 `colors.danger.withValues(alpha: .15)`。
- knowledge_page.dart:177-187、memory_page.dart:202-218 同模式（仅左滑删除）。
- 下拉刷新：history/knowledge/memory/agents 四页 `RefreshIndicator(onRefresh: _reload, child: 列表)`。RefreshIndicator 颜色走 `colorScheme.primary`，无需额外配置；注意 `_reload` 已 `mounted` 保护，直接引用方法撕标签即可。

**改动清单**：4 个页面文件，各 +15~25 行；无新依赖（Dismissible/RefreshIndicator 均内置）。
**测试**：widget 测试——右滑置顶回调、左滑弹确认后删除；`_reload` 为 Future 的签名已满足。
**工作量**：1 天。

### P1.7 气泡进场动效与流式打字光标

**现状**：chat_message_list.dart:86-96 `itemBuilder` 直接返回 `MessageBubble`，新消息无进场；流式中 message_bubble.dart 的 lightweight 分支（:98-103）是裸 `SelectableText`，无"正在输出"视觉。

**设计**：
- **进场动效（只动尾部，避免窗口加载时旧消息集体闪动）**：`_ChatMessageListState` 记录 `_lastAnimatedLength`，`build` 时若 `widget.messages.length > _lastAnimatedLength` 且该项是末条，用 `ImmersiveMotion.fadeIn`（durationFast, offset 8）包裹——`ImmersiveMotion` 已内置 disableAnimations 降级（immersive_motion.dart:104-109），零额外处理：

  ```dart
  final animate = widget.messages.length > _lastAnimatedLength &&
      index == widget.messages.length - 1;
  _lastAnimatedLength = widget.messages.length; // build 内赋值需放 postFrame
  final bubble = MessageBubble(...);
  return animate ? ImmersiveMotion.fadeIn(child: bubble) : bubble;
  ```
  注意 `didUpdateWidget` 的 `_resetWindow` 分支同步重置 `_lastAnimatedLength`，防止切会话后误判。

- **打字光标**：message_bubble lightweight 分支改为：
  ```dart
  Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
    Flexible(child: SelectableText(...)),
    const _TypingCaret(),
  ])
  class _TypingCaret extends StatefulWidget { ... }
  // 2×16px 圆角竖条，colors.brandAccent；AnimationController 600ms repeat(reverse) 淡入淡出；
  // 复用 _ReducedAware 思路：disableAnimations → 常亮不闪。
  ```

**改动清单**：chat_message_list.dart（+12 行）、message_bubble.dart（+40 行）。
**测试**：widget 测试——流式尾部出现 caret、`running=false` 时消失；进场动画只作用于末条（两条消息连发时倒数第二条不重播）。
**工作量**：1 天。

### P1.8 触觉反馈规范化

**现状**：仅 chat_page.dart、floating_capsule_input.dart、chat_catalog_drawer.dart 三处散落 `HapticFeedback`，无规范。

**设计**：

```dart
abstract final class AppHaptics {
  static void select() => HapticFeedback.selectionClick();  // 列表选中/chip 切换
  static void tap() => HapticFeedback.lightImpact();        // 发送、按钮
  static void longPress() => HapticFeedback.mediumImpact(); // 长按气泡、滑到删除阈值
  static void alert() => HapticFeedback.heavyImpact();      // 危险审批弹窗、删除确认
}
```

映射表落地：发送/新建对话=tap；长按气泡、Dismissible 越过阈值=longPress；`showConfirmAction` 弹出且 confirmLabel 为删除类=alert（在 confirm_action.dart 内统一触发）；sheet 内选择项=select。替换现有 3 文件裸调用。
**改动清单**：新建 app_haptics.dart；~8 个触点替换。
**测试**：无自动化价值，真机手感走查；`flutter analyze`。
**工作量**：0.5 天。

### P1.9 错误信息人性化

**现状**：错误以 `错误：${原始异常}` 拼进助手消息持久化（chat_controller.dart:1028、:1074），CORS 场景用户看到整段 XMLHttpRequest 技术文本（酷安发布图即真实案例）。

**设计**：新增 `application/error_humanizer.dart`，写入时转换、渲染时折叠：

```dart
class HumanizedError {
  final String summary;   // 一句话人话
  final String detail;    // 原始异常全文
}
HumanizedError humanizeError(String raw) {
  // 规则表按序匹配（contains 大小写不敏感）：
  //  XMLHttpRequest / CORS          → '网络请求被浏览器拦截（Web 版直连受限），请改用桌面端或在设置中配置代理网关'
  //  SocketException / Failed host  → '连不上模型服务，请检查网络或服务地址'
  //  TimeoutException               → '请求超时，模型服务响应过慢'
  //  401 / 403 / invalid_api_key    → 'API 密钥无效或已过期，请到设置中检查'
  //  429 / rate_limit               → '触发限流，稍等片刻再试'
  //  500/502/503                    → '模型服务暂时不可用'
  //  兜底                            → '出错了，详情见技术细节'
}
```

- **写入侧**（chat_controller 两处）：消息文本改为 `错误：${h.summary}\n\n[技术细节]\n${h.detail}`——内容仍是纯文本，**无 DB schema 变更**（schemaVersion 保持 11）。
- **渲染侧**（message_bubble.dart）：检测正文含 `\n[技术细节]\n` 时拆分：首行正常渲染，技术细节走现有 `reasoning_block` 同款折叠（紫色竖条改 `colors.danger`），避免改动 Markdown 管线。
- 存量旧消息（已是长文本）渲染侧兜底：正文以 `错误：` 开头且 >200 字符时自动折叠后半段。

**改动清单**：新建 error_humanizer.dart（~80 行 + 单测）；chat_controller.dart 2 行；message_bubble.dart +30 行。
**测试**：humanizer 规则表单测全覆盖（每规则一例 + 兜底）；渲染拆分 widget 测试。
**工作量**：1 天。

---

## P2 无障碍与国际化

### P2.10 对比度、Semantics、大字体

**现状**：全 lib 0 处显式 `Semantics(`；灰字大量 `withValues(alpha: 0.6/0.7)`（drawer `_SectionHeader`:447、`_HistoryTile`:548 等）；无一处 TextScaler 处理，固定高度控件（抽屉新建按钮 SizedBox(height:44)（chat_catalog_drawer.dart:153）、floating_capsule_input 胶囊行）在大字体下溢出。

**设计**：
1. **对比度**：`alpha: 0.6/0.7` 的灰字统一提到 `colors.textMuted` 原值（light 0xFF64748B 对白底 4.76:1、dark 0xFF94A3B8 对 0xFF080D17 ≈ 8:1，均过 AA）；跑 `grep -rn "alpha: 0.6\|alpha: 0.7" presentation` 逐点替换（预计 ~15 处）。装饰性元素（分隔线、描边）不动。
2. **Semantics**：只给无文字语义的交互件补标签——气泡复制/重生成 IconButton（`Semantics(button:true, label:'复制这条消息'/'重新生成回复')`）、HUD 百分比（`Semantics(label:'上下文已用 $percent%')`）、计划面板三菜单、附件图片（`label:'附件图片，点按查看大图'`，配合 P3.15）。预计 8~10 处，用原生 `Semantics` 不引新依赖。
3. **大字体**：两步——
   - 固定高改最小高：`SizedBox(height:44)` → `ConstrainedBox(constraints: BoxConstraints(minHeight:44))`（抽屉新建按钮、sheet 主按钮）；
   - floating_capsule_input 内部 Row 布局包 `FittedBox` 的仅限模型 pill 文案，正文区自适应。
   - 验收手段：新增 widget 测试以 `MediaQuery(textScaler: TextScaler.linear(1.3))` pump 聊天页空态 + 输入条 + 气泡，断言无 `RenderFlex overflow`（debug 下 overflow 会抛异常，天然断言）。

**改动清单**：~20 个小点分散在 presentation/；新增 2 个 widget 测试。
**工作量**：2 天。

### P2.11 动效偏好全面尊重

**现状**：`ImmersiveMotion._ReducedAware`（immersive_motion.dart:104-109）与 `ImmersiveSurface` 已各自处理 `disableAnimations`；弹层过渡（immersive_sheet.dart 两处 transitionBuilder）未处理。

**设计**：showImmersiveSheet / showImmersiveDialog 的 `transitionBuilder` 开头加：

```dart
if (MediaQuery.of(context).disableAnimations) return child;
```

以及 P1.5 骨架屏光扫内置降级（见前）。此后新增任何动画一律走 ImmersiveMotion，规范写入组件 doc 注释。
**工作量**：0.5 小时 + 走查。

### P2.12 国际化地基（字符串收敛）

**现状**：`AppStrings`（l10n/app_strings.dart）已是 `abstract final class` + `static const` 的集中表，注释明确"后续替换为 AppLocalizations 即可，无需改动调用点"；但 chat/ 等页面大量中文直写（历史遗留待办）。

**设计**（三步走，本阶段只做前两步）：
1. **收敛**：按目录顺序迁移到 AppStrings：`chat/` → `presentation/widgets/` → `workspace/` → 各 page。每目录一个 PR 粒度，机械搬运 + 命名归组（`chatEditResendTitle` 等）。
2. **结构化**：AppStrings 按页面分区注释（已具备）保持字母序可选；新增字符串一律入表（写进 CLAUDE/贡献约束）。
3. **ARB 化（后续版本）**：`flutter gen-l10n` 接入，把 `static const x = '中文'` 批量改为 getter `String get x => AppLocalizations.of(locale).x`——调用点零改动，这是当初设计的目的。

**验收**：`grep -rn "Text('" presentation/chat` 中文命中数为 0（图标 tooltip 一并收敛）。
**工作量**：chat/ 目录 1 天，全量收敛 3~4 天（可拆散进多个迭代）。

---

## P3 平台进阶

### P3.13 宽屏双栏

**现状**：chat_page.dart build 里 `Stack` 全屏渐变 + 单栏；ChatCatalogDrawer 是 `Drawer` 壳（chat_catalog_drawer.dart:106-114）包内容 Column，宽度 `min(width*0.84, 340)`（:86）。

**设计**：
1. 把 Drawer 内 `ImmersiveSurface + SafeArea + Column` 整体抽为 `CatalogPanel`（无路由语义，回调签名不变）；
2. chat_page build 外层加：
   ```dart
   LayoutBuilder(builder: (context, c) {
     final twoPane = c.maxWidth >= 900;
     return twoPane
       ? Row(children: [
           SizedBox(width: 340, child: CatalogPanel(...原 Drawer 回调透传...)),
           VerticalDivider(width: 1, color: colors.border),
           Expanded(child: 原聊天区),
         ])
       : 原单栏 + openDrawer();
   })
   ```
3. 双栏时汉堡按钮隐藏（capsule_top_bar 加 `showMenuButton` 参数），抽屉内所有 `Navigator.pop(context)` 在 CatalogPanel 场景为 no-op（pop 仅在 Drawer 模式传入）。

**改动清单**：chat_catalog_drawer.dart 重构（逻辑不动纯搬移）、chat_page.dart +25 行、capsule_top_bar.dart +1 参数。
**测试**：900dp 断点 widget 测试（两栏渲染 / 单栏 Drawer 路径）；真机横屏 + Windows 走查。
**工作量**：2 天。

### P3.14 会话全文搜索（FTS5）

**现状**：Drift 2.22.1、schemaVersion 11；Messages 表字段 app_database.dart:22-29（`content` 为正文）；history_page 搜索仅匹配标题（:45-51 `_filtered`）。

**设计**：
- **迁移 v11→v12**（`onUpgrade` stepVersion 12）：
  ```sql
  CREATE VIRTUAL TABLE messages_fts USING fts5(
    content, message_id UNINDEXED, conversation_id UNINDEXED, tokenize='trigram');
  -- + 3 个触发器（AFTER INSERT/UPDATE/DELETE on messages）同步
  -- 回填：INSERT INTO messages_fts(...) SELECT content, id, conversation_id FROM messages;
  ```
  选 `trigram` 分词：中文子串可查（`tokenize='unicode61'` 对中文是整段 token，不可用）；trigram 需 ≥3 字符，**1~2 字查询降级 LIKE**：
  ```dart
  Future<List<SearchHit>> searchMessages(String kw) => kw.length >= 3
    ? _ftsMatch(kw)      // MATCH '"kw"' + ORDER BY rank LIMIT 50
    : _likeFallback(kw); // content LIKE '%kw%' LIMIT 50（现有量级无压力）
  ```
- **UI**：history_page 搜索框下加 `SegmentedButton(标题/全文)`；全文结果行显示会话名 + 命中片段（content 前 80 字含高亮 `TextSpan`）。
- **跳转定位**：ChatPage 增加 `initialFocusMessageId` 参数 → 进页后 ChatMessageList 若目标在窗口外扩窗到包含它，滚动定位后气泡 2 秒高亮描边（`colors.focusGlow` + `brandAccent` 边框渐隐）。

**改动清单**：app_database.dart（迁移 + 触发器 + 查询方法 ~80 行，schemaVersion 11→12）、history_page.dart（+40 行）、chat_page.dart / chat_message_list.dart / message_bubble.dart（定位高亮 ~40 行）。
**测试**：DB 层——中文 2 字/3 字/长句三态查询单测 + 迁移测试（v11 数据库打开升级）；UI——搜索跳转定位。
**风险**：trigram 索引体积约为原文 2~3 倍，移动端可接受；`MATCH` 语法需转义双引号防注入（参数化即可）。
**工作量**：3 天。

### P3.15 附件图片全屏查看器

**现状**：attachment_strip.dart 图片缩略图无任何 onTap（grep 证实），点击无响应。

**设计**：复用 showGeneralDialog 自制轻量查看器（不引 photo_view 依赖）：

```dart
Future<void> showImmersiveImageViewer(BuildContext, {required Uint8List? bytes, String? path}) {
  // showGeneralDialog: barrierColor black .92, transitionBuilder 复用弹层 fade；
  // 内容：InteractiveViewer(maxScale 5) + Hero(tag: 'img-$messageId') 与缩略图联动；
  // 手势：双击缩放切换（1x↔2.5x，AnimatedScale）、拖拽下滑关闭（DraggableScrollableSheet 或位移+透明度手势）；
  // 底部玻璃工具条（ImmersiveSurface thick）：保存 / 分享（share_plus 已有依赖）/ 关闭。
}
```

attachment_strip 图片项包 `GestureDetector(onTap: viewer) + Semantics`。
**改动清单**：新建 image_viewer.dart（~120 行）；attachment_strip.dart +6 行。
**测试**：widget——点击弹出、双击缩放状态切换；真机手势走查。
**工作量**：1.5 天。

### P3.16 输入草稿保持

**现状**：floating_capsule_input 的 TextEditingController 为页面持有，切换会话不清也不换——所有会话共享同一输入框内容（误触即丢语境）。

**设计**：

```dart
/// application/draft_store.dart
class DraftStore {
  static final _mem = <String, String>{};               // 会话内热缓存
  static Future<void> save(String convId, String text); // 防抖 300ms 写 SharedPreferences 'drafts_json'（仅保留最近 20 条）
  static Future<String> load(String convId);
  static Future<void> clear(String convId);
}
```

接线点：chat_page 的 `switchConversation`（chat_controller 既有钩子）→ 旧会话 `save`、新会话 `load`；发送成功后 `clear`。
**测试**：单测 save/load/clear + 防抖；widget——切会话草稿恢复。
**工作量**：1 天。

### P3.17 代码块增强

**现状**：markdown/code_block.dart（13 处硬编码色）由 flutter_markdown 的 builder 驱动；pub 依赖 flutter_markdown 0.7.7+1 已 discontinued（官方建议迁 flutter_markdown_plus）。

**设计**：本项只做 UI 增强，**markdown 库迁移单列**（涉及 MathMarkdown 管线，另立技术方案）：
- 头部信息条：语言标签（取自 fence info string）+ 一键复制按钮，条本身用 `ImmersiveSurface(level: thin, borderRadius: 垂直上圆角)`；
- ≥20 行显示行号列（等宽字体、`colors.mutedOnGlass`，与代码横向滚动联动用 `Table` 双列结构）；
- 横向滚动：SingleChildScrollView(scrollDirection: horizontal)（若现状缺失）；
- 配色收敛到 P0.3 扩展的 codeBackground / codeKeyword 等 token。
**工作量**：1.5 天（不含库迁移）。

### P3.18 桌面键鼠适配

**现状**：Windows 目录存在、应用可跑；无 hover 定制、长按菜单无右键等价、无快捷键。

**设计**：
- hover：listTileTheme 增 `hoverColor: colors.focusGlow`（主题级一处，全应用 ListTile 生效）；
- 右键菜单：message_bubble 外包 `GestureDetector(onSecondaryTapUp: (d) => showMenu(position: d.globalPosition &, items 与长按菜单同一枚举))`——桌面仅 Windows/macOS/Linux 启用（`kIsWeb || Platform.isWindows…` 判断，与 settings_page MCP stdio 可用性判断同款写法）；
- 快捷键：floating_capsule_input 包 `KeyboardListener`，桌面端 `Ctrl+Enter` 发送（与 Enter 换行并存）、`Esc` 停止生成。

**工作量**：1 天。

---

## 实施顺序与里程碑

| 里程碑 | 内容 | 出口标准 |
|---|---|---|
| M1（本周） | P0.1→P0.4 + P1.9 | analyze/test 全绿；grep 无系统弹出层；错误气泡首行人话 |
| M2（+1 迭代） | P1.5→P1.8 + P2.10 对比度部分 | 无转圈首屏；列表全手势；1.3x 字体无溢出测试就位 |
| M3（+2 迭代） | P2.10 剩余 + P2.11 + P2.12 chat/ 目录 | TalkBack 可用；chat/ 中文收敛完成 |
| M4（按反馈排） | P3.14 → P3.15 → P3.13 → 其余 | 每项独立可发版 |

## 总体风险与回滚

1. **AppSemanticColors 扩容**是纯增量（加字段不改旧值），任何一步可单独回滚；替换 diff 全是颜色字面量，code review 逐行可查。
2. **Drift 迁移 v12**（P3.14）是唯一动数据的改动：FTS 表是派生数据，可随时 `DROP` 重建，迁移写 `onUpgrade` 幂等分支（`user_version` 判断）；发布前用 v11 真机库升级冒烟。
3. **chat_page 双栏重构**（P3.13）触碰主页面 build：CatalogPanel 抽取保持回调签名不变，单栏路径行为 diff 为零，出问题仅回滚双栏分支。
4. 所有阶段出口统一跑 `flutter analyze` + `flutter test`，深/浅色双主题真机走查（清单：聊天页、计划卡片、抽屉、模型选择、任一设置表单弹窗）。
