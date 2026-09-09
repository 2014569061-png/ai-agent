import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/providers.dart';
import '../../infrastructure/files/vault_exporter.dart';
import '../../infrastructure/sync/sync_service.dart';
import '../vault/vault_page.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';
import 'settings_components.dart';

class DataBackupPage extends ConsumerStatefulWidget {
  const DataBackupPage({super.key});

  @override
  ConsumerState<DataBackupPage> createState() => _DataBackupPageState();
}

class _DataBackupPageState extends ConsumerState<DataBackupPage> {
  static const _autoBackupKey = 'settings.backup.auto';
  static const _lastBackupKey = 'settings.backup.last_time';

  bool _autoBackup = false;
  String _lastBackupTime = '暂无备份记录';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoBackup = prefs.getBool(_autoBackupKey) ?? false;
      _lastBackupTime = prefs.getString(_lastBackupKey) ?? '暂无备份记录';
      _loading = false;
    });
  }

  Future<void> _toggleAutoBackup(bool val) async {
    setState(() => _autoBackup = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoBackupKey, val);
    if (mounted) {
      FloatingToast.show(
        context,
        val ? '已开启每日自动数据备份' : '已关闭自动备份',
      );
    }
  }

  Future<void> _restoreAutomaticBackup() async {
    if (!mounted) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['nexusauto'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    try {
      final picked = result.files.first;
      final content = picked.bytes != null
          ? utf8.decode(picked.bytes!)
          : await File(picked.path!).readAsString();
      final plaintext = await SyncService().decryptString(content);
      final json = jsonDecode(plaintext) as Map<String, dynamic>;
      final db = await ref.read(databaseProvider.future);
      await restoreVault(db, json);
      if (mounted) FloatingToast.show(context, '自动备份已恢复');
    } catch (e) {
      if (mounted) FloatingToast.show(context, '自动备份恢复失败: $e');
    }
  }

  Future<void> _clearLocalData() async {
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ 危险操作：清除本地全部数据？'),
        content: const Text(
          '此操作将永久清空本地数据库中的全部历史会话、长期记忆、自定义 Prompt 预设与本地缓存。\n\n此操作不可撤销，请确保已事先导出备份！',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('下一步确认'),
          ),
        ],
      ),
    );

    if (firstConfirm != true || !mounted) return;

    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('最终二次确认'),
        content: const Text('你确定要完全抹掉本机上的所有 NEXUS 数据吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('放弃'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定立即清除'),
          ),
        ],
      ),
    );

    if (secondConfirm == true && mounted) {
      try {
        final db = await ref.read(databaseProvider.future);
        await db.clearAllUserData();
        if (mounted) {
          FloatingToast.show(context, '本地核心数据已成功清空', tone: ToastTone.success);
        }
      } catch (e) {
        if (mounted) FloatingToast.show(context, '清除数据失败: ');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: const NexusPageHeader(
        title: '数据备份',
        subtitle: '全量数据导出、备份恢复与本地存储管理',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
              children: [
                const SettingsSectionTitle('备份与迁移'),
                SettingsGroupCard(
                  children: [
                    SettingsTile(
                      icon: Icons.shield_rounded,
                      iconColor: const Color(0xFF5856D6),
                      title: '隐私保险箱 (加密导出/导入)',
                      subtitle: '端到端高强度主密码加密备份',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const VaultPage(),
                          ),
                        );
                      },
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.backup_rounded,
                      iconColor: const Color(0xFF34C759),
                      title: '自动备份',
                      subtitle: '应用处于空闲状态时自动创建增量快照',
                      trailingWidget: SettingsSwitch(
                        value: _autoBackup,
                        onChanged: _toggleAutoBackup,
                      ),
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.history_rounded,
                      iconColor: const Color(0xFF8E8E93),
                      title: '最近备份时间',
                      subtitle: _lastBackupTime,
                      trailingWidget: IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        onPressed: () {
                          setState(() {
                            _lastBackupTime = DateTime.now()
                                .toLocal()
                                .toString()
                                .substring(0, 16);
                          });
                          SharedPreferences.getInstance().then((p) {
                            p.setString(_lastBackupKey, _lastBackupTime);
                          });
                          FloatingToast.show(context, '已生成新的数据快照记录');
                        },
                      ),
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.restore_rounded,
                      iconColor: const Color(0xFF007AFF),
                      title: '恢复自动备份',
                      subtitle: '选择 .nexusauto 文件并恢复本机数据',
                      onTap: _restoreAutomaticBackup,
                    ),
                  ],
                ),
                const SettingsSectionTitle('备份内容说明'),
                SettingsGroupCard(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '备份包将完整包含以下内容：',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• 对话记录：全部历史会话与关联消息\n'
                      '• 长期记忆：跨会话的事实与个性化记忆条目\n'
                      '• Agent 与预设：自定义助手模型设定与参数配置\n'
                      '• 提示词模板：自定义 Prompt 库内容\n'
                      '• MCP 配置：服务器连接端点与调用偏好\n'
                      '• Provider 密钥：保险箱模式下支持主密码全量加密封存',
                      style: TextStyle(
                        height: 1.6,
                        fontSize: 12,
                        color: settingsMutedColor(context),
                      ),
                    ),
                  ],
                ),
                const SettingsSectionTitle('危险区域'),
                SettingsGroupCard(
                  children: [
                    SettingsTile(
                      icon: Icons.delete_forever_rounded,
                      iconColor: const Color(0xFFFF3B30),
                      title: '清除本地全部数据',
                      titleColor: const Color(0xFFFF3B30),
                      subtitle: '永久抹除本机数据库中的所有数据（不可撤销）',
                      onTap: _clearLocalData,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
