# 聊天 UI 优化交付记录

日期：2026-09-22

## 交付结论

本轮聊天信息层级、输入稳定性、助手消息降噪、指标面板分层及自动化视觉/状态检查已完成。最终全量测试 **1232 项全部通过**；静态分析 **No issues found**；最新 Android arm64 Debug APK 已保留数据覆盖安装到 PKX110 真机。

## 已实施

| 区域 | 修改 |
|---|---|
| 顶栏 | 突出会话名、模型和模式；项目和上下文细项移至 Tooltip，相关入口保留。大字体时顶栏与消息列表留白同步增长，修复 Flat 外层固定高度溢出。 |
| 会话指标条 | 普通状态仅保留会话/运行详情摘要，不再常驻轮数、步骤、耗时等多组数字；高预算告警和压缩入口保留。 |
| 输入区 | 减少装饰性内边距；避免键盘 inset 的第二次布局动画；固定主动作 48×48dp 槽位；代码插入收进“更多输入工具”，模式、审批和附件入口保持可用。 |
| 助手消息 | 短纯文本回复去除多余头部、描边和阴影；复制、重试仍可发现。长模型名省略处理，失败操作可换行，保留重试、编辑问题和切换模型。 |
| 指标面板 | 默认展示上下文、输入/输出、耗时、状态四项概要；详细诊断显式展开，原有运行选择器及各页签保留。区分估算、服务商上报、累计记录和未记录。 |
| 进度条 | 总览传入实际输入 tokens、输出预留及窗口上限；零输入 fallback 明确中性底色，避免低占用看成满格。 |

没有更改数据库 schema、Agent 执行顺序或上下文预算语义，没有清理或重置原有工作树，没有提交 Git。

## 主要源码

- `lib/presentation/chat/chat_page.dart`
- `lib/presentation/chat/widgets/capsule_top_bar.dart`
- `lib/presentation/chat/widgets/floating_capsule_input.dart`
- `lib/presentation/chat/widgets/message_bubble.dart`
- `lib/presentation/chat/widgets/session_metrics_bar.dart`
- `lib/presentation/chat/widgets/session_metrics_sheet.dart`
- `lib/presentation/chat/widgets/session_metrics_summary.dart`（新增）
- `lib/presentation/chat/widgets/context_budget_bar.dart`

## 自动化验证

新增 65 项测试：

- `test/chat_visual_hierarchy_test.dart`：38 项，包含 320/360/390dp × 1.0/2.0 字体 × 深浅色 × 三种材质的 36 组布局，以及诊断入口和输入动作稳定性。
- `test/chat_state_matrix_test.dart`：24 项，320/390dp、2 倍字体、深浅色下的空态、流式、停止、失败、待审批、指标页。
- `test/session_metrics_summary_budget_test.dart`：3 项，验证进度条三段比例、中性 fallback、未上报数据不伪装成实测零。

与新产品行为冲突的旧测试已同步更新，继续断言诊断可达性、键盘开合、工具入口和布局，而非删除测试。流式局部重建相关回归保持通过。

最终证据位于 `device-check/20260922-ui-polish/`：

- `reconnect-full-tests.log`：1232 项通过，命令退出码 0。
- `reconnect-analyze-final.log`：No issues found，退出码 0。
- `reconnect-targeted-final.log`：进度条与更新服务 17 项通过。
- `reconnect-diff-check.log`：git diff --check 退出码 0。
- `reconnect-build.log`：arm64 Debug APK 构建成功，退出码 0。

历史中间结果如实保留：首次新增矩阵发现并修复了 Flat 大字体溢出；旧 UI 契约测试更新后，一次全量为 1228 通过、1 项更新服务临时目录清理失败。最终专项与全量均已复跑通过，未改动更新服务业务代码。新增进度条测试曾缺少 TimingSnapshot import，已修正并重新验证。

## 真机交付

- 设备：PKX110；应用包：`com.nexusagent.app.debug`。
- APK：`build/app/outputs/flutter-apk/app-debug.apk`。
- SHA-256：`1c4dfefab0178fcc224778ab31de19215b5b590b5f1d374e4ee09225e96cede8`。
- 使用 `adb install -r` 保留数据覆盖安装，返回 Success。
- 已在既有测试会话检查短回复、会话摘要、指标总览、详细诊断和键盘开合；未发送模型请求、未触发工具执行、未清除应用数据、未更改系统字号/主题。检查结束已收起键盘。
- 最终指标截图：`device-check/20260922-ui-polish/reconnect-metrics-final.png`，约 1% 与低占用可视化一致。
- 聊天改后截图：`device-check/20260922-ui-polish/device-chat.png`。
- 其余操作证据保留在同目录；部分设备截图有无关通知横幅，不作为公开展示图使用。

## 验收边界

- 36 张 widget 渲染图是布局检查证据，测试字体不等于真机中文字体；并非经过人工批准的像素级 golden 基线。
- 多尺寸、多字体、深浅色和材质组合已通过自动化测试，不等于在每种配置下完成真机人工验收。
- 本轮真机为 Debug 冒烟，不提供 Profile FPS、功耗、对比度测量或完整端到端读屏认证结论。
- 构建提示现有 Gradle/AGP/Kotlin 版本未来支持变更，本轮未越界升级工具链。
