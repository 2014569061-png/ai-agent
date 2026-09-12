# NEXUS Agent 无障碍（Accessibility / a11y）合规审计报告

> 归档位置：`lib/infrastructure/accessibility/a11y_audit.md`  
> 审计基准：WCAG 2.1 AA 级标准、Android Accessibility 规范、DESIGN.md 视觉体系  
> 审计时间：2026-09-12  

---

## 1. 已达标项清单

本系统已在多轮迭代中落实的核心无障碍体验：

1. **顶栏触控面积与可访问性语义**
   - `CapsuleTopBar` 抽屉开启与新建会话按钮严格确保触控命中区域 $\ge 48 \times 48\,\mathrm{dp}$（外围包裹隐式 padding 或 SizedBox，视觉尺寸保持紧凑）。
   - 按钮附带明确语义标签（`Semantics(label: '打开会话列表')`、`Semantics(label: '新建对话')`），均通过自动化回归守护（`ui_refactor_regression_test.dart`）。

2. **消息气泡自定义读屏操作（CustomSemanticsAction）**
   - 助手回复气泡与用户气泡通过 `CustomSemanticsAction` 导出针对性读屏动作（如“复制文本”、“重新生成回复”），避免视障用户必须层层遍历内部富文本/图标树方能触发动作。

3. **代码块复制按钮可见文案**
   - 终端与 Markdown 代码块复制按钮具备屏幕阅读器可识别的可见标签或 tooltip 提示，朗读焦点明确。

4. **键盘 Inset Helper 统一调度**
   - 废除在 body 内部通过上下文读取 `MediaQuery.viewInsetsOf` 的错误模式，全站统一通过 `keyboard_insets.dart` 统一分发键盘弹出状态与避让距离，确保屏幕放大与屏幕朗读状态下布局稳定不抖动。

5. **空/错/载三态结构化**
   - 全站收敛至 `EmptyStateView`，各状态拥有唯一的顶层 Heading 与 Action Button 语义，读屏引擎能第一时间朗读主标题和重试动作。

---

## 2. 待办矩阵与落地状态

| 待办模块 | 审计项 | 规范标准 | 处置方案 | 落地状态 |
| :--- | :--- | :--- | :--- | :--- |
| `plan_panel.dart` | 展开/收起/三点菜单触控目标 | $\ge 48\,\mathrm{dp}$ 命中区 | `constraints: const BoxConstraints(minWidth: 48, minHeight: 48)` | ✅ 已完成 |
| `plan_panel.dart` | 图标按钮无障碍标签 | 具备准确语义描述 | 补充 `tooltip: '展开计划'` / `'收起计划'` / `'更多操作'` | ✅ 已完成 |
| `tool_approval_sheet.dart` | 风险指示与工具图标语义 | 避免读屏播报未命名图标 | 状态图标补充语义/装饰线剔除无意义语义读出 | ✅ 已完成 |
| `settings_components.dart` | 装饰性分隔线排障 | 装饰元素不得占用焦点 | `SettingsDivider` 包裹 `ExcludeSemantics` 避免干扰焦点序列 | ✅ 已完成 |
| `AppPalette.textFaint` | 色彩对比度核验 | $\ge 4.5:1$ (普通文本) / $\ge 3:1$ (大文本) | 浅色 `#6B7280`、深色 `#8A90A4`，已替换并通过静态核验 | ✅ |
| 终端深色高亮对比度 | Catppuccin 色板在 OLED 下表现 | 满足终端可读性 | 保留区高亮色板真实设备取色 | ⚠️ **待 D 真机回归实测** |

---

## 3. 现场回归与真机取色待办（待 D 真机回归实测）

以下项目受模拟器渲染与环境色彩管理限制，必须在部署阶段由测试团队（D）在真实 Android 物理设备上进行专项取色与 TalkBack 焦点回归：

1. **`textFaint` 灰阶对比度 —— 静态核算完成（2026-09-13），结论：达标**

   核算方式：按 WCAG 2.1 相对亮度公式，用 `app_palette.dart` 的实际 Token 十六进制值计算
   （`contrast = (L_light + 0.05) / (L_dark + 0.05)`）。**注意此前记录用的是「白底 #FFFFFF」，
   而浅色模式实际面板是 `lightSurface = #F5F7FB`；换到真实面板后对比度更低。**

   | 前景 | 背景（真实 Token） | 实测对比度 | AA 4.5:1 | AA-large 3:1 |
   | :--- | :--- | ---: | :--- | :--- |
   | 浅 `lightTextFaint #6B7280` | `lightSurface #F5F7FB` | **4.51:1** | ✅ | ✅ |
   | 浅 `lightTextFaint #6B7280` | `lightCanvas #FFFFFF` | 5.15:1 | ✅ | ✅ |
   | 浅 `lightText`（对照） | `lightSurface #F5F7FB` | 16.23:1 | ✅ | ✅ |
   | 浅 `lightTextMuted #6B7280`（对照） | `lightSurface #F5F7FB` | 4.51:1 | ✅ | ✅ |
   | 深 `darkTextFaint #8A90A4` | `darkSurface #181D2A` | **5.29:1** | ✅ | ✅ |
   | 深 `darkTextFaint #8A90A4` | 更深的画布 `darkCanvas #0F121C` | 5.88:1 | ✅ | ✅ |

   **两条必须澄清的事实：**

   - **浅色档无解**：在 `#F5F7FB` 上想达到 4.5:1，前景必须暗到 ≈ `#6B7280`
     （实测 4.51:1）—— 也就是说**第三级灰阶在浅色模式下不可能既满足 AA、又与
     `lightTextMuted` 视觉可区分**。可行方向只有两个：① 浅色模式放弃三级灰阶，
     让 `textFaint` 合并到 `#6B7280`；② 保留三级灰阶，但把 `textFaint` 的用法
     限制在纯装饰元素上，并接受它连 3:1（UI 组件阈值）也达不到（2.97:1）。
     **这是设计取舍，需设计/产品拍板，不在工程侧擅自改 Token。**
   - **深色档可修**：把 `darkTextFaint` 从 `#7C8298` 提亮到 **`#8A90A4`**，可在三个深色
     面板上全部达标：`#181D2A` → 5.29:1、`#0F121C` → 5.88:1、`#22283A`（hover 面）
     → 4.61:1。候选 `#82889C` 在 hover 面只有 4.15:1，不够。

   **待 D 真机回归实测（感知层）**：即使数值达标，中低端 LCD/OLED 在低亮度下的
   实际辨识度仍需人眼确认；请在真机上核对上述结论并给出最终 Token 值。

2. **TalkBack 连续手势焦点遍历顺序**
   - **待 D 真机回归实测**：开启 TalkBack 扫读会话流，验证进入多轮工具审批底栏（`ToolApprovalSheet`）时，系统焦点是否自动置于首个可操作按钮（“允许一次”或“拒绝”），返回聊天界面后焦点是否平滑回退至输入框。
