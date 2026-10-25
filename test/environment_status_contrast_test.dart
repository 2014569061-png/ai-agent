import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/environment_service.dart';
import 'package:mobile_agent/infrastructure/terminal/linux_runtime.dart';
import 'package:mobile_agent/presentation/environment/environment_status_view.dart';
import 'package:mobile_agent/presentation/theme/app_palette.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

// Pure display fixtures: no runtime inspection, command, model or device I/O.
EnvironmentSnapshot _snapshot() {
  const shell = LinuxRuntimeInfo(
    kind: LinuxRuntimeKind.androidShell,
    label: 'Android Shell',
    available: true,
    detail: 'Display-only fixture',
    supportsShellSyntax: true,
    supportsInteractive: false,
    supportsLiveOutput: false,
  );
  return EnvironmentSnapshot(
    selected: shell,
    candidates: const [
      LinuxRuntimeInfo(
        kind: LinuxRuntimeKind.builtinProot,
        label: 'Alpine',
        available: false,
        detail: 'Fixture unavailable',
      ),
      LinuxRuntimeInfo(
        kind: LinuxRuntimeKind.termux,
        label: 'Termux',
        available: false,
        detail: 'Fixture unavailable',
      ),
      shell,
    ],
    architecture: 'fixture',
    freeBytes: null,
    checkedAt: DateTime(2026, 10, 18),
    missingCapabilities: const ['fixture-missing-capability'],
    templates: const [],
    tools: const [
      EnvironmentToolStatus(
        id: 'git',
        label: 'Git',
        available: true,
        detail: 'Fixture available',
      ),
      EnvironmentToolStatus(
        id: 'flutter',
        label: 'Flutter',
        available: false,
        detail: 'Fixture required',
      ),
      EnvironmentToolStatus(
        id: 'docker',
        label: 'Docker',
        available: false,
        detail: 'Fixture optional',
        required: false,
      ),
      EnvironmentToolStatus(
        id: 'node',
        label: 'Node',
        available: false,
        detail: 'Fixture unprobed',
        probed: false,
      ),
    ],
  );
}

const _roles = <String, String>{
  'Alpine · 不可用': 'warning',
  'Termux · 不可用': 'warning',
  'Android Shell · 可用': 'success',
  '完整 Shell · 可用': 'success',
  '交互式终端 · 缺失': 'danger',
  '实时日志 · 缺失': 'danger',
  'Git · 可用': 'success',
  'Flutter · 缺失': 'danger',
  'Docker · 缺失': 'warning',
  'Node · 未探测': 'warning',
};

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

Future<void> _pump(
  WidgetTester tester, {
  required bool dark,
  bool highContrast = false,
  double width = 390,
  double scale = 1,
  bool compact = true,
  bool card = false,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final snapshot = _snapshot();
  final content = card
      ? EnvironmentStatusCard(snapshot: snapshot)
      : EnvironmentStatusView(
          snapshot: snapshot,
          compact: compact,
          toolIds: const {'git', 'flutter', 'docker', 'node'},
        );
  await tester.pumpWidget(MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        highContrast: highContrast,
        disableAnimations: true,
      ),
      child: child!,
    ),
    // A deliberately unrelated parent color detects translucent chip fills.
    home: Scaffold(
      backgroundColor: Colors.purple,
      body: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(16), child: content),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void _assertChips(
  WidgetTester tester, {
  required bool dark,
  bool highContrast = false,
  bool full = false,
  bool report = false,
}) {
  final labels = {..._roles};
  if (full) labels['缺失 · fixture-missing-capability'] = 'danger';
  final reported = <String>{};
  for (final entry in labels.entries) {
    final elements = find.text(entry.key).evaluate().toList();
    expect(elements, isNotEmpty,
        reason: 'State label must remain: ${entry.key}');
    for (final element in elements) {
      final text = element.widget as Text;
      Container? chip;
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget is Container && widget.decoration is BoxDecoration) {
          chip = widget;
          return false;
        }
        return true;
      });
      expect(chip, isNotNull);
      final decoration = chip!.decoration! as BoxDecoration;
      final background = decoration.color!;
      final foreground = text.style!.color!;
      expect(background.a, 1,
          reason: 'Stable fill independent of parent glass');
      expect(foreground.a, 1);
      expect(text.style!.fontSize, 12, reason: 'Do not shrink labels to fit');
      expect(text.softWrap, isTrue);
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      final ratio = _contrast(foreground, background);
      expect(ratio, greaterThanOrEqualTo(highContrast ? 7 : 4.5),
          reason: '${entry.key}: ${ratio.toStringAsFixed(4)}:1');
      final expectedBackground = switch ((dark, entry.value)) {
        (false, 'success') => AppPalette.lightSuccessSoft,
        (false, 'warning') => AppPalette.lightWarningSoft,
        (false, _) => AppPalette.lightDangerSoft,
        (true, 'success') => AppPalette.darkSuccessSoft,
        (true, 'warning') => AppPalette.darkWarningSoft,
        (true, _) => AppPalette.darkDangerSoft,
      };
      expect(background, expectedBackground);
      if (highContrast) {
        expect(foreground, dark ? AppPalette.darkText : AppPalette.lightText);
        expect(decoration.border, isNotNull);
      } else {
        expect(decoration.border, isNull);
      }
      if (report && reported.add(entry.value)) {
        debugPrint('CONTRAST dark=$dark highContrast=$highContrast '
            '${entry.value}: ${ratio.toStringAsFixed(4)}:1 '
            'fg=${foreground.toARGB32().toRadixString(16)} '
            'bg=${background.toARGB32().toRadixString(16)}');
      }
    }
  }
  expect(find.text('Node · 缺失'), findsNothing,
      reason: 'Unprobed must not be reported as missing');
  expect(tester.takeException(), isNull);
}

void main() {
  for (final dark in [false, true]) {
    for (final highContrast in [false, true]) {
      testWidgets('status contrast dark=$dark highContrast=$highContrast',
          (tester) async {
        await _pump(tester, dark: dark, highContrast: highContrast);
        _assertChips(tester,
            dark: dark, highContrast: highContrast, report: true);
      });
    }
    for (final width in [320.0, 360.0, 411.0]) {
      for (final scale in [1.0, 1.6, 2.0]) {
        testWidgets('status layout dark=$dark width=$width scale=$scale',
            (tester) async {
          await _pump(tester, dark: dark, width: width, scale: scale);
          _assertChips(tester, dark: dark);
          for (final label in _roles.keys) {
            final rect = tester.getRect(find.text(label));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
          }
        });
      }
    }
    testWidgets('high contrast narrow large text dark=$dark', (tester) async {
      await _pump(tester, dark: dark, highContrast: true, width: 320, scale: 2);
      _assertChips(tester, dark: dark, highContrast: true);
    });
    testWidgets('full status card keeps candidate and missing roles dark=$dark',
        (tester) async {
      await _pump(tester, dark: dark, compact: false, card: true);
      _assertChips(tester, dark: dark, full: true);
      expect(find.text('Git · 可用'), findsNWidgets(2));
    });
  }
  testWidgets('status colors follow live inherited theme changes',
      (tester) async {
    await _pump(tester, dark: false);
    _assertChips(tester, dark: false);
    await _pump(tester, dark: true);
    _assertChips(tester, dark: true);
    await _pump(tester, dark: false);
    _assertChips(tester, dark: false);
  });
}
