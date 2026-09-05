import 'package:flutter/material.dart';

import '../chat/chat_page.dart';

/// 应用根壳：首页即对话工作台，不再提供底部导航栏。
/// 智能体管理 / 设置 / 历史入口统一迁移到对话页顶部工具栏。
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const ChatPage();
  }
}
