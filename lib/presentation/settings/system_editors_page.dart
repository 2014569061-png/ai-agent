import '../widgets/nexus_page_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/device_action_runner.dart';
import '../../domain/system_connector_request.dart';
import '../../infrastructure/tools/android_system_editor_actions.dart';
import '../widgets/nexus_page_header.dart';
import 'device_action_confirm_sheet.dart';

/// Calendar/contact editor handoff. No implicit permission, storage or network.
class SystemEditorsPage extends ConsumerStatefulWidget {
  const SystemEditorsPage({super.key});
  @override
  ConsumerState<SystemEditorsPage> createState() => _SystemEditorsPageState();
}

class _SystemEditorsPageState extends ConsumerState<SystemEditorsPage> {
  var _kind = SystemConnectorId.calendar;
  final _name = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  List<Map<String, String>> _handlers = const [];
  int? _selected;
  int _generation = 0;
  bool _loading = true;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadHandlers();
  }

  @override
  void dispose() {
    for (final controller in [_name, _start, _end, _phone, _email]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadHandlers() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _handlers = const [];
      _selected = null;
      _message = null;
    });
    try {
      final rows = await AndroidSystemEditorActions.handlers(_kind)
          .timeout(const Duration(seconds: 5));
      if (!mounted || generation != _generation) return;
      setState(() {
        _handlers = rows;
        _selected = rows.length == 1 ? 0 : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _message = '未能读取编辑器。原生接点变更后需重新构建；也可能是系统不支持。';
      });
    }
  }

  Future<void> _prepare() async {
    if (_busy || _selected == null) return;
    final runner = ref.read(deviceActionRunnerProvider);
    const userRequest = '用户在连接器页面请求系统编辑器交接';
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final receiver = Map<String, String>.from(_handlers[_selected!]);
      final request = SystemConnectorRequest.fromJson({
        'connectorId': _kind.name,
        'operation': SystemConnectorRequest.operations[_kind],
        'arguments': _kind == SystemConnectorId.calendar
            ? {'title': _name.text, 'start': _start.text, 'end': _end.text}
            : {
                'name': _name.text,
                if (_phone.text.isNotEmpty) 'phone': _phone.text,
                if (_email.text.isNotEmpty) 'email': _email.text
              },
      });
      final prepared = await runner.prepare('系统编辑器交接（不是保存完成）', {
        'action': AndroidSystemEditorActions.action,
        'connectorRequest': request.toJson(),
        'packageName': receiver['packageName'],
        'receiverActivity': receiver['activityName'],
        'receiverVersion': receiver['version'],
      });
      if (!mounted) {
        await runner.reject([prepared], userRequest: userRequest);
        return;
      }
      if (!prepared.executable) {
        setState(() => _message = prepared.error ?? '无法生成预览，未交接');
        return;
      }
      final confirmed = await showDeviceActionConfirmSheet(context,
          title: '确认交给系统编辑器',
          subtitle: '内容将交给所列应用；请核对接收方与参数。最终保存需在系统界面确认。',
          actions: [prepared],
          confirmLabel: '请求打开编辑器');
      if (confirmed != true || !mounted) {
        await runner.reject([prepared], userRequest: userRequest);
        if (mounted) setState(() => _message = '已取消，未交接');
        return;
      }
      final outcomes =
          await runner.executeConfirmed([prepared], userRequest: userRequest);
      if (mounted) setState(() => _message = outcomes.single.result.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => _message = error.message.toString());
    } catch (_) {
      if (mounted) setState(() => _message = '流程未正常完成；如已出现系统界面请先检查，不要自动重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final calendar = _kind == SystemConnectorId.calendar;
    return Scaffold(
      appBar: const NexusPageHeader(
          title: '系统编辑器连接', subtitle: '日历 / 联系人 · 预览与审批后交接'),
      body: NexusPageLayout(
          child: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('本页不会读取通讯录或日历，不申请额外权限，也不会自动保存或发送内容。地图、文件和媒体适配仍在实施，未在此开放。'),
        const SizedBox(height: 16),
        DropdownButton<SystemConnectorId>(
          value: _kind,
          isExpanded: true,
          items: const [
            DropdownMenuItem(
                value: SystemConnectorId.calendar, child: Text('日历事件')),
            DropdownMenuItem(
                value: SystemConnectorId.contacts, child: Text('联系人'))
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value == null || value == _kind) return;
                  setState(() {
                    _kind = value;
                    _name.clear();
                  });
                  _loadHandlers();
                },
        ),
        if (_loading)
          const LinearProgressIndicator()
        else if (_handlers.isEmpty)
          const Text('未发现可处理的系统编辑器；不会自动安装应用或绕过到其他接收方。')
        else
          DropdownButton<int>(
            value: _selected,
            isExpanded: true,
            hint: const Text('选择内容接收方'),
            items: [
              for (var i = 0; i < _handlers.length; i++)
                DropdownMenuItem(
                    value: i,
                    child: Text(
                        '${_handlers[i]['label']} (${_handlers[i]['packageName']})',
                        overflow: TextOverflow.ellipsis))
            ],
            onChanged:
                _busy ? null : (value) => setState(() => _selected = value),
          ),
        TextButton(
            onPressed: _busy || _loading ? null : _loadHandlers,
            child: const Text('重新检测编辑器')),
        if (_handlers.isNotEmpty) ...[
          TextField(
              controller: _name,
              enabled: !_busy,
              maxLength: 200,
              decoration:
                  InputDecoration(labelText: calendar ? '事件标题' : '联系人名称')),
          if (calendar) ...[
            TextField(
                controller: _start,
                enabled: !_busy,
                decoration: const InputDecoration(
                    labelText: '开始时间（含 UTC 偏移）',
                    hintText: '2026-10-19T10:00:00+08:00')),
            TextField(
                controller: _end,
                enabled: !_busy,
                decoration: const InputDecoration(
                    labelText: '结束时间（含 UTC 偏移）',
                    hintText: '2026-10-19T11:00:00+08:00')),
          ] else ...[
            TextField(
                controller: _phone,
                enabled: !_busy,
                maxLength: 80,
                decoration: const InputDecoration(labelText: '电话（可选）')),
            TextField(
                controller: _email,
                enabled: !_busy,
                maxLength: 254,
                decoration: const InputDecoration(labelText: '电子邮件（可选）')),
          ],
          const SizedBox(height: 20),
          FilledButton(
              onPressed:
                  _busy || _loading || _selected == null ? null : _prepare,
              child: Text(_busy ? '处理中…' : '预览并核对交接')),
        ],
        if (_message != null)
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Semantics(liveRegion: true, child: Text(_message!))),
      ]))),
    );
  }
}
