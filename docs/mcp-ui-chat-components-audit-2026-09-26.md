# UI 打磨 · 聊天组件（非 WIP）审计（2026-09-26）

范围：用户选择「只做未改动的组件」。不触碰 WIP：chat_page、capsule_top_bar、chat_empty_state、
floating_capsule_input、session_metrics_sheet 及未跟踪的 dock / viewport / session header 等。
基线截图：`artifacts/ui-shots/chat_shots_test.dart` → `ch_{msgs,approval,picker,plan}_{light,dark}.png`
（消息列表按 ChatMessageList 默认内边距 16 渲染；按钮上的 □ 为测试字体伪影）。

## 问题清单

| # | 组件 | 问题 | 严重度 |
|---|---|---|---|
| 1 | NexusStatusBadge（全局） | success/warning/danger 前景固定用浅色值：深色下「待确认」「高危」「安全」等徽标文字对比度不足 | 高 |
| 2 | 消息 Markdown 表格 | 表头居中而正文左对齐、表头无底色区分、四周实线网格偏重 | 中 |
| 3 | 工具审批 sheet | 副标题「执行前需要你的授权」与「技术细节」用 `colorScheme.outline`（描边色）作文字，浅色下几乎不可见；风险色用浅色固定值；终端命令在摘要参数行与指令预览中重复 | 中 |
| 4 | 模型选择 sheet | 厂商筛选为描边 + 阴影胶囊（与 X3/W4 无描边填充不一致）；无匹配模型的厂商仍显示；行尾重复显示分组名 | 中 |
| 5 | 计划面板 | 展开态固定高度 min(410, 58% 屏高)，步骤少时按钮上方大片空白 | 中 |
| — | 引用块 | 底色随文字宽度收缩（框架 Wrap 布局），需自定义 builder，暂不改 | 低 |

## 计划（Z 系列，逐项提交）

- **Z1** NexusStatusBadge 深色前景改用 dark 语义色。
- **Z2** 表格：表头左对齐 + 浅底，横向细分隔线，单元格内边距（两处样式表同步）。
- **Z3** 审批 sheet：副标题/技术细节改 textMuted；风险色随主题；与指令预览重复的参数行不再显示。
- **Z4** 模型选择：无描边填充筛选胶囊；隐藏无匹配模型的厂商（“全部”与当前选中始终保留）；去掉行尾重复分组名。
- **Z5** 计划面板：高度随内容收缩，上限不变。

约束：不改业务逻辑；非 formatter-clean 文件（model_picker_sheet、plan_panel、nexus_status_badge）只手改不格式化。

## 交付（2026-09-26）

| 项 | 提交 | 文件 | 结果 |
|---|---|---|---|
| Z1 | `6d02149` | widgets/nexus_status_badge.dart、test/nexus_status_badge_theme_test.dart（+2） | 深色下 success/warning/danger 徽标前景改用 dark 语义色（「待确认」等可读） |
| Z2 | `c116ec0` | chat/widgets/message_bubble.dart | 表格表头左对齐 + 浅底、仅横向细线、单元格 10×6 内边距（两处样式表同步） |
| Z3 | `8f73a63` | chat/widgets/tool_approval_sheet.dart | 副标题/技术细节改 textMuted；风险色随主题；与指令预览相同的参数行不再重复；sheet 按内容定高（上限不变） |
| Z4 | `0408be1` | chat/widgets/model_picker_sheet.dart（手改）、test/model_picker_sheet_test.dart（+1） | 无描边填充厂商胶囊；隐藏无模型厂商；去掉行尾重复分组名；筛选规则抽为 `_matchesCategory`，行为不变 |
| Z5 | `b51a48b` | chat/widgets/plan_panel.dart（手改） | 展开态按内容定高（上限 410 / 58% 不变），去掉按钮上方空白 |

验证：每项 analyze 无问题、13 个聊天/组件相关测试文件 + chat/tools 截图 20/20；全量 `flutter test` 1544 通过；
fast ARM64 APK 构建成功（64.6s）。未触碰任何 WIP 文件；分支未推送。
遗留：引用块底色随文字收缩（需自定义 builder）；聊天页主体 / 输入框 / 顶栏待用户提交重构后再做。
