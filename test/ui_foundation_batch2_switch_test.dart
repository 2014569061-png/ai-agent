import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_switch.dart';
import 'package:mobile_agent/presentation/settings/settings_components.dart';
import 'package:mobile_agent/presentation/widgets/nexus_list_tile.dart';

Widget host(Widget Function(bool, ValueChanged<bool>) make,
    {bool dark = false, bool desktop = false, double scale = 1}) {
  var value = false;
  final theme = dark ? AppTheme.dark() : AppTheme.light();
  return MaterialApp(
      theme: desktop ? DesktopTheme.apply(theme) : theme,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale), disableAnimations: true),
          child: child!),
      home: Scaffold(
          body: Center(
              child: StatefulBuilder(
                  builder: (context, set) =>
                      make(value, (next) => set(() => value = next))))));
}

void main() {
  for (final dark in [false, true]) {
    for (final desktop in [false, true]) {
      testWidgets('switch hit slot preserves track dark=$dark desktop=$desktop',
          (t) async {
        await t.pumpWidget(host(
            (v, set) => NexusSwitch(value: v, onChanged: set),
            dark: dark,
            desktop: desktop));
        expect(
            t.getSize(find.byType(NexusSwitch)), Size(60, desktop ? 40 : 48));
        expect(t.getSize(find.byKey(const ValueKey('nexus_switch_track'))),
            const Size(52, 32));
        expect(t.takeException(), isNull);
      });
    }
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'list tile switch is not scaled below48 dark=$dark scale=$scale',
          (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(320, 800);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.view.resetPhysicalSize);
        var calls = 0;
        await t.pumpWidget(host(
            (v, set) => NexusListTile(
                title: '独立列表开关的完整名称',
                switchValue: v,
                onChanged: (n) {
                  calls++;
                  set(n);
                }),
            dark: dark,
            scale: scale));
        final finder = find.byType(NexusSwitch), r = t.getRect(finder);
        expect(r.width, greaterThanOrEqualTo(48));
        expect(r.height, greaterThanOrEqualTo(48));
        expect(t.getSize(find.byKey(const ValueKey('nexus_switch_track'))),
            const Size(52, 32));
        await t.tapAt(Offset(r.center.dx, r.bottom - 1));
        await t.pumpAndSettle();
        expect(calls, 1);
        expect(t.widget<NexusSwitch>(finder).value, isTrue);
        expect(t.widget<NexusSwitch>(finder).semanticLabel, '独立列表开关的完整名称');
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets('Space Enter numpadEnter activate once with visible focus',
      (t) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    final old = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = old);
    var calls = 0;
    await t.pumpWidget(host((v, set) => NexusSwitch(
        value: v,
        onChanged: (n) {
          calls++;
          set(n);
        },
        focusNode: node,
        autofocus: true,
        semanticLabel: '键盘开关')));
    await t.pumpAndSettle();
    expect(node.hasFocus, isTrue);
    for (final key in [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter
    ]) {
      await t.sendKeyEvent(key);
      await t.pumpAndSettle();
    }
    expect(calls, 3);
    expect(t.widget<NexusSwitch>(find.byType(NexusSwitch)).value, isTrue);
    final decoration = t
        .widget<DecoratedBox>(
            find.byKey(const ValueKey('nexus_switch_focus_ring')))
        .decoration as BoxDecoration;
    expect((decoration.border! as Border).top.color, isNot(Colors.transparent));
    expect(t.takeException(), isNull);
  });
  testWidgets('disabled switch cannot focus or activate', (t) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await t.pumpWidget(host((v, set) => NexusSwitch(
        value: v, onChanged: null, focusNode: node, autofocus: true)));
    await t.pumpAndSettle();
    expect(node.hasFocus, isFalse);
    await t.tap(find.byType(NexusSwitch));
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(t.widget<NexusSwitch>(find.byType(NexusSwitch)).value, isFalse);
    expect(t.takeException(), isNull);
  });
  testWidgets('switch exposes label state and one accessibility activation',
      (t) async {
    final handle = t.ensureSemantics();
    try {
      var calls = 0;
      await t.pumpWidget(host((v, set) => NexusSwitch(
          value: v,
          onChanged: (n) {
            calls++;
            set(n);
          },
          semanticLabel: '独立开关')));
      await t.pumpAndSettle();
      var node = t.getSemantics(find.bySemanticsLabel('独立开关'));
      expect(
          node,
          matchesSemantics(
              label: '独立开关',
              hasEnabledState: true,
              isEnabled: true,
              hasToggledState: true,
              isFocusable: true,
              hasTapAction: true));
      node.owner!.performAction(node.id, ui.SemanticsAction.tap);
      await t.pumpAndSettle();
      expect(calls, 1);
      node = t.getSemantics(find.bySemanticsLabel('独立开关'));
      expect(
          node,
          matchesSemantics(
              label: '独立开关',
              hasEnabledState: true,
              isEnabled: true,
              hasToggledState: true,
              isToggled: true,
              isFocusable: true,
              hasTapAction: true));
    } finally {
      handle.dispose();
    }
  });
  testWidgets('disabled semantics has no activation', (t) async {
    final handle = t.ensureSemantics();
    try {
      await t.pumpWidget(host((v, set) =>
          NexusSwitch(value: v, onChanged: null, semanticLabel: '禁用开关')));
      await t.pumpAndSettle();
      expect(
          t.getSemantics(find.bySemanticsLabel('禁用开关')),
          matchesSemantics(
              label: '禁用开关', hasEnabledState: true, hasToggledState: true));
    } finally {
      handle.dispose();
    }
  });
  testWidgets('whole row tail semantics and keyboard each toggle once',
      (t) async {
    final handle = t.ensureSemantics();
    try {
      var calls = 0;
      await t.pumpWidget(host((v, set) => NexusSwitchListTile(
          title: const Text('整行开关'),
          value: v,
          onChanged: (n) {
            calls++;
            set(n);
          })));
      await t.pumpAndSettle();
      await t.tap(find.text('整行开关'));
      await t.pumpAndSettle();
      expect(calls, 1);
      await t.tap(find.byType(NexusSwitch));
      await t.pumpAndSettle();
      expect(calls, 2);
      final node = t.getSemantics(find.bySemanticsLabel('整行开关'));
      node.owner!.performAction(node.id, ui.SemanticsAction.tap);
      await t.pumpAndSettle();
      expect(calls, 3);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pumpAndSettle();
      expect(calls, 4);
      expect(t.widget<NexusSwitch>(find.byType(NexusSwitch)).value, isFalse);
      expect(t.takeException(), isNull);
    } finally {
      handle.dispose();
    }
  });
  testWidgets('disabled whole row and tail do not change value', (t) async {
    await t.pumpWidget(host((v, set) => NexusSwitchListTile(
        title: const Text('不可切换'), value: v, onChanged: null)));
    await t.tap(find.text('不可切换'));
    await t.tap(find.byType(NexusSwitch));
    await t.pumpAndSettle();
    expect(t.widget<NexusSwitch>(find.byType(NexusSwitch)).value, isFalse);
    expect(t.takeException(), isNull);
  });
  testWidgets('generic list row does not also fire when tail wins gesture',
      (t) async {
    var row = 0, tail = 0;
    await t.pumpWidget(host((v, set) => NexusListTile(
        title: '分别命中',
        switchValue: v,
        onChanged: (n) {
          tail++;
          set(n);
        },
        onTap: () {
          row++;
          set(!v);
        })));
    await t.tap(find.byType(NexusSwitch));
    await t.pumpAndSettle();
    expect(tail, 1);
    expect(row, 0);
    await t.tap(find.text('分别命中'));
    await t.pumpAndSettle();
    expect(tail, 1);
    expect(row, 1);
    expect(t.takeException(), isNull);
  });
  testWidgets('drag switches once', (t) async {
    var calls = 0;
    await t.pumpWidget(host((v, set) => NexusSwitch(
        value: v,
        onChanged: (n) {
          calls++;
          set(n);
        })));
    await t.drag(find.byType(NexusSwitch), const Offset(45, 0));
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(t.widget<NexusSwitch>(find.byType(NexusSwitch)).value, isTrue);
    expect(t.takeException(), isNull);
  });
  testWidgets('cancelled drag returns to controlled value', (t) async {
    var calls = 0;
    await t.pumpWidget(host((v, set) => NexusSwitch(
        value: v,
        onChanged: (n) {
          calls++;
          set(n);
        })));
    final original =
        t.getCenter(find.byKey(const ValueKey('nexus_switch_thumb'))).dx;
    final gesture = await t.startGesture(t.getCenter(find.byType(NexusSwitch)));
    await gesture.moveBy(const Offset(25, 0));
    await t.pump();
    await gesture.cancel();
    await t.pumpAndSettle();
    expect(calls, 0);
    expect(t.getCenter(find.byKey(const ValueKey('nexus_switch_thumb'))).dx,
        closeTo(original, .1));
    expect(t.takeException(), isNull);
  });
  for (final desktop in [false, true]) {
    testWidgets('settings wrapper preserves mobile hit area desktop=$desktop',
        (t) async {
      var calls = 0;
      await t.pumpWidget(host(
          (v, set) => SettingsSwitch(
              value: v,
              onChanged: (n) {
                calls++;
                set(n);
              }),
          desktop: desktop));
      final r = t.getRect(find.byType(SettingsSwitch));
      expect(r.height, desktop ? 28 : 48);
      if (!desktop) {
        expect(r.width, greaterThanOrEqualTo(48));
        await t.tapAt(Offset(r.center.dx, r.bottom - 1));
        await t.pumpAndSettle();
        expect(calls, 1);
      }
      expect(t.takeException(), isNull);
    });
  }
}
