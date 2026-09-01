# NEXUS Agent

移动端 AI Agent 聚合客户端的 MVP。

## 当前范围

- Flutter + Riverpod
- OpenAI 兼容 Provider 抽象
- Agent 执行状态机
- 工具注册与风险分级
- 本地优先的数据模型
- 最小聊天界面

## 开发环境

需要 Flutter SDK（Dart 3.5+）。安装后执行：

```bash
flutter pub get
flutter run
```

当前版本暂不包含本地 Shell 执行；联网和有副作用工具必须经过用户确认。

## 构建

```bash
flutter analyze
flutter test
flutter build apk --release
flutter build web --release
```

Android 发布签名配置保存在本机的 `android/key.properties` 和
`android/app/upload-keystore.jks`，这两个文件不会提交到仓库。克隆后未配置签名时，
项目会自动回退到 debug 签名，仍可用于开发和本地测试。
