import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_palette.dart';
import '../widgets/nexus_sheet.dart';

/// 确保拿到 Android 的「所有文件访问权限」（MANAGE_EXTERNAL_STORAGE）。
///
/// 为什么必须走引导而不能只调一次 `request()`：
/// 这个权限不是普通运行时权限，`request()` 只是把用户送到系统设置页，
/// 用户返回后**本进程拿不到任何回调**。所以完整流程必须是
/// 「先说明原因 → 请求 → 回到前台复查 → 仍未通过则给手动入口」。
/// 否则用户点一下导入就直接撞上「目录不可写」，完全不知道下一步该做什么。
///
/// 返回 `true` 表示已授权，调用方可以继续选择目录并导入。
Future<bool> ensureAllFilesAccess(BuildContext context) async {
  // 只有 Android 需要它；桌面 / Web 直接放行。
  if (kIsWeb || !Platform.isAndroid) return true;

  if (await Permission.manageExternalStorage.isGranted) return true;

  if (!context.mounted) return false;
  final granted = await showNexusDialog<bool>(
    context: context,
    // 授权是导入动作的前置条件，误触遮罩不该把整个流程丢掉。
    barrierDismissible: false,
    builder: (_) => const _StorageAccessDialog(),
  );
  return granted ?? false;
}

/// 授权引导弹窗：说明用途 → 跳系统设置 → 回前台自动复查。
class _StorageAccessDialog extends StatefulWidget {
  const _StorageAccessDialog();

  @override
  State<_StorageAccessDialog> createState() => _StorageAccessDialogState();
}

class _StorageAccessDialogState extends State<_StorageAccessDialog>
    with WidgetsBindingObserver {
  bool _busy = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 用户从系统设置页返回时没有权限回调可用，只能靠生命周期事件复查。
    if (state == AppLifecycleState.resumed) {
      _recheck();
    }
  }

  Future<void> _recheck() async {
    if (!mounted) return;
    final granted = await Permission.manageExternalStorage.isGranted;
    if (!mounted) return;
    if (granted) {
      Navigator.of(context).pop(true);
      return;
    }
    if (_busy) {
      setState(() => _busy = false);
    }
  }

  Future<void> _requestAccess() async {
    setState(() {
      _busy = true;
      _hint = null;
    });
    final status = await Permission.manageExternalStorage.request();
    if (!mounted) return;
    if (status.isGranted) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _hint = status.isPermanentlyDenied
          // 永久拒绝后 request() 不再弹系统页面，只能指路到应用详情页。
          ? '系统不再弹出授权框了。请在「设置 → 应用 → NEXUS Agent」里找到'
              '「所有文件访问权限」并手动开启，然后回来继续导入。'
          : '还没有开启「所有文件访问权限」。导入后需要在项目目录里创建和修改文件，'
              '请开启后再回来。';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return AlertDialog(
      title: const Text('需要文件访问权限'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('导入本地工作区后，应用要在该目录里创建和修改项目文件，'
              '这需要「所有文件访问权限」。'),
          const SizedBox(height: 12),
          Text(
            '点「去授权」会跳到系统设置页，打开开关再返回即可继续导入。',
            style: TextStyle(fontSize: 13, color: muted),
          ),
          if (_hint != null) ...[
            const SizedBox(height: 12),
            Text(
              _hint!,
              style: const TextStyle(fontSize: 13, color: AppPalette.danger),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('暂不导入'),
        ),
        FilledButton(
          onPressed: _busy ? null : _requestAccess,
          child: Text(_busy ? '等待授权…' : '去授权'),
        ),
      ],
    );
  }
}
