import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../application/device_automation_service.dart';
import '../../domain/device_automation.dart';
import '../theme/app_palette.dart';
import '../widgets/nexus_loading_skeleton.dart';
import '../widgets/nexus_page_header.dart';
import 'device_action_confirm_sheet.dart';
import 'settings_components.dart';
import '../widgets/nexus_sheet.dart';

/// 设备自动化：触发器状态、待确认触发、规则、执行记录与撤销。
///
/// 触发只会产生通知；在这里点开待确认项后逐项预览，确认才执行。
class DeviceAutomationPage extends ConsumerStatefulWidget {
  const DeviceAutomationPage({
    super.key,
    this.initialFireId,
    this.isAndroidPlatform,
  });

  /// 从通知进入时要立即打开确认面板的触发 ID。
  final String? initialFireId;
  final bool? isAndroidPlatform;

  @override
  ConsumerState<DeviceAutomationPage> createState() =>
      _DeviceAutomationPageState();
}

class _DeviceAutomationPageState extends ConsumerState<DeviceAutomationPage> {
  bool _loading = true;
  bool _busy = false;
  bool _androidSupported = true;
  List<AutomationRule> _rules = const [];
  List<AutomationRun> _runs = const [];
  List<AutomationFire> _fires = const [];
  Map<String, dynamic> _status = const {};
  String? _statusError;
  bool _handledInitialFire = false;

