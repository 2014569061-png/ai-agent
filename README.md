# NEXUS Agent

移动端 AI Agent 聚合客户端的 MVP。

## 下载安装（手机用户）

1. 打开 [Releases](https://github.com/2014569061-png/ai-agent/releases) 页面
2. 下载最新的 `app-release.apk` 到手机
3. 点击安装；若提示"未知来源"，按提示到系统设置中允许该来源安装应用即可

> 每次发版会自动发布新的 APK，版本号递增，可直接覆盖安装。

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

### 自动发版

推送 tag（如 `v0.1.0`）会触发 GitHub Actions 自动构建签名 APK 并发布到
[Releases](https://github.com/2014569061-png/ai-agent/releases)：

```bash
git tag v0.1.0
git push origin v0.1.0
```

签名凭据存于 GitHub Secrets（`KEYSTORE_BASE64` / `STORE_PASSWORD` /
`KEY_PASSWORD` / `KEY_ALIAS`），不入库。本地签名配置保存在 `android/key.properties`
和 `android/app/upload-keystore.jks`（已被 gitignore 忽略）。克隆后未配置签名时，
项目会自动回退到 debug 签名，仍可用于开发和本地测试。
