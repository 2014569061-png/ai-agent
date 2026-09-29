import '../../domain/models.dart';

/// Android 上有 terminal 工具时注入的内置环境规则。
///
/// 内置规则与业务 system prompt 分开构造，确保调用方未传 prompt 或历史已带
/// system 消息时，模型仍然知道当前设备的真实能力边界。
List<String> builtInEnvironmentRules({
  required bool isAndroid,
  required bool hasTerminal,
}) {
  if (!isAndroid || !hasTerminal) return const [];
  return const [
    '[运行环境说明] 当前运行在 Android 手机上。terminal 工具优先使用内置 '
        'Alpine Linux（PRoot + ARM64 rootfs），不可用时回退到 Termux，再回退到 Android Shell。'
        '内置 Alpine 默认是精简 rootfs，提供 sh/ash/BusyBox 基础命令；Go/Git/Node/Python 等工具'
        '可能尚未安装，需要先在 Alpine 中执行 apk add，或使用已配置的 Termux 工具链。'
        '不要默认声称环境无法运行 Linux 命令；编译或测试报错时先检查当前 Runtime 和缺失工具，'
        '再安装依赖或切换备用 Runtime。',
    '[共享存储] 手机共享存储只有在用户授予「所有文件访问权限」后，才会挂载到内置 '
        'Alpine 的 /sdcard 与 /storage/emulated/0。访问这些路径报 No such file 或 '
        'Permission denied 时说明尚未授权：不要换路径反复重试，直接请用户到系统设置 → '
        '应用 → 本应用 → 权限中开启「所有文件访问」，授权后再继续。',
  ];
}

/// 把调用方的 system prompt 与内置规则合并进消息列表（原地修改 [messages]）。
///
/// - 已有 system 消息：只追加其中尚未包含的部分，保证幂等。
/// - 没有 system 消息：在最前面插入一条（内容为空则不插入）。
void mergeSystemPrompt(
  List<ChatMessage> messages, {
  String? requested,
  List<String> builtInRules = const [],
}) {
  final builtInSystemText = builtInRules.join('\n\n');
  final requestedSystemText = requested?.trim() ?? '';
  final systemIndex = messages.indexWhere((m) => m.role == MessageRole.system);
  if (systemIndex >= 0) {
    final existing = messages[systemIndex];
    final additions = <String>[];
    if (requestedSystemText.isNotEmpty &&
        !existing.text.contains(requestedSystemText)) {
      additions.add(requestedSystemText);
    }
    if (builtInSystemText.isNotEmpty &&
        !existing.text.contains(builtInSystemText)) {
      additions.add(builtInSystemText);
    }
    if (additions.isNotEmpty) {
      final combined = [existing.text.trim(), ...additions]
          .where((value) => value.isNotEmpty)
          .join('\n\n');
      messages[systemIndex] = existing.copyWith(
        parts: [MessagePart.text(combined)],
      );
    }
    return;
  }
  final systemText = [requestedSystemText, builtInSystemText]
      .where((value) => value.isNotEmpty)
      .join('\n\n');
  if (systemText.isNotEmpty) {
    messages.insert(
      0,
      ChatMessage(
        role: MessageRole.system,
        parts: [MessagePart.text(systemText)],
      ),
    );
  }
}
