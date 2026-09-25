import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'application/approval_bridge.dart';
import 'application/device_automation_service.dart';
import 'application/onboarding_service.dart';
import 'infrastructure/background/foreground_service.dart';
import 'application/scheduled_task_runner.dart';
import 'infrastructure/notifications/notification_intent.dart';
import 'infrastructure/notifications/notification_service.dart';
import 'infrastructure/observability/sentry_service.dart';
import 'infrastructure/share/deep_link_service.dart';
import 'infrastructure/share/sharing_service.dart';
import 'presentation/chat/chat_layout_controller.dart';
import 'presentation/motion/motion_tier.dart';
import 'presentation/navigation/app_shell.dart';
import 'presentation/l10n/app_locale_controller.dart';
import 'presentation/onboarding/onboarding_page.dart';
import 'presentation/theme/app_palette.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/theme/app_theme_controller.dart';
import 'presentation/theme/app_appearance_controller.dart';
import 'presentation/theme/app_presentation_preferences.dart';
import 'presentation/widgets/brand_mark.dart';
import 'presentation/widgets/liquid_glass.dart';
import 'presentation/widgets/nexus_background.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Keep startup/plugin failures inside a zone until Sentry's Flutter
  // integration is initialized after the first frame.
  runZonedGuarded(
    () {
      // F-5：四处分头 load() 各自触发一次平台通道往返，合并为一次实例获取后并发载入。
      // 仍不阻塞首帧（unawaited），只是把 4 次 SharedPreferences 往返压成 1 次。
      unawaited(_loadUiPreferences());

      // The first Flutter frame must not wait for platform services or storage.
      runApp(const ProviderScope(child: MobileAgentApp()));
      // 动效档位：按帧耗时在会话内自动降级装饰层（粒子 / 光晕 / 流光）。
      MotionTierController.app.startMonitoring();
      // S1：动效强度偏好同步给档位控制器，MotionTierScope 随之通知重建。
      void syncIntensity() => MotionTierController.app.intensity =
          AppAppearanceController.motionIntensity.value;
      syncIntensity();
      AppAppearanceController.motionIntensity.addListener(syncIntensity);
      unawaited(_initializeServices());
    },
    (error, stack) {
      unawaited(SentryService.reportException(error, stack));
    },
  );
}

Future<void> _loadUiPreferences() async {
  final prefs = await SharedPreferences.getInstance();
  await Future.wait([
    AppThemeController.load(prefs),
    ChatLayoutController.load(prefs),
    AppLocaleController.load(prefs),
    AppAppearanceController.load(prefs),
  ]);
}

Future<void> _initializeServices() async {
  try {
    // C2 foreground service communication port.
    ForegroundService.initCommunicationPort();
    // Cold-start sharing is buffered; hot sharing is listened to in parallel.
    unawaited(SharingService.instance.init());
    // E3 local notifications are optional for the foreground experience.
    // 同时接上两个入口：点击通知（前台/热启动）走 onResponse 做页面路由；锁屏审批
    // 动作走 onBackgroundResponse，它在独立 isolate 里按 callback handle 调用，
    // 所以必须传顶层函数，不能传闭包。
    unawaited(_initNotifications());
    // 设备自动化：接通知点击回调 + 把规则同步给原生触发器。
    unawaited(_initDeviceAutomation());

    // app_links emits the initial URI on this stream as well. Subscribe before
    // slow background setup; do not also call getInitialLink (duplicate route).
    try {
      AppLinks().uriLinkStream.listen(
            DeepLinkService.instance.handleUri,
            onError: (Object error) => debugPrint('深链监听失败: $error'),
          );
    } catch (error) {
      debugPrint('深链监听失败: $error');
    }

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

    // Initialize crash reporting after the first frame.
    try {
      await SentryService.init();
    } catch (error) {
      debugPrint('崩溃上报初始化失败: $error');
    }
  } catch (error, stack) {
    debugPrint('后台启动服务初始化失败: $error\n$stack');
  }
}

/// 通知点击（前台 / 热启动）入口。
///
/// 只把 payload 转成意图投递给 [NotificationIntentRouter]，**不在回调里导航**：
/// 点击可能发生在启动早期，或用户正停在任意页面上，导航必须由持有 `Navigator`
/// 的页面（ChatPage）统一消费。
void _handleNotificationResponse(NotificationResponse response) {
  final intent = NotificationIntent.parse(response.payload);
  if (intent != null) NotificationIntentRouter.dispatch(intent);
}

