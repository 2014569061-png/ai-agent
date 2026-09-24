// ChatPage 附件管线的端到端 widget 测试。
//
// 为什么需要它：附件逻辑（选择 → 体检 → 渲染缩略图 → 移除）此前只被「限额纯函数」
// 的单元测试间接覆盖，页面这一层没有任何测试。而这里恰好藏过两个真实漂移 bug
// （能选不能发的扩展名差异、gif 能发却不显示缩略图），因此必须从真实 UI 入口验证，
// 而不是继续测纯函数。
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/chat/chat_page.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

/// 1x1 的合法 PNG，用于让缩略图能真正解码。
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// 把字符串转成附件字节。
Uint8List _bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

/// 只提供可控空状态的控制器：本测试关注附件 UI，不需要真实运行。
class _IdleController extends ChatController {
  @override
  ChatState build() => const ChatState(
        loading: false,
        conversationId: 'conv-attachments',
      );
}

/// 测试用的具体 [PlatformFile]。
///
/// file_picker 13 把 `PlatformFile` 改成了抽象基类且不可构造，因此测试里必须自己
/// 提供一个具体实现来喂给选择器返回值。
base class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile({required this.name, required this.bytes});

  @override
  final String name;

  final Uint8List bytes;

  @override
  final String? path = null;

  @override
  Uri get uri => Uri.file(name);

  @override
  XFile get xFile => XFile.fromData(bytes, name: name);

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() async* {
    yield bytes;
  }
}

/// 覆写文件选择器平台实现，按测试给定的文件返回，并记录收到的 allowedExtensions。
///
/// file_picker 13 的 `FilePicker` 是 `abstract final class`（只有静态方法，不可继承），
/// 因此注入点改为 `FilePickerPlatform.instance`——磁盘上真实的 `FilePicker.pickFiles`
/// 正是转发到它。
class _ScriptedPickerPlatform extends FilePickerPlatform {
  _ScriptedPickerPlatform(this._files);

  final List<PlatformFile> _files;
  List<String>? lastAllowedExtensions;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    lastAllowedExtensions = allowedExtensions;
    return _files;
  }
}

Future<_ScriptedPickerPlatform> _pumpChatPage(
  WidgetTester tester,
  List<PlatformFile> files,
) async {
  SharedPreferences.setMockInitialValues({});
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final picker = _ScriptedPickerPlatform(files);
  FilePickerPlatform.instance = picker;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        chatControllerProvider.overrideWith(_IdleController.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const ChatPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 64));
  return picker;
}

/// 打开附件面板并点「文件」。
Future<void> _pickViaFileMenu(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('添加附件或更多工具'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('文件'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('选择器开放的扩展名来自单一来源，且不含发不出去的音视频', (tester) async {
    final picker = await _pumpChatPage(tester, const []);

    await _pickViaFileMenu(tester);

    final allowed = picker.lastAllowedExtensions;
    expect(allowed, isNotNull, reason: '文件菜单应触达 pickFiles');
    // 与发送端真实能力一致：5 种图片 + 4 种文本。
    expect(allowed, containsAll(['png', 'jpg', 'jpeg', 'webp', 'gif']));
    expect(allowed, containsAll(['txt', 'md', 'csv', 'json']));
    // 音视频此前「能选不能发」，现在必须不在名单里。
    for (final ext in ['mp3', 'm4a', 'wav', 'ogg', 'aac', 'mp4', 'mov']) {
      expect(allowed, isNot(contains(ext)), reason: '$ext 发不出去就不该能选');
    }
  });

  testWidgets('选中图片后展示缩略图，且可移除', (tester) async {
    await _pumpChatPage(tester, [
      _FakePlatformFile(name: 'photo.png', bytes: _pngBytes),
    ]);

    await _pickViaFileMenu(tester);

    // 图片走 DecorationImage 缩略图，而不是文件图标。
    expect(find.byTooltip('移除附件 photo.png'), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNothing,
        reason: '图片应显示缩略图而非通用文件图标');

    await tester.tap(find.byTooltip('移除附件 photo.png'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('移除附件 photo.png'), findsNothing);
  });

  testWidgets('gif 也要显示缩略图（此前硬编码名单漏了它）', (tester) async {
    await _pumpChatPage(tester, [
      _FakePlatformFile(name: 'anim.gif', bytes: _pngBytes),
    ]);

    await _pickViaFileMenu(tester);

    expect(find.byTooltip('移除附件 anim.gif'), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNothing,
        reason: 'gif 属于图片，不应退化成文件图标');
  });

  testWidgets('文本附件用文件图标，不带缩略图', (tester) async {
    await _pumpChatPage(tester, [
      _FakePlatformFile(name: 'notes.md', bytes: _bytesOf('# hi')),
    ]);

    await _pickViaFileMenu(tester);

    expect(find.byTooltip('移除附件 notes.md'), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget,
        reason: '非图片附件应显示文件图标');
  });

  testWidgets('超过数量上限的文件被拒绝，并给出可见提示', (tester) async {
    // 上限 10；一次给 12 个文本附件，应只接受 10 个并提示。
    final many = [
      for (var i = 0; i < 12; i++)
        _FakePlatformFile(name: 'f$i.txt', bytes: _bytesOf('abc')),
    ];
    await _pumpChatPage(tester, many);

    await _pickViaFileMenu(tester);

    expect(find.byTooltip('移除附件 f0.txt'), findsOneWidget);
    // 第 11、12 个（索引 10、11）应被拒。
    expect(find.byTooltip('移除附件 f10.txt'), findsNothing);
    expect(find.byTooltip('移除附件 f11.txt'), findsNothing);
    // 用户必须被告知，而不是静默丢弃。
    expect(find.textContaining('已跳过'), findsOneWidget);
  });

  testWidgets('超过单文件上限的文件被拒绝并提示', (tester) async {
    // 体检按 bytes.length 判定，因此必须给真实超限的字节（8MB + 1）。
    // 只写 size 而不写 bytes 是无效的：那样会被当成小文件通过。
    final overLimit = Uint8List(8 * 1024 * 1024 + 1);
    final big = _FakePlatformFile(name: 'huge.txt', bytes: overLimit);
    await _pumpChatPage(tester, [big]);

    await _pickViaFileMenu(tester);

    expect(find.byTooltip('移除附件 huge.txt'), findsNothing);
    expect(find.textContaining('已跳过'), findsOneWidget);
  });

  testWidgets('取消选择不改变附件区', (tester) async {
    await _pumpChatPage(tester, const []);

    await _pickViaFileMenu(tester);

    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNothing);
    expect(find.textContaining('已跳过'), findsNothing);
  });
}