import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/chat/widgets/provider_setup_hint.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  Future<void> pumpHint(
    WidgetTester tester, {
    required Future<void> Function() onConfigure,
    double textScale = 1.0,
  }) async {
    const size = Size(360, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(size: size)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: ProviderSetupHint(onConfigure: onConfigure),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('点击去配置会调用 Provider 配置入口', (tester) async {
    var calls = 0;
    await pumpHint(tester, onConfigure: () async => calls++);

    expect(find.text('还没有配置模型服务'), findsOneWidget);
    expect(find.text('配置 API Key 或连接本地模型后即可发送消息'), findsOneWidget);

    await tester.tap(find.text('去配置'));
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('关闭按钮隐藏当前引导条', (tester) async {
    await pumpHint(tester, onConfigure: () async {});

    expect(find.text('还没有配置模型服务'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭模型配置引导'));
    await tester.pumpAndSettle();

    expect(find.text('还没有配置模型服务'), findsNothing);
  });

  testWidgets('配置按钮执行期间避免重复提交', (tester) async {
    final completer = Completer<void>();
    var calls = 0;
    await pumpHint(
      tester,
      onConfigure: () {
        calls++;
        return completer.future;
      },
    );

    await tester.tap(find.text('去配置'));
    await tester.pump();
    expect(calls, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
      reason: '执行期间按钮应禁用，避免重复提交',
    );
    completer.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('360x800 大字模式下引导条不溢出', (tester) async {
    await pumpHint(
      tester,
      onConfigure: () async {},
      textScale: 1.3,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('还没有配置模型服务'), findsOneWidget);
    expect(find.byTooltip('关闭模型配置引导'), findsOneWidget);
  });
}
