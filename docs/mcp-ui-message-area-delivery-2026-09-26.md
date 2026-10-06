# 消息区 UI 美化交付记录（2026-09-26）

分支 `feat/harmony-motion`，全部仅本地提交，未推送。范围只含消息区四个文件：
`message_bubble.dart`、`reasoning_block.dart`、`chat_message_list.dart`、
`markdown/code_block.dart`。他人未提交的聊天页拆分 WIP 未触碰。

## 提交

| 项 | 提交 | 内容 |
| --- | --- | --- |
| S2 | e7e095a | 去掉圆角代码块后面的方形 Markdown 底 |
| S3 | f28088c | 行内代码：0.9 倍字号、等宽、文字色低透明度浅底 |
| S4 | 6614b26 | 列表与段落间距：blockSpacing 6、listIndent 24、标题下距 2 |
| S5 | 37c6797 | 工具消息改为自适应宽度胶囊芯片，只显示结果摘要（失败加「失败：」） |
| S6 | 3b9d36f | 推理头部简化为「已思考 N 秒 ⌄」，整行可点；运行中「进度 · 阶段 计时」 |
| S7 | 2708d77 | 节奏：轮内 12、新一轮用户消息前 24、流式进度卡与正文 10 |
| S1 | c6d5ec8 | 圆角统一（卡片 16、代码块 12、芯片半高、用户气泡 20+右下 6），描边改浅底 |

## 验证

每项均执行：`dart format`（仅改动文件）、`dart analyze --fatal-infos lib test`、
`flutter test --no-pub`（最终 1535 通过）、`build-apk.bat --fast`（约 60 秒成功）。
前后对比截图由 `artifacts/ui-shots/message_area_shots_test.dart` 生成（393×852 @2x，
动效关闭），各项 diff 存于 `artifacts/ui-shots/s*_changes.patch.txt`。

## 行为说明

- S5 只影响展示：工具消息内容（`ToolResult.encode` 的 JSON）不变，芯片取 `message`
  字段单行显示；完整结果仍在工具活动面板。新增 `test/tool_result_summary_test.dart`。
- S6 更新了三处测试断言（原先查找「思考过程」按钮 / REASONING 文字）。
- S1 未改全局 token（`radiusCard` 等被 WIP 文件引用），只在消息区局部取值。

## 待办 / 需真机确认

- 真机检查浅色模式代码块浅灰底与页面的对比度、推理卡整行点按的水波纹。
- WIP 合并后再做输入框、顶栏、空状态与页面布局。
- U7（流式时原始反引号）按计划不处理。
