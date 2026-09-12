import 'dart:async';

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        ValueListenable,
        ValueNotifier,
        defaultTargetPlatform,
        kIsWeb,
        visibleForTesting;
import 'package:flutter_tts/flutter_tts.dart';

/// G1（长按朗读）：系统 TTS 朗读服务。
///
/// 设计约束（照着做，别退回去）：
/// * **懒加载单例**：不在顶层初始化 —— 单测/Web 环境没有平台通道，构造即炸。
/// * **平台判定不用 `dart:io`**：改用 `kIsWeb` + `defaultTargetPlatform`，
///   避免把平台判定耦合到 Web 构建不支持的库上。
/// * 本版只支持 **Android 真机**朗读；其余平台 [isAvailable] 为 false，
///   UI 据此隐藏入口。构造器里的平台调用全部 try/catch 降级，绝不向上抛。
class TtsService {
  TtsService._();

  /// 供测试子类化 / 注入假实现使用（真机路径不受影响）。
  @visibleForTesting
  TtsService.forTesting();

  static TtsService? _instance;
  static TtsService get instance => _instance ??= TtsService._();

  /// 仅测试使用：替换单例（例如注入不触发平台通道的假实现）。
  @visibleForTesting
  static void debugOverride(TtsService? value) => _instance = value;

  FlutterTts? _engine;
  final ValueNotifier<bool> _speaking = ValueNotifier<bool>(false);

  /// 当前平台是否具备朗读能力。UI 只在该值为 true 时展示「朗读」入口。
  bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 朗读状态的可监听视图：读屏动作标签、菜单项文案据此刷新。
  ValueListenable<bool> get speakingListenable => _speaking;

  /// 是否正在朗读。UI 据此把菜单项显示为「停止朗读」。
  bool get isSpeaking => _speaking.value;

  void _setSpeaking(bool value) {
    if (_speaking.value == value) return;
    _speaking.value = value;
  }

  /// 朗读 [text]；正在朗读时先停止再开始。
  ///
  /// 返回 false 表示本次没有开始朗读（平台不支持、内容为空或引擎初始化失败），
  /// 调用方据此决定是否提示「当前设备不支持语音朗读」。
  Future<bool> speak(String text) async {
    final content = text.trim();
    if (content.isEmpty || !isAvailable) return false;
    try {
      final engine = await _ensureEngine();
      if (engine == null) return false;
      if (isSpeaking) {
        await engine.stop();
        _setSpeaking(false);
      }
      // 乐观置位：引擎回调有可感知延迟，先认「正在朗读」才能立刻切到「停止朗读」。
      _setSpeaking(true);
      unawaited(engine.speak(content).then<void>((_) {}, onError: (Object _) {
        _setSpeaking(false);
      }));
      return true;
    } catch (_) {
      // 平台通道异常（无引擎 / 测试环境）一律降级为“本次没开始朗读”，不向上抛。
      _setSpeaking(false);
      return false;
    }
  }

  /// 停止朗读。幂等，未在朗读时调用无副作用。
  Future<void> stop() async {
    _setSpeaking(false);
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.stop();
    } catch (_) {
      // 引擎已失效：忽略，状态位已复位。
    }
  }

  /// 首次使用时才构造引擎并完成语言/回调配置。
  ///
  /// 初始化失败**不缓存失败态**：Android 的 TTS 引擎是异步绑定的，首次调用可能
  /// 恰好落在绑定完成前；缓存失败态会让朗读功能整个会话都不可用。重复构造
  /// `FlutterTts` 只会覆盖同名方法通道监听，没有泄漏。
  Future<FlutterTts?> _ensureEngine() async {
    final cached = _engine;
    if (cached != null) return cached;
    if (!isAvailable) return null;

    final engine = FlutterTts();
    engine.setStartHandler(() => _setSpeaking(true));
    engine.setCompletionHandler(() => _setSpeaking(false));
    engine.setCancelHandler(() => _setSpeaking(false));
    engine.setErrorHandler((_) => _setSpeaking(false));
    try {
      await engine.setLanguage('zh-CN');
      // 让 speak() 的 Future 在朗读结束时才完成，配合回调维护状态机。
      await engine.awaitSpeakCompletion(true);
    } catch (_) {
      // 无 TTS 引擎或运行在测试环境（无平台通道）：退回“不支持”，不向上抛。
      return null;
    }
    _engine = engine;
    return engine;
  }
}
