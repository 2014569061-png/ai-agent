import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/presentation/settings/settings_page.dart';
import 'package:mobile_agent/presentation/settings/provider_detail_page.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/app_appearance_controller.dart';

class _InMemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> _store = {};
  @override
  Future<void> write(
          {required String key,
          required String value,
          required Map<String, String> options}) async =>
      _store[key] = value;
  @override
  Future<String?> read(
          {required String key, required Map<String, String> options}) async =>
      _store[key];
  @override
  Future<void> delete(
          {required String key, required Map<String, String> options}) async =>
      _store.remove(key);
  @override
  Future<bool> containsKey(
          {required String key, required Map<String, String> options}) async =>
      _store.containsKey(key);
  @override
  Future<Map<String, String>> readAll(
          {required Map<String, String> options}) async =>
      Map.of(_store);
  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      _store.clear();
}

void main() {
  late double previous;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
    previous = AppAppearanceController.glassIntensity.value;
    AppAppearanceController.glassIntensity.value = 0;
  });
  tearDown(() => AppAppearanceController.glassIntensity.value = previous);
  Future<void> pump(
      WidgetTester tester, Widget page, bool dark, double scale) async {
    tester.view.physicalSize = const Size(360, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: child!,
      ),
      home: const Scaffold(),
      initialRoute: '/detail',
      routes: {'/detail': (_) => page},
    )));
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('settings back hit region dark=$dark scale=$scale',
          (tester) async {
        await pump(tester, const SettingsPage(), dark, scale);
        final button =
            find.widgetWithIcon(IconButton, Icons.arrow_back_ios_new_rounded);
        expect(button, findsOneWidget);
        final size = tester.getSize(button);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      });
      testWidgets(
          'provider action slots grow with text dark=$dark scale=$scale',
          (tester) async {
        // Blank configuration, memory-only storage; never press test/save.
        await pump(tester, const ProviderDetailPage(), dark, scale);
        for (final finder in [
          find.widgetWithText(OutlinedButton, '测试连接'),
          find.widgetWithText(FilledButton, '保存并启用')
        ]) {
          expect(finder, findsOneWidget);
          final size = tester.getSize(finder);
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
