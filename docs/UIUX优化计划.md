# NEXUS Agent UI/UX 优化计划

> 基于 2026-09-05 现状盘点：毛玻璃设计系统（ImmersiveSurface / showImmersiveSheet / showImmersiveDialog）已全量落地，
> 全应用无遗留不透明弹层。本计划覆盖其之后的下一阶段：一致性收尾 → 手感与动效 → 无障碍与国际化 → 平台进阶。
> 每项给出涉及文件与验收标准，按优先级分四阶段推进，每阶段可独立发版。

---

## P0 一致性收尾（小改动，快速消化，1~2 天）

毛玻璃体系刚铺完，先把这一轮留下的尾巴剪掉，避免设计系统出现"例外"。

1. **系统下拉菜单玻璃化（毛玻璃最后漏网）**
   - 现状：settings / scheduled 任务表单里的 `DropdownButtonFormField` 展开的菜单仍走不透明 `popupMenuTheme`。
   - 方案：接入自定义玻璃下拉（复用 showImmersiveSheet 或包 BackdropFilter 的 PopupRoute），或封装 `ImmersiveDropdown` 组件统一替换。
   - 验收：全应用 grep 不到非玻璃弹出面。

2. **清理 theme 层过时配置**
   - 现状：`app_theme.dart` 的 dialogTheme / bottomSheetTheme / popupMenuTheme 已无实际调用方（弹层全走沉浸式入口），保留不透明默认值反而误导后续开发。
   - 方案：dialogTheme 仅保留文字样式（titleTextStyle/contentTextStyle），背景色改透明并注释说明；或直接删除断言无回归。

3. **收敛硬编码颜色到语义 token（第一批）**
   - 现状：硬编码 `Color(0x…)` 全 lib 约 120+ 处，重灾区：plan_panel(20)、markdown/code_block(13)、message_bubble(10)、floating_capsule_input(9)；`AppSemanticColors` 已有 chatUser/chatAssistant 语义色但气泡未使用。
   - 方案：扩充 AppSemanticColors（品牌蓝 0xFF1677FF、紫 0xFF9333EA、成功/警告/错误、代码块配色），逐文件替换；先做 chat/ 与 widgets/ 两个目录。
   - 验收：chat 与 widgets 目录 0 处 `Color(0x`（theme 文件除外）。

4. **双层玻璃与手写表面统一**
   - model_picker_sheet.dart:291 内层又包 ImmersiveSurface，叠在外壳 ultraThick 上偏浑浊 → 内层改用 ImmersiveListTile/普通行 + 选中态高亮。
   - plan_panel.dart 自写 surface/border 阴影 → 改 ImmersiveSurface(showGlow: true)，与全应用卡片同源。

---

## P1 手感与动效（核心体验，约 1 周）

目标：从"能用、好看"到"跟手、有生命感"。

5. **骨架屏替代转圈**
   - 现状：所有加载态都是 `CircularProgressIndicator`（历史列表、知识库、文件树、Agent 列表等），冷启动观感廉价。
   - 方案：基于现有玻璃材质做 `SkeletonBox`（半透明圆角块 + 光扫动画，尊重 disableAnimations），替换 AsyncStateView 的 loading 分支与列表首屏。
   - 验收：主列表页首屏无转圈。

6. **列表手势补齐**
   - 历史会话行加 `Dismissible` / Slidable：右滑置顶/收藏、左滑删除（删除走现有玻璃确认框）；知识库/记忆/Prompt 列表同规则。
   - 会话列表/消息列表加下拉刷新（数据源都支持重载，纯 UI 补齐）。
   - 验收：所有数据库驱动列表：滑动操作 + 下拉刷新齐备。

7. **流式与气泡微动效**
   - 新消息气泡进入动画（fade + 轻微上移，现有 AppTokens.durationFast/curveStandard 直接可用）；
   - 流式输出尾部加打字光标；工具卡片执行中脉冲已有个体样式，统一由 ImmersiveMotion 驱动。
   - 验收：聊天滚动中无跳变感；`flutter test` 中 widget 测试不因动画超时。

8. **触觉反馈规范化**
   - 现状：仅 3 个文件用 HapticFeedback，规则不明。
   - 方案：定一页规范并封装 `AppHaptics`（轻点=selectionClick、发送=lightImpact、危险确认=mediumImpact、长按=heavyImpact），替换散落调用。
   - 验收：grep 无裸 HapticFeedback 调用。

