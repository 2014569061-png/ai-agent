import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/mcp_service.dart';
import '../../infrastructure/mcp/mcp_server_config.dart';
import '../../infrastructure/mcp/mcp_tool_provider.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/immersive_sheet.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';

/// 独立的 MCP 服务器管理页，供设置页和深链接复用。
class McpServersPage extends StatefulWidget {
  const McpServersPage({super.key});

  @override
  State<McpServersPage> createState() => _McpServersPageState();
}

class _McpServersPageState extends State<McpServersPage> {
  final _service = McpService();
  final _toolProvider = McpToolProvider();
  List<McpServerConfig> _servers = const [];
  final Map<String, bool> _testing = {};

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
              style: FilledButton.styleFrom(
                elevation: 0,
                backgroundColor: AppPalette.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppTokens.radiusControl),
                ),
              ),
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
    unawaited(HapticFeedback.mediumImpact());
    await _reload();
    if (mounted) {
      FloatingToast.show(context, '已添加 MCP 服务器', tone: ToastTone.success);
    }
  }

  @override
  void dispose() {
    _toolProvider.dispose();
    super.dispose();
  }

  Future<void> _edit(McpServerConfig server) async {
    final name = TextEditingController(text: server.name);
    final url = TextEditingController(text: server.url);
    final command = TextEditingController(text: server.command);
    final args = TextEditingController(text: server.args.join(' '));
    final ok = await showImmersiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑 MCP 服务器'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '名称')),
          const SizedBox(height: 4),
          if (server.kind == McpServerKind.http)
            TextField(
                controller: url,
                decoration: const InputDecoration(labelText: 'HTTP URL'))
          else ...[
            TextField(
                controller: command,
                decoration: const InputDecoration(labelText: '启动命令')),
            TextField(
                controller: args,
                decoration: const InputDecoration(labelText: '参数（空格分隔）')),
          ],
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(
                elevation: 0,
                backgroundColor: AppPalette.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppTokens.radiusControl),
                ),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;

    final isHttp = server.kind == McpServerKind.http;
    if (isHttp && url.text.trim().isEmpty) return;
    if (!isHttp && command.text.trim().isEmpty) return;

    await _service.save(server.copyWith(
      name: name.text.trim(),
      url: isHttp ? url.text.trim() : null,
      command: isHttp ? null : command.text.trim(),
      args: isHttp
          ? server.args
          : args.text
              .split(RegExp(r'\s+'))
              .where((arg) => arg.isNotEmpty)
              .toList(),
    ));
    unawaited(HapticFeedback.mediumImpact());
    await _reload();
    if (mounted) {
      FloatingToast.show(context, '已保存修改', tone: ToastTone.success);
    }
  }

  Future<void> _testConnection(McpServerConfig server) async {
    if (_testing[server.id] == true) return;
    setState(() => _testing[server.id] = true);
    final result = await _toolProvider.testConnection(server);
    if (!mounted) return;
    setState(() => _testing[server.id] = false);
    FloatingToast.show(
      context,
      result.ok ? '连接成功：发现 ${result.toolCount} 个工具' : '连接失败：${result.error}',
      tone: result.ok ? ToastTone.success : ToastTone.danger,
    );
  }

  Future<void> _deleteServer(McpServerConfig server) async {
    final confirmed = await showImmersiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 MCP 服务器'),
        content: Text('确定删除服务器“${server.name}”吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    unawaited(HapticFeedback.mediumImpact());
    await _service.delete(server.id);
    await _reload();
    if (mounted) {
      FloatingToast.show(context, '已删除服务器', tone: ToastTone.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      appBar: NexusPageHeader(
        title: 'MCP 服务器',
        subtitle: 'Model Context Protocol 协议扩展与工具注入',
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '新增服务器',
            onPressed: _add,
          ),
        ],
      ),
      body: _servers.isEmpty
          ? const EmptyStateView(
              icon: Icons.dns_outlined,
              title: '尚未配置 MCP 服务器',
              message: '点击右下角按钮添加你的第一个 MCP 服务。',
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _servers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final server = _servers[index];
                return SectionCard(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: server.enabled
                                ? (isDark
                                    ? AppPalette.brandSoftDark
                                    : AppPalette.brandSoftLight)
                                : (isDark
                                    ? AppPalette.darkSurface
                                    : AppPalette.lightSurface),
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusControl),
                            border: Border.all(
                              color: server.enabled
                                  ? AppPalette.brand
                                  : (isDark
                                      ? AppPalette.darkHairline
                                      : AppPalette.lightHairline),
                            ),
                          ),
                          child: Icon(
                            server.kind == McpServerKind.http
                                ? Icons.dns_outlined
                                : Icons.terminal_rounded,
                            size: 18,
                            color: server.enabled
                                ? AppPalette.brand
                                : (isDark
                                    ? AppPalette.darkTextMuted
                                    : AppPalette.lightTextMuted),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      server.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppPalette.darkSurface
                                          : AppPalette.lightSurface,
                                      borderRadius: BorderRadius.circular(
                                          AppTokens.radiusControl),
                                      border: Border.all(
                                        color: isDark
                                            ? AppPalette.darkHairline
                                            : AppPalette.lightHairline,
                                      ),
                                    ),
                                    child: Text(
                                      server.kind == McpServerKind.http
                                          ? 'HTTP'
                                          : 'STDIO',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? AppPalette.darkTextMuted
                                            : AppPalette.lightTextMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                server.url ?? server.command ?? '未指定地址',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? AppPalette.darkTextMuted
                                      : AppPalette.lightTextMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: server.enabled,
                          onChanged: (enabled) async {
                            unawaited(HapticFeedback.selectionClick());
                            await _service.toggleServer(server.id, enabled);
                            await _reload();
                          },
                        ),
                        IconButton(
                          icon: _testing[server.id] == true
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.wifi_tethering_rounded,
                                  size: 20),
                          tooltip: '测试连接',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _testConnection(server),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: '编辑此服务',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _edit(server),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 20),
                          tooltip: '删除此服务',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _deleteServer(server),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        backgroundColor: AppPalette.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        ),
        tooltip: '新增 MCP 服务器',
        child: const Icon(Icons.add),
      ),
    );
  }
}
