import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/desktop_preview_service.dart';
import 'package:mobile_agent/presentation/navigation/desktop_preview_panel.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DesktopPreviewServer.parseUrl enforces web safety contracts', () {
    // 1. 合法本地与远程地址
    expect(
        DesktopPreviewServer.parseUrl('http://localhost:3000').toString(),
        'http://localhost:3000');
    expect(
        DesktopPreviewServer.parseUrl('http://127.0.0.1:8080/index.html').toString(),
        'http://127.0.0.1:8080/index.html');
    expect(
        DesktopPreviewServer.parseUrl('https://example.com/demo').toString(),
        'https://example.com/demo');

    // 2. 危险与非 Web 协议拦截
    expect(() => DesktopPreviewServer.parseUrl('javascript:alert(1)'),
        throwsFormatException);
    expect(() => DesktopPreviewServer.parseUrl('file:///C:/Windows/System32'),
        throwsFormatException);
    expect(() => DesktopPreviewServer.parseUrl('data:text/html;base64,...'),
        throwsFormatException);

    // 3. 拦截携带账号凭据的伪装 URL
    expect(() => DesktopPreviewServer.parseUrl('http://admin:secret@malicious.com'),
        throwsFormatException);
  });

  testWidgets('DesktopPreviewPanel initial state shows server guidance',
      (tester) async {
    var projectTapped = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: DesktopTheme.apply(ThemeData(useMaterial3: true)),
          home: Scaffold(
            body: DesktopPreviewPanel(
              onProject: () => projectTapped = true,
              onTerminal: _noop,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 初始展示
    expect(find.textContaining('预览真实项目页面'), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-preview-address')), findsOneWidget);
    expect(find.byTooltip('打开预览地址'), findsOneWidget);

    // 无项目时提示选择项目
    final projectBtn = find.text('选择项目');
    expect(projectBtn, findsOneWidget);
    await tester.tap(projectBtn);
    expect(projectTapped, isTrue);
  });

  testWidgets('DesktopPreviewPanel rejects unsafe address with error message',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: DesktopTheme.apply(ThemeData(useMaterial3: true)),
          home: const Scaffold(
            body: DesktopPreviewPanel(
              onProject: _noop,
              onTerminal: _noop,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 输入非法协议
    final addressField = find.byKey(const ValueKey('desktop-preview-address'));
    await tester.enterText(addressField, 'javascript:void(0)');
    await tester.tap(find.byTooltip('打开预览地址'));
    await tester.pump();

    expect(find.textContaining('请输入完整的 http:// 或 https:// 地址'), findsOneWidget);
  });
}

void _noop() {}
