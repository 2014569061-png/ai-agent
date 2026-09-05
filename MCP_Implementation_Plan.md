# MCP 协议生态接入及联网搜索架构实现方案

## 1. 背景与目标
目前 NEXUS Agent 底层基础设施 (`lib/infrastructure/mcp/`) 已经包含了 `mcp_server_config.dart` 和 `mcp_tool_provider.dart`，并引入了 `mcp_dart` 核心库。
但目前缺乏**数据持久化**、**用户配置 UI 面板**以及**引擎动态桥接**。
本方案旨在彻底打通 MCP 协议，让 Agent 能够动态加载外部工具（例如基于 MCP 的高阶无头浏览器联网搜索等）。

## 2. 核心任务拆解

### 任务一：数据库层 (Drift) 扩展
需要在 `lib/infrastructure/database/app_database.dart` 中新增 MCP 服务器的实体表。
1. **定义 Table**: `McpServers`
   - `id` (Text, unique)
   - `name` (Text)
   - `kind` (Text - 区分 'http' 或 'stdio')
   - `url` (Text, nullable - 适用于 http sse)
   - `command` (Text, nullable - 适用于 stdio)
   - `args` (Text, nullable - JSON array 存储 stdio 参数)
   - `enabled` (Bool, default true)
2. **重新生成代码**: 运行 `flutter pub run build_runner build --delete-conflicting-outputs` 更新 `.g.dart`。

### 任务二：状态管理与控制器
创建 `lib/application/mcp_service.dart` 或 `mcp_controller.dart` (Riverpod Notifier)。
- 负责从数据库 CRUD `McpServerConfig` 记录。
- 提供 `toggleServer(String id, bool enabled)` 方法供 UI 实时启停服务器。

### 任务三：UI 面板开发
1. **入口配置**：在 `lib/presentation/settings/settings_page.dart` 中添加一个新的列表项，点击跳转至 MCP 管理页面。
2. **MCP 列表页 (`lib/presentation/mcp/mcp_servers_page.dart`)**：
   - 展现已添加的服务器列表（带有开启/关闭 Switch）。
   - 提供一个 FAB (悬浮按钮) 用于“新增 MCP 服务器”。
3. **新增/编辑表单 (`lib/presentation/mcp/widgets/mcp_edit_dialog.dart`)**：
   - 使用 `SegmentedButton` 让用户选择连接方式 (HTTP SSE vs 本地 STDIO 进程)。
   - HTTP 模式下：输入 Server Name 和 SSE URL。
   - STDIO 模式下：输入 Server Name、可执行程序路径 (Command) 和 启动参数 (Args，逗号分隔)。

### 任务四：执行引擎动态桥接 (`chat_controller.dart`)
在 `_runAgent` 函数启动大模型对话流之前，动态将 MCP 工具混入现有的 `ToolRegistry` 中：
1. **拉取配置**：从数据库读取所有 `enabled == true` 的 MCP 服务器配置。
2. **建立连接**：实例化 `McpToolProvider`，并遍历调用内部的连接逻辑，桥接至各 MCP Server。
3. **注册工具**：调用 `await mcpProvider.getTools()`，将返回的所有外部工具全部注册至 `registry`。
4. **生命周期清理**：在 `AgentExecutor` 运行结束（不论成功或失败）后，必须调用 `mcpProvider.dispose()` 断开所有长连接与子进程。

## 3. 为什么这种架构能解决“联网搜索”？
一旦完成上述对接，我们只需在本地跑一个 Fetch MCP Server，或者使用 Brave Search 提供的官方 MCP URL，并在新开发的 UI 中将其添加进去。大模型在获取 `systemPrompt` 后，会自动发现注册表里多出了类似 `brave_web_search` 或 `puppeteer_browse` 的高级工具，从而实现零代码的强大联网搜索能力。
