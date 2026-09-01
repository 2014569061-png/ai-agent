import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/chat/chat_page.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/theme/app_theme_controller.dart';

void main() {
  AppThemeController.load();
  runApp(const ProviderScope(child: MobileAgentApp()));
}

class MobileAgentApp extends StatelessWidget {
  const MobileAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.mode,
      builder: (context, themeMode, _) => MaterialApp(
      title: 'NEXUS Agent',
      debugShowCheckedModeBanner: false,
      // 本地化：支持中文/英文；Material 内置组件（对话框按钮、日期等）
      // 按系统 locale 渲染。业务文案走 AppStrings（当前默认中文）。
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const ChatPage(),
      ),
    );
  }
}
