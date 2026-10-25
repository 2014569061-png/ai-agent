# Windows 运行异常修复与 SDK 隔离记录（2026-10-16）

## 当前结论

**两处应用缺陷已修复；Windows 无障碍兼容问题独立存在，整体验收仍阻塞。**

不是“全部页面通过”，也不是“所有运行异常已消失”。既有现场仍为 13 个不同视图已查看、32 个入口未进入。本轮没有借修复之机扩大业务写入范围。

## 已实施的最小应用修复

1. **启动 Zone 不一致** — `lib/main.dart`：将 binding 初始化和 SystemChrome 调用移入既有 `runZonedGuarded`，与 `runApp` 保持同一 Zone；未移除错误处理或压制异常。
2. **编辑器加载态嵌套列表高度无约束** — `lib/presentation/widgets/nexus_loading_skeleton.dart`：`NexusListSkeleton` 使用 `LayoutBuilder`，设置 `primary: false`，仅当高度无界时启用 `shrinkWrap`。有界根加载器仍使用普通 viewport；未给所有场景强制 shrinkWrap，也未改 AgentEditor 的业务流程。

修复前的定向测试确实失败：首个完整异常是 `Vertical viewport was given unbounded height`，指向当时 `nexus_loading_skeleton.dart:199` 的 ListView。它是加载首帧的问题，不能用数据加载完成后的正常截图代替验证。

## 回归与静态验证

新增 `test/desktop_runtime_regression_test.dart` 共 6 项：

- 启动源码顺序保护（只作补充，另有全新原生启动实测）。
- 有界根加载器尺寸及 `shrinkWrap: false`。
- 嵌套加载器在 semantics 明确关闭/开启两种状态下均正确布局；最终测试设置 `semanticsEnabled` 并断言 binding 的实际状态。
- AgentEditor 在 1280×800 与 390×844 下，以未完成的数据库 Future 保持真实 pending 首帧，随后加载完成；开启 semantics，使用内存数据库，断言未保存任何 Agent。

| 检查 | 实际结果 |
|---|---|
| 修复前定向复现 | 退出码 1，首个完整布局堆栈已保存 |
| 新 6 项 + 既有 startup_gate | 7 项通过，退出码 0 |
| 最终选定回归（79 个文件，含上述检查） | **413 项通过**，退出码 0；不是宣称所有测试文件全量通过 |
| `flutter analyze --no-pub` | No issues found，退出码 0 |
| `git diff --check` | 退出码 0；存在既有 LF/CRLF 提醒，不是 diff-check 失败 |

测试中的额外 SemanticsHandle 最终均在测试回调内用 try/finally 释放，未通过取消 semantics 覆盖或降低功能断言换取通过。首轮红测试用于证明布局缺陷；其名称中的 semantics=false 当时仅表示不额外申请 handle，不当作关闭 semantics 的红证据。最终两态检查已显式配置并通过。

## 修复后的真实 Windows 应用复验

使用当前源码重新构建并运行 Debug 应用，不是 WidgetTester 截图或旧产物。

- 首次修复后运行 PID 23792：启动未再出现 Zone mismatch；不主动调用 UIA/MSAA，进入 Agent 列表和新建编辑页后，未见原布局错误，但仍记录到 9 条原生 AXTree 错误。
- 在该会话中随后主动请求 UIA 和 MSAA：UIA 仍仅见 FLUTTERVIEW；MSAA `AccessibleObjectFromWindow` 返回 HResult=0、HasObject=true。请求本身未新增运行日志。**接口调用成功不代表无障碍树有效。**
- 最后恢复 `lib/main.dart` 正常入口，再全新构建运行，PID 42136：普通启动和进入 Agent 列表的日志增量均无错误；进入新建编辑页后出现 5 条原生 AXTree 错误，未出现 Zone、viewport、RenderBox 或 sliver 布局异常。
- 上述不主动请求辅助功能的对照路径不等于关闭操作系统或框架 semantics；没有修改系统辅助功能设置。

