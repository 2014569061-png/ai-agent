import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/presentation/chat/widgets/model_picker_sheet.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  testWidgets('model picker supports search and selection', (tester) async {
    const profiles = [
      ProviderConfig(
        id: 'openai',
        name: '常用模型',
        baseUrl: 'https://example.com/v1',
        model: 'gpt-5.6-terra',
        apiKey: 'key',
      ),
      ProviderConfig(
        id: 'local',
        name: '本地模型',
        baseUrl: 'http://localhost:11434/v1',
        model: 'qwen3',
        apiKey: '',
      ),
    ];

    ModelPickerSelection? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showModalBottomSheet<ModelPickerSelection>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const ModelPickerSheet(
                  profiles: profiles,
                  selectedId: 'openai',
                  reasoningEffort: ReasoningEffort.medium,
                  planMode: false,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('选择模型'), findsOneWidget);
    expect(find.text('gpt-5.6-terra'), findsOneWidget);
    expect(find.text('聊天'), findsAtLeastNWidgets(1));
    expect(find.text('Agent'), findsAtLeastNWidgets(1));
    expect(find.text('计划'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), 'qwen');
    await tester.pump();
    expect(find.text('qwen3'), findsOneWidget);
    expect(find.text('gpt-5.6-terra'), findsNothing);

    await tester.tap(find.text('qwen3'));
    await tester.pumpAndSettle();
    expect(result?.profile.id, 'local');
    expect(result?.mode, ChatMode.chat);
    expect(tester.takeException(), isNull);
  });

  testWidgets('model picker keeps Agent and plan as distinct modes',
      (tester) async {
    const profiles = [
      ProviderConfig(
        id: 'openai',
        name: '常用模型',
        baseUrl: 'https://example.com/v1',
        model: 'gpt-5.6-terra',
        apiKey: 'key',
      ),
    ];
    ModelPickerSelection? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showModalBottomSheet<ModelPickerSelection>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const ModelPickerSheet(
                  profiles: profiles,
                  selectedId: 'openai',
                  reasoningEffort: ReasoningEffort.auto,
                  planMode: false,
                  mode: ChatMode.chat,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agent'));
    await tester.tap(find.text('gpt-5.6-terra'));
    await tester.pumpAndSettle();

    expect(result?.mode, ChatMode.agent);
    expect(result?.planMode, isFalse);
  });
}
