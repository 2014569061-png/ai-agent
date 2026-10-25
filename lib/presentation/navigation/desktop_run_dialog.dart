import 'package:flutter/material.dart';
import '../../application/desktop_run_service.dart';

class DesktopRunDialog extends StatefulWidget {
  const DesktopRunDialog({super.key, required this.root});
  final String root;
  @override
  State<DesktopRunDialog> createState() => _DesktopRunDialogState();
}

class _DesktopRunDialogState extends State<DesktopRunDialog> {
  final _command = TextEditingController();
  final _url = TextEditingController(text: 'http://localhost:3000');
  bool _busy = true;
  String? _error;
  final _service = DesktopRunService.instance;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await DesktopRunConfiguration.load(widget.root);
      if (config != null) {
        _command.text = config.command;
        _url.text = config.url;
      }
    } catch (error) {
      _error = '$error';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = DesktopRunConfiguration(
          command: _command.text.trim(), url: _url.text.trim());
      await config.save(widget.root);
      if (!_service.running(widget.root)) {
        await _service.start(widget.root, config);
      }
      await _service.waitReady(widget.root, config.previewUrl);
      if (mounted) Navigator.pop(context, config.previewUrl);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _command.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('项目运行配置'),
          content: SizedBox(
              width: 620,
              height: 420,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.root,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _command,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                            labelText: '启动命令',
                            hintText: 'npm run dev -- --port 3000')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _url,
                        enabled: !_busy,
                        decoration: const InputDecoration(labelText: '预览地址')),
                    const SizedBox(height: 12),
                    const Text('点击启动将在当前项目执行上述命令。停止会结束它的子进程。'),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 8),
                    Expanded(
                        child: ListenableBuilder(
                            listenable: _service,
                            builder: (_, child) => SingleChildScrollView(
                                child: SelectableText(
                                    _service.output(widget.root),
                                    style: const TextStyle(
                                        fontFamily: 'Consolas',
                                        fontSize: 12))))),
                  ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭')),
            TextButton(
                onPressed: _service.running(widget.root)
                    ? () async {
                        await _service.stop(widget.root);
                        if (mounted) setState(() {});
                      }
                    : null,
                child: const Text('停止服务器')),
            FilledButton(
                onPressed: _busy ? null : _start,
                child: Text(_busy
                    ? '等待服务器…'
                    : (_service.running(widget.root) ? '打开预览' : '保存并启动'))),
          ]);
}
