import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 工作区管理服务
class WorkspaceService {
  static const _prefKey = 'active_workspace_path';
  static const _historyKey = 'recent_workspaces';

  /// 获取当前保存的工作区路径
  Future<String?> getActiveWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_prefKey);
    if (path != null && path.isNotEmpty) {
      if (!kIsWeb) {
        final dir = Directory(path);
        if (await dir.exists()) return path;
      } else {
        return path;
      }
    }
    return null;
  }

  /// 设置当前工作区
  Future<void> setActiveWorkspace(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_prefKey);
    } else {
      await prefs.setString(_prefKey, path);
      await _addRecent(path);
    }
  }

  /// 唤起系统文件夹选择器
  Future<String?> pickDirectory() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        // 请求所有的文件访问权限 (MANAGE_EXTERNAL_STORAGE) 和基本读写权限
        if (await Permission.manageExternalStorage.isDenied) {
          await Permission.manageExternalStorage.request();
        }
        if (await Permission.storage.isDenied) {
          await Permission.storage.request();
        }
      }

      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择本地项目工作区目录',
      );
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        await setActiveWorkspace(selectedDirectory);
        return selectedDirectory;
      }
    } catch (e) {
      debugPrint('选择目录失败: $e');
    }
    return null;
  }

  /// 创建一个默认的本地项目演示目录（如用户没有指定文件夹）
  Future<String> createDefaultWorkspace(String projectName) async {
    if (kIsWeb) {
      final path = '/projects/$projectName';
      await setActiveWorkspace(path);
      return path;
    }

    final docDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${docDir.path}/projects/$projectName');
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }
    await setActiveWorkspace(projectDir.path);
    return projectDir.path;
  }

  /// 获取最近打开的工作区历史
  Future<List<String>> getRecentWorkspaces() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_historyKey) ?? [];
  }

  Future<void> _addRecent(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey) ?? [];
    list.remove(path);
    list.insert(0, path);
    if (list.length > 8) {
      list.removeLast();
    }
    await prefs.setStringList(_historyKey, list);
  }
}

final workspaceServiceProvider = Provider<WorkspaceService>((ref) {
  return WorkspaceService();
});
