# 移动端本地工作区与文件编程 Agent 落地实施方案

## 背景与目标
在移动端（Android / iOS / Web），用户希望让 AI 能够直接读取、修改并生成手机本地的文件与项目代码（例如直接在手机上写出完整的 Web 网页项目、修改 Python/Dart 脚本、整理本地知识库等）。

本方案旨在为 NEXUS Agent 构建一套完整的**「本地工作区沙盒 + 编程 Agent 工具集 + 实时运行预览」**系统，使应用蜕变为类似移动端 Cursor / Claude Code 的本地智能开发环境。

---

## User Review Required

> [!IMPORTANT]
> 1. **权限与沙盒安全机制**：
>    - 默认情况下，Agent 所有的文件读写操作均被限制在用户主动授权绑定的 **当前工作区目录 (Workspace Root)** 范围内，禁止越界访问整个手机的敏感根目录。
>    - `delete_file`（删除文件）与大范围覆写操作会被标记为高风险（`ToolRisk.dangerous`），每次触发前必须弹出确认提示框。
> 2. **Web 平台与原生移动端的差异适配**：
>    - 原生 Android/iOS/Desktop：操作手机真实存储目录（如 `Download/MyProject` 或 App 私有文档目录）。
>    - Web 预览版：使用 IndexedDB / LocalStorage 虚拟目录或浏览器本地沙盒无缝适配。

---

## 架构与核心模块设计

```
┌────────────────────────────────────────────────────────┐
│ UI 展现层 (ChatPage & Workspace 面板)                   │
│   • 📁 当前工作区选择与切换胶囊 (Workspace Bar)         │
│   • 🌲 项目文件树实时浏览器 (File Tree Drawer)           │
│   • ▶️ 前端网页即时渲染器 (In-App Web Preview)          │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│ 业务编排层 (ChatController & WorkspaceService)          │
│   • 动态注入工作区路径到 systemPrompt                   │
│   • 联动已有的 Plan Mode（分步写代码打勾）              │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│ 底层工具集 (Workspace Tools)                            │
│   • read_file       • write_file    • edit_file        │
│   • list_directory  • search_files  • delete_file      │
└────────────────────────────────────────────────────────┘
```

---

## Proposed Changes

### 1. 本地工作区工具集 (Infrastructure / Tools)
#### [NEW] [lib/infrastructure/tools/workspace_tools.dart](file:///d:/AIIIIII/ai%20agent/mobile_agent/lib/infrastructure/tools/workspace_tools.dart)
实现 6 个核心标准 Agent 工具，均继承自 `AgentTool`：
- **`ReadFileTool` (`read_file`)**: 读取指定相对路径文件，支持按起止行（`startLine`/`endLine`）切片读取。
- **`WriteFileTool` (`write_file`)**: 新建或覆盖文件，自动递归创建缺失的父目录。
- **`EditFileTool` (`edit_file`)**: 局部精确替换文件内容（传入 `targetContent` 和 `replacementContent`），避免重写整个大文件。
- **`ListDirectoryTool` (`list_directory`)**: 递归或单层列出工作区内的目录与文件树。
- **`SearchFilesTool` (`search_files`)**: 基于正则/关键词在所有代码文件中快速全文搜索。
- **`DeleteFileTool` (`delete_file`)**: 删除指定文件，设置风险级别为 `ToolRisk.dangerous`。

---

### 2. 工作区管理服务 (Application Layer)
#### [NEW] [lib/application/workspace_service.dart](file:///d:/AIIIIII/ai%20agent/mobile_agent/lib/application/workspace_service.dart)
- 负责调用系统的 `file_picker`（`FilePicker.platform.getDirectoryPath`）选取本地目录。
- 持久化存储最近使用的项目目录记录（最近项目列表）。
- 校验工作区路径的合法性与读写权限。

#### [MODIFY] [lib/application/chat_controller.dart](file:///d:/AIIIIII/ai%20agent/mobile_agent/lib/application/chat_controller.dart)
- `ChatState` 新增字段：`String? currentWorkspacePath`。
- 在 `_buildRegistry` 中：如果 `currentWorkspacePath` 存在，自动实例化并注册全套 `WorkspaceTools`。
- 在 `_runAgent` 提示词中动态注入：
  ```
  [本地工作区已挂载] 
  当前项目根目录为：$workspacePath
  你可以使用 read_file、write_file、edit_file、list_directory 等工具直接读写和创建本地项目代码。
  ```

---

### 3. UI 交互与文件树预览 (Presentation Layer)
#### [NEW] [lib/presentation/workspace/file_tree_sheet.dart](file:///d:/AIIIIII/ai%20agent/mobile_agent/lib/presentation/workspace/file_tree_sheet.dart)
- 底部上拉面板或侧边栏，以折叠树形结构展示当前工作区的所有文件。
- 点击文件支持快速查看代码/语法高亮。

#### [NEW] [lib/presentation/workspace/web_preview_dialog.dart](file:///d:/AIIIIII/ai%20agent/mobile_agent/lib/presentation/workspace/web_preview_dialog.dart)
- 针对前端项目（包含 `index.html`），提供一键「运行预览」按钮。
- 在应用内部直接渲染 HTML/CSS/JS 运行效果。

#### [MODIFY] [lib/presentation/chat/chat_page.dart](file:///d:/AIIIIII/ai%20agent/mobile_agent/lib/presentation/chat/chat_page.dart)
- 在聊天顶部 AppBar 下方增加工作区胶囊条（显示当前打开的文件夹名字，点击可切换文件夹或打开文件树）。

---

### 4. 权限与平台配置 (Platform Configuration)
#### [MODIFY] [android/app/src/main/AndroidManifest.xml](file:///d:/AIIIIII/ai%20agent/mobile_agent/android/app/src/main/AndroidManifest.xml)
- 确保已声明 `READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE` 以及 `MANAGE_EXTERNAL_STORAGE`（Android 11+ 用于操作自定义公开文件夹）。

---

## 落地验证计划 (Verification Plan)

### 自动化与单元测试
- 编写 `test/workspace_tools_test.dart`：
  - 测试在临时沙盒目录下使用 `write_file` 创建文件并读取。
  - 测试使用 `edit_file` 精确替换多行代码。
  - 测试安全边界（防止 `../../` 路径穿越越权访问）。

### 交互演练测试
1. 在聊天界面点击「选择工作区」，选定一个空文件夹（如 `test_project`）。
2. 输入指令：“*帮我写一个网页版的简易计算器，包含 HTML/CSS/JS*”。
3. 观察计划模式弹出 -> 确认执行 -> Agent 自动调用 `write_file` 创建 `index.html`、`style.css`、`app.js`。
4. 打开项目文件树，确认文件已落地在本地磁盘，并点击「预览」查看网页真实运行效果。