  DeviceAutomationService get _service =>
      ref.read(deviceAutomationServiceProvider);

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
    final service = _service;
    await service.syncToNative();
    final rules = await service.rules();
    final runs = await service.runs();
    final fires = await service.pendingFires();
    Map<String, dynamic> status = const {};
    String? statusError;
    try {
      status = await service.bridge.triggerStatus();
    } catch (error) {
      statusError = '$error';
    }
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _runs = runs;
      _fires = fires;
      _status = status;
      _statusError = statusError;
      _loading = false;
    });
    final initial = widget.initialFireId;
    if (!_handledInitialFire && initial != null) {
      _handledInitialFire = true;
      final fire = fires.where((fire) => fire.fireId == initial).firstOrNull;
      if (fire != null) {
        unawaited(_confirmFire(fire));
      } else {
        _snack('该触发已处理或已过期（待确认记录保留 12 小时）');
      }
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------------------------------------------------------------
  // 执行确认
  // -------------------------------------------------------------------------

  Future<void> _confirmFire(AutomationFire fire) async {
    final rule = _rules.where((rule) => rule.id == fire.ruleId).firstOrNull ??
        await _service.findRule(fire.ruleId);
    if (rule == null) {
      await _service.discardFire(fire);
      _snack('规则已被删除，已清除该触发');
      await _load();
      return;
    }
    await _runRule(rule, fire: fire);
  }

  Future<void> _runRule(AutomationRule rule, {AutomationFire? fire}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final prepared = await _service.prepare(rule, fire: fire);
      if (!mounted) return;
      final confirmed = await showDeviceActionConfirmSheet(
        context,
        title: '执行「${rule.name}」？',
        subtitle: '${prepared.triggerText} · 预览 2 分钟内有效。每项单独签发一次性票据并写入审计日志。',
        actions: prepared.actions,
      );
      if (confirmed == true) {
        final run = await _service.executePrepared(prepared);
        if (mounted) await _showRun(run);
      } else {
        await _service.dismiss(prepared);
        _snack(fire == null ? '已取消运行' : '已放弃本次触发');
      }
    } catch (error) {
      _snack('执行失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _undoStep(AutomationRun run, int index) async {
    try {
      final prepared = await _service.prepareUndo(run.id, index);
      if (!mounted) return;
      final confirmed = await showDeviceActionConfirmSheet(
        context,
        title: '撤销这一步？',
        actions: [prepared],
        confirmLabel: '确认撤销',
      );
      if (confirmed != true) {
        await _service.runner.reject([prepared],
            userRequest: '撤销自动化执行记录 ${run.id}', toolName: 'android_automation');
        return;
      }
      final outcome = await _service.executeUndo(run.id, index, prepared);
      _snack(outcome.result.ok ? '已撤销' : '撤销失败：${outcome.result.message}');
    } catch (error) {
      _snack('无法撤销：$error');
    }
    await _load();
  }

  Future<void> _showRun(AutomationRun run) async {
    await showNexusSheet<void>(
context: context,
showDragHandle: true,
isScrollControlled: true,
builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('${run.ruleName} · ${_statusLabel(run.status)}',
                style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${run.trigger} · ${_time(run.startedAtMs)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (run.steps.isEmpty) const Text('本次没有执行任何动作。'),
            for (var i = 0; i < run.steps.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  run.steps[i].ok
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color:
                      run.steps[i].ok ? AppPalette.success : AppPalette.danger,
                ),
                title: Text(run.steps[i].description),
                subtitle: Text([
                  run.steps[i].message,
                  if (run.steps[i].undoneAtMs != null)
                    '已于 ${_time(run.steps[i].undoneAtMs!)} 撤销'
                  else if (run.steps[i].ok && !run.steps[i].reversible)
                    '不可撤销'
                  else if (run.steps[i].ok &&
                      run.steps[i].undoArguments == null)
                    '无法自动撤销（执行前状态未知或已是目标状态）',
                ].join('\n')),
                trailing: run.steps[i].canUndo
                    ? TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          unawaited(_undoStep(run, i));
                        },
                        child: const Text('撤销'),
                      )
                    : null,
              ),
          ],
        ),
      ),
);
  }

  // -------------------------------------------------------------------------
  // 规则管理
  // -------------------------------------------------------------------------

  /// 无特权通道时的降级提示；返回 false 表示用户取消。
  Future<bool> _confirmFallback(
    AutomationRule rule, {
    required String title,
    required String confirmLabel,
    List<String> extraLines = const [],
  }) async {
    final warnings = await _service.privilegeFallbackWarnings(rule);
    if (!mounted) return false;
    if ((warnings == null || warnings.isEmpty) && extraLines.isEmpty) {
      return true;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text([
            ...extraLines,
            if (warnings != null && warnings.isNotEmpty) ...[
              if (extraLines.isNotEmpty) '',
              '当前没有 Root/Shizuku（或缺少对应系统权限），以下动作触发时无法自动完成，只能打开系统页面由你手动操作：',
              ...warnings.map((warning) => '· $warning'),
              '',
              '可在“设备能力”页连接 Shizuku 或授予权限后再启用。',
            ],
          ].join('\n')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _toggle(AutomationRule rule, bool enabled) async {
    if (enabled &&
        !await _confirmFallback(rule, title: '启用规则', confirmLabel: '仍然启用')) {
      return;
    }
    try {
      await _service.setEnabled(rule.id, enabled, userRequest: '在设置页切换规则');
    } catch (error) {
      _snack('$error');
    }
    await _load();
  }

  Future<void> _delete(AutomationRule rule) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${rule.name}」？'),
        content: const Text('删除后不再触发；执行历史会保留。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await _service.deleteRule(rule.id, userRequest: '在设置页删除规则');
    await _load();
  }

  Future<void> _ruleMenu(AutomationRule rule) async {
    final choice = await showNexusSheet<String>(
context: context,
showDragHandle: true,
builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('立即运行（先预览）'),
              onTap: () => Navigator.pop(context, 'run'),
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('执行记录'),
              onTap: () => Navigator.pop(context, 'history'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: AppPalette.danger),
              title: const Text('删除规则'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
);
    if (!mounted) return;
    switch (choice) {
      case 'run':
        await _runRule(rule);
      case 'history':
        final runs = _runs.where((run) => run.ruleId == rule.id).toList();
        if (runs.isEmpty) {
          _snack('暂无执行记录');
        } else {
          await _showRun(runs.first);
        }
      case 'delete':
        await _delete(rule);
    }
  }

  Future<void> _addFromTemplate() async {
    final template = await showNexusSheet<String>(
context: context,
showDragHandle: true,
builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: const Text('定时开启勿扰'),
              subtitle: const Text('例如每天 23:00'),
              onTap: () => Navigator.pop(context, 'dnd'),
            ),
            ListTile(
              leading: const Icon(Icons.wifi_rounded),
              title: const Text('连上指定 Wi-Fi 后打开应用'),
              subtitle: const Text('需要定位权限以识别 Wi-Fi 名称'),
              onTap: () => Navigator.pop(context, 'wifi'),
            ),
            ListTile(
              leading: const Icon(Icons.battery_alert_outlined),
              title: const Text('电量低时省电'),
              subtitle: const Text('降低亮度并关闭蓝牙（关闭蓝牙需 Root）'),
              onTap: () => Navigator.pop(context, 'battery'),
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('定时清理授权目录中的旧文件'),
              subtitle: const Text('不可撤销；每次最多 100 个，执行前列出清单'),
              onTap: () => Navigator.pop(context, 'clean'),
            ),
          ],
        ),
      ),
);
    if (!mounted || template == null) return;
    final draft = await showDialog<_RuleDraft>(
      context: context,
      builder: (context) => _TemplateDialog(
        template: template,
        loadFolders: _service.authorizedFolders,
      ),
    );
    if (draft == null || !mounted) return;
    final probe = AutomationRule(
      id: 'draft',
      name: draft.name,
      enabled: true,
      trigger: draft.trigger,
      actions: draft.actions,
      createdAtMs: 0,
      updatedAtMs: 0,
    );
    final ok = await _confirmFallback(
      probe,
      title: '确认创建',
      confirmLabel: '创建',
      extraLines: probe.requiresRoot || probe.hasIrreversibleAction
          ? [
              '触发：${draft.trigger.describe()}',
              ...draft.actions.map((action) => '· ${action.describe()}'),
              '',
              if (probe.requiresRoot) '包含需要 Root/Shizuku 的动作。',
              if (probe.hasIrreversibleAction) '包含不可撤销动作。',
              '触发时只发通知，每次仍需你确认才会执行。',
            ]
          : const [],
    );
    if (!ok || !mounted) return;
    try {
      await _service.createRule(
        name: draft.name,
        trigger: draft.trigger,
        actions: draft.actions,
        userRequest: '在设置页从模板创建',
      );
      if (draft.trigger.type == AutomationTriggerType.wifiConnected) {
        await _requestLocation();
      }
      await Permission.notification.request();
    } catch (error) {
      _snack('创建失败：$error');
    }
    await _load();
  }

  Future<void> _requestLocation() async {
    final fine = await Permission.locationWhenInUse.request();
    if (fine.isGranted) {
      // Android 11+ 需单独申请“始终允许”，系统会跳转到设置页。
      await Permission.locationAlways.request();
    }
    await _load();
  }

  // -------------------------------------------------------------------------
  // 构建
  // -------------------------------------------------------------------------

  String _time(int ms) => DateTime.fromMillisecondsSinceEpoch(ms)
      .toLocal()
      .toString()
      .substring(0, 16);

  String? _lastEvaluation(Object? raw) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['atMs'] is! num) return null;
      final fired = decoded['fired'] is num ? decoded['fired'] as num : 0;
      final skipped =
          decoded['skipped'] is List ? (decoded['skipped'] as List).length : 0;
      return '${_time((decoded['atMs'] as num).toInt())} · 触发 $fired 条'
          '${skipped > 0 ? ' · $skipped 条因条件不可判定而跳过' : ''}';
    } catch (_) {
      return null;
    }
  }

  String _statusLabel(String status) => switch (status) {
        'executed' => '已执行',
        'partial' => '部分成功',
        'failed' => '失败',
        'dismissed' => '已放弃',
        'skipped' => '已跳过',
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: NexusPageHeader(
        title: '设备自动化',
        subtitle: '触发 → 通知 → 预览确认 → 执行',
        actions: [
          IconButton(
            tooltip: '从模板新建',
            onPressed: _androidSupported && !_loading ? _addFromTemplate : null,
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _body(context),
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
              subtitle: 'Wi-Fi、电量触发与设备动作需要 Android 系统接口。',
              showChevron: false,
            ),
          ]),
        ],
      );
    }
    if (_loading && _rules.isEmpty && _runs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: NexusListSkeleton(itemCount: 5),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
        children: [
          if (_fires.isNotEmpty) ...[
            const SettingsSectionTitle('待确认的触发'),
            SettingsGroupCard(children: [
              for (var i = 0; i < _fires.length; i++) ...[
                if (i > 0) const SettingsDivider(),
                SettingsTile(
                  key: Key('fire-${_fires[i].fireId}'),
                  icon: Icons.notifications_active_outlined,
                  iconColor: AppPalette.warning,
                  title: _fires[i].ruleName,
                  subtitle:
                      '${_fires[i].trigger} · ${_time(_fires[i].firedAtMs)} · 点按查看预览',
                  onTap: _busy ? null : () => _confirmFire(_fires[i]),
                ),
              ],
            ]),
          ],
          const SettingsSectionTitle('触发器状态'),
          _statusCard(),
          const SettingsSectionTitle('规则'),
          _rulesCard(),
          const SettingsSectionTitle('最近执行'),
          _runsCard(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              '规则触发后只发送通知，不会在后台静默执行。执行时每个动作都经过 android_device '
              '的白名单校验、预览与一次性票据，并写入审计日志；Root 与不可撤销动作需要二次确认。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final status = _status;
    if (_statusError != null) {
      return SettingsGroupCard(children: [
        SettingsTile(
          icon: Icons.error_outline_rounded,
          iconColor: AppPalette.danger,
          title: '无法读取触发器状态',
          subtitle: _statusError,
          showChevron: false,
        ),
      ]);
    }
    final battery = status['batteryPercent'];
    final ssidStatus = status['ssidStatus']?.toString();
    final ssid = status['ssid']?.toString();
    final fine = status['fineLocationGranted'] == true;
    final background = status['backgroundLocationGranted'] == true;
    final notifications = status['notificationsGranted'] != false;
    return SettingsGroupCard(children: [
      SettingsTile(
        icon: Icons.battery_std_rounded,
        title: '电量',
        subtitle: battery is num
            ? '$battery%${status['charging'] == true ? ' · 充电中' : ''}'
            : '未知',
        showChevron: false,
      ),
      const SettingsDivider(),
      SettingsTile(
        icon: Icons.wifi_rounded,
        title: '当前 Wi-Fi',
        subtitle: switch (ssidStatus) {
          'ok' => ssid ?? '未知',
          'not_connected' => '未连接 Wi-Fi',
          'wifi_disabled' => 'Wi-Fi 已关闭',
          'wifi_unavailable' => '设备不支持 Wi-Fi',
          'location_permission_required' => '需要定位权限才能识别 Wi-Fi 名称',
          'ssid_hidden_or_location_off' => '无法识别名称：系统定位可能已关闭',
          _ => ssid ?? ssidStatus ?? '未知',
        },
        showChevron: false,
      ),
      const SettingsDivider(),
      SettingsTile(
        icon: Icons.location_on_outlined,
        iconColor: fine && background ? AppPalette.success : AppPalette.warning,
        title: '定位权限（Wi-Fi 触发）',
        subtitle: fine
            ? background
                ? '已授权（含后台）'
                : '仅前台；后台检测 Wi-Fi 需“始终允许”'
            : '未授权',
        onTap: fine && background ? null : _requestLocation,
        showChevron: !(fine && background),
      ),
      const SettingsDivider(),
      SettingsTile(
        icon: Icons.notifications_outlined,
        iconColor: notifications ? AppPalette.success : AppPalette.danger,
        title: '通知权限',
        subtitle: notifications ? '已授权' : '未授权：触发后无法提醒你确认',
        onTap: notifications
            ? null
            : () async {
                await Permission.notification.request();
                await _load();
              },
        showChevron: !notifications,
      ),
      if (_lastEvaluation(status['lastEvaluation']) case final last?) ...[
        const SettingsDivider(),
        SettingsTile(
          icon: Icons.update_rounded,
          title: '最近检查',
          subtitle: last,
          showChevron: false,
        ),
      ],
    ]);
  }

  Widget _rulesCard() {
    if (_rules.isEmpty) {
      return SettingsGroupCard(children: [
        SettingsTile(
          icon: Icons.add_circle_outline_rounded,
          title: '还没有规则',
          subtitle: '点右上角 + 从模板新建，或在对话中让助手创建。',
          onTap: _addFromTemplate,
        ),
      ]);
    }
    return SettingsGroupCard(children: [
      for (var i = 0; i < _rules.length; i++) ...[
        if (i > 0) const SettingsDivider(),
        SettingsTile(
          key: Key('rule-${_rules[i].id}'),
          icon: Icons.bolt_outlined,
          iconColor: _rules[i].requiresRoot ? AppPalette.warning : null,
          title: _rules[i].name,
          subtitle: [
            _rules[i].trigger.describe(),
            _rules[i].actions.map((action) => action.describe()).join('；'),
            if (_rules[i].requiresRoot) 'Root',
            if (_rules[i].hasIrreversibleAction) '含不可撤销动作',
          ].join(' · '),
          trailingWidget: SettingsSwitch(
            value: _rules[i].enabled,
            onChanged: (value) => _toggle(_rules[i], value),
          ),
          showChevron: false,
          onTap: () => _ruleMenu(_rules[i]),
        ),
      ],
    ]);
  }

  Widget _runsCard() {
    if (_runs.isEmpty) {
      return const SettingsGroupCard(children: [
        SettingsTile(
          icon: Icons.history_rounded,
          title: '暂无执行记录',
          showChevron: false,
        ),
      ]);
    }
    final shown = _runs.take(20).toList();
    return SettingsGroupCard(children: [
      for (var i = 0; i < shown.length; i++) ...[
        if (i > 0) const SettingsDivider(),
        SettingsTile(
          // X5：部分成功属于警告而非错误。
          icon: switch (shown[i].status) {
            'executed' => Icons.check_circle_outline,
            'partial' => Icons.warning_amber_rounded,
            'dismissed' => Icons.do_not_disturb_on_outlined,
            _ => Icons.error_outline,
          },
          iconColor: switch (shown[i].status) {
            'executed' => AppPalette.success,
            'partial' => AppPalette.warning,
            'dismissed' => null,
            _ => AppPalette.danger,
          },
          title: '${shown[i].ruleName} · ${_statusLabel(shown[i].status)}',
          subtitle: '${shown[i].trigger} · ${_time(shown[i].startedAtMs)}'
              '${shown[i].steps.any((step) => step.canUndo) ? ' · 可撤销' : ''}',
          onTap: () => _showRun(shown[i]),
        ),
      ],
    ]);
  }
}

class _RuleDraft {
  const _RuleDraft(this.name, this.trigger, this.actions);

  final String name;
  final AutomationTrigger trigger;
  final List<AutomationAction> actions;
}

class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog({required this.template, required this.loadFolders});

  final String template;
  final Future<List<Map<String, String>>> Function() loadFolders;

  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  final _name = TextEditingController();
  final _text = TextEditingController();
  TimeOfDay _time = const TimeOfDay(hour: 23, minute: 0);
  double _threshold = 20;
  double _days = 30;
  String? _folderUri;
  String? _folderName;
  List<Map<String, String>>? _folders;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.text = switch (widget.template) {
      'dnd' => '夜间勿扰',
      'wifi' => '到公司打开应用',
      'battery' => '低电量省电',
      _ => '清理旧文件',
    };
    if (widget.template == 'clean') {
      _time = const TimeOfDay(hour: 3, minute: 0);
      unawaited(_loadFolders());
    }
  }

  Future<void> _loadFolders() async {
    try {
      final folders = await widget.loadFolders();
      if (mounted) setState(() => _folders = folders);
    } catch (error) {
      if (mounted) setState(() => _folders = const []);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    AutomationTrigger trigger;
    List<AutomationAction> actions;
    switch (widget.template) {
      case 'dnd':
        trigger =
            AutomationTrigger.time(hour: _time.hour, minute: _time.minute);
        actions = const [
          AutomationAction('set_do_not_disturb', {'enabled': true})
        ];
      case 'wifi':
        final parts = _text.text.split('|');
        final ssid = parts.first.trim();
        final app = parts.length > 1 ? parts[1].trim() : '';
        if (ssid.isEmpty || app.isEmpty) {
          setState(() => _error = '请按“Wi-Fi 名称|应用名”填写');
          return;
        }
        trigger = AutomationTrigger.wifiConnected(ssid);
        actions = [
          AutomationAction('launch_app_by_name', {'appName': app})
        ];
      case 'battery':
        trigger = AutomationTrigger.batteryBelow(_threshold.round());
        actions = const [
          AutomationAction('set_brightness', {'value': 0.2}),
          AutomationAction('set_bluetooth', {'enabled': false}),
        ];
      default:
        if (_folderUri == null) {
          setState(() => _error = '请选择已授权目录（在“设备能力”页授权）');
          return;
        }
        final extension = _text.text.trim().replaceFirst('.', '');
        trigger =
            AutomationTrigger.time(hour: _time.hour, minute: _time.minute);
        actions = [
          AutomationAction('clean_folder', {
            'treeUri': _folderUri,
            'olderThanDays': _days.round(),
            if (extension.isNotEmpty) 'extension': extension,
          }),
        ];
    }
    final rule = AutomationRule(
      id: 'draft',
      name: name,
      enabled: true,
      trigger: trigger,
      actions: actions,
      createdAtMs: 0,
      updatedAtMs: 0,
    );
    final error = rule.validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, _RuleDraft(name, trigger, actions));
  }

  @override
  Widget build(BuildContext context) {
    final template = widget.template;
    return AlertDialog(
      title: const Text('新建自动化'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              maxLength: 40,
              decoration: const InputDecoration(labelText: '规则名称'),
            ),
            if (template == 'dnd' || template == 'clean')
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('每天触发时间'),
                trailing: Text(_time.format(context)),
                onTap: () async {
                  final picked = await showTimePicker(
                      context: context, initialTime: _time);
                  if (picked != null) setState(() => _time = picked);
                },
              ),
            if (template == 'wifi')
              TextField(
                controller: _text,
                decoration: const InputDecoration(
                  labelText: 'Wi-Fi 名称|应用名',
                  hintText: 'Office-5G|钉钉',
                ),
              ),
            if (template == 'battery') ...[
              Text('电量低于 ${_threshold.round()}% 时'),
              Slider(
                value: _threshold,
                min: 5,
                max: 95,
                divisions: 18,
                onChanged: (value) => setState(() => _threshold = value),
              ),
            ],
            if (template == 'clean') ...[
              if (_folders == null)
                const LinearProgressIndicator()
              else if (_folders!.isEmpty)
                const Text('没有已授权目录；请先在“设备能力”或文件管理中授权目录。')
              else
                DropdownButton<String>(
                  isExpanded: true,
                  value: _folderUri,
                  hint: const Text('选择目录'),
                  items: [
                    for (final folder in _folders!)
                      DropdownMenuItem(
                        value: folder['uri'],
                        child: Text(folder['name'] ?? folder['uri'] ?? ''),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _folderUri = value;
                    _folderName = _folders!
                        .firstWhere((folder) => folder['uri'] == value)['name'];
                  }),
                ),
              if (_folderName != null)
                Text('目录：$_folderName',
                    style: Theme.of(context).textTheme.bodySmall),
              Text('删除 ${_days.round()} 天前修改的文件'),
              Slider(
                value: _days,
                min: 1,
                max: 365,
                onChanged: (value) => setState(() => _days = value),
              ),
              TextField(
                controller: _text,
                decoration: const InputDecoration(
                  labelText: '仅限扩展名（可选）',
                  hintText: 'apk',
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('下一步')),
      ],
    );
  }
}
