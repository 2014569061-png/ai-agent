import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/device_action_runner.dart';
import '../../application/device_backup_service.dart';
import '../../application/local_error_copy.dart';
import '../theme/app_palette.dart';
import '../widgets/nexus_loading_skeleton.dart';
import '../widgets/nexus_page_header.dart';
import 'device_action_confirm_sheet.dart';
import 'settings_components.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/nexus_segmented_button.dart';

/// 备份与恢复：通讯录/短信/通话记录导出、应用数据与目录备份（Root）、
/// 按备份恢复。所有写操作都经 android_device 预览 → 确认 → 审计。
///
/// 不提供整机一键恢复；恢复前会列出归档内容、大小与覆盖范围，并自动
/// 生成恢复前快照以便回滚。
class DeviceBackupsPage extends ConsumerStatefulWidget {
  const DeviceBackupsPage({super.key, this.catalog, this.isAndroidPlatform});

  final DeviceBackupCatalog? catalog;
  final bool? isAndroidPlatform;

  @override
  ConsumerState<DeviceBackupsPage> createState() => _DeviceBackupsPageState();
}

class _DeviceBackupsPageState extends ConsumerState<DeviceBackupsPage> {
  bool _loading = true;
  bool _busy = false;
  bool _androidSupported = true;
  Map<String, dynamic> _listing = const {};
  String? _error;

