# NEXUS Agent

面向移动端开发者的多模型 AI Agent 工作台，当前公开版本为 **v0.8.8**（Android versionCode `90`）。

## 核心能力

- 支持 OpenAI 兼容接口、Anthropic、Gemini 和托管代理。
- 支持流式对话、多轮 Agent 执行、工具调用、计划确认、风险审批和失败重试。
- 内置工作区文件工具、MCP 服务、长期记忆、知识库和定时任务。终端默认需要逐次确认；“完全访问”模式下终端可自动执行，cwd 不是完整沙箱边界。
- 使用 Drift/SQLite 保存会话、任务和运行记录，支持离线数据和运行恢复。
- 提供运行时间线、Token/费用统计、缓存命中信息、诊断日志和报告导出。
- 支持协作分析：启动前确认角色、预算、轮次和只读权限，多个子 Agent 并行分析后生成结构化汇总。
- API Key 使用系统安全存储，隐私保险箱支持加密备份与恢复。

## Android 隐私边界

- 剪贴板和图片附件只在模型明确请求的当前回合按需读取，不会作为后台监听持续采集。
- 敏感工具的原始参数、结果、运行日志、会话导出和保险箱导出均在持久化出口脱敏；当前回合只向模型提供完成任务所需的原文。
- 删除会话会联动删除关联的运行事件、日志和审批轨迹。

## Android 权限、侧载与后台任务

- 当前验证范围是 Android-only、ARM64（`arm64-v8a`）；不提供 Web 或桌面发布承诺。
- 从 GitHub Releases 下载 `app-release.apk` 侧载安装。系统可能要求在设置中允许本应用安装未知来源应用；请只安装可信 Release，并在安装前用同名 `.sha256` sidecar 校验 SHA-256。
- 网络、通知、前台服务和电池优化豁免等权限只为对应功能使用。后台任务依赖系统调度与资源，是尽力而为，不保证精确到点。

## 终端与工作区边界

工作区是默认工作目录，不是完整文件系统沙箱。终端/解释器脚本可能访问工作区外文件和网络；终端属于需要确认的工具，而完全访问模式会自动执行包括终端在内的确认级工具。执行前请检查命令、参数和目标路径。

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

Android release 默认要求正式签名。配置 `android/key.properties` 后执行正式构建；仅本地验证安装流程时，才显式允许 debug 签名：

```bash
flutter build apk --release
# 仅本地测试，产物不可作为发布包
cd android && ./gradlew app:assembleRelease -PallowDebugSigning=true
```

正式发布 tag 使用 `v<versionName>`，本版本为 `v0.8.8`；`+90` 仅作为 Android versionCode。

## 构建 APK

```bash
flutter build apk --release
```

产物路径：

```text
build/app/outputs/flutter-apk/app-release.apk
```

## 项目结构（Android-only）

```text
lib/       应用源码
assets/    图片与品牌资源
android/   Android 工程
```

## 发布版本

GitHub Releases：

https://github.com/2014569061-png/ai-agent/releases

下载对应版本的 `app-release.apk`，即可在 Android 设备上安装。
