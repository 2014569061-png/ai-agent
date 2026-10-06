# NEXUS Agent 功能、缺陷与性能审查

> 2026-09-22 对当前工作区源码的静态审查。未重跑全量 `flutter analyze` / `flutter test`。相关修复跑过对应测试，见第 6 节。
> 相关文档：`README.md`、`docs/mcp-code-review.md`、`docs/mcp-project-completeness.md`。
> 旧审查里的若干 P1 已在当前代码中修好，不能再当现状。

## 1. 结论

功能面已经比较完整，不是半成品。多模型对话、Agent 工具循环、审批、MCP、记忆、知识库、定时任务、终端、技能、协作分析和隐私保险箱都有实现和测试。不能说无 bug。

Android Shell 的 stderr、detached PATH、租约心跳、编辑重发、SSH 首次指纹和 `http_request` 重绑定已在 2026-09-22 按当前源码修好，并跑过相关测试。聊天热路径的性能设计仍然是对的。历史气泡已不再跟着 `liveReply` 重建，超时和停止也会清理进程组。剩余成本主要在超长回复的段落扫描，以及少数动作仍会全量读消息。

## 2. 功能完善度

已经具备，并且和 README 对得上：

- OpenAI 兼容、Anthropic、Gemini 和托管代理；流式对话、步数预算、失败重试、计划确认。
- 工作区文件工具、MCP、长期记忆、知识库、定时任务、协作子 Agent。
- 审批分级。危险级任何模式都要确认；完全访问只自动放行确认级工具。
- 会话分页、运行恢复、上下文压缩、锁屏通知审批、TTS、加密保险箱。
- 内置技能覆盖手机开发体检和小型 Java APK 构建。

有意未做，不应算成空功能：

- 桌面小组件只做深链入口，不显示任务进度。
- 手机 Linux 环境不能产出 Windows `.exe`。
- Web 导入本地目录、隐私保险箱明确不支持。
- 界面以中文硬编码为主，`AppStrings` 没有覆盖全部页面。

仍不完整：

- `chat_page.dart`、`chat_controller.dart` 和 `app_database.dart` 仍然是两三千行的大文件。拆分目标已经回退。

## 3. 当前缺陷

优先级 | 位置 | 问题 | 影响 | 建议
--- | --- | --- | --- | ---
P1 | `lib/infrastructure/terminal/android_shell_runtime_adapter.dart` | 已修：前台同时收集 stderr；detached 使用同一份消毒环境并附加 owner token。 | 编译器报错不再被丢掉，后台命令能找到 `sh` 里的程序。 | 已补前台 stderr 测试，并改掉锁死错误环境的期望。
P2 | `lib/infrastructure/terminal/android_shell_runtime_adapter.dart` | 已修：有 `/system/bin/setsid` 时用它启动，使 shell 成为进程组组长。超时和停止先发 SIGTERM，200ms 后仍存活再 SIGKILL。没有 setsid 时按 `/proc` 子进程树发信号。非 Android 不读 `/proc`，也不调用 `kill(-pid)`。 | 管道和孙进程不再只杀掉 shell 本身。 | 已补组长、子进程树、setsid 和 stop 测试。真机杀进程恢复仍未测。批准文案继续写明 cwd 不是沙箱。
P2 | `background_execution_gateway.dart`；`execution_lease_service.dart` | 已修：心跳失败不再只被吃掉。租约丢失立即取消；连续 3 次数据库失败也取消当前 run。 | 数据库抖动后，本任务会在租约过期前停写。 | 已用短间隔测试覆盖丢失和连续失败。
P2 | `chat_controller.dart`；`app_database.dart` | 已修：编辑重发写库失败会中止并提示。锚点按 `created_at, rowid` 取第 n 条用户消息，截断也按这个顺序。 | 重开会话不会在保存失败后跑出新回复。同一秒的消息不再截错。 | 已补保存失败和同秒截断测试。
P2 | `terminal_page.dart` | 已修：三处会话创建都传入 `confirmUnknownHostKey`。首次连接弹出指纹确认，拒绝或关闭对话框都不保存。 | 第一次中间人密钥不再被默认记成可信。 | 密钥变更拒绝逻辑未改。
P2 | `core_tools.dart`；`network_access_policy.dart`；`pinned_host_connector.dart` | 已修：连接前把已检查地址钉进 `PinnedHostConnector`，请求仍用原主机名。响应先按文本读，JSON 失败则返回截断正文。 | DNS 重绑定不能再把第二次解析指到内网。普通网页不再被当成网络失败。 | 已补钉地址和 HTML 响应测试。
P3 | `lib/infrastructure/terminal/adaptive_linux_runtime_adapter.dart:28-32` | 尚未选中运行时时，`supportsShellSyntax` 和 `supportsInterpreterEvaluation` 默认 true。 | 当前 Android 候选都支持完整 shell，所以现在不会误放行到受限进程。以后插入受限运行时，选中前的门禁会偏乐观。 | 默认改为 false。
P3 | `lib/application/approval_policy.dart:36-37`；`command_tool.dart:1203` | 终端是确认级。完全访问会自动批准 `sh -c`。 | 这是 README 已写明的产品行为，不是意外分支。提示注入在完全访问下可以驱动手机 shell。 | 保持危险命令永远确认。完全访问的说明继续放在批准前，而不是只写在 README。

