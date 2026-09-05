import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 语音输出服务（A2）：长按助手消息朗读；系统 TTS 免费零 Key，作为主引擎。
/// 云端 TTS 走 provider `/audio/speech`，此处仅保留系统引擎实现（无 Key 时隐藏云端开关）。
class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized || kIsWeb) return;
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      _initialized = true;
    } catch (error) {
      debugPrint('TTS 初始化失败: $error');
    }
  }

  Future<void> speak(String text) async {
    if (kIsWeb || text.trim().isEmpty) return;
    await _ensureInit();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (error) {
      debugPrint('TTS 朗读失败: $error');
    }
  }

  Future<void> stop() async {
    if (kIsWeb) return;
    try {
      await _tts.stop();
    } catch (error) {
      debugPrint('TTS 停止失败: $error');
    }
  }
}

final ttsServiceProvider = Provider<TtsService>((ref) => TtsService.instance);
