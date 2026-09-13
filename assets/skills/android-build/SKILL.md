---
name: android-build
description: 仅在 Android Linux/Alpine PRoot 中，把单 Activity/View 的小型 Java/静态资源项目直接构建成可安装的本地 debug APK；不用于 Flutter 或大型 Gradle 工程。
author: NEXUS
version: 1.0.0
tags: [android, apk, build]
---

# 手机直构建 APK（无 Gradle）

适用于单 Activity/View 的 Java 小项目（游戏、工具页）。只读取与当前动作相关的参考文件，不要为普通源码修改读取安装或签名章节。

## 路由

- 工具链缺失或尚未验证时，读取 references/toolchain.md；只安装缺失项。
- 需要创建签名辅助类、构建 APK 或处理 Manifest 时，读取 references/build.md。
- 构建和验证必须从项目根（终端 cwd）执行。
- 完成条件是生成 app-debug.apk，并完成参考文件中的聚焦验证；构建失败时继续修复本次变更导致的失败并重跑受影响步骤。
- 安全的本地构建和测试不需要逐步确认。涉及外部发布、生产签名、未授权的源/权限变更或用户秘密时暂停并说明原因。