9. **Web/桌面错误信息人性化**
   - 现状：Web 端 CORS 等底层错误（如 XMLHttpRequest onError 全文）直接吐进气泡。
   - 方案：错误展示层截断技术细节进「技术细节」折叠（tool_humanizer 已有同款模式），首屏一句话人话 + 重试按钮。
   - 验收：断网/CORS 场景气泡首行是人话。

---

## P2 无障碍与国际化（合规与受众扩大，约 1~2 周）

10. **对比度与字号适配**
    - 现状：全项目 0 处显式 Semantics；大量 `onSurfaceVariant.withValues(alpha: 0.6~0.7)` 小字在玻璃上对比度存疑；无任何 TextScaler 处理，系统大字体下固定高度控件（44px 按钮、胶囊输入条）会溢出。
    - 方案：
      - 灰字 alpha 下限提到 0.75 或换用主题 token，跑一遍深/浅色对比度自查（WCAG AA 4.5:1 正文）；
      - 关键自定义控件包 Semantics(label:)（气泡复制按钮、工具卡片状态、HUD 百分比）；
      - 用 `MediaQuery.textScalerOf` 验证布局，固定高度改 minHeight。
    - 验收：系统字体放大到 1.3x 无溢出截断；TalkBack 可朗读气泡操作。

11. **动效偏好全面尊重**
    - ImmersiveSurface 已处理 disableAnimations 降级；把同一开关推广到骨架屏光扫、ImmersiveMotion、弹层 scale 过渡（统一入口 `MotionPreferences.enabled`）。

12. **国际化地基（先收敛再翻译）**
    - 现状：大量硬编码中文绕过 `l10n/app_strings.dart`（历史遗留待办）。
    - 方案：不急于翻译，先做字符串收敛——新增字符串一律入 AppStrings，存量按页面分批迁移；完成后接 ARB 生成，英文版作为首个第二语言。
    - 验收：chat/ 目录 0 处硬编码 UI 中文。

---

## P3 平台进阶（大功能，按发版节奏排）

13. **宽屏双栏布局**：≥900dp（平板/桌面/Web 宽窗）时目录抽屉变常驻左栏，聊天居中限宽；复用 ChatLayoutController 的 widthFactor 逻辑。
14. **会话内全文搜索**：目前只有标题搜索；在 Drift 加 FTS5 索引，搜索结果跳转定位到消息并高亮。
15. **图片查看器**：附件图片点击进全屏玻璃查看器（捏合缩放/保存/转发）；现点击无响应是高频反馈点（发布后验证）。
16. **草稿保持**：切换会话时输入框草稿按会话存内存（或 SharedPreferences），避免误触丢内容。
17. **代码块增强**：语言标签、行号（>20 行时）、横向滚动、复制按钮进玻璃体系；code_block.dart 一并完成 token 收敛。
18. **桌面键鼠适配**（Windows 运行已有雏形）：hover 态补齐（ImmersiveListTile）、右键菜单等价长按菜单、Ctrl+Enter 发送。

---

## 已知技术风险（与 UX 直接相关，随阶段处理）

| 风险 | 影响 | 处理时机 |
|---|---|---|
| Flutter Web 每条气泡一个 BackdropFilter，长会话滚动掉帧 | Web 端体验 | P1.7 时实测帧率，必要时超 N 条降级为纯色 |
| plan_panel 计划模式状态分叉（ChatController vs SharedPreferences） | 设置开关互不同步 | 并入 P0.4 顺带修 |
| MCP 双入口（设置内嵌 + 独立页）| 信息架构混乱 | P3 信息架构整理时合并 |
| 插件声明式工具未接入运行时（`PluginStore.loadDeclarativeTools` 未被调用） | 装插件无效，属功能性但伤害信任 | 不属 UI，单列跟踪 |

## 节奏建议

- 本周：P0 全部 + P1.9（都是小刀，随下个 0.6.x 直接发）
- 下个迭代：P1 全量 + P2.10 对比度部分
- 之后：P2 剩余与 P3 按反馈热度排序（建议 14 全文搜索 > 15 图片查看器 > 13 双栏）
- 每阶段结束跑 `flutter analyze` + `flutter test` 全绿，并在真机过一遍深/浅色双主题
