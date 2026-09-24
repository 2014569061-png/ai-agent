---
name: flutter-ui
description: 设计和修改 Flutter 界面，关注响应式布局、主题一致性、可访问性、状态反馈和组件复用。
author: NEXUS
version: 1.0.0
tags: [flutter, ui, responsive]
triggers: [Flutter 界面, UI, 页面设计, 组件]
examples: [优化这个 Flutter 页面, 做一个设置页面]
---

# Flutter 界面实现

## 实现原则

先检查现有页面结构、主题令牌、路由和状态管理，再进行最小范围修改。

- 优先复用项目已有组件、颜色、间距、圆角和文字层级。
- 为加载、空态、错误、成功和禁用状态提供清晰反馈。
- 处理窄屏、长文本、键盘、深色模式和滚动溢出。
- 保持业务逻辑在 controller/provider 中，Widget 负责展示和交互。
- 对关键交互补充 Widget 测试；不要用固定像素掩盖布局问题。

完成后运行格式化、静态分析和受影响的测试。