  DeviceBackupCatalog get _bridge =>
      widget.catalog ?? ref.read(deviceBackupCatalogProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final supported = widget.isAndroidPlatform ??
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
    if (!supported) {
      setState(() {
        _androidSupported = false;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final listing = await _bridge.listBackups();
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = LocalErrorCopy.of(error, action: '读取备份').summary;
        _loading = false;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 预览 → 确认 → 执行（单项）。
  Future<void> _run(String description, Map<String, dynamic> arguments,
      {String confirmLabel = '确认执行'}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final runner = ref.read(deviceActionRunnerProvider);
    final userRequest = '在“备份与恢复”页：$description';
    try {
      final prepared = await runner.prepare(description, arguments);
      if (!mounted) return;
      if (!prepared.executable) {
        _snack(prepared.error ?? '无法生成预览');
        return;
      }
      final confirmed = await showDeviceActionConfirmSheet(
        context,
        title: description,
        subtitle: '预览 2 分钟内有效；执行结果会写入审计日志。',
        actions: [prepared],
        confirmLabel: confirmLabel,
      );
      if (confirmed != true) {
        await runner.reject([prepared], userRequest: userRequest);
        return;
      }
      final outcome = (await runner.executeConfirmed(
        [prepared],
        userRequest: userRequest,
      ))
          .single;
      final result = outcome.result;
      final undo = result.data?['undoBackupId'];
      _snack(result.ok
          ? '${result.message}${undo != null ? '；恢复前快照：$undo' : ''}'
          : '失败（${result.code}）：${result.message}');
    } catch (error) {
      _snack(LocalErrorCopy.of(error, action: '备份操作').headline());
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _newBackup() async {
    final choice = await showNexusSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.contacts_outlined),
              title: const Text('通讯录'),
              subtitle: const Text('导出为 vCard；首次会请求通讯录权限'),
              onTap: () => Navigator.pop(context, 'contacts'),
            ),
            ListTile(
              leading: const Icon(Icons.sms_outlined),
              title: const Text('短信'),
              subtitle: const Text('导出为 JSON（只读备份）；首次会请求短信权限'),
              onTap: () => Navigator.pop(context, 'sms'),
            ),
            ListTile(
              leading: const Icon(Icons.call_outlined),
              title: const Text('通话记录'),
              subtitle: const Text('导出为 JSON（只读备份）；首次会请求通话记录权限'),
              onTap: () => Navigator.pop(context, 'call_log'),
            ),
            ListTile(
              leading: const Icon(Icons.apps_outlined),
              title: const Text('应用数据（Root）'),
              subtitle: const Text('配置包：shared_prefs/databases/files；或完整数据'),
              onTap: () => Navigator.pop(context, 'app'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('目录打包（Root）'),
              subtitle: const Text('/sdcard 下的指定目录'),
              onTap: () => Navigator.pop(context, 'dir'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'contacts':
      case 'sms':
      case 'call_log':
        final label = switch (choice) {
          'contacts' => '通讯录',
          'sms' => '短信',
          _ => '通话记录',
        };
        await _run('备份$label', {
          'action': 'backup_personal_data',
          'category': choice,
        });
      case 'app':
        final input = await _askText(
          title: '备份应用数据',
          label: '应用包名',
          hint: 'com.example.app',
          withScope: true,
        );
        if (input == null) return;
        await _run('备份 ${input.$1} 的${input.$2 == 'full' ? '完整数据' : '配置包'}', {
          'action': 'backup_app_data',
          'packageName': input.$1,
          'scope': input.$2,
        });
      case 'dir':
        final input = await _askText(
          title: '打包目录',
          label: '目录路径',
          hint: '/sdcard/Documents/notes',
        );
        if (input == null) return;
        await _run('打包目录 ${input.$1}', {
          'action': 'backup_directory',
          'path': input.$1,
        });
    }
  }

  Future<(String, String)?> _askText({
    required String title,
    required String label,
    required String hint,
    bool withScope = false,
  }) {
    final controller = TextEditingController();
    var scope = 'config';
    return showDialog<(String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(labelText: label, hintText: hint),
              ),
              if (withScope) ...[
                const SizedBox(height: 12),
                NexusSegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'config', label: Text('配置包')),
                    ButtonSegment(value: 'full', label: Text('完整数据')),
                  ],
                  selected: {scope},
                  onSelectionChanged: (value) =>
                      setDialogState(() => scope = value.first),
                ),
                const SizedBox(height: 6),
                Text(
                  scope == 'config' ? '设置、数据库与文件，不含缓存' : '整个数据目录（不含缓存）',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) Navigator.pop(context, (text, scope));
              },
              child: const Text('生成预览'),
            ),
          ],
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _backupMenu(Map<String, dynamic> backup) async {
    final id = backup['backupId']?.toString() ?? '';
    final kind = backup['kind']?.toString();
    final canRestoreApp = kind == 'app_data' && backup['restorable'] == true;
    final canRestoreContacts =
        kind == 'personal' && backup['category'] == 'contacts';
    final choice = await showNexusSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('查看内容与完整性'),
              onTap: () => Navigator.pop(context, 'inspect'),
            ),
            if (canRestoreApp)
              ListTile(
                leading: const Icon(Icons.restore_rounded),
                title: const Text('恢复到应用（Root）'),
                subtitle: const Text('先预览覆盖范围；恢复前自动快照当前数据'),
                onTap: () => Navigator.pop(context, 'restore_app'),
              ),
            if (canRestoreContacts)
              ListTile(
                leading: const Icon(Icons.person_add_alt_outlined),
                title: const Text('导入通讯录'),
                subtitle: const Text('交给系统通讯录应用导入，可在其中选择账户'),
                onTap: () => Navigator.pop(context, 'restore_contacts'),
              ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: AppPalette.danger),
              title: const Text('删除备份（不可撤销）'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'inspect':
        await _inspect(id);
      case 'restore_app':
        await _run('恢复 ${backup['packageName']} 的应用数据',
            {'action': 'restore_app_data', 'backupId': id},
            confirmLabel: '确认恢复');
      case 'restore_contacts':
        await _run(
            '导入通讯录备份 $id', {'action': 'restore_contacts', 'backupId': id});
      case 'delete':
        await _run('删除备份 $id', {'action': 'backup_delete', 'backupId': id},
            confirmLabel: '确认删除');
    }
  }

  Future<void> _inspect(String id) async {
    Map<String, dynamic> detail;
    try {
      detail = await _bridge.inspectBackup(id);
    } catch (error) {
      _snack(LocalErrorCopy.of(error, action: '读取备份').headline());
      return;
    }
    if (!mounted) return;
    final entries = detail['entries'] is List ? detail['entries'] as List : [];
    final files = detail['files'] is List ? detail['files'] as List : [];
    await showNexusSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(id, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText([
              '类型：${_kindLabel(detail)}',
              if (detail['packageName'] != null)
                '应用：${detail['packageName']} ${detail['versionName'] ?? ''}',
              if (detail['installedVersionName'] != null)
                '当前安装版本：${detail['installedVersionName']}',
              if (detail['restoreCompatibility'] != null)
                '恢复兼容性：${detail['restoreCompatibility']}',
              if (detail['sourcePath'] != null) '来源：${detail['sourcePath']}',
              '归档大小：${_size(detail['totalBytes'])}',
              if (detail['uncompressedBytes'] != null)
                '解压后：${_size(detail['uncompressedBytes'])}',
              if (detail['entryCount'] != null)
                '条目：${detail['entryCount']}'
                    '${(detail['remainingEntries'] ?? 0) is num && (detail['remainingEntries'] as num) > 0 ? '（下方仅列前 20 个，另有 ${detail['remainingEntries']} 个）' : ''}',
              if (detail['itemCount'] != null) '记录数：${detail['itemCount']}',
              if (detail['restoreCoverage'] is List &&
                  (detail['restoreCoverage'] as List).isNotEmpty)
                '可恢复范围：${(detail['restoreCoverage'] as List).join('、')}',
              if (detail['notes'] != null) '说明：${detail['notes']}',
              '文件完整性：${files.every((f) => f is Map && f['sizeMatches'] == true) ? '通过' : '异常，请勿恢复'}',
              if (detail['unsafeEntries'] is List &&
                  (detail['unsafeEntries'] as List).isNotEmpty)
                '不安全条目：${(detail['unsafeEntries'] as List).join('、')}',
            ].join('\n')),
            if (entries.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('内容（前 20 个）', style: Theme.of(context).textTheme.titleSmall),
              for (final entry in entries.take(20))
                Text(
                  entry is Map
                      ? '${entry['path'] ?? entry['name']}  ${_size(entry['bytes'] ?? entry['size'])}'
                      : '$entry',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _size(Object? bytes) {
    if (bytes is! num) return '未知';
    var size = bytes.toDouble();
    const units = ['B', 'KB', 'MB', 'GB'];
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  String _kindLabel(Map<String, dynamic> backup) => switch (backup['kind']) {
        'personal' => switch (backup['category']) {
            'contacts' => '通讯录',
            'sms' => '短信',
            'call_log' => '通话记录',
            _ => '个人数据',
          },
        'app_data' => '${backup['tag']}'.startsWith('pre_restore')
            ? '恢复前快照'
            : backup['scope'] == 'full'
                ? '应用完整数据'
                : '应用配置包',
        'directory' => '目录打包',
        _ => '${backup['kind']}',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: NexusPageHeader(
        title: '手机资料备份',
        subtitle: '预览后执行 · 恢复前自动快照',
        actions: [
          IconButton(
            tooltip: '新建备份',
            onPressed: _androidSupported && !_busy ? _newBackup : null,
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: NexusPageLayout(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (!_androidSupported) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SettingsGroupCard(children: [
            SettingsTile(
              icon: Icons.info_outline_rounded,
              title: '此页面仅支持 Android',
              subtitle: '备份与恢复依赖 Android 的文件访问接口。',
              showChevron: false,
            ),
          ]),
        ],
      );
    }
    if (_loading && _listing.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: NexusListSkeleton(itemCount: 4),
      );
    }
    final backups = (_listing['backups'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            SettingsGroupCard(children: [
              SettingsTile(
                icon: Icons.error_outline_rounded,
                iconColor: AppPalette.danger,
                title: '无法读取备份列表',
                subtitle: _error,
                showChevron: false,
              ),
            ]),
          SettingsSectionTitle(
              '备份（${_listing['total'] ?? backups.length}）· 剩余空间 ${_size(_listing['freeBytes'])}'),
          if (_error == null && backups.isEmpty)
            SettingsGroupCard(children: [
              SettingsTile(
                icon: Icons.backup_outlined,
                title: '还没有备份',
                subtitle: '点右上角 + 新建。通讯录/短信/通话记录首次备份时才会请求权限。',
                onTap: _newBackup,
              ),
            ]),
          if (backups.isNotEmpty)
            SettingsGroupCard(children: [
              for (var i = 0; i < backups.length; i++) ...[
                if (i > 0) const SettingsDivider(),
                SettingsTile(
                  key: Key('backup-${backups[i]['backupId']}'),
                  icon: switch (backups[i]['kind']) {
                    'personal' => Icons.contacts_outlined,
                    'app_data' => Icons.apps_outlined,
                    _ => Icons.folder_zip_outlined,
                  },
                  title:
                      '${_kindLabel(backups[i])}${backups[i]['packageName'] != null ? ' · ${backups[i]['packageName']}' : ''}',
                  subtitle: [
                    if (backups[i]['createdAtMs'] is num)
                      DateTime.fromMillisecondsSinceEpoch(
                              (backups[i]['createdAtMs'] as num).toInt())
                          .toLocal()
                          .toString()
                          .substring(0, 16),
                    _size(backups[i]['totalBytes']),
                    if (backups[i]['itemCount'] != null)
                      '${backups[i]['itemCount']} 条',
                    if (backups[i]['sourcePath'] != null)
                      '${backups[i]['sourcePath']}',
                  ].join(' · '),
                  onTap: _busy ? null : () => _backupMenu(backups[i]),
                ),
              ],
            ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              '备份保存在应用专属外部目录（卸载应用会一并删除，请自行导出重要备份）。'
              '不提供整机一键恢复；恢复只针对单个应用，且会先展示文件清单、大小与覆盖范围。'
              '短信与通话记录仅做只读备份，Android 不允许普通应用写回。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
