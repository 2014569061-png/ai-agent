// M1 整屏层级转场：上层整屏位移 + 下层视差暗化。
//
// 这里只验证几何与分档策略（位置、遮罩、各档位降级），绘制次数的性能契约
// 见 `route_transition_paint_test.dart`。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/motion/nexus_motion.dart';
import 'package:mobile_agent/presentation/motion/nexus_page_route_factory.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

const _frame = Duration(milliseconds: 16);

class _Page extends StatelessWidget {
  const _Page(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Align(alignment: Alignment.topLeft, child: Text(label)),
    );
  }
}

Future<GlobalKey<NavigatorState>> _pumpApp(
  WidgetTester tester, {
  MotionLevel level = MotionLevel.full,
  MotionTier? tier,
}) async {
  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navKey,
      theme: AppTheme.light(),
      builder: (context, child) {
        Widget result = NexusMotionScope(level: level, child: child!);
        if (tier != null) {
          result = MotionTierScope(
            controller: MotionTierController(initial: tier),
            child: result,
          );
        }
        return result;
      },
      home: const _Page('home'),
    ),
  );
  return navKey;
}

void _push(GlobalKey<NavigatorState> navKey,
    {RoutePresentation presentation = RoutePresentation.detail}) {
  navKey.currentState!.push(
    NexusPageRoute<void>(
      builder: (_) => const _Page('detail'),
      presentation: presentation,
    ),
  );
}

double _x(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text, skipOffstage: false)).dx;

void main() {
  group('NexusSpringCurve', () {
    test('端点精确、单调不越界', () {
      final curve = NexusSpringCurve(NexusMotion.springRelease);
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
      var previous = 0.0;
      for (var i = 1; i <= 100; i++) {
        final v = curve.transform(i / 100);
        expect(v, inInclusiveRange(0.0, 1.0));
        expect(v, greaterThanOrEqualTo(previous - 1e-9));
        previous = v;
      }
      // 离手弹簧前段快：进度过半时已走完绝大部分位移。
      expect(curve.transform(0.5), greaterThan(0.85));
    });

    test('稳定时长随刚度变化', () {
      final soft = NexusSpringCurve(NexusMotion.springRelease);
      final stiff = NexusSpringCurve(
        const SpringDescription(mass: 1, stiffness: 600, damping: 45),
      );
      expect(stiff.settleSeconds, lessThan(soft.settleSeconds));
    });
  });

  group('NexusPageRoute 整屏转场', () {
    testWidgets('进入：上层从右侧整屏滑入，下层左移视差并暗化', (tester) async {
      final navKey = await _pumpApp(tester);
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final homeX = _x(tester, 'home');

      _push(navKey);
      await tester.pump();
      await tester.pump(_frame);

      // 首帧附近：上层几乎还在屏幕右侧之外。
      expect(_x(tester, 'detail'), greaterThan(width * 0.5));

      await tester.pump(const Duration(milliseconds: 100));
      final homeMid = _x(tester, 'home');
      expect(homeMid, lessThan(homeX - 1), reason: '下层必须向左视差位移');
      expect(homeMid, greaterThanOrEqualTo(homeX - width * 0.3 - 0.5));
      expect(find.byType(ColoredBox, skipOffstage: false), findsWidgets);

      await tester.pumpAndSettle();
      expect(_x(tester, 'detail'), closeTo(homeX, 0.5));
      // 稳态下层不再参与合成（opaque 路由遮挡）。
      expect(find.text('home'), findsNothing);
    });

    testWidgets('返回：下层回到原位且无残留位移', (tester) async {
      final navKey = await _pumpApp(tester);
      final homeX = _x(tester, 'home');
      _push(navKey);
      await tester.pumpAndSettle();

      navKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(_x(tester, 'home'), lessThan(homeX), reason: '返回中段下层仍在视差位');
      await tester.pumpAndSettle();
      expect(_x(tester, 'home'), closeTo(homeX, 0.01));
      expect(find.text('detail'), findsNothing);
    });

    testWidgets('嵌套 NexusPageRoute：下层同为 Nexus 路由时同样让位', (tester) async {
      final navKey = await _pumpApp(tester);
      navKey.currentState!.push(
        NexusPageRoute<void>(builder: (_) => const _Page('middle')),
      );
      await tester.pumpAndSettle();
      final middleX = _x(tester, 'middle');

      _push(navKey);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_x(tester, 'middle'), lessThan(middleX - 1));
      await tester.pumpAndSettle();

      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(_x(tester, 'middle'), closeTo(middleX, 0.01));
    });

    testWidgets('先收起 Sheet 再推入：让位的是 Sheet 下方的页面', (tester) async {
      final navKey = await _pumpApp(tester);
      final homeX = _x(tester, 'home');
      unawaited(showModalBottomSheet<void>(
        context: navKey.currentContext!,
        builder: (context) => TextButton(
          onPressed: () {
            final navigator = Navigator.of(context);
            navigator.pop();
            navigator.push(
              NexusPageRoute<void>.workspace(
                builder: (_) => const _Page('detail'),
              ),
            );
          },
          child: const Text('open'),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_x(tester, 'home'), lessThan(homeX - 1));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsNothing);
      expect(find.text('detail'), findsOneWidget);
      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(_x(tester, 'home'), closeTo(homeX, 0.01));
    });

    testWidgets('低档设备：只暗化、不视差', (tester) async {
      final navKey = await _pumpApp(tester, tier: MotionTier.low);
      final homeX = _x(tester, 'home');
      _push(navKey);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_x(tester, 'home'), closeTo(homeX, 0.01));
      await tester.pumpAndSettle();
    });

    testWidgets('减少动态效果：120ms 淡入，无位移', (tester) async {
      final navKey = await _pumpApp(tester, level: MotionLevel.reduced);
      final homeX = _x(tester, 'home');
      _push(navKey);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(_x(tester, 'detail'), closeTo(homeX, 0.01));
      expect(_x(tester, 'home'), closeTo(homeX, 0.01));
      expect(find.byType(FadeTransition), findsWidgets);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();
      expect(find.text('home'), findsNothing, reason: '120ms 内完成');
    });

    testWidgets('关闭动效：零时长直接到位', (tester) async {
      final navKey = await _pumpApp(tester, level: MotionLevel.off);
      _push(navKey);
      await tester.pump();
      await tester.pump();
      expect(find.text('home'), findsNothing);
      expect(find.text('detail'), findsOneWidget);
    });

    testWidgets('fade 档：下层保持不动', (tester) async {
      final navKey = await _pumpApp(tester);
      final homeX = _x(tester, 'home');
      _push(navKey, presentation: RoutePresentation.fade);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_x(tester, 'home'), closeTo(homeX, 0.01));
      expect(_x(tester, 'detail'), closeTo(homeX, 0.01));
      await tester.pumpAndSettle();
    });

    test('时长：进入 350ms，返回 250ms', () {
      final route =
          NexusPageRoute<void>.detail(builder: (_) => const SizedBox());
      expect(route.transitionDuration, NexusMotion.pageSpring);
      expect(route.reverseTransitionDuration, NexusMotion.page);
      expect(route.delegatedTransition, isNotNull);
      expect(
        NexusPageRoute<void>.fade(builder: (_) => const SizedBox())
            .delegatedTransition,
        isNull,
      );
    });
  });
}
