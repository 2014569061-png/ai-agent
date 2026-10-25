import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../application/desktop_workflow_service.dart';

class DesktopWorkflowsDialog extends StatefulWidget {
  const DesktopWorkflowsDialog({super.key});
  @override
  State<DesktopWorkflowsDialog> createState() => _DesktopWorkflowsDialogState();
}

class _DesktopWorkflowsDialogState extends State<DesktopWorkflowsDialog> {
  final _service = DesktopWorkflowService();
  List<DesktopWorkflow> _custom = [];
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _service.custom();
      if (mounted) setState(() => _custom = items);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _create() async {
    final name = TextEditingController(), prompt = TextEditingController();
    try {
      final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('保存自定义工作流'),
                  content: SizedBox(
                      width: 500,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(
                            controller: name,
                            decoration: const InputDecoration(labelText: '名称')),
                        TextField(
                            controller: prompt,
                            minLines: 4,
                            maxLines: 8,
                            decoration:
                                const InputDecoration(labelText: '目标、步骤与约束'))
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('保存'))
                  ]));
      if (accepted != true) return;
      final item = DesktopWorkflow.fromJson({
        'id': 'custom-${DateTime.now().microsecondsSinceEpoch}',
        'name': name.text,
        'prompt': prompt.text
      });
      await _service.save([..._custom, item]);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      name.dispose();
      prompt.dispose();
    }
  }

  Future<void> _import() async {
    try {
      final files = await FilePicker.pickFiles(
          type: FileType.custom, allowedExtensions: ['json']);
      if (files.isEmpty) return;
      final imported =
          _service.parse(utf8.decode(await files.first.readAsBytes()));
      await _service.save([
        ..._custom,
        ...imported.map((w) => DesktopWorkflow(
            id: 'import-${DateTime.now().microsecondsSinceEpoch}-${w.id}',
            name: w.name,
            prompt: w.prompt))
      ]);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '导入失败：$error');
    }
  }

  Future<void> _export() async {
    try {
      await FilePicker.saveFile(
          fileName: 'nexus-workflows.json',
          bytes: utf8.encode(_service.export(_custom)));
    } catch (error) {
      if (mounted) setState(() => _error = '导出失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('工作流'),
          content: SizedBox(
              width: 660,
              height: 440,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('选中后将指令放入当前草稿；发送前可补充目标、选择模型并检查工具授权。'),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    Expanded(
                        child: ListView(children: [
                      for (final workflow in [
                        ...DesktopWorkflow.builtins,
                        ..._custom
                      ])
                        ExpansionTile(title: Text(workflow.name), children: [
                          Padding(
                              padding: const EdgeInsets.all(12),
                              child: SelectableText(workflow.prompt)),
                          Wrap(children: [
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, workflow),
                                child: const Text('使用此工作流')),
                            if (_custom.contains(workflow))
                              TextButton(
                                  onPressed: () async {
                                    await _service.save(_custom
                                        .where((w) => w.id != workflow.id)
                                        .toList());
                                    await _load();
                                  },
                                  child: const Text('删除'))
                          ])
                        ])
                    ])),
                  ])),
          actions: [
            TextButton(onPressed: _import, child: const Text('导入')),
            TextButton(onPressed: _export, child: const Text('导出')),
            TextButton(onPressed: _create, child: const Text('新建工作流')),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'))
          ]);
}
