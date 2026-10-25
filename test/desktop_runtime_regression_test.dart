import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config_store.dart';
import 'package:mobile_agent/presentation/agents/agent_editor_page.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_loading_skeleton.dart';
import 'package:mobile_agent/presentation/widgets/section_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyProviderStore extends ProviderConfigStore {
  @override
  Future<ProviderConfig> load() async =>
      const ProviderConfig(baseUrl: '', model: '', apiKey: '');
}

Widget _host(Widget child, {bool desktop = true}) => MaterialApp(
      theme: desktop ? DesktopTheme.apply(AppTheme.light()) : AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: child,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // A source guard supplements the fresh Windows startup smoke check. Calling
  // production main from testWidgets cannot prove this: its binding already
  // belongs to the test runner, which deliberately overrides zone checking.
  test('production binding initialization stays inside the guarded app zone',
      () {
    final source = File('lib/main.dart').readAsStringSync();
    final entry = source.indexOf('void main() {');
    final zone = source.indexOf('runZonedGuarded(', entry);
    final initialize =
        source.indexOf('WidgetsFlutterBinding.ensureInitialized();', entry);
    final systemUi =
        source.indexOf('SystemChrome.setEnabledSystemUIMode(', entry);
    final launch = source.indexOf('runApp(', zone);
    expect(entry, greaterThanOrEqualTo(0));
    expect(zone, greaterThan(entry));
    expect(initialize, greaterThan(zone));
    expect(systemUi, greaterThan(initialize));
    expect(launch, greaterThan(systemUi));
  });

  testWidgets('bounded list skeleton retains its viewport and row count',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(const Scaffold(
      body: SizedBox(
        width: 400,
        height: 320,
        child: NexusListSkeleton(itemCount: 3),
      ),
    )));
    expect(tester.takeException(), isNull);
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.shrinkWrap, isFalse);
    expect(
        tester.getSize(find.byType(NexusListSkeleton)), const Size(400, 320));
    expect(find.byType(NexusSkeletonLine), findsNWidgets(9));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final semantics in [false, true]) {
    testWidgets(
        'nested list skeleton handles unbounded height, semantics=$semantics',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final handle = semantics ? tester.ensureSemantics() : null;
      try {
        expect(tester.binding.semanticsEnabled, semantics);
        await tester.pumpWidget(_host(Scaffold(
          body: ListView(
            children: const [
              Text('Before loading tools'),
              SectionCard(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: NexusListSkeleton(itemCount: 3),
                ),
              ),
              Text('After loading tools'),
            ],
          ),
        )));
        expect(tester.takeException(), isNull);
        final nested = tester.widget<ListView>(find.byType(ListView).last);
        expect(nested.shrinkWrap, isTrue);
        expect(nested.primary, isFalse);
        expect(find.text('After loading tools'), findsOneWidget);
        expect(find.byType(NexusSkeletonLine), findsNWidgets(9));
        final size = tester.getSize(find.byType(NexusListSkeleton));
        expect(size.height.isFinite, isTrue);
        expect(size.height, greaterThan(100));
        expect(size.height, lessThan(400));
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      } finally {
        handle?.dispose();
      }
    }, semanticsEnabled: semantics);
  }

  for (final desktop in [true, false]) {
    testWidgets(
        'Agent editor first frame waits for tools safely, desktop=$desktop',
        (tester) async {
      await tester.binding.setSurfaceSize(
          desktop ? const Size(1280, 800) : const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final handle = tester.ensureSemantics();
      try {
        expect(tester.binding.semanticsEnabled, isTrue);
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final pending = Completer<AppDatabase>();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            databaseProvider.overrideWith((ref) => pending.future),
            providerConfigStoreProvider
                .overrideWithValue(_EmptyProviderStore()),
          ],
          child: _host(const AgentEditorPage(), desktop: desktop),
        ));
        // Keep the async database unresolved while the loading card enters the
        // outer lazy viewport. A settled-data screenshot misses this first frame.
        final outer = find.byType(ListView).first;
        await tester.drag(outer, const Offset(0, -580));
        await tester.pump();
        expect(find.byType(NexusListSkeleton), findsOneWidget);
        expect(tester.takeException(), isNull);
        final skeletonList = tester.widget<ListView>(find.descendant(
            of: find.byType(NexusListSkeleton),
            matching: find.byType(ListView)));
        expect(skeletonList.shrinkWrap, isTrue);
        expect(find.text('保存智能体'), findsOneWidget);
        expect(await db.select(db.agents).get(), isEmpty);

        pending.complete(db);
        await tester.pumpAndSettle();
        expect(find.byType(NexusListSkeleton), findsNothing);
        expect(find.byType(CheckboxListTile), findsWidgets);
        expect(tester.takeException(), isNull);
        // Opening, loading and dismissing a new form must not save an Agent.
        expect(await db.select(db.agents).get(), isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    });
  }
}
