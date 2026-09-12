import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../infrastructure/files/vault_exporter.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/confirm_action.dart';
import '../widgets/floating_toast.dart';
import '../widgets/immersive_sheet.dart';
import '../widgets/nexus_page_header.dart';
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
    final path =
        await exportVaultFile(db, password, includeSecrets: includeSecrets);
    if (!mounted) return;
    if (path == null) {
      FloatingToast.show(context, '导出失败');
    } else {
      FloatingToast.show(context,
          '已导出到 $path（${includeSecrets ? '包含密钥' : '不包含密钥'}，忘记密码将无法找回）');
    }
  }

  Future<bool?> _confirmSensitiveExport() async {
    final include = await showConfirmAction(
      context,
      title: '导出密钥？',
      message: '默认只导出会话、记忆和应用数据。包含 API Key 和工具密钥会增加备份泄露风险，是否明确包含？',
      confirmLabel: '包含密钥',
      cancelLabel: '不包含密钥',
      isDanger: false,
      bulletItems: const [
        '会话记录与提示词模板',
        '长期记忆与知识库索引',
        '敏感密钥：API Key 与工具凭据',
      ],
    );
    return include;
  }

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
    final confirmed = await showConfirmAction(
      context,
      title: '将覆盖本地数据',
      message: '导入将清空并覆盖当前本机会话/记忆/设置，且无法撤销。是否继续？',
      confirmLabel: '继续导入',
      isDanger: true,
      requiredKeyword: '覆盖导入',
      bulletItems: const [
        '当前所有本地会话将被清空',
        '记忆与知识库将被备份全量替换',
        '模型与服务商设置将被恢复为备份状态',
      ],
    );
    if (!confirmed || !mounted) return;
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
            decoration: const InputDecoration(labelText: '密码（不能为空）')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(
                elevation: 0,
                backgroundColor: AppPalette.brandAction,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                ),
              ),
              onPressed: () {
                if (controller.text.trim().isEmpty) return;
                Navigator.pop(context, controller.text);
              },
              child: const Text('确定')),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      appBar: const NexusPageHeader(
        title: '隐私保险箱',
        subtitle: '全量加密导出与备份恢复',
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SectionCard(
          child: ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark
                    ? AppPalette.brandSoftDark
                    : AppPalette.brandSoftLight,
                borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              ),
              child: const Icon(Icons.upload_file_outlined,
                  size: 20, color: AppPalette.brand),
            ),
            title: const Text(
              '加密导出',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '默认不包含 API Key；可在导出时手动选择',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppPalette.darkTextMuted
                    : AppPalette.lightTextMuted,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _export,
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark
                    ? AppPalette.brandSoftDark
                    : AppPalette.brandSoftLight,
                borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              ),
              child: const Icon(Icons.download_outlined,
                  size: 20, color: AppPalette.brand),
            ),
            title: const Text(
              '密码导入',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '从 .nexusvault 恢复（将覆盖本地数据）',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppPalette.darkTextMuted
                    : AppPalette.lightTextMuted,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _import,
          ),
        ),
        const SizedBox(height: 16),
        Text('注意：忘记密码将无法找回，密码永不存储。',
            style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppPalette.darkTextMuted
                    : AppPalette.lightTextMuted)),
      ]),
    );
  }
}
