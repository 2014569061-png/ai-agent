import '../theme/app_palette.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/providers.dart';
import '../../application/scheduled_task_runner.dart';
import '../../infrastructure/files/vault_exporter.dart';
import '../../infrastructure/files/local_crypto_service.dart';
import '../../application/data_maintenance_actions.dart';
import '../vault/vault_page.dart';
import '../motion/nexus_page_route_factory.dart';
import '../widgets/async_state_view.dart';
import '../widgets/confirm_action.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_disclosure.dart';
import '../theme/desktop_theme.dart';
import 'settings_components.dart';
import '../../application/local_error_copy.dart';

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
  bool _canRecover = false;
  bool _recovering = false;
  String _recoveryMessage = '正在检查运行状态';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var canRecover = false;
    var recoveryMessage = '维护状态暂不可用，请稍后重新检查';
    try {
      final status =
          await ref.read(dataMaintenanceActionsProvider).recoveryStatus();
      canRecover = status.canRecover;
      recoveryMessage = status.message;
    } catch (_) {/* Keep recovery disabled when evidence is unavailable. */}
    if (!mounted) return;
    setState(() {
      _canRecover = canRecover;
      _recoveryMessage = recoveryMessage;
      _autoBackup = prefs.getBool(_autoBackupKey) ?? false;
      final rawTime = prefs.getString(_lastBackupKey);
      final time =
          rawTime == null ? null : DateTime.tryParse(rawTime)?.toLocal();
      _lastBackupTime = time == null
          ? rawTime ?? '暂无备份记录'
          : '${time.year}年${time.month}月${time.day}日 '
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      _loading = false;
    });
  }

  Future<void> _recoverInterruptedMaintenance() async {
    if (!_canRecover || _recovering) return;
    final confirmed = await showConfirmAction(context,
        title: '恢复中断维护后的运行能力？',
        message: '只在操作系统确认旧进程退出后解除遗留运行屏障，不清除或覆盖业务数据。'
            '此操作不会自动回滚崩溃时的文件或密钥；请保留原备份与恢复暂存文件，'
            '检查数据，必要时重新导入完整备份。',
        confirmLabel: '恢复运行',
        isDanger: true,
        requiredKeyword: '恢复运行');
    if (!confirmed || !mounted) return;
    setState(() => _recovering = true);
    try {
      await ref.read(dataMaintenanceActionsProvider).recoverInterrupted();
      if (mounted) FloatingToast.show(context, '遗留运行状态已解除，请检查数据，必要时重新恢复备份');
    } catch (error) {
      if (mounted) {
        FloatingToast.show(context, error.toString(), tone: ToastTone.danger);
      }
    } finally {
      if (mounted) {
        setState(() => _recovering = false);
        await _load();
      }
    }
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
        FloatingToast.show(context, LocalErrorCopy.of(e, action: '备份').headline(), tone: ToastTone.danger);
      }
    }
  }

  Future<void> _restoreAutomaticBackup() async {
    if (!mounted) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['nexusauto'],
    );
    if (picked.isEmpty) return;
    try {
      final file = picked.first;
      if (await file.xFile.length() > VaultLimits.maxCipherBytes) {
        throw const FormatException('备份文件过大');
      }
      if (!mounted) return;
      final confirmed = await showConfirmAction(context,
          title: '覆盖恢复本地数据？',
          message: '当前数据将被备份替换，请先保存现有数据。',
          confirmLabel: '恢复',
          isDanger: true,
          requiredKeyword: '覆盖导入');
      if (!confirmed || !mounted) return;
      // file_picker 13 已移除 withData，字节按需读取。
      final content = utf8.decode(await file.readAsBytes());
      final plaintext = await LocalCryptoService().decryptString(content);
      final json = jsonDecode(plaintext) as Map<String, dynamic>;
      final report =
          await ref.read(dataMaintenanceActionsProvider).restore(json);
      await _load();
      if (mounted) FloatingToast.show(context, report.summary);
    } catch (e) {
      if (mounted) {
        FloatingToast.show(context,
            e is DataMaintenanceRefreshFailure ? e.toString() : LocalErrorCopy.of(e, action: '自动备份恢复').headline());
      }
    }
  }

  Future<void> _clearLocalData() async {
    final confirmed = await showConfirmAction(
      context,
      title: '危险操作：清除本地核心数据？',
      message:
          '此操作将永久抹掉本机数据库、Provider 配置、MCP 配置与本地密钥，操作不可撤销，请确保已事先导出备份。请输入确认词继续：',
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
      await ref.read(dataMaintenanceActionsProvider).clear();
      await _load();
      if (mounted) {
        FloatingToast.show(context, '本地核心数据已成功清空', tone: ToastTone.success);
      }
    } catch (e) {
      if (mounted) {
        FloatingToast.show(context,
            e is DataMaintenanceRefreshFailure ? e.toString() : LocalErrorCopy.of(e, action: '清除数据').headline(),
            tone: ToastTone.danger);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backupContents = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('备份包将完整包含以下内容：',
            style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: theme.colorScheme.onSurface)),
        const SizedBox(height: 8),
        Text(
          '• 对话记录：全部历史会话与关联消息\n'
          '• 长期记忆：跨会话的事实与个性化记忆条目\n'
          '• Agent 与预设：自定义助手模型设定与参数配置\n'
          '• 提示词模板：自定义 Prompt 库内容\n'
          '• MCP 配置：服务器连接端点与调用偏好\n'
          '• Provider 密钥：保险箱模式下支持主密码全量加密封存',
          style: TextStyle(
              height: 1.6, fontSize: 12, color: settingsMutedColor(context)),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: const NexusPageHeader(
        title: '数据备份',
        subtitle: '全量数据导出、备份恢复与本地存储管理',
      ),
      body: NexusPageLayout(
          desktopMaxWidth: 920,
          child: AsyncStateView(
            loading: _loading,
            child: ListView(
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
                      subtitle: '每 24 小时创建加密全量快照；桌面关闭程序后无法调度',
                      subtitleMaxLines: 4,
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
                if (DesktopTheme.maybeOf(context) != null)
                  const SettingsSectionTitle('备份内容说明')
                else
                  const SizedBox(height: 12),
                SettingsGroupCard(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (DesktopTheme.maybeOf(context) == null)
                      NexusDisclosure(
                        title: const Text('备份内容说明'),
                        headerPadding: const EdgeInsets.symmetric(vertical: 8),
                        child: backupContents,
                      )
                    else
                      backupContents,
                  ],
                ),
                NexusDisclosure(
                  key: ValueKey(_canRecover),
                  title: Text(_canRecover ? '需要恢复运行状态' : '运行维护'),
                  initiallyExpanded: _canRecover,
                  headerPadding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  contentPadding: EdgeInsets.zero,
                  child: Column(children: [
                    const SettingsSectionTitle('运行恢复'),
                    SettingsGroupCard(children: [
                      SettingsTile(
                        icon: Icons.health_and_safety_outlined,
                        iconColor: settingsMutedColor(context),
                        title: _recovering ? '正在恢复运行状态' : '恢复中断的数据维护',
                        subtitle: _recoveryMessage,
                        onTap: _canRecover && !_recovering
                            ? _recoverInterruptedMaintenance
                            : null,
                        trailingWidget: IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          tooltip: '重新检查维护状态',
                          onPressed: _recovering ? null : _load,
                        ),
                      ),
                    ]),
                  ]),
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
          )),
    );
  }
}
