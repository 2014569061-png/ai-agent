import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/settings/provider_template_import_page.dart';

void main() {
  String template(String host) => jsonEncode({
        'schemaVersion': 1,
        'name': '本地模型',
        'baseUrl': host,
        'model': 'test',
        'protocol': 'openaiCompatible'
      });
  testWidgets('preview requires explicit consent and editing invalidates it',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(const MaterialApp(home: ProviderTemplateImportPage()));
    final input = find.byKey(const ValueKey('provider-template-input'));
    await tester.enterText(input, template('http://localhost:11434/v1'));
    await tester.tap(find.text('解析并预览'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不是你的电脑'), findsOneWidget);
    final next = find.byKey(const ValueKey('provider-template-continue'));
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
    await tester.ensureVisible(input);
    await tester.enterText(input, template('https://example.com/v1'));
    await tester.pumpAndSettle();
    expect(next, findsNothing);
    await tester.tap(find.text('解析并预览'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
  });
  testWidgets('invalid template is an actionable error, not an import',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: ProviderTemplateImportPage()));
    await tester.enterText(
        find.byType(TextField), '{"apiKey":"not-a-real-secret"}');
    await tester.tap(find.text('解析并预览'));
    await tester.pumpAndSettle();
    expect(find.textContaining('模板含未知字段'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('provider-template-continue')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