已核对、当前不再成立的旧问题：

- 重新生成已按 id 删除最后一条用户消息之后的 assistant/tool，并用 `created_at, rowid` 排序。见 `app_database.dart:1094-1119` 和 `chat_controller.dart:1486-1495`。
- 应用锁读取失败现在返回 true，失败即锁定。见 `app_lock_service.dart:22-24`。
- 前台 Android Shell 已 `includeParentEnvironment: false`，并设置固定 PATH。
- SSH 已接 `onVerifyHostKey`。`dartssh2` 的 fingerprint 本身就是 UTF-8 的 `SHA256:` 文本，这里的 `utf8.decode` 与库约定一致。
- HTTP 出口已走 `inspectResolved`，重定向逐跳校验，不再只拦字面 IP。
- 2026-09-22 又把 `inspectResolved` 改成返回已检查地址，`http_request` 连接钉死该地址。

未发现 `TODO`、`FIXME`、`UnimplementedError`。

## 4. 性能

做得好的部分：

- 流式文本走单独的 `liveReplyProvider`，70ms 且至少 24 个字符才刷新。输入区和顶栏不订阅它。见 `chat_page.dart:2550-2552`、`chat_run_execution.dart:166-167`。
- 正在生成的最后一条助手消息走 `_StreamingMarkdown`：已完成段落才解析 Markdown，未闭合代码块保持纯文本。见 `message_bubble.dart:96-97`。
- 列表只构建窗口内消息，初始 40 条，每次再展开 20 条；数据库按 200/100 做键集分页。会话切换不加载最多 2000 条运行事件。
- 长回复超过约 3000 到 5000 字会延迟富文本解析。稳定段落用 `RepaintBoundary` 和内容 key。

仍偏贵的部分：

- 已修：`liveReply` 仍会重建消息列表，但历史消息对象、会话/索引、末条/选择/运行状态、相关进度、回调可用性、朗读监听、主题和文字缩放均未变化时复用同一个 `MessageBubble`。消息通过 `copyWith` 替换时保守失效，覆盖附件、工具参数、模型和用量；正在流式输出的那一条不缓存。见 `lib/presentation/chat/widgets/chat_message_list.dart`。
- `MarkdownRenderPolicy.splitForStreaming` 每次从全文重新扫描段落和代码围栏。超长回复会变成按刷新次数累加的扫描。可以缓存上次边界。
- 编辑重发、分叉和保险箱导出仍调用不带 limit 的 `messagesFor`。万级消息会话会在这些动作上卡一下。分页路径已经有，这些调用方应改用键集或只取锚点行。
- 三个核心文件继续变长。这不直接掉帧，但回归和热路径修改会越来越慢。

没有在本次连接真机，不能给出掉帧数字。从代码看，普通会话的流式路径已经避开了整页 `setState`；风险集中在长会话流式和全量读消息的少数动作。

## 5. 建议顺序

1. 已完成：Android Shell stderr 和 detached PATH。
2. 已完成：心跳失败停掉当前后台 run；编辑重发写库失败则中止，锚点按 rowid。
3. 已完成：SSH 首次连接确认指纹；`http_request` 钉死地址并支持非 JSON。
4. 已完成：流式期间历史 Markdown 气泡不跟着 `liveReply` 重建。
5. 已完成：Android Shell 超时和停止清理进程组，停不掉再 SIGKILL。
6. 有设备后再测：杀进程恢复、长列表流式、锁屏审批、压缩标记重启后是否还在。

## 6. 2026-09-22 修复记录

这次按第 5 节当时的前三项改了当前源码，并跑了相关测试。没有重跑全量 `flutter test`，也没有真机。

已通过：

- `test/runtime_adapters_test.dart`
- `test/background_execution_gateway_test.dart`
- `test/http_request_ssrf_test.dart`
- `test/terminal_page_test.dart`
- `test/chat_controller_test.dart` 中编辑重发失败和同秒截断两条

同日第二轮补了进程组清理和流式历史气泡，并跑了相关测试。没有重跑全量 `flutter test`，也没有真机。

已通过：

- `test/runtime_adapters_test.dart` 的 Android Shell 组，包括进程组、子进程树、setsid 和 stop。
- `test/chat_rebuild_scope_test.dart`。20 帧 `liveReply` 后，历史 `MessageBubble` 实例不变，流式气泡会变。

顺手修正：源码仍引用 `package:flutter_markdown`，而 `pubspec.yaml` 已是 `flutter_markdown_plus`。相关 5 个导入已改到当前包，否则气泡测试无法编译。

