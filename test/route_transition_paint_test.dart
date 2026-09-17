// 转场绘制的性能回归测试。
//
// 这套断言保护的是一个只能用「谁被光栅化」来验证的性能契约，而不是视觉结果：
// 转场期间下层路由必须完全不参与绘制。
//
// 验证手段：`CustomPainter.paint` 只在宿主 layer 真正被重录时执行。如果上层
// 路由的 `modalBarrier` 是 opaque，`Overlay` 会把下层整个跳过（不计入
// `_Theatre` 的 onstage 集合），计数就不会增长。因此「计数增量 == 0」精确等价于
// 「下层没有被光栅化」。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/nexus_page_route_factory.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

int _paints = 0;
int _upperPaints = 0;

class _CountingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    _paints++;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0x11000000),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 上层页面里的计数画笔。返回期间它应该最多只被调用一次。
class _CountingUpperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    _upperPaints++;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0x11000000),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 静态首页：没有任何常驻动画。
///
/// 用来隔离「位移本身是否触发重绘」这个变量——实测它是 `[0]*N`，
/// 证明 `SlideTransition` 只改 layer 的 transform，不会让子树变脏。
class _StaticHome extends StatelessWidget {
  const _StaticHome();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(child: Text('home')),
    );
  }
}

/// 活跃详情页：内部有常驻动画 + 一个 BackdropFilter 面板。
///
/// 这模拟真实的上层页面（例如带实时内容或玻璃顶栏的设置页）。
/// 它是「逐帧重绘」的触发源：内容每帧变脏 → 整页重录。
class _LiveDetail extends StatefulWidget {
  const _LiveDetail();

  @override
  State<_LiveDetail> createState() => _LiveDetailState();
}

class _LiveDetailState extends State<_LiveDetail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _ticker,
        builder: (context, _) => Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _CountingUpperPainter()),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  height: 56,
                  color: Colors.white.withValues(alpha: 0.6),
                  alignment: Alignment.center,
                  child: Text('bar ${_ticker.value.toStringAsFixed(2)}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 模拟聊天页：有持续变化的内容（流式增量、光标），且**没有** RepaintBoundary
/// 隔离，所以顶层边界层会一直处于脏状态。
///
/// 这正是被返回操作打中的那种下层页面：它在整个 push 期间都被跳过绘制，
/// `_needsPaint` 始终为脏；一旦允许恢复，第一帧就要把整棵子树重新光栅化。
class _LiveHome extends StatefulWidget {
  const _LiveHome();

  @override
  State<_LiveHome> createState() => _LiveHomeState();
}

class _LiveHomeState extends State<_LiveHome>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _ticker,
        builder: (context, _) => Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _CountingPainter())),
            Center(child: Text('home ${_ticker.value.toStringAsFixed(2)}')),
          ],
        ),
      ),
    );
  }
}

Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// 逐帧推进并返回每一帧的绘制增量。
Future<List<int>> _pumpDeltas(WidgetTester tester, int count) async {
  final deltas = <int>[];
  var previous = _paints;
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    deltas.add(_paints - previous);
    previous = _paints;
  }
  return deltas;
}

/// 建好「活跃首页 + 已就位的详情页」这个栈，返回 navigator key。
Future<GlobalKey<NavigatorState>> _pumpStack(WidgetTester tester) async {
  _paints = 0;
  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navKey,
      theme: AppTheme.light(),
      home: const _LiveHome(),
    ),
  );
  await _pumpFrames(tester, 8);

  navKey.currentState!.push(
    NexusPageRoute.workspace(
      builder: (_) => const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: Text('detail')),
      ),
    ),
  );
  // 进入转场 220ms + 稳定若干帧。
  await _pumpFrames(tester, 20);
  return navKey;
}

