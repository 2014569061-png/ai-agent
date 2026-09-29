# ADR 0002: ModuleHost 与 RunProfile

- 状态：已采纳（阶段 3）
- 相关：ADR 0001（会话日志）、`docs/nexus-harness-final-plan.md`

## 背景

阶段 2 把 `AgentExecutor.run()` 的扩展点整理成 `AgentLoopHooks`（request transform /
request observer / tool outcome observer / turn-stopping）。但谁来提供这些钩子、
哪些运行需要哪些行为，此前散落在各调用方（聊天直接 new `SessionRecorder`，后台运行
完全没有会话日志）。

## 决定

1. **RunProfile**：运行形态的静态配置，目前只有两个维度——`interactive`（有无真人在场）
   与 `recordSession`（是否写会话日志）。预置 `chat / background / scheduled /
   subagent / collaboration`。新增维度前必须至少有两种形态会用到。
2. **RunScope**：一次运行的标识（`runId`、`model`、`sessionId`、`taskId`、`workspacePath`）。
3. **AgentModule**（仅第一方 Dart 模块，不做第三方插件）：`appliesTo(scope)` 决定是否挂载，
   `attach(scope)` 返回 `ModuleAttachment { hooks, onEvent, onFinish }`。
4. **ModuleHost / ModuleSession**：按注册顺序挂载、合并钩子；事件广播给各模块；收尾按
   **逆序**且每个模块恰好一次（借鉴 Cordis 的可逆副作用）。模块的任何异常只上报，
   不影响运行和其他模块。
5. **SessionLogModule**：会话日志双写的模块化形态。后台运行中只有绑定任务的运行会记录，
   `sessionId = task:<taskId>`，同一任务的多次恢复依次追加到同一条日志；删除任务
   （含随会话级联删除的任务）时一并删除。子 Agent 与协作角色不单独记录，它们的结果
   已作为工具结果或协作记录进入上游。定时任务目前没有 taskId，暂不记录。

## 影响

- `HeadlessExecutor.runDetailed` / `BackgroundExecutionGateway.run` 新增 `profile`
  （默认 `background`）；定时、子 Agent、协作调用方显式传入各自的 profile。
- 聊天路径同样通过 ModuleHost 挂载（`RunProfile.chat`，阶段 3c），
  `session_log_chat_wiring_test` 未改动即通过。
- 远程/桌面连接（阶段 5 以后）预计也以模块形式挂载，不改执行器。
