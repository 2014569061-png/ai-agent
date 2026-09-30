# ADR 0003：能力 seam（WorkspaceFs / ProcessRunner / ModelRoute）

- 状态：已采纳（阶段 5）
- 相关：ADR 0001（会话日志）、ADR 0002（ModuleHost 与 RunProfile）

## 背景

Harness 把「能力」拆成定义（接口）/ 提供方（实现）/ 使用方三层，使用方只依赖定义，
提供方可以替换（本地、远端、测试替身）。我们的目标是：以后接入局域网桌面端时，
文件、进程和模型调用可以按能力逐项切到远端，而不用改工具和执行器。

本阶段只建立 seam 并迁移现有使用方，**不实现任何远端提供方**。

## 决策

### WorkspaceFs（`lib/infrastructure/files/workspace_fs.dart`）

- 操作只包含文件工具实际用到的：`kindOf`、`readText`（有上限，语义同
  `BoundedTextReader`）、`writeText`（自动建父目录）、`list`（不跟随链接）、
  `ensureDirectory`、`deleteFile`、`deleteEmptyDirectory`、`rename`。
- `WorkspaceSandbox` 携带 `fs`，默认 `LocalWorkspaceFs`。read/write/edit/list/search/
  delete/move 七个工具只经由 `sandbox.fs` 访问文件；创建这些工具的调用点不用改。
- 路径策略（越界、符号链接逃逸、禁止操作根目录）仍由 `WorkspaceSandbox` 在本地完成，
  之后才调用能力。**远端实现必须在自己一侧再次把路径限制在工作区内**，不能只信任
  手机端的校验。
- 暂未迁移：变更集回退、文件基线、项目上下文等服务仍直接用 `dart:io`。它们处理的是
  手机本地工作区的记账数据，等远端工作区真正出现时再按需迁移。

### ProcessRunner = 现有的 `LinuxRuntimeAdapter`

- `LinuxRuntimeAdapter`（以及可脱离进程的 `DetachedLinuxRuntimeAdapter`）已经是
  进程执行的 seam，约定也已写明：超时返回 124，不可用时返回非 0，不向 Agent 主流程
  抛出未处理异常，工作目录由调用方限制在工作区内。
- 决定**不改名**、不再包一层：改名只带来改动面，不带来能力。文档与计划中的
  「ProcessRunner」即指这个接口。
- 远端运行时按同一接口实现（新增一个 `LinuxRuntimeKind` 取值），`notExecuted`
  与 `timedOut` 的区分必须保留：前者保证没有副作用，后者不能保证。

### ModelRoute（`lib/infrastructure/providers/model_route.dart`）

- `ModelRoute.providerFor(config)` 返回 Provider，或返回 null 交给下一条路由；
  `ModelRouter` 按顺序尝试，全部失败时退回 `DemoProvider`（`resolve`），或者返回
  null 由调用方降级（`tryResolve`）。
- 默认 `ModelRouter.standard = [DirectModelRoute]`，行为与原先各调用点的
  `config.isConfigured ? createLlmProvider(config) : DemoProvider()` 完全一致。
- 使用方：
  - 聊天读 `modelRouterProvider`（Riverpod），远端路由以后在这里接入；
  - `HeadlessExecutor.run/runDetailed` 接受可选的 `modelRouter`；
  - Agent 草稿生成用 `tryResolve`。

## 远端提供方的预留约束（以后实现时必须满足）

1. 配对与传输：端到端加密；只暴露白名单 RPC，每个方法对应一个能力操作。
2. 路径、命令与模型请求在远端再次校验，不能只信任手机端。
3. 失败语义与本地实现一致：文件写入中断要报告为「可能已改动」，进程区分
   「未执行」与「超时」。这样工具层的 `ToolEffect` 判断不用变。
4. 模型可见 = 已记录（ADR 0001）：远端路由的请求同样经过执行器的请求观察者，
   会话日志不用区分本地与远端。

## 后果

- 测试可以用内存 `WorkspaceFs` 和脚本化 `ModelRoute` 覆盖工具与无 UI 运行，
  不碰磁盘和网络（`test/workspace_fs_test.dart`、`test/model_route_test.dart`）。
- 七个文件工具不再直接依赖 `dart:io`，唯一例外是沙盒的符号链接检查。
