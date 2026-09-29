import 'package:flutter/foundation.dart' show kReleaseMode;

/// 会话日志开关（阶段 1：双写期）。
///
/// 默认只在 debug / profile 构建中双写，正式版保持关闭，直到影子比对确认
/// 零差异后再默认开启。可用 `--dart-define=NEXUS_SESSION_LOG=true|false`
/// 覆盖。关闭时行为与引入会话日志之前完全一致。
abstract final class SessionLogSettings {
  static const bool dualWrite = bool.fromEnvironment(
    'NEXUS_SESSION_LOG',
    defaultValue: !kReleaseMode,
  );
}
