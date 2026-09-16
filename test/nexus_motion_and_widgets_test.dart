import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/chat/widgets/nexus_back_to_latest_button.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/nexus_motion.dart';
import 'package:mobile_agent/presentation/motion/nexus_page_route_factory.dart';
import 'package:mobile_agent/presentation/widgets/nexus_async_content.dart';
import 'package:mobile_agent/presentation/widgets/nexus_disclosure.dart';
import 'package:mobile_agent/presentation/widgets/nexus_execution_status.dart';
import 'package:mobile_agent/presentation/widgets/nexus_loading_skeleton.dart';
import 'package:mobile_agent/presentation/widgets/nexus_status_badge.dart';

void main() {
  group('NexusMotion & MotionPreferences Tests', () {
    testWidgets('MotionPreferences respects disableAnimations', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              expect(MotionPreferences.shouldReduceMotion(context), isTrue);
              expect(
                MotionPreferences.adjustDuration(
                  context,
                  const Duration(milliseconds: 220),
                ),
                Duration.zero,
              );
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('NexusMotion builds transitions safely', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final animation = const AlwaysStoppedAnimation<double>(0.5);
                final fade = NexusMotion.fadeTransition(
                  context,
                  animation,
                  const Text('Test Child'),
                );
                final slide = NexusMotion.slideFadeTransition(
                  context,
                  animation,
                  const Text('Slide Child'),
                );
                final size = NexusMotion.sizeTransition(
                  context,
                  animation,
                  const Text('Size Child'),
                );
                return Column(
                  children: [fade, slide, size],
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Test Child'), findsOneWidget);
      expect(find.text('Slide Child'), findsOneWidget);
      expect(find.text('Size Child'), findsOneWidget);
    });

    test('NexusPageRouteFactory has standard durations', () {
      final detailRoute = NexusPageRoute.detail(
        builder: (_) => const SizedBox(),
      );
      expect(detailRoute.transitionDuration, const Duration(milliseconds: 220));
      expect(detailRoute.reverseTransitionDuration, const Duration(milliseconds: 150));

      final fadeRoute = NexusPageRoute.fade(
        builder: (_) => const SizedBox(),
      );
      expect(fadeRoute.transitionDuration, const Duration(milliseconds: 150));
    });
  });

  group('NexusAsyncContent Tests', () {
    testWidgets('renders skeleton during loading', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NexusAsyncContent(
              loading: true,
              loadingSkeleton: NexusChatMessageSkeleton(),
              child: Text('Content'),
            ),
          ),
        ),
      );

      expect(find.byType(NexusChatMessageSkeleton), findsOneWidget);
      expect(find.text('Content'), findsNothing);
    });

    testWidgets('renders empty state when isEmpty is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NexusAsyncContent(
              loading: false,
              isEmpty: true,
              emptyTitle: '暂无会话',
              child: Text('Content'),
            ),
          ),
        ),
      );

      expect(find.text('暂无会话'), findsOneWidget);
      expect(find.text('Content'), findsNothing);
    });

    testWidgets('renders error view with retry and disclosure', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NexusAsyncContent(
              loading: false,
              error: 'Failed host lookup: api.openai.com',
              onRetry: () => retried = true,
              child: const Text('Content'),
            ),
          ),
        ),
      );

      expect(find.text('加载未成功'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      await tester.tap(find.text('重试'));
      expect(retried, isTrue);
    });

    testWidgets('renders normal content when loaded successfully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NexusAsyncContent(
              loading: false,
              child: Text('Content Ready'),
            ),
          ),
        ),
      );

      expect(find.text('Content Ready'), findsOneWidget);
    });
  });

  group('NexusExecutionStatus Tests', () {
    testWidgets('renders running state with label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NexusExecutionStatus(
              state: NexusExecutionState.running,
              label: '正在执行：search_files',
              detail: '耗时 1.2s',
            ),
          ),
        ),
      );

      expect(find.text('正在执行：search_files'), findsOneWidget);
      expect(find.text('耗时 1.2s'), findsOneWidget);
    });

    testWidgets('renders waitingForUser with approve and reject actions', (tester) async {
      var approved = false;
      var rejected = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NexusExecutionStatus(
              state: NexusExecutionState.waitingForUser,
              label: '等待授权：执行终端命令',
              onApprove: () => approved = true,
              onReject: () => rejected = true,
            ),
          ),
        ),
      );

      expect(find.text('等待授权：执行终端命令'), findsOneWidget);
      expect(find.text('授权继续'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);

      await tester.tap(find.text('授权继续'));
      expect(approved, isTrue);

      await tester.tap(find.text('拒绝'));
      expect(rejected, isTrue);
    });

    testWidgets('compact mode renders correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NexusExecutionStatus(
              state: NexusExecutionState.succeeded,
              label: '执行成功',
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('执行成功'), findsOneWidget);
    });
  });

  group('NexusDisclosure Tests', () {
    testWidgets('expands and collapses on tap', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NexusDisclosure(
              title: Text('思考过程'),
              child: Text('这是详细的思考推导过程'),
            ),
          ),
        ),
      );

      expect(find.text('思考过程'), findsOneWidget);

      // Tap header to expand
      await tester.tap(find.text('思考过程'));
      await tester.pumpAndSettle();

      expect(find.text('这是详细的思考推导过程'), findsOneWidget);

      // Tap header to collapse
      await tester.tap(find.text('思考过程'));
      await tester.pumpAndSettle();

      expect(find.text('这是详细的思考推导过程'), findsNothing);
    });
  });

  group('NexusStatusBadge & NexusBackToLatestButton Tests', () {
    testWidgets('renders NexusStatusBadge with tone', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NexusStatusBadge(
              label: '已连接',
              tone: NexusBadgeTone.success,
              showDot: true,
            ),
          ),
        ),
      );

      expect(find.text('已连接'), findsOneWidget);
    });

    testWidgets('renders NexusBackToLatestButton and responds to tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NexusBackToLatestButton(
              unreadCount: 3,
              isRunning: true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
      expect(find.text('生成中…'), findsOneWidget);

      await tester.tap(find.byType(NexusBackToLatestButton));
      expect(tapped, isTrue);
    });
  });
}
