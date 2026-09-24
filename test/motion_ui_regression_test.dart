import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/application/install_job_service.dart';
import 'package:mobile_agent/application/project_kind.dart';
import 'package:mobile_agent/main.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_message_list.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/onboarding/onboarding_page.dart';
import 'package:mobile_agent/presentation/motion/nexus_page_route_factory.dart';
import 'package:mobile_agent/presentation/settings/appearance_theme_page.dart';
import 'package:mobile_agent/presentation/projects/install_job_sheet.dart';
import 'package:mobile_agent/presentation/theme/app_appearance_controller.dart';
import 'package:mobile_agent/presentation/widgets/nexus_loading_skeleton.dart';
import 'package:mobile_agent/presentation/widgets/nexus_execution_status.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppAppearanceController.effects.value = 'full';
    AppAppearanceController.glassIntensity.value = 0.45;
    AppAppearanceController.fontScale.value = 1;
  });
  tearDown(() {
    AppAppearanceController.effects.value = 'full';
    AppAppearanceController.glassIntensity.value = 0.45;
    AppAppearanceController.fontScale.value = 1;
  });

  testWidgets(
      'application Off preference disables motion immediately and after reload',
      (tester) async {
    await tester.pumpWidget(
        const ProviderScope(child: MobileAgentApp(showOnboarding: true)));
    await tester.pumpAndSettle();
    await AppAppearanceController.setEffects('off');
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(OnboardingPage));
    expect(MediaQuery.disableAnimationsOf(context), isTrue);
    await AppAppearanceController.load();
    expect(AppAppearanceController.effects.value, 'off');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('new routes have zero real duration when effects are Off',
      (tester) async {
    AppAppearanceController.effects.value = 'off';
    await tester.pumpWidget(
        const ProviderScope(child: MobileAgentApp(showOnboarding: true)));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(OnboardingPage));
    final route = NexusPageRoute<void>.detail(
        builder: (_) => const Scaffold(body: Text('destination')));
    Navigator.of(context).push(route);
    await tester.pump();
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Flat preference does not produce an out-of-range Slider',
      (tester) async {
    AppAppearanceController.glassIntensity.value = 0;
    await tester.pumpWidget(const MaterialApp(home: AppearanceThemePage()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final skeleton in [true, false]) {
    testWidgets('reduce-motion stops decorative ticker (skeleton=$skeleton)',
        (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: skeleton
            ? const NexusLoadingSkeleton(child: Text('loading'))
            : const NexusExecutionStatus(
                state: NexusExecutionState.running, label: 'running'),
      )));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets('background lifecycle stops the skeleton ticker', (tester) async {
    addTearDown(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await tester.pumpWidget(
        const MaterialApp(home: NexusLoadingSkeleton(child: Text('loading'))));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('an active message entrance finishes when motion is reduced',
      (tester) async {
    final controller = ScrollController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
    final messages = [
      ChatMessage(
          id: 'old',
          role: MessageRole.user,
          parts: [const MessagePart.text('old')]),
    ];

    Widget host(MotionLevel level, List<ChatMessage> items, bool running) =>
        MaterialApp(
          home: NexusMotionScope(
            level: level,
            child: Scaffold(
              body: ChatMessageList(
                messages: items,
                controller: controller,
                running: running,
                onLongPress: (_) {},
                onRegenerate: () {},
              ),
            ),
          ),
        );

    await tester.pumpWidget(host(MotionLevel.full, messages, false));
    await tester.pump();
    final nextMessages = [
      ...messages,
      ChatMessage(
          id: 'new',
          role: MessageRole.assistant,
          parts: [const MessagePart.text('new')]),
    ];
    await tester.pumpWidget(host(MotionLevel.full, nextMessages, true));
    await tester.pump(const Duration(milliseconds: 40));
    final entrance = tester.widget<FadeTransition>(find
        .descendant(
          of: find.byType(ChatMessageList),
          matching: find.byType(FadeTransition),
        )
        .last);
    expect(entrance.opacity.value, lessThan(1));

    await tester.pumpWidget(host(MotionLevel.reduced, nextMessages, true));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    final completedEntrance = tester.widget<FadeTransition>(find
        .descendant(
          of: find.byType(ChatMessageList),
          matching: find.byType(FadeTransition),
        )
        .last);
    expect(completedEntrance.opacity.value, 1);
  });

  testWidgets('project installation button shows progress while busy',
      (tester) async {
    const job = InstallJob(
      id: 'install-1',
      kind: ProjectKind.flutter,
      runtimeId: 'android',
      steps: [
        InstallJobStep(
          id: 'flutter',
          label: '安装 Flutter',
          command: 'install flutter',
          estimatedBytes: 1024,
        ),
      ],
    );

    Widget sheet(bool busy) => MaterialApp(
          home: Scaffold(
            body: InstallJobSheet(job: job, busy: busy, onStart: () {}),
          ),
        );

    await tester.pumpWidget(sheet(false));
    expect(find.text('开始安装'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(sheet(true));
    expect(find.text('安装中…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
