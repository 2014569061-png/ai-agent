# NEXUS Agent

移动端 AI Agent 聚合客户端的 MVP。

## 下载安装（手机用户）

1. 打开 [Releases](https://github.com/2014569061-png/ai-agent/releases) 页面
2. 下载最新的 `app-release.apk` 到手机
3. 点击安装；若提示"未知来源"，按提示到系统设置中允许该来源安装应用即可

> 每次发版会自动发布新的 APK，版本号递增，可直接覆盖安装。

## 当前范围

- Flutter + Riverpod，本地优先的数据模型（Drift/SQLite）
- 多 Provider 抽象：OpenAI 兼容 / Anthropic / Gemini / 托管代理，SSE 流式
- Agent 执行状态机：多轮工具调用、危险工具审批分级、首轮计划确认、
  失败自动重试（仅限尚未产出内容的空流，指数退避）
- 上下文窗口管理：按 token 预算自动裁剪较早历史（默认 32000，
  可在 Provider 设置中按模型调整），保持工具调用与结果成组
- 工具生态：计算/时间/JSON/HTTP/搜索/图片生成、工作区文件工具、
  受限终端命令（白名单 + 禁 shell 管道重定向 + 拦截解释器内联求值）、
  MCP 服务器（HTTP/stdio）、声明式插件工具、子 Agent
- 记忆、知识库（本地 RAG）、Skill 市场（GitHub tar.gz 安装，纯指令注入）、
  定时任务（WorkManager + 电池优化豁免引导）
- 隐私保险箱：全量数据（含 Provider 密钥与 MCP 配置）AES-256-GCM 加密导出/恢复

## 开发环境

需要 Flutter SDK（Dart 3.5+）。安装后执行：

```bash
flutter pub get
flutter run
```

联网和有副作用的工具必须经过用户确认；终端命令运行在工作区沙箱内，
但注意 python/node 等解释器实际执行的脚本代码本身不受沙箱限制。

## 构建

```bash
flutter analyze
flutter test
flutter build apk --release
flutter build web --release
```

### 自动发版

推送 tag（如 `v0.6.0`）会触发 GitHub Actions 自动构建签名 APK 并发布到
[Releases](https://github.com/2014569061-png/ai-agent/releases)：

```bash
git tag v0.6.0
git push origin v0.6.0
```

签名凭据存于 GitHub Secrets（`KEYSTORE_BASE64` / `STORE_PASSWORD` /
`KEY_PASSWORD` / `KEY_ALIAS`），不入库。本地签名配置保存在 `android/key.properties`
和 `android/app/upload-keystore.jks`（已被 gitignore 忽略）。克隆后未配置签名时，
项目会自动回退到 debug 签名，仍可用于开发和本地测试。
