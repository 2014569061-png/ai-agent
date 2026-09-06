import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// G1 聊天背景服务:三种模式 —— default(跟随主题渐变)/ clouds(内置云朵栈桥)
/// / custom(用户从相册选择,拷贝进应用私有目录持久化)。
class BackgroundService {
  static const _modeKey = 'chat_background_mode';
  static const _pathKey = 'chat_background_path';
  static const cloudsAsset = 'assets/images/bg_default.jpg';

  /// 当前背景配置的跨页通知器;设置页修改后聊天页即时生效。
  static final ValueNotifier<BackgroundConfig> bgNotifier =
      ValueNotifier(const BackgroundConfig(mode: 'default'));

  Future<BackgroundConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_modeKey) ?? 'default';
    final path = prefs.getString(_pathKey);
    final validPath = (path != null && path.isNotEmpty && File(path).existsSync())
        ? path
        : null;
    return BackgroundConfig(
      mode: mode == 'clouds' || mode == 'custom' ? mode : 'default',
      customPath: validPath,
    );
  }

  Future<void> setMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode);
    final current = bgNotifier.value;
    bgNotifier.value = BackgroundConfig(mode: mode, customPath: current.customPath);
  }

  /// 从用户选择的源路径拷贝到应用私有目录并记录,同时切到 custom 模式。
  Future<String> setCustomBackground(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final ext = sourcePath.toLowerCase().endsWith('.png') ? '.png' : '.jpg';
    final target = '${dir.path}${Platform.pathSeparator}chat_background$ext';
    File(sourcePath).copySync(target);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pathKey, target);
    await prefs.setString(_modeKey, 'custom');
    bgNotifier.value = BackgroundConfig(mode: 'custom', customPath: target);
    return target;
  }
}

class BackgroundConfig {
  const BackgroundConfig({required this.mode, this.customPath});
  final String mode; // default | clouds | custom
  final String? customPath;
}
