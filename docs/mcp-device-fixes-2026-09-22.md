# 真机问题修复与验证

日期：2026-09-22

**结论：修复已应用并保留数据安装到真机 Debug 应用。D1 未读提示和 D2 冷/热深链接在下述范围内复测通过；新增回复元信息的保存/恢复已通过主机回归，本轮未在真机追加付费回复。**

## 实现范围

### D1：新消息提示与滚动状态

将滚动跟随及未读计数集中到 `lib/presentation/chat/chat_scroll_coordinator.dart`，由聊天页调用：

- 列表尚未挂载或尚无布局尺寸，不再被判断为用户已离开底部。
- 会话切换、历史恢复、空会话重置状态，计数不跨会话累积。
- 通过稳定消息 ID 区分尾部追加与历史前插，分页不计作新消息。
- 手动滚到底部、内容缩短或视口变化时同步清零，而非只隐藏按钮。
- 延后滚动回调校验会话代次与用户拖拽修订，避免旧回调抢夺新会话或用户的滚动位置。
- 仅重建提示按钮，不把高频流式更新升级为聊天页全量重建。

### D2：冷启动、热链接与空会话入口

- `DeepLinkService` 改为通知订阅者，不再仅保存无人消费的标记。
- 聊天页等待初始化或会话恢复结束，在帧后处理待消费链接；销毁时移除监听。
- 用空字符串表示明确的“新建空会话”，和 null（无待处理请求）区分。
- 新会话预填只写草稿，不自动发送。
- `main.dart` 提前订阅 app_links 的 URI stream，不再同时读取 initial URI 而重复消费。已核对 app_links 7.2.1 的 Android 原生实现：stream 会发送初始链接。
- Android Manifest 明确关闭 Flutter 默认深链接路由，交由 app_links 单一入口处理，避免 Navigator 竞争处理 `nexus://`。
- 跨异步等待的草稿回填检查当前会话 ID，避免把迟到的草稿写入另一个会话。

### O1：历史回复显示信息

- 新增 `MessageDisplayMetadata`，序列化模型名、usage、elapsed、ttft 与 reasoningDuration 等已有显示字段，不包含服务凭据。
- Messages 增加可空的 `display_metadata_json`，Drift schema 24 → 25，增列前检查表与字段是否存在。
- 正常保存、历史恢复和分叉复制接入此字段；Drift 生成的行 JSON 包含新字段，本轮未执行设备备份恢复。
- 格式错误、未知版本和缺失元数据不会阻止旧消息正文显示。

**不能补造旧数据：** 老版本没有写入的模型名/耗时仍为空；本次只保证以后保存的已有测量信息可恢复。运行步数 `totalSteps` 原本就是未持久化的运行态，不用消息条数伪造历史步数。

## 主机验证

| 检查 | 结果 |
|---|---|
| Drift 代码生成 | 成功，退出码 0；已更新 `app_database.g.dart` |
| Flutter analyze | 最后一次无问题，退出码 0 |
| 全量 Flutter 测试 | 1091 项通过，0 失败 |
| 后补 Android 深链接入口配置测试 | 1 项通过，退出码 0 |
| 本轮新增回归用例 | 共 22 项 |
| 格式检查 | 18 个手写 Dart 文件，0 个需要修改 |
| scoped git diff --check | 退出码 0，无输出 |
| Python 设备探针语法 | 通过 |

新增用例覆盖未读提示、首次布局、分页/会话隔离、延后滚动、冷/热链接、销毁生命周期、元数据兼容/迁移/分叉，以及通过本地演示 Provider 验证真实 ChatController 的保存、切换和重建。主机测试使用模拟服务或隔离数据库，不调用用户配置的付费模型。

回归过程中的问题没有隐藏：首轮相关测试一个原有用例在等待初始化时超时，单独重跑通过后，将固定事件轮数等待改成监听 loading 状态完成；首次全量测试又发现一个旧 schemaVersion 断言及缺少 messages 表的迁移夹具不兼容，分别更新断言并补齐增列前的表存在检查，然后重新跑完全量测试。

主要日志：

- `artifacts/logs/2026-09-22/.mcp-device-fix-codegen.log`
- `artifacts/logs/2026-09-22/.mcp-device-fix-analyze-verified.log`
- `artifacts/logs/2026-09-22/.mcp-device-fix-all-tests-final.log`
- `artifacts/logs/2026-09-22/.mcp-device-fix-manifest-test.log`
- `artifacts/baselines/2026-09-22/.mcp-device-fix-quality.json`（含源码摘要、格式及 diff 检查结果）

## 构建与真机复测

### 构建与安装

