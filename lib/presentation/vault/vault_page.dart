import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../infrastructure/files/vault_exporter.dart';
import '../theme/app_theme.dart';
import '../widgets/floating_toast.dart';
import '../widgets/immersive_sheet.dart';
import '../widgets/section_card.dart';

/// 隐私保险箱（G3）：加密导出/导入全量本地数据（AES-256-GCM 密码保护）。
class VaultPage extends ConsumerStatefulWidget {
  const VaultPage({super.key});

  @override
  ConsumerState<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends ConsumerState<VaultPage> {
  Future<void> _export() async {
    final includeSecrets = await _confirmSensitiveExport();
    if (includeSecrets == null || !mounted) return;
    final password = await _askPassword('设置加密密码');
    if (password == null || !mounted) return;
    final db = await ref.read(databaseProvider.future);
    final path = await exportVaultFile(db, password,
        includeSecrets: includeSecrets);
    if (!mounted) return;
    if (path == null) {
      FloatingToast.show(context, '导出失败');
    } else {
      FloatingToast.show(context,
          '已导出到 $path（${includeSecrets ? '包含密钥' : '不包含密钥'}，忘记密码将无法找回）');
    }
  }

  Future<bool?> _confirmSensitiveExport() => showImmersiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导出密钥？'),
          content: const Text(
              '默认只导出会话、记忆和应用数据。包含 API Key 和工具密钥会增加备份泄露风险，是否明确包含？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('不包含密钥'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('包含密钥'),
            ),
          ],
        ),
      );

  Future<void> _import() async {
    final result =
        await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (result == null || result.files.isEmpty || !mounted) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      FloatingToast.show(context, '无法读取文件');
      return;
    }
    final password = await _askPassword('输入加密密码');
    if (password == null || !mounted) return;
    final confirmed = await showImmersiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('将覆盖本地数据'),
        content: const Text('导入将清空并覆盖当前本机会话/记忆/设置，且无法撤销。是否继续？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续导入')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final db = await ref.read(databaseProvider.future);
      final summary = await importVaultBytes(db, bytes, password);
      if (mounted) FloatingToast.show(context, summary);
    } catch (_) {
      if (mounted) FloatingToast.show(context, '导入失败：密码错误或文件损坏');
    }
  }

  Future<String?> _askPassword(String title) async {
    final controller = TextEditingController();
    final result = await showImmersiveDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('确定')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐私保险箱')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SectionCard(
          child: ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('加密导出'),
            subtitle: const Text('默认不包含 API Key；可在导出时手动选择'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _export,
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('密码导入'),
            subtitle: const Text('从 .nexusvault 恢复（将覆盖本地数据）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _import,
          ),
        ),
        const SizedBox(height: 16),
        Text('注意：忘记密码将无法找回，密码永不存储。',
            style: TextStyle(
                fontSize: 12,
                color: AppTheme.semanticOf(context).mutedOnGlass)),
      ]),
    );
  }
}
