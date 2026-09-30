# ADR 0004：ToolSpec v2——工具声明行为特征

- 状态：已采纳（阶段 6a）
- 相关：ADR 0003（能力 seam）

## 背景

「这个工具会不会改工作区文件、改哪些路径」「审计时算不算文件操作」这类判断原先散落在
多处工具名单里（`FileBaselineInterceptor.mutatingTools`，聊天与无 UI 路径各一份
`*_file || list_directory || search_files`）。新增或改名一个工具时，要记得同步所有名单；
漏掉一处不会报错，只会让基线保存或审计形态悄悄出错。

## 决策

- 新增 `ToolTraits`（`lib/domain/tool_traits.dart`），挂在 `UnifiedTool.traits` 上，
  `ToolSpec` 通过 `fromManifest` / `toManifest` / `copyWith` 原样携带，目录拷贝与能力
  投影都保留它。字段：
  - `readOnly`：不产生外部副作用；
  - `scopes`：影响范围 `workspace` / `process` / `device` / `network`；
  - `pathArguments`：取值为工作区相对路径的参数名；
  - `fileOperation`：审计中按文件操作记录；
  - `declared`：是否由工具自己声明。
- 预设：`workspaceRead`、`workspaceWrite`、`pure`；`writesWorkspace` 为
  「已声明、非只读、作用于工作区、且路径可由参数确定」。
- 已声明的工具：七个工作区文件工具、`terminal`（process + workspace，路径无法从参数
  确定，所以不保存基线）、`calculator`（pure）。
- 使用方改为**特征优先，名称规则兜底**：
  - `FileBaselineInterceptor`：已声明时只看 `writesWorkspace` / `pathArguments`；
    未声明或未注册时沿用 `mutatingTools`；
  - `isFileOperation(spec, name)`（`tool_registry.dart`）：聊天与 `RunEventInterceptor`
    共用。未声明时沿用旧的名称规则，MCP 等外部工具的记录形态不变。
- 测试断言旧名单与内置工具的声明一致（`test/tool_traits_test.dart`），两边不会悄悄分叉。

## 不做的事

- 不从特征推导审批：`risk` / `sensitive` 仍是审批的唯一依据。
- 不从特征推导持久化脱敏：`SensitiveToolPolicy` 口径不同，保持独立。
- 允许清单与任务模板里的工具名是策略数据（用户可见的配置），不改。
- 并发安全等调度相关特征先不加，等执行器真的支持并行工具调用时再加。

## 后续

- 其余内置工具（设备、技能、子代理、图片生成、计划）逐步补声明；
  未补之前按 `undeclared` 保守处理。
- MCP / 插件工具可以在各自的清单里声明特征，届时由提供方映射到 `ToolTraits`。
