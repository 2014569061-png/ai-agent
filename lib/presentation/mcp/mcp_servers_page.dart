import 'package:flutter/material.dart';

import '../../application/mcp_service.dart';
import '../../infrastructure/mcp/mcp_server_config.dart';
import '../widgets/immersive_sheet.dart';

/// 独立的 MCP 服务器管理页，供设置页和深链接复用。
class McpServersPage extends StatefulWidget {
  const McpServersPage({super.key});

  @override
  State<McpServersPage> createState() => _McpServersPageState();
}

class _McpServersPageState extends State<McpServersPage> {
  final _service = McpService();
  List<McpServerConfig> _servers = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final servers = await _service.loadAll();
    if (mounted) setState(() => _servers = servers);
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final ok = await showImmersiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增 MCP 服务器'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '名称')),
          TextField(
              controller: url,
              decoration: const InputDecoration(labelText: 'HTTP URL')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true || url.text.trim().isEmpty) return;
    await _service.save(McpServerConfig(
      id: 'mcp-${DateTime.now().microsecondsSinceEpoch}',
      name: name.text.trim().isEmpty ? 'MCP Server' : name.text.trim(),
      kind: McpServerKind.http,
      url: url.text.trim(),
    ));
    await _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('MCP 服务器')),
        body: _servers.isEmpty
            ? const Center(child: Text('尚未配置 MCP 服务器'))
            : ListView.builder(
                itemCount: _servers.length,
                itemBuilder: (context, index) {
                  final server = _servers[index];
                  return SwitchListTile(
                    secondary: Icon(server.kind == McpServerKind.http
                        ? Icons.dns_outlined
                        : Icons.terminal),
                    title: Text(server.name),
                    subtitle: Text(server.url ?? server.command ?? ''),
                    value: server.enabled,
                    onChanged: (enabled) async {
                      await _service.toggleServer(server.id, enabled);
                      await _reload();
                    },
                  );
                },
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: _add,
          tooltip: '新增 MCP 服务器',
          child: const Icon(Icons.add),
        ),
      );
}
