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

## 阶段 6b：补齐声明

- 内置工具全部声明，只有 `sub_agent` 例外：它的影响取决于子代理拿到的工具，
  保持 `undeclared`。
  - pure：`get_time`、`json_query`、`memory_get`、`manage_plan`、`skills_read`、
    `skills_read_resource`、`android_device_preview`、`android_app_private_data_preview`；
  - network：`web_search`（只读）、`http_request`、`generate_image`；
  - device：`android_device`、`android_automation`、`android_app_private_data`（只读）；
  - 应用内状态：`remember`、`memory_write`（`readOnly: false`，无 scope）。
- MCP：`McpTool.traitsFor(annotations)`，`readOnly` 取 `readOnlyHint`（缺省 false），
  scope 为 network。注解是服务器自报的提示，**只用于描述性判断，不影响审批**。
  MCP 工具作用在远端，所以 `mcp_*.*_file` 不再按本机文件操作记录（此前按名称规则会
  误记为 `file_operation`），也不保存文件基线。
- 插件声明式工具：`DeclarativeTool.traitsFor(request)`，GET/HEAD 只读，其余有副作用，
  scope 为 network。
