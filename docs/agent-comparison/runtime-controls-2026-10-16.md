# 第四阶段：运行控制、累计预算、上下文恢复与验收

接续第三阶段，本轮实现此前列出的四项工作。以下保留第四阶段最初的实现与验收记录，当时真实模型调用因鉴权失败阻塞；用户修正本地配置后的真实模型复验已通过，见文末接续记录。

## 1. 验证运行中取消与生命周期租约

- `TerminalCommandService.run/executeSession` 接受继续执行条件。命令获得串行执行槽后才启动 100ms 取消检查；排队中的取消不会停止其他命令。取消后调用运行时停止，等待命令真正退出，再返回退出码 130。
- `DevelopmentVerificationService` 将条件传入正在执行的命令，并阻止后续检查和修复。取消后的结果不能判为通过。
- Windows 本机进程按 PID 停止整棵子进程树，避免 Flutter/Gradle 启动器退出后子进程仍占用输出管道。其他平台沿用对应运行时的停止能力。
- `WorkspaceLeaseGuard` 负责持有、心跳、失效取消和释放租约。心跳串行执行、有超时和失效期限检查；连续失败或失去所有权时取消运行。
- 聊天执行和任务恢复从模型执行前开始持有租约，覆盖编辑、验证、修复及结果落库。修复显式借用外层租约，不重新获取或释放它。
- 同一 taskId 的另一 run 也不能替换活跃租约。恢复入口遇到冲突时不将正在执行的任务错误标为失败。排队入口只判断忙碌状态，实际执行时再取得租约，避免无人维护的占位租约。
- 子任务 HTTP 取消令牌各自独立，父取消向下传递，单项失败不会主动取消父请求及其他子项。

租约约束使用该执行入口的 Agent 运行；外部编辑器或终端仍可改变文件，因此读前写与哈希冲突检查继续生效。

## 2. 累计 token 预算

- `AgentExecutor.totalTokenBudget` 建立一次运行共用的账本。主请求、自动重试、续写和历史摘要都扣同一预算。
- 每次请求先预留输入和输出，再压低服务商请求的 `maxTokens`。预算不足则不发送请求，产生 `tokenBudget` 暂停原因并保留断点。
- 文本输入按序列化内容的 UTF-8 字节数及额外消息开销保守预留。服务商完整成功回报 usage 时，以输入+输出实际值结算；缓存和推理 token 已包含在其中，不重复相加。
- 缺 usage、零用量、错误、中断或只回报部分用量时保留预留额度，避免失败请求变成免费重试。暂不向受硬预算约束的运行发送无法本地估上界的多模态请求。
- 子任务累计上限默认是 `maxTokens` 的四倍；单次上限仍为 500–8000。一批输出上限之和不超过 12000，因此累计分配上限不超过 48000。
- 子任务预算不足返回 `TOKEN_BUDGET_EXHAUSTED`、停止原因、已有摘要和已报告用量；提示主模型汇总已有结果，不得通过自动重派相同任务重置预算。
- 请求观察与会话日志记录的是实际发送的输出上限。

这是客户端的请求准入和结算限制。服务商隐藏提示、特殊 tokenizer、服务端未遵守输出上限等情况无法由通用客户端精确控制；账本如实累计实际回报，不将保守预留宣称为准确账单。

## 3. 压缩后恢复

成功生成历史摘要后，`CompactionRecovery` 自动恢复当前计划、工作区根规则（AGENTS/NEXUS/CLAUDE/.nexus/rules/.cursorrules）以及最近最多五个已请求读取的文件。规则和文件重新从当前沙箱读取，不复用旧工具结果。

恢复总量最多 6000 字符且受上下文窗口比例限制，每个文件最多读取 64KiB；所有片段作为引用数据注入，并给摘要与恢复内容共同预留空间。文件缺失、过大、越界或不可读会保留说明。摘要失败时继续使用诚实裁剪告示，不伪造恢复成功。

恢复会清除旧的读前写许可。自动恢复提供的片段不足以授权编辑，模型须调用 `read_file` 获取当前内容后再修改。

## 4. 第四阶段最初的验收结果

