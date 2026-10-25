# 架构概览

NEXUS Agent 使用 Flutter、Riverpod 与 Drift/SQLite，Android 和 Windows 共享应用与领域逻辑，平台宿主及页面布局分别实现。

| 目录 | 职责 |
|---|---|
| lib/domain/ | 模型、工具结果、风险与状态规则 |
| lib/application/ | 对话、执行协调、项目、费用与上下文流程 |
| lib/infrastructure/ | 模型服务商、数据库、文件系统、终端与工具接入 |
| lib/presentation/ | 页面、组件、平台主题与交互 |
| lib/debug/ | 隔离 UI 验收及诊断入口 |

## 对话与执行

对话控制器组织消息、附件、模型路由和执行状态。Agent 执行器完成多轮模型请求与工具调用，工具声明风险和能力特征，经审批与执行管线运行。文件读取、补丁、快照及变更记录提供项目内修改的追踪与恢复基础。

## 数据与记录

Drift/SQLite 保存会话、任务、运行和审计数据。会话日志提供请求快照、分支、续办与大附件记录基础；展示消息、运行事件和会话日志有不同职责。外部凭据使用平台安全存储。

## 平台能力

Android 提供系统入口、临时 WebView 浏览器、分享、后台通知和 ARM64 PRoot 运行时。Windows 提供文件、Git、网页预览、终端与设备面板。模拟器用于通用功能和布局，不能执行 ARM64 内置运行时的真机验收。

## 架构决策

- [会话日志与执行器观察点](../architecture/adr/0001-harness-style-session-log.md)
- [ModuleHost 与运行配置](../architecture/adr/0002-module-host-and-run-profiles.md)
- [能力边界](../architecture/adr/0003-capability-seams.md)
- [工具声明 v2](../architecture/adr/0004-tool-spec-v2.md)

[安全与数据边界](security.md) · [开发与构建](getting-started.md)