两次修复后应用运行的错误条目数不同，不把重复条目当作多个独立缺陷。

## 独立 Flutter 入口定位残留 AXTree 问题

新增仅供诊断的 `tool/diagnostics/windows_slider_ax_repro.dart`：无业务导入、数据库、存储、服务、应用主题、ListView 或 Tooltip；在同一项目 Windows runner 和当前 SDK 内，只使用标准 Material 控件。它显式持有进程生命周期的 semantics handle，不关闭语义支持。

环境：Flutter **3.47.2 stable**，Dart **3.13.2**；framework `d3b14c876900e553bc736ca19295fc09e3853e8e`，engine `a804b261645ef8c13eb3d5c44a5c2fb0340c5539`。

实际原生运行 PID 43952 的对照：

| 状态 | 日志增量 |
|---|---|
| 首页包含标准 Slider，semantics 开启 | 无 AXTree 错误 |
| 点击 Push slider route，推入含同类 Slider 的新路由 | 2 条 `Failed to update ui::AXTree`，节点 10、9 `will not be in the tree and is not the new root` |

这证明同类错误无需业务页面、加载骨架或数据库即可产生，与已公开的 Flutter Windows Slider/pushed-route 语义问题一致。[4](https://github.com/flutter/flutter/issues/190357)

上游记录说明此类错误可能冻结屏幕阅读器所见的树；本轮未执行屏幕阅读器端到端验收，不能据“画面正常”认定无障碍无影响。也没有穷尽主工程内全部潜在语义触发器。

单独复现命令（关闭正常 Debug 应用后运行；完成后需恢复主入口）：

```bash
/c/src/flutter/bin/flutter run -d windows --debug --no-pub -t tool/diagnostics/windows_slider_ax_repro.dart
```

本轮未升级或修改全局 Flutter SDK，没有将可操作 Slider 替换为进度条，没有禁用 semantics，没有改 C++ AX bridge 或过滤错误日志。SDK/框架兼容处理需另行决定，不能冒充应用层修复已覆盖。

## 证据路径

`artifacts/desktop-live/` 下：

- `runtime-repair-red-first-error.log`：修复前首个完整异常及调用链（不是完整 366,638 字节原输出）。
- `runtime-repair-targeted.log`、`runtime-repair-regression.log`、`runtime-repair-analyze.log`：成功回归和静态检查输出。
- `runtime-repair-native.log`、`runtime-repair-slider-isolate.log`、`runtime-repair-restored-main.log`：三次原生会话输出，包含正常退出。
- `runtime-repair-accessibility.json`、`runtime-repair-validation.json`：辅助功能请求结果、命令标识、字节偏移及验收边界。
- `fixed-startup.png`、`fixed-agent-editor.png`、`ax-isolate-home.png`、`ax-isolate-pushed.png`、`restored-main.png`、`restored-agent-editor.png`：对应真实窗口截图与探针元数据；不是新增业务页面数量。

## 数据、产物与退出状态

未发送模型消息、执行应用任务、测试连接、导入、保存表单或变更权限/配置。新回归测试使用隔离的内存数据库；真实应用正常启动可能更新自身运行元数据，不声称数据库字节完全不变。既有工作区改动保留，未提交或重置 Git。

三次自启原生会话均通过各自 `flutter run` 的 q 正常退出，退出码 0。最后产物已重新构建为 **lib/main.dart 正常入口**，不是最小复现程序；最终进程检查 `Count=0`。未关闭其他应用。

## 仍待决定

- 独立处理 Flutter Windows 无障碍兼容：隔离 SDK 对照或可验证且不损失操作/语义能力的兼容方案；不要直接改全局 SDK。
- 或明确记录该阻塞后，先继续其余页面的非写入型 UI 验收，但不能宣布整体验收通过。
