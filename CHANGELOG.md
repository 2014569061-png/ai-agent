# Changelog

## [Unreleased]

### 体验修复
- **工具执行明细折叠卡材质统一**：外壳由原生 Card/ExpansionTile（实心灰面层，体系外）迁移至 `ImmersiveSurface` 玻璃 + `ImmersiveMotion.expand` 展开动效，与顶栏/工具卡同材质语言，消除视觉割裂

## [0.6.0] - 2026-09-05（体验与 Skill 生态版）

### 产品定位
在 v0.1「首个可上线版本」基础上，聚焦移动端 Agent 的连续性与使用体验：
计划看得见、后台不断线、多模态更顺手、记忆更懂你。

### 体验增强
- **计划模式体验闭环**：聊天页改为 PlanPanel 卡片化展示，出计划 → 确认 → 逐步执行 → 步骤状态/当前步高亮，支持折叠展开
- **后台任务持久化（Android 前台服务）**：Agent 执行时保持前台服务，退后台/切应用任务不中断；断网/杀进程后支持状态恢复与「继续执行」提示
- **记忆生效体验**：跨会话长期记忆 + 自定义记忆（remember 工具），新会话首轮注入，设置页可查看/编辑/删除
- **推理过程展示**：reasoning tokens 流式折叠展示（OpenAI/Claude/Gemini），支持思考程度设置
- **多模态输入补强**：语音输入（按住说话转文字）、拍照直传、剪贴板图片、系统分享面板入站建会话
- **音频/视频附件**：录音/音视频文件发送与播放基础支持
- **对话分享**：文本分享已有，长图/链接卡片按验收结果决定是否随版
- **Markdown / 数学公式**：公式渲染（LaTeX）与 Markdown 展示完善
- **TTS 语音输出**：长按气泡朗读（按完成度随版）
- **主屏幕 Widget**：最近会话快捷入口（按完成度随版）
- **新用户引导**：首次启动 4 步引导 + 设置页常驻入口
- **GitHub Skill 商店**：支持从 GitHub 公开仓库或 `owner/repo` 安装纯指令 Skill，支持根目录/子目录、预览、启用/停用、更新和删除
- **Skill 安全校验**：仅允许 `SKILL.md` 与静态资源，拒绝脚本、二进制、符号链接、路径穿越和超限归档
- **Skill 归档恢复**：Skill 安装记录与文件随 `.nexusvault` 一起导出和恢复

### 稳定性与体验修复
- 聊天气泡宽度、间距、深色主题标题可读性优化
- 清理旧内联计划卡片死代码，统一为 PlanPanel
- 数据库迁移链持续扩展，覆盖新增功能表（记忆/工具链/Agent/计划/后台任务等）

### 测试
- `flutter test` 全部通过（82 项）
- `flutter analyze` 无新增 error/warning；剩余为既有 `print` 信息提示
- 自动化测试覆盖：协议转换、Agent 执行、工具审批、记忆注入、后台任务恢复、计划模式、DB 迁移链

### 说明
- 本版聚焦使用体验，付费/盈利化模块暂缓，不在发布叙事内
- 功能列表以最终 Release 实际验收为准

## [0.1.0] - 2026-09-01（首个可上线版本）

### 产品定位
移动端 AI Agent 聚合客户端：一个入口接入多家大模型服务商（OpenAI 兼容 / Anthropic / Gemini / Ollama 等），支持工具调用与人工审批的 Agent 工作流。

### 核心功能
- **多 Provider 聚合**：OpenAI 兼容协议（OpenAI/DeepSeek/OpenRouter/Groq/Together/Ollama）+ Anthropic + Gemini 原生适配，SSE 流式输出
- **Agent 工作流**：多步工具调用状态机（created → waitingModel → approvalRequired → executingTool → completed/failed/cancelled），支持停止生成
- **工具与风险分级**：内置计算器/时间/JSON 查询/HTTP 请求/联网搜索；safe 静默执行、需确认/危险操作强制审批弹窗（参数可视化 + 风险色徽章）
- **工具调用可视化**：工具卡片实时回显（执行中脉冲/已完成/失败），会话重启后历史工具链可恢复
- **会话管理**：搜索 / 重命名 / 置顶 / 收藏 / 删除 / 新建；Markdown 导出与复制
- **Prompt 模板库**：CRUD / 分类 / 收藏 / 搜索，应用为系统提示词或插入输入框
- **Agent 配置**：系统提示词、温度 / Top P / 最大输出 Token / 最大执行步数 / 可用工具开关
- **MCP 支持**：HTTP 型 MCP 服务器接入（远端工具自动注册，默认需确认）
- **本地优先存储**：Drift/SQLite（会话、消息、Agent、Prompt 模板），API Key 存系统 Keystore
- **多端适配**：Android / Web 双平台；浅色/深色/跟随系统主题

### 稳定性与安全修复（上线前回归）
- 修复 release 包缺失 INTERNET 权限导致无法联网的问题
- 配置正式签名（非 Debug 证书）；统一应用名为 NEXUS Agent，正式包名 `com.nexusagent.app`
- 全链路异常兜底：损坏/加密 PDF、DB 写入失败、网络中断均不再导致 UI 卡死，错误信息可见
- SSE 流式请求排除自动重试（避免重复文本与重复计费）；流式输出按 50ms 窗口节流，长会话更流畅
- Ollama 等本地无 Key 模型正确识别为已配置
- `http_request` 工具 SSRF 防护（拒绝云元数据/链路本地/内网域名）；工具请求超时保护
- 修复导入图片后消息气泡显示一长串 base64 乱码（`ChatMessage.text` 对图片附件返回占位符，气泡内改为真实缩略图渲染）
- 会话消息按会话建索引，大数据量查询性能优化
- 数据库迁移链 v1→v5 完整（置顶/收藏/温度/Top P/Prompt 模板/工具链/tags）

### 测试
- 37 个自动化测试全通过（协议转换、Agent 执行、工具审批、错误恢复、停止/重新生成/会话切换、SSRF、配置判定、DB 清理）
- `flutter analyze` 0 问题；APK / AAB / Web 构建通过

### 已知事项
- MCP stdio 型服务器仅桌面端可用（Android/Web 隐藏入口）
- 会话导出为 Markdown 文件（Android 存应用文档目录）