- 新增 `test/run_completion_controls_test.dart`：14 个测试，包含真实长进程取消、排队取消不误杀、同任务租约冲突、修复借用、预算重试、摘要共享账本、缺 usage、子任务停止原因、五文件恢复及完整修复流程。
- 18 个核心回归文件合计 162 个测试通过；8 个终端/运行时文件合计 59 个测试通过，共 **221 个相关测试通过**。
- 21 个涉及的源码、测试与验收文件定向静态分析无问题。
- 确定性端到端验收使用真实 Agent 工具、真实临时文件、临时数据库和真实 Node 进程：注入错误 → 断言失败 → 修复 → 全量重验通过；断言文件哈希不变，租约贯穿收尾。模型响应采用脚本供应器，不能替代真实模型验收。
- 原生 Windows 验收程序成功编译并运行，使用已保存的 `gpt-4o-mini` 配置实际发起模型请求，返回 `authentication`，因此真实模型验收未通过。
- 正常应用 `lib/main.dart` 的 Windows Debug 构建通过，验收入口构建后已恢复正常应用。

入口为 `tool/run-agent-live-acceptance.ps1`，报告写入 `build/agent-live-acceptance.json`。验收读取现有模型配置，所有编辑和记录放在临时项目及临时数据库；报告不输出密钥或原始异常。脚本结束时恢复正常应用构建入口。

修正 NEXUS 桌面端模型配置后可重跑：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/run-agent-live-acceptance.ps1
```

跨语言引用图、跨文件补丁批次与可写 worktree 子任务不包含在本轮四项运行控制与验收工作中。后续补丁预校验、补偿回滚与持久化恢复见[第五阶段及接续收尾](multi-file-patch-2026-10-16.md)；桌面可写 worktree 提案见[第六阶段](isolated-edit-2026-10-16.md)，四语言候选引用图见[索引接续收尾](remaining-mechanisms-2026-10-16.md#接续收尾多语言候选引用图)。这些机制不构成跨文件崩溃原子性保证，也不替代真实模型验收。

## 接续复验：真实模型与正常应用恢复

2026-10-16，用户确认已在本地修正模型配置后，通过 MCP 原生 Bash 执行真实模型验收。未修改或输出用户密钥，没有改用演示模型或脚本模型。

- 当前配置在报告中的模型标识为 `gpt-6-luna`；这是服务配置中的名称，不据此推断底层模型身份。
- 原生验收程序实际完成：读取并修改临时文件 → Node 断言失败 → 真实模型自动修复一次 → 重跑 Node 检查通过。
- 新报告：`build/agent-live-acceptance-resume-1748659a.json`。`status=passed`、`repairs=1`、`verified=true`、`testUnchanged=true`、`leaseHeldThroughFinalization=true`；Node 检查 `exitCode=0`，原生程序退出码为 0。
- 旧 `build/agent-live-acceptance.json` 的鉴权失败记录未覆盖，避免把旧失败静默改写成成功。
- 验收使用临时项目、临时数据库和真实 Node 进程；临时资源已由验收程序清理。可用 API 配置由用户在本地修正，不在对话或实施记录中保存密钥。
- 验收目标构建通过；随后已重新 assemble 并构建 `lib/main.dart`，恢复正常应用，整个 Bash 验收及恢复命令退出码为 0。核对生成配置的 `FLUTTER_TARGET=lib/main.dart`。

本次首次直接构建发现 Windows 临时生成目录缺少 C++ 包装源码；使用 Flutter 的资产 assemble 重新生成后，正常 Windows Debug 构建通过。没有通过删除业务源码、清理未提交改动或手改 Flutter CMake 模板来绕过错误。恢复生成产物与正常入口使用的 Bash 命令为：

```bash
flutter assemble --no-version-check --output=build '-dTargetPlatform=windows-x64' '-dBuildMode=debug' '-dTargetFile=lib/main.dart' '-dTrackWidgetCreation=true' debug_bundle_windows-x64_assets
flutter build windows --debug --no-pub --target lib/main.dart
```

本次接续的 9 个相关测试文件共 103 项通过，10 个源码与测试文件静态分析无问题；Windows 构建仍有 `webview_windows` 的非阻塞 CMake 开发者警告。上述真实模型验收覆盖故障注入、自动修复、重验、测试文件完整性和收尾租约；取消、外部修改、预算及隔离子任务等边界另有自动化回归，不宣称所有边界都逐项通过了真实供应商模型实测。未执行发行打包。