- `flutter build apk --debug --no-pub` 成功，退出码 0。
- APK：`build/app/outputs/flutter-apk/app-debug.apk`。
- 用户确认解锁后，先确认应用没有运行中的生成，再执行 `adb install -r`，返回 Success；没有卸载或清数据。
- 测试包 `com.nexusagent.app.debug`；设备 PKX110 / Android 16 / API 36，Release 包未操作。
- 设备 base.apk 的摘要与主机 APK 相同：

  `3fc69a21d95afe05bf3969fae0319031b2c91fc7b5eae4241b1f697d7036176f`

构建有 Gradle 8.14.3、AGP 8.13.0 和 Kotlin 2.2.20 将来停止支持的提示，不是本轮构建失败；未扩大范围升级构建工具链。

### 真机证据

证据目录：`device-check/20260922-fix/`。每个界面检查保存 `.txt` / `.xml` / `.png`。

| 检查 | 实际结果 | 证据 |
|---|---|---|
| 更新后恢复 | B 会话升级前已有的 4 条正文全部保留，无错误新消息提示 | `00-before-install` → `01-upgraded` |
| 切回原 A | 原提示和 OK-A / Ready. 保留，无错误提示 | `03-original-a` |
| 新建测试分支 | 复制两条消息，无额外模型请求，未出现原先的“2 条新消息”提示 | `04-message-menu`、`05-fork` |
| 热链接带 prompt | 准确预填 MCP-FIX-WARM 草稿，没有自动发送 | `06-warm-draft` |
| 热链接无 prompt | 显示空会话，输入为空，发送禁用，无错误提示 | `07-empty-link` |
| 冷启动带 prompt | 从已停止的 Debug 进程启动后准确预填 MCP-FIX-COLD 草稿，没有自动发送 | `08-cold-draft` |
| 冷启动无 prompt | 显示空会话，输入为空，发送禁用，无错误提示 | `09-cold-empty` |
| 最后切回 B | 原有 4 条正文仍在，无错误提示；输入为空，未生成回复 | `10-sessions`、`11-final-b` |

已查看分支及冷启动预填的截图。真机中新消息计数的验证覆盖历史恢复、分叉、空入口及会话切换；新模型回复追加、历史前插和拖拽跟随由主机回归覆盖，不冒称本轮已在真机重新跑付费流式回复。

### 日志与结束状态

- `warm-errors.txt`、`cold-errors.txt`、`final-errors.txt`、`after_return-errors.txt` 均为空；它们只过滤对应 Debug 进程的 `flutter:E`、`AndroidRuntime:E`、`libc:F`，不是完整日志审计。
- `exit-info.txt` 本轮退出为包更新和两次测试用 FORCE STOP，没有本轮异常崩溃退出记录。
- 冷启动带提示词/空入口的 Android TotalTime 分别为 1518ms / 1522ms；只记录启动结果，不当作首帧或 Release 性能基准。
- 最后已回到安装前的 B 会话，没有运行中请求；保留独立测试分支和草稿供复核，没有删除其他会话。
- 安装前 B 中已存在后来追加的一轮正文，本轮只是保留和查看。助手本轮没有发送新的真实模型请求。

主要日志还包括 `artifacts/logs/2026-09-22/.mcp-device-fix-build.log`、`artifacts/logs/2026-09-22/.mcp-device-fix-install.log`、`artifacts/baselines/2026-09-22/.mcp-device-fix-apk-sha256.txt` 与设备目录的 `installed-sha256.txt`。

## 范围与保护

- 不清数据、不卸载；若签名冲突则停止安装。只更新独立 Debug 包，不操作 Release 包。
- 本轮不追加付费模型请求；此前获准的 3 次请求已用完。
- 不通过被测 Agent 执行工具、文件写入或终端命令。
- 不提取 API Key，不编辑用户原有会话；设备复测使用先前建立的 MCP 测试会话及新草稿。
- 保留现有脏工作区，无 reset、clean、commit 或 push。
- 不把 Debug 结果当作 Release 性能验收；长历史压力、实际流式中途取消和执行中故障恢复仍不在本轮已验证范围内。

## 仍需注意

- 旧回复的模型和耗时数据过去没有保存，升级后仍可能显示 NEXUS AI / 0ms；不会根据当前模型配置或截图给旧记录伪造元信息。
- 历史运行步数恢复、长历史真机压力、实际流式中途取消、活跃任务故障恢复、Release 性能都没有在本轮宣告通过。
- 非审批弹层的“关闭审批弹窗”无障碍标签属于之前记录的附加观察，本轮未修改。
- 主机全量日志中的 1091 项与随后单独执行的 1 项 Android 入口配置测试分别记录，不把它们描述成同一次全量运行。