仍未做：真机杀进程恢复、长列表流式、锁屏审批、压缩标记重启后是否还在。`lib/infrastructure/terminal/adaptive_linux_runtime_adapter.dart` 的能力默认值也未改。

## 7. 2026-09-22 第三轮：清理边界与缓存失效补修

本轮先核实了当前源码。前两轮修复已经存在，旧的 `package:flutter_markdown/` 导入在 `lib/` 和 `test/` 中没有匹配，因此没有再次修改依赖或五处导入。下面的边界修复补充第 3、4、6 节，不表示前两轮的模拟测试能够覆盖全部设备行为。

### Shell

涉及 `lib/infrastructure/terminal/android_shell_runtime_adapter.dart`：

- 原实现升级 SIGKILL 前只检查根进程。现在独立检查原进程组；组长收到 TERM 后退出，不再直接跳过仍存活的进程组。
- TERM 前保存子孙 PID，升级时检查这份快照，避免根进程退出、子进程重新挂接后从树中消失。组内已另建进程组的、可发现的后代也单独清理。
- 没有子进程的 shell 也会经过宽限期并在仍存活时接收 KILL。
- 读取到 `/proc` 启动时间时，延迟清理会核对进程身份，以降低 PID 重用误杀的风险；子树遍历增加去重和非法 PID 防护。
- 启动阶段已算运行中；在 `Process.start` 完成前调用 `stop()` 会记住请求，拿到进程后立即清理。并发前台 `run()` 被拒绝，避免覆盖当前进程句柄。
- 重复停止共用一次清理 Future。前台/后台超时以及前台停止会等待清理宽限期完成；`Process.kill()` 的布尔返回值不再被无条件改成 true。
- 运行后的截止时间同时覆盖 shell 退出和 stdout/stderr EOF；超时/停止会取消输出订阅，避免 shell 已退出但继承的管道不关闭时无限等待。由 setsid 启动且组长已退出的命令仍使用原组号检查和清理。
- `verifyDetached` 也增加平台检查。默认 `/proc` 探测只在 Android 执行；主机回归通过显式注入的进程/信号/存活检查模拟，不给真实进程组发信号。

### 历史气泡

涉及 `lib/presentation/chat/widgets/chat_message_list.dart`：

- 原签名只比较正文及工具调用数量，会漏掉同占位文本的附件变化、工具参数、模型和用量。现在以历史 `ChatMessage` 对象为失效依据，兼顾会话、索引和界面状态；该策略依赖现有 `copyWith` 替换消息的约定，不支持原地修改消息内的可变集合。
- 缓存保留时，动作通过列表 State 转发到当前父组件回调，避免重生成等操作继续调用旧闭包。
- 回调是否存在、朗读监听器、最后一条的进度、主题及文字缩放变化会失效；单纯 `liveReply` 刷新不改变历史气泡实例。
- 流式实例不缓存；新增对真正的历史助手 Markdown 气泡的 20 帧复用断言，不再只验证首条用户气泡。

### 回归范围

新增回归包括：组长退出、子进程重新挂接、独立 shell 忽略 TERM、启动期间 stop、重复 stop、detached 等待升级、非 Android detached 校验，以及附件/工具参数/模型/用量失效、回调转发、选择态/进度/朗读状态更新。

最终验证通过：

- 修改的两个源码文件和两个测试文件经过 `flutter analyze --no-pub`，结果 `No issues found!`。
- 下列 7 个测试文件合并运行，**51 项全部通过**（含前台、后台超时覆盖输出 EOF 和停止取消输出订阅的新增用例）：

```sh
flutter test test/runtime_adapters_test.dart test/chat_rebuild_scope_test.dart test/chat_message_list_window_test.dart test/message_longpress_test.dart test/markdown_render_policy_test.dart test/markdown_render_metrics_test.dart test/chat_page_attachments_test.dart --reporter expanded
```

- 文件已用 Flutter 自带 Dart SDK 格式化；相关文件的 `git diff --check` 通过。
- 日志已归档至 `artifacts/logs/2026-09-22/.mcp-repair-analyze-final.log`、`artifacts/logs/2026-09-22/.mcp-repair-tests-final.log`；未将探测脚本或日志放入 `docs/`。

### 仍未验证及边界

- 未运行全仓库测试，未构建或安装 APK，未做 Android 真机测试。
- 主机模拟不能证明设备 `/proc` 可见性、setsid 实际行为、SELinux/权限限制、进程逃逸或进程组清理一定成功。进程树降级仍是尽力清理，不是安全沙箱。
- 没有 setsid 且根进程在清理前已退出时，无法保证从 `/proc` 找回已经重新挂接且未被快照记录的后代；截止时间可以结束输出等待，但不等于证明这些进程全部退出。
- 真机杀进程恢复、长列表帧耗时、锁屏审批仍待设备验证。
