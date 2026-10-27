import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_page_layout.dart';
import '../widgets/nexus_disclosure.dart';
import '../widgets/nexus_status_pill.dart';
import '../theme/desktop_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../application/assistant_role.dart';

class DefaultAssistantPage extends StatefulWidget {
  const DefaultAssistantPage(
      {super.key, this.source = const PlatformAssistantRoleSource()});
  final AssistantRoleSource source;
  @override
  State<DefaultAssistantPage> createState() => _DefaultAssistantPageState();
}

class _DefaultAssistantPageState extends State<DefaultAssistantPage>
    with WidgetsBindingObserver {
  AssistantRoleStatus? _status;
  bool _busy = false;
  String? _message;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    try {
      final status =
          await widget.source.status().timeout(const Duration(seconds: 5));
      if (mounted && generation == _generation) {
        setState(() => _status = status);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _status = null;
          _message = '未能读取系统状态，请刷新重试。';
        });
      }
    }
  }

  Future<void> _action(Future<bool> Function() action, String success) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final opened = await action().timeout(const Duration(seconds: 5));
      if (mounted) {
        setState(() => _message = opened ? success : '操作未完成，请核对系统设置后重试。');
      }
    } catch (_) {
      if (mounted) setState(() => _message = '系统操作未完成，请刷新后重试。');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
      }
    }
  }

  /// 一行「标签 + 状态徽标」，替代原来「标签：值」的纯文字。
  Widget _statusRow(String label, String value, {required bool ok}) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: 10),
        NexusStatusPill.fromString(
          ok ? 'completed' : 'draft',
          customLabel: value,
          isCompact: true,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    const privacyDetails = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('进入助手后点击麦克风，主动开始前台单句语音；默认使用设备端识别。系统入口不会自动录音，不启用后台唤醒词。'),
        SizedBox(height: 8),
        Text(
            '系统助手面板可主动“读取本页文字（仅本次）”。读取后会标明来源，须检查、编辑后才能加入草稿，两分钟后过期。会跳过可识别的输入控件，不读取截图；页面正文仍可能包含敏感信息。受保护页面无法读取时，请分享可分享的内容。'),
        SizedBox(height: 8),
        Text('锁屏时需先解锁。选择默认助手不会替你发送内容或执行手机动作，原有审批和预算继续生效。'),
      ],
    );
    return Scaffold(
      appBar: NexusPageHeader(title: '默认系统助手', actions: [
        IconButton(
            tooltip: '刷新状态',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh)),
      ]),
      body: NexusPageLayout(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        Text(status?.label ?? (_message == null ? '正在核对系统状态' : '暂时无法读取系统状态'),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text('选择 NEXUS 后，可用系统助手手势唤起入口面板，再进入原有助手对话。不同手机的手势和按键设置可能不同。'),
        const SizedBox(height: 16),
        if (status != null && status.supported) ...[
          // 状态用徽标而不是「文字：值」：一眼能看出是/否，不用读完整句。
          _statusRow(
            '默认选择',
            status.selected || status.roleHeld ? '已选择' : '未选择',
            ok: status.selected || status.roleHeld,
          ),
          const SizedBox(height: 8),
          _statusRow(
            '系统服务',
            status.active && status.ready ? '已激活' : '未激活',
            ok: status.active && status.ready,
          ),
          const SizedBox(height: 12),
          FilledButton(
              key: const ValueKey('assistant-role-request'),
              onPressed: _busy
                  ? null
                  : () => _action(
                      widget.source.requestRole, '已打开系统选择页，请选择 NEXUS 后返回。'),
              child: const Text('选择默认助手')),
          OutlinedButton(
              key: const ValueKey('assistant-role-settings'),
              onPressed: _busy
                  ? null
                  : () => _action(
                      widget.source.openSettings, '已打开系统设置，可更换或撤销默认助手。'),
              child: const Text('管理或撤销默认助手')),
          OutlinedButton(
              key: const ValueKey('assistant-role-show'),
              onPressed: _busy || !status.connected || status.locked
                  ? null
                  : () => _action(
                      widget.source.showSession, '已请求系统面板；也可用系统助手手势检查。'),
              child: const Text('检查系统唤起')),
        ],
        if (_message != null) ...[const SizedBox(height: 12), Text(_message!)],
        const SizedBox(height: 24),
        if (DesktopTheme.maybeOf(context) == null) ...[
          const Text('不会自动录音、发送内容或执行动作。读取页面文字需主动操作并确认，锁屏时需先解锁。'),
          const NexusDisclosure(
            title: Text('语音与页面内容说明'),
            headerPadding: EdgeInsets.symmetric(vertical: 12),
            child: privacyDetails,
          ),
        ] else ...[
          Text('语音与页面内容', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          privacyDetails,
        ],
      ])),
    );
  }
}