void main() {
  group('NexusPageRoute 转场绘制', () {
    testWidgets('进入转场期间，下层页面不参与绘制', (tester) async {
      _paints = 0;
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          theme: AppTheme.light(),
          home: const _LiveHome(),
        ),
      );
      await _pumpFrames(tester, 8);

      navKey.currentState!.push(
        NexusPageRoute.workspace(
          builder: (_) => const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: Text('detail')),
          ),
        ),
      );

      final deltas = await _pumpDeltas(tester, 12);

      // 第 1 帧允许 1 次：下层在「被跳过」之前的那一帧还是 attached 的，
      // 它的最后一次变脏会触发一次 `repaintCompositedChild`（重录结果不会进入
      // 合成，因为此时它已经不在 onstage 集合里）。从第 2 帧起 layer 已 detach，
      // 一切 `markNeedsPaint` 都走 `_skippedPaintingOnLayer`，不再产生绘制。
      expect(deltas.first, lessThanOrEqualTo(1));
      expect(
        deltas.take(2),
        everyElement(lessThanOrEqualTo(1)),
        reason: '新页面完成首帧合成前最多允许一次下层兜底绘制。deltas=$deltas',
      );
      expect(
        deltas.skip(2),
        everyElement(0),
        reason: '进入动画进入稳定段后，下层必须保持零绘制：否则两层内容同框，'
            '玻璃面板还会把下层文字折进卡片。deltas=$deltas',
      );

      // 释放常驻动画，避免 ticker 泄漏。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('返回转场期间，下层页面零绘制；转场结束后恢复绘制', (tester) async {
      final navKey = await _pumpStack(tester);

      navKey.currentState!.pop();

      // 返回动画 150ms ≈ 9 帧，取 8 帧确保仍落在转场窗口内。
      final duringPop = await _pumpDeltas(tester, 8);

      expect(
        duringPop,
        everyElement(0),
        reason: '返回动画期间下层必须零绘制。下层在整个 push 期间没被绘制过，'
            '第一帧恢复就要重新光栅化整棵页面（聊天页里是全屏背景图 + 消息列表 + '
            '两处玻璃面板），而这一帧还压着上层退出动画的绘制，必然掉帧。'
            '如果这里不再是 0，说明 NexusPageRoute 丢掉了返回方向的遮挡维持。'
            'deltas=$duringPop',
      );

      // 反向保护：压制必须是「转场期间」的，不能把下层永久冻住。
      final afterPop = await _pumpDeltas(tester, 6);
      expect(
        afterPop.reduce((a, b) => a + b),
        greaterThan(0),
        reason: '转场结束后下层必须恢复绘制，否则返回后会停在残影上。'
            'deltas=$afterPop',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('返回转场期间，上层页面自身只绘制一次（快照替代逐帧重绘）', (tester) async {
      _upperPaints = 0;
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          theme: AppTheme.light(),
          home: const _StaticHome(),
        ),
      );
      await _pumpFrames(tester, 8);

      navKey.currentState!.push(
        NexusPageRoute.workspace(builder: (_) => const _LiveDetail()),
      );
      await _pumpFrames(tester, 24);

      _upperPaints = 0;
      navKey.currentState!.pop();

      // 返回动画 150ms ≈ 9 帧。
      final duringPop = await _pumpDeltas(tester, 8);
      final upperDuringPop = _upperPaints;

      // 唯一的绘制来自「拍摄快照」本身。如果没有快照，活跃上层（内部有常驻
      // 动画 + BackdropFilter）会在返回期间每一帧都重录一次整页（实测 8~10 次），
      // 而这段位移里那些重录在视觉上完全不可见——`SlideTransition` 只改 layer 的
      // transform，本身不触发重绘。
      expect(
        upperDuringPop,
        lessThanOrEqualTo(1),
        reason: '返回期间上层页面最多允许一次绘制（拍快照）。'
            '若这个数字接近帧数，说明 `_SnapshotOnExit` 失效，'
            '每帧都在重录整页（含所有 BackdropFilter 与折射着色器）。'
            'deltas=$duringPop upperPaints=$upperDuringPop',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('快照只在返回期间生效：转场结束后页面必须恢复真实绘制', (tester) async {
      // 三层栈：静态首页 → 活跃页(存活) → 临时页。pop 掉临时页后，
      // 那个活跃页重新成为栈顶，必须恢复逐帧真实绘制——否则它的内容会被
      // 永久冻结在快照上（进度条不动、光标不闪）。
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          theme: AppTheme.light(),
          home: const _StaticHome(),
        ),
      );
      await _pumpFrames(tester, 8);

      navKey.currentState!.push(
        NexusPageRoute.workspace(builder: (_) => const _LiveDetail()),
      );
      await _pumpFrames(tester, 24);

      navKey.currentState!.push(
        NexusPageRoute.workspace(
          builder: (_) => const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: Text('temp')),
          ),
        ),
      );
      await _pumpFrames(tester, 24);

      navKey.currentState!.pop();
      await _pumpFrames(tester, 16); // 走完 150ms 退出动画

      _upperPaints = 0;
      await _pumpFrames(tester, 8);
      expect(
        _upperPaints,
        greaterThan(0),
        reason: '转场结束后活动页必须恢复真实绘制，否则内容被永久冻结在快照上。',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
