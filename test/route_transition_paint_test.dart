// 转场绘制的性能回归测试。
//
// 这套断言保护的是一个只能用「谁被光栅化」来验证的性能契约，而不是视觉结果：
// 整屏转场期间下层路由可见（视差 + 暗化），但只能以**快照**参与绘制——
// 整段转场最多重录 1~2 次（拍快照），之后每帧只改 layer transform。
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
  // 进入转场 350ms + 稳定若干帧。
  await _pumpFrames(tester, 26);
  return navKey;
}

void main() {
  group('NexusPageRoute 转场绘制', () {
    testWidgets('进入转场期间，下层以快照参与绘制，不逐帧重录', (tester) async {
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

      // 进入动画 350ms ≈ 22 帧，取 18 帧确保仍落在转场窗口内。
      final deltas = await _pumpDeltas(tester, 18);

      // 下层是活跃页（每帧变脏），如果没有快照这里会是 [1,1,1,...]。
      // 允许的重录只来自「拍快照」那一帧（以及路由包装层切换那一帧）。
      expect(
        deltas.reduce((a, b) => a + b),
        lessThanOrEqualTo(2),
        reason: '进入期间下层只允许拍快照时重录。deltas=$deltas',
      );
      expect(
        deltas.skip(2),
        everyElement(0),
        reason: '快照就绪后下层必须零重录：位移只改 transform。deltas=$deltas',
      );

      // 释放常驻动画，避免 ticker 泄漏。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('返回转场期间，下层以快照参与绘制；转场结束后恢复绘制', (tester) async {
      final navKey = await _pumpStack(tester);

      navKey.currentState!.pop();

      // 返回动画 250ms ≈ 15 帧，取 13 帧确保仍落在转场窗口内。
      final duringPop = await _pumpDeltas(tester, 13);

      // 下层在整个 push 稳态期间没被绘制过，返回时必须至少光栅化一次才能
      // 拍快照；之后整段只改 transform。如果这里接近帧数，说明下层快照失效，
      // 聊天页（全屏背景 + 消息列表 + 玻璃面板）会在返回期间逐帧重录。
      expect(
        duringPop.reduce((a, b) => a + b),
        lessThanOrEqualTo(2),
        reason: '返回期间下层只允许拍快照时重录。deltas=$duringPop',
      );
      expect(
        duringPop.skip(2),
        everyElement(0),
        reason: '快照就绪后下层必须零重录。deltas=$duringPop',
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

      // 返回动画 250ms ≈ 15 帧，取前 8 帧。
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
            '若这个数字接近帧数，说明上层 `_SnapshotWhile` 失效，'
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
      await _pumpFrames(tester, 20); // 走完 250ms 退出动画

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
