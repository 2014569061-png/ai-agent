import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'application/onboarding_service.dart';
import 'application/account_services.dart';
import 'application/billing_api.dart';
import 'application/run_event_queue.dart';
import 'infrastructure/background/foreground_service.dart';
import 'infrastructure/background/scheduled_task_runner.dart';
import 'infrastructure/database/database_provider.dart';
import 'infrastructure/notifications/notification_service.dart';
import 'infrastructure/observability/sentry_service.dart';
import 'infrastructure/share/deep_link_service.dart';
import 'infrastructure/share/sharing_service.dart';
import 'infrastructure/widgets/nexus_widget.dart';
import 'presentation/chat/chat_layout_controller.dart';
import 'presentation/navigation/app_shell.dart';
import 'presentation/onboarding/onboarding_page.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/theme/app_theme_controller.dart';
import 'presentation/widgets/immersive_background.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  AppThemeController.load();
  ChatLayoutController.load();

  // The first Flutter frame must not wait for platform services or storage.
  runApp(const ProviderScope(child: MobileAgentApp()));
  unawaited(_initializeServices());
}

Future<void> _initializeServices() async {
  try {
    // C2 foreground service communication port.
    ForegroundService.initCommunicationPort();
    // Cold-start sharing is buffered; hot sharing is listened to in parallel.
    unawaited(SharingService.instance.init());
    // E3 local notifications are optional for the foreground experience.
    unawaited(NotificationService.instance.init());

    // C5 periodic background task registration.
    if (!kIsWeb) {
      try {
        await Workmanager()
            .initialize(scheduledTaskCallbackDispatcher)
            .timeout(const Duration(seconds: 5));
        await Workmanager()
            .registerPeriodicTask(
              'nexus_scheduled_check',
              'nexus_scheduled_check',
              frequency: const Duration(minutes: 15),
              // 定时任务需要调用 LLM API，无网络时执行必然失败，交给系统等联网再触发。
              constraints: Constraints(networkType: NetworkType.connected),
            )
            .timeout(const Duration(seconds: 5));
      } catch (error) {
        debugPrint('后台任务注册失败: $error');
      }
    }

    // E4 deep links. Cold-start lookup is bounded; hot links are independent.
    final appLinks = AppLinks();
    try {
      final initial =
          await appLinks.getInitialLink().timeout(const Duration(seconds: 2));
      if (initial != null) DeepLinkService.instance.handleUri(initial);
    } catch (error) {
      debugPrint('深链冷启动读取失败: $error');
    }
    try {
      appLinks.uriLinkStream.listen(DeepLinkService.instance.handleUri);
    } catch (error) {
      debugPrint('深链监听失败: $error');
    }

    // E2 home-screen widget actions.
    NexusWidget.onWidgetClicked(
      (uri) => DeepLinkService.instance.handleUri(uri),
    );

    // Initialize crash reporting after the first frame.
    try {
      await SentryService.init(() {});
    } catch (error) {
      debugPrint('崩溃上报初始化失败: $error');
    }

    // Refresh widget data without holding up the foreground UI.
    unawaited(_refreshWidget());
    // Recover events captured while offline after the first frame. Backoff in
    // RunEventQueue prevents repeated startup failures from causing a storm.
    unawaited(_recoverRunEvents());
  } catch (error, stack) {
    debugPrint('后台启动服务初始化失败: $error\n$stack');
  }
}

Future<void> _recoverRunEvents() async {
  try {
    final queue = RunEventQueue();
    if (await queue.pendingCount() == 0) return;
    final api = BillingApi(baseUrl: defaultBackendBaseUrl());
    final session = await AccountService(api: api).restoreSession();
    if (session == null) return;
    await queue.recover(api: api, access: session.access);
  } catch (error) {
    debugPrint('离线运行事件恢复失败: $error');
  }
}

Future<void> _refreshWidget() async {
  try {
    final db = await DatabaseProvider.instance.database;
    final conversations = await db.recentConversations();
    final items = conversations.take(3).map((c) => c.title).toList();
    await NexusWidget.updateWidget(items: items);
  } catch (error) {
    debugPrint('刷新桌面 Widget 失败: $error');
  }
}

class MobileAgentApp extends StatelessWidget {
  const MobileAgentApp({super.key, this.showOnboarding});

  final bool? showOnboarding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.mode,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'NEXUS Agent',
        debugShowCheckedModeBanner: false,
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
        builder: (context, child) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              statusBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
              systemNavigationBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
              systemStatusBarContrastEnforced: false,
              systemNavigationBarContrastEnforced: false,
            ),
            child: ImmersiveBackground(
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
        home: showOnboarding == null
            ? const StartupGate()
            : (showOnboarding! ? const OnboardingPage() : const AppShell()),
      ),
    );
  }
}

/// Loads first-run state after the first frame and falls back to the shell if
/// platform storage is unavailable.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late final Future<bool> _onboardingDone = _loadOnboardingState();

  Future<bool> _loadOnboardingState() async {
    try {
      return await OnboardingService.isDone().timeout(
        const Duration(seconds: 2),
        onTimeout: () => true,
      );
    } catch (error) {
      debugPrint('新手引导状态读取失败: $error');
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _onboardingDone,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const _StartupLoadingView();
        return snapshot.data! ? const AppShell() : const OnboardingPage();
      },
    );
  }
}

class _StartupLoadingView extends StatelessWidget {
  const _StartupLoadingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          color: theme.colorScheme.primary,
          strokeWidth: 2.5,
        ),
      ),
    );
  }
}
