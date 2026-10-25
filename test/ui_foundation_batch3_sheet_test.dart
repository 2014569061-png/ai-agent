import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/infrastructure/providers/tool_trust_store.dart';
import 'package:mobile_agent/presentation/settings/tool_list_page.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/app_palette.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_sheet.dart';

// Exact current built-in descriptions/policies, not shortened test substitutes.
const samples = [
  (
    name: "android_device",
    title: "Android 设备控制",
    description: "控制应用、文件、网络与系统设置；变更前提供只读预览，并按 action 风险审批。",
    policy: "Root、危险系统开关、网络规则与不可逆操作需逐次明确批准；Root 变更须先预览。"
  ),
  (
    name: "android_automation",
    title: "Android 设备自动化",
    description: "创建定时、连上 Wi-Fi、低电量触发的设备自动化规则；触发后只发通知，由你确认后执行。",
    policy: "创建/启用规则需确认；含 Root 或不可撤销动作的规则按危险操作审批。每次执行仍需在通知中确认。"
  ),
  (
    name: "web_search",
    title: "网页搜索 (Web Search)",
    description: "使用搜索引擎检索互联网实时信息与文档。",
    policy: "安全工具，已配置 Key 时自动执行。"
  ),
  (
    name: "http_request",
    title: "HTTP 请求 (HTTP Request)",
    description: "向指定 URL 发起 HTTP GET/POST 网络请求，具备外部副作用。",
    policy: "高危网络操作，每次调用均需用户手动审批。"
  ),
  (
    name: "calculator",
    title: "数学计算器 (Calculator)",
    description: "对数字进行精确加减乘除与数学公式求值。",
    policy: "安全纯函数，无需审批自动执行。"
  ),
  (
    name: "get_time",
    title: "获取本地时间 (Get Time)",
    description: "读取当前系统的本地日期与时间。",
    policy: "安全只读接口，自动执行。"
  ),
  (
    name: "json_query",
    title: "JSON 字段解析 (JSON Query)",
    description: "按点号路径提取 JSON 文本中的键值内容。",
    policy: "安全数据解析，自动执行。"
  ),
  (
    name: "read_file",
    title: "读取文件 (Read File)",
    description: "从当前工作区沙箱读取文本文件内容。",
    policy: "沙箱内只读操作，自动放行。"
  ),
  (
    name: "write_file",
    title: "写入文件 (Write File)",
    description: "向工作区指定路径写入新文件或全量覆盖。",
    policy: "写文件操作，按当前审批策略确认后执行。"
  ),
  (
    name: "edit_file",
    title: "编辑文件 (Edit File)",
    description: "针对已有文件执行精确的代码块或文本替换。",
    policy: "代码与文本修改，需要审批或信任放行。"
  ),
  (
    name: "delete_file",
    title: "删除文件 (Delete File)",
    description: "从工作区永久删除指定文件。",
    policy: "不可逆高危破坏性操作，强制单次逐条审批。"
  ),
  (
    name: "move_file",
    title: "移动/重命名 (Move File)",
    description: "在工作区内移动文件或变更文件名。",
    policy: "文件结构调整，按当前审批策略控制。"
  ),
  (
    name: "list_directory",
    title: "列出目录 (List Directory)",
    description: "枚举工作区或子目录中的文件与文件夹树。",
    policy: "沙箱内只读枚举，自动放行。"
  ),
  (
    name: "search_files",
    title: "文件搜索 (Search Files)",
    description: "在工作区内根据关键字进行文件名与内容检索。",
    policy: "沙箱只读搜索，自动放行。"
  ),
  (
    name: "terminal",
    title: "终端命令执行 (Terminal Command)",
    description: "在 Termux 或系统环境中执行 Shell 脚本与系统命令。cwd 不是完整沙箱边界。",
    policy: "默认始终需要确认；完全访问模式下终端可自动执行。cwd 不是完整沙箱。"
  ),
  (
    name: "remember",
    title: "长期记忆写入 (Remember)",
    description: "将用户偏好或关键上下文持久化写入长期记忆库。",
    policy: "用户偏好存储，安全自动放行。"
  ),
  (
    name: "sub_agent",
    title: "子任务自主委派 (Sub Agent)",
    description: "派生独立的子 Agent 无 UI 处理耗时计算或搜索任务。",
    policy: "受「自主委派」总开关控制；关闭时需逐次确认。"
  ),
  (
    name: "generate_image",
    title: "图像生成 (Generate Image)",
    description: "调用绘图模型生成高质量视觉图片与设计资产。",
    policy: "需要配置对应模型或服务端点。"
  ),
];
const initialPreferences = <String, Object>{
  'settings.tool.workspace_files': false,
  'settings.tool.terminal': false,
  'settings.tool.auto_verification': false,
};
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(initialPreferences));
  Future<void> detail(WidgetTester t, String name,
      {bool dark = false,
      Size size = const Size(320, 568),
      double scale = 2,
      double inset = 0,
      bool desktop = false,
      bool keyboard = false}) async {
    final sample = samples.singleWhere((s) => s.name == name);
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    final insets = ValueNotifier<double>(0);
    addTearDown(insets.dispose);
    final store = ToolTrustStore();
    await store.init();
    var databaseReads = 0;
    final theme = dark ? AppTheme.dark() : AppTheme.light();
    await t.pumpWidget(ProviderScope(
        overrides: [
          toolTrustStoreProvider.overrideWith((ref) async => store),
          databaseProvider.overrideWith((ref) async {
            databaseReads++;
            throw StateError('Database forbidden in detail-only fixture');
          }),
        ],
        child: MaterialApp(
            theme: desktop ? DesktopTheme.apply(theme) : theme,
            builder: (context, child) => ValueListenableBuilder<double>(
                valueListenable: insets,
                builder: (context, bottom, _) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        viewInsets: EdgeInsets.only(bottom: bottom),
                        disableAnimations: true),
                    child: child!)),
            home: const ToolListPage())));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text(sample.title), 300,
        scrollable: find.byType(Scrollable).first, maxScrolls: 60);
    await t.pumpAndSettle();
    await t.tap(find.text(sample.title));
    await t.pumpAndSettle();
    if (inset > 0) {
      insets.value = inset;
      await t.pumpAndSettle();
    }
    final body = find.byKey(const ValueKey('tool-detail-body'));
    final close = find.widgetWithText(FilledButton, '我知道了');
    expect(body, findsOneWidget);
    expect(close, findsOneWidget);
    expect(t.takeException(), isNull);
    expect(MediaQuery.viewInsetsOf(t.element(body)).bottom, 0);
    final policy = find.byKey(const ValueKey('tool-detail-policy'));
    final background =
        (t.widget<Container>(policy).decoration! as BoxDecoration).color!;
    expect(background.a, 1);
    expect(background, dark ? AppPalette.darkSurface : AppPalette.lightSurface);
    for (final text in t.widgetList<Text>(
        find.descendant(of: policy, matching: find.byType(Text)))) {
      final foreground = Color.alphaBlend(text.style!.color!, background);
      final a = foreground.computeLuminance(),
          b = background.computeLuminance();
      expect(((a > b ? a : b) + .05) / ((a > b ? b : a) + .05),
          greaterThanOrEqualTo(4.5));
    }
    final closeBefore = t.getRect(close);
    expect(closeBefore.height, greaterThanOrEqualTo(desktop ? 44 : 48));
    expect(closeBefore.left, greaterThanOrEqualTo(0));
    expect(closeBefore.right, lessThanOrEqualTo(size.width));
    expect(closeBefore.bottom, lessThanOrEqualTo(size.height - inset));
    expect(close.hitTestable(), findsOneWidget);
    expect(find.descendant(of: body, matching: close), findsNothing);
    for (final text in [
      sample.description,
      '权限与审批策略',
      sample.policy,
      '遵循全局当前生效的审批策略与沙箱安全边界。'
    ]) {
      final target = find.descendant(of: body, matching: find.text(text));
      expect(target, findsOneWidget);
      expect(t.widget<Text>(target).maxLines, isNull);
      await t.ensureVisible(target);
      await t.pumpAndSettle();
      expect(t.getRect(target).overlaps(t.getRect(body)), isTrue);
      expect(t.getRect(close), closeBefore);
      expect(close.hitTestable(), findsOneWidget);
    }
    expect(store.alwaysAllowed, isEmpty);
    expect(store.sessionAllowed, isEmpty);
    if (keyboard) {
      final semantics = t.ensureSemantics();
      try {
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pumpAndSettle();
        expect(Focus.of(t.element(find.text('我知道了'))).hasFocus, isTrue);
        expect(
            t.getSemantics(close),
            matchesSemantics(
                isButton: true,
                isEnabled: true,
                hasEnabledState: true,
                isFocusable: true,
                isFocused: true,
                hasTapAction: true,
                hasFocusAction: true,
                label: '我知道了',
                textDirection: TextDirection.ltr));
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
      } finally {
        semantics.dispose();
      }
    } else {
      await t.tap(close);
    }
    await t.pumpAndSettle();
    expect(body, findsNothing);
    expect(databaseReads, 0);
    final prefs = await SharedPreferences.getInstance();
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)},
        initialPreferences);
    expect(store.alwaysAllowed, isEmpty);
    expect(store.sessionAllowed, isEmpty);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    for (final sample in samples) {
      testWidgets('tool detail320x568 font2 dark=$dark ${sample.name}',
          (t) => detail(t, sample.name, dark: dark));
    }
    for (final spec in [
      (size: const Size(360, 640), scale: 1.0, inset: 0.0, desktop: false),
      (size: const Size(360, 640), scale: 1.6, inset: 0.0, desktop: false),
      (size: const Size(640, 360), scale: 2.0, inset: 0.0, desktop: false),
      (size: const Size(320, 640), scale: 2.0, inset: 240.0, desktop: false),
      (size: const Size(640, 360), scale: 2.0, inset: 160.0, desktop: false),
      (size: const Size(1280, 900), scale: 1.0, inset: 0.0, desktop: true),
    ]) {
      testWidgets(
          'tool detail matrix dark=$dark size=${spec.size} scale=${spec.scale} inset=${spec.inset} desktop=${spec.desktop}',
          (t) => detail(t, 'terminal',
              dark: dark,
              size: spec.size,
              scale: spec.scale,
              inset: spec.inset,
              desktop: spec.desktop));
    }
  }
  testWidgets(
      'tool close keyboard and semantics does not change approval policy',
      (t) => detail(t, 'terminal', keyboard: true));
  for (final removeInner in [false, true]) {
    testWidgets(
        'shared sheet applies keyboard offset once removeInner=$removeInner',
        (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(320, 640);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      double? observedInset;
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  viewInsets: const EdgeInsets.only(bottom: 240),
                  disableAnimations: true),
              child: child!),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showNexusSheet<void>(
                          context: context,
                          removeInnerViewInsets: removeInner,
                          builder: (ctx) {
                            observedInset = MediaQuery.viewInsetsOf(ctx).bottom;
                            return Column(
                                key: const ValueKey('inset-contract'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                      child: SingleChildScrollView(
                                          child: Column(children: [
                                    for (var i = 0; i < 30; i++)
                                      Text(
                                          'Blank synthetic long form section $i'),
                                    const TextField(
                                        decoration: InputDecoration(
                                            labelText: 'Blank fixture input'))
                                  ]))),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Close fixture'))
                                ]);
                          }),
                      child: const Text('Open fixture'))))));
      await t.tap(find.text('Open fixture'));
      await t.pumpAndSettle();
      expect(observedInset, removeInner ? 0 : 240);
      expect(t.getRect(find.byKey(const ValueKey('inset-contract'))).bottom,
          closeTo(640 - 240 - 8, .01));
      expect(find.widgetWithText(FilledButton, 'Close fixture').hitTestable(),
          findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Close fixture'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('inset-contract')), findsNothing);
    });
  }
}