/// 初始化通知插件并接上两个入口。
///
/// 冷启动（应用是被点击通知拉起的）不会触发 `onResponse`，必须单独读取
/// `getNotificationAppLaunchDetails()`，否则「点通知打开应用」这条路径会丢意图，
/// 用户点完通知只会看到首页而没有任何跳转。
Future<void> _initNotifications() async {
  await NotificationService.instance.init(
    onResponse: _handleNotificationResponse,
    onBackgroundResponse: handleApprovalNotificationAction,
  );
  final launchIntent = NotificationIntent.parse(
    await NotificationService.instance.notificationLaunchPayload(),
  );
  if (launchIntent != null) NotificationIntentRouter.dispatch(launchIntent);
}

/// 设备自动化通知点击 → 投递 `automation:<fireId>` 意图，由 ChatPage 打开确认页。
///
/// 冷启动时原生侧把 fireId 写入 launch fire；运行中则通过 automationFired 回调，
/// 两条路径都会清除 launch fire，避免重复打开。
Future<void> _initDeviceAutomation() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  const bridge = DeviceAutomationBridge();
  void dispatch(String fireId) => NotificationIntentRouter.dispatch(
        NotificationIntent(NotificationIntentKind.automation, fireId),
      );
  try {
    DeviceAutomationBridge.listen((fireId) {
      unawaited(bridge.consumeLaunchFire().catchError((_) => null));
      dispatch(fireId);
    });
    final launchFire = await bridge.consumeLaunchFire();
    if (launchFire != null && launchFire.isNotEmpty) dispatch(launchFire);
    final service = DeviceAutomationService();
    await service.syncToNative();
    await bridge.evaluateNow();
  } catch (error) {
    debugPrint('设备自动化初始化失败: $error');
  }
}

class MobileAgentApp extends StatelessWidget {
  const MobileAgentApp({super.key, this.showOnboarding});

  final bool? showOnboarding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppAppearanceController.effects,
      builder: (context, effects, _) => ValueListenableBuilder<double>(
      valueListenable: AppAppearanceController.glassIntensity,
      builder: (context, _, __) => ValueListenableBuilder<ThemeMode>(
        valueListenable: AppThemeController.mode,
        builder: (context, themeMode, _) => ValueListenableBuilder<Locale?>(
          valueListenable: AppLocaleController.locale,
          builder: (context, locale, _) => MaterialApp(
            title: 'NEXUS Agent',
            debugShowCheckedModeBanner: false,
            locale: locale,
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeMode,
            themeAnimationDuration: effects == 'off' ? Duration.zero
                : effects == 'reduced' ? const Duration(milliseconds: 120)
                : kThemeChangeDuration,
            builder: (context, child) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return MotionTierScope(
                controller: MotionTierController.app,
                // 纯扁平玻璃 = 用户选择朴素风格，装饰层按最低档处理。
                cap: AppAppearanceController.resolvedGlassIntensity ==
                        GlassIntensity.flat
                    ? MotionTier.low
                    : null,
                child: AppPresentationPreferences(
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: SystemUiOverlayStyle(
                    statusBarColor: Colors.transparent,
                    systemNavigationBarColor: Colors.transparent,
                    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
                    systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
                    systemStatusBarContrastEnforced: false,
                    systemNavigationBarContrastEnforced: false,
                  ),
                  child: NexusBackground(child: child ?? const SizedBox.shrink()),
                ),
                ),
              );
            },
            home: showOnboarding == null
                ? const StartupGate()
                : (showOnboarding! ? const OnboardingPage() : const AppShell()),
          ),
        ),
      ),
    ),
    );
  }
}

/// Loads first-run state after the first frame and falls back to the shell if
/// platform storage is unavailable.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key, this.onboardingLoader});

  /// Test seam for the first-run gate; production uses SharedPreferences.
  final Future<bool> Function()? onboardingLoader;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late final Future<bool> _onboardingDone =
      widget.onboardingLoader?.call() ?? _loadOnboardingState();

  Future<bool> _loadOnboardingState() async {
    try {
      return await OnboardingService.isDone().timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
    } catch (error) {
      debugPrint('新手引导状态读取失败: $error');
      return false;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;

    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 36),
            const SizedBox(height: 16),
            Text(
              'NEXUS Agent',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: isDark
                      ? AppPalette.darkHairline
                      : AppPalette.lightHairline,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? AppPalette.brand : AppPalette.brandAction,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
