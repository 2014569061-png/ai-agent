# Changelog

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
