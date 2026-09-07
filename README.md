# NEXUS Agent

面向移动端的多模型 AI Agent 客户端，当前版本为 **v0.7.2**（Android versionCode `72`）。

## 核心能力

- 支持 OpenAI 兼容接口、Anthropic、Gemini 和托管代理。
- 支持流式对话、多轮 Agent 执行、工具调用、计划确认、风险审批和失败重试。
- 内置工作区文件工具、MCP 服务、长期记忆、知识库和定时任务。
- 使用 Drift/SQLite 保存会话、任务和运行记录，支持离线数据和运行恢复。
- 提供运行时间线、Token/费用统计、缓存命中信息、诊断日志和报告导出。
- API Key 使用系统安全存储，隐私保险箱支持加密备份与恢复。

## 环境要求

- Flutter 3.47 或更高版本
- Dart 3.13 或更高版本
- Android 构建需要 JDK 17

## 本地运行

```bash
flutter pub get
flutter run
```

首次启动后，在“设置”中配置模型服务商、接口地址、模型和 API Key。

## 构建 APK

```bash
flutter build apk --release
```

产物路径：

```text
build/app/outputs/flutter-apk/app-release.apk
```

## 项目结构

```text
lib/       应用源码
assets/    图片与品牌资源
android/   Android 工程
ios/       iOS 工程
web/       Web 工程
macos/     macOS 工程
windows/   Windows 工程
linux/     Linux 工程
```

## 发布版本

GitHub Releases：

https://github.com/2014569061-png/ai-agent/releases

下载对应版本的 `app-release.apk`，即可在 Android 设备上安装。
