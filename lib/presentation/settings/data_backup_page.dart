import '../theme/app_palette.dart';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/providers.dart';
import '../../application/scheduled_task_runner.dart';
import '../../infrastructure/files/vault_exporter.dart';
import '../../infrastructure/files/local_crypto_service.dart';
import '../../infrastructure/providers/provider_config_store.dart';
import '../vault/vault_page.dart';
import '../motion/nexus_page_route_factory.dart';
import '../widgets/confirm_action.dart';
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

  Future<void> _createManualBackup() async {
    try {
      final db = await ref.read(databaseProvider.future);
      final path = await createAutomaticBackupNow(db);
      if (!mounted) return;
      if (path == null) {
        FloatingToast.show(context, '备份失败', tone: ToastTone.danger);
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _lastBackupTime = prefs.getString(_lastBackupKey) ?? _lastBackupTime;
      });
      FloatingToast.show(context, '已生成新的数据快照', tone: ToastTone.success);
    } catch (e) {
      if (mounted) {
        FloatingToast.show(context, '备份失败: $e', tone: ToastTone.danger);
      }
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
      final plaintext = await LocalCryptoService().decryptString(content);
      final json = jsonDecode(plaintext) as Map<String, dynamic>;
      final db = await ref.read(databaseProvider.future);
      await restoreVault(db, json);
      if (mounted) FloatingToast.show(context, '自动备份已恢复');
    } catch (e) {
      if (mounted) FloatingToast.show(context, '自动备份恢复失败: $e');
    }
  }

  Future<void> _clearLocalData() async {
    final confirmed = await showConfirmAction(
      context,
      title: '危险操作：清除本地核心数据？',
      message: '此操作将永久抹掉本机数据库、Provider 配置、MCP 配置与本地密钥，操作不可撤销，请确保已事先导出备份。请输入确认词继续：',
      confirmLabel: '确认清空',
      cancelLabel: '取消',
      isDanger: true,
      requiredKeyword: '清空',
      bulletItems: const [
        '全部历史会话与消息记录',
        '长期记忆库',
        '自定义 Prompt 模板与定时任务',
        '模型调用缓存与本地诊断日志',
        'Provider / 工具密钥与 MCP 服务器配置',
      ],
    );

    if (confirmed != true || !mounted) return;

    try {
      final db = await ref.read(databaseProvider.future);
      await db.clearAllUserData();
      await db.clearMcpServers();
      await ProviderConfigStore().clearAll();
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove(_autoBackupKey),
        prefs.remove(_lastBackupKey),
      ]);
      if (mounted) {
        FloatingToast.show(context, '本地核心数据已成功清空', tone: ToastTone.success);
      }
    } catch (e) {
      if (mounted) {
        FloatingToast.show(context, '清除数据失败: $e', tone: ToastTone.danger);
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
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
              children: [
                const SettingsSectionTitle('备份与迁移'),
                SettingsGroupCard(
                  children: [
                    SettingsTile(
                      icon: Icons.shield_rounded,
                      iconColor: settingsMutedColor(context),
                      title: '隐私保险箱 (加密导出/导入)',
                      subtitle: '端到端高强度主密码加密备份',
                      onTap: () {
                        Navigator.push(
                          context,
                          NexusPageRoute.settingsPage(
                            builder: (_) => const VaultPage(),
                          ),
                        );
                      },
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.backup_rounded,
                      iconColor: AppPalette.success,
                      title: '自动备份',
                      subtitle: '应用空闲时自动创建加密全量快照',
                      trailingWidget: SettingsSwitch(
                        value: _autoBackup,
                        onChanged: _toggleAutoBackup,
                      ),
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.history_rounded,
                      iconColor: settingsMutedColor(context),
                      title: '最近备份时间',
                      subtitle: _lastBackupTime,
                      trailingWidget: IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        tooltip: '立即备份',
                        onPressed: _createManualBackup,
                      ),
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.restore_rounded,
                      iconColor: settingsMutedColor(context),
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
                        fontWeight: FontWeight.w500,
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
                      iconColor: AppPalette.danger,
                      title: '清除本地全部数据',
                      titleColor: AppPalette.danger,
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
