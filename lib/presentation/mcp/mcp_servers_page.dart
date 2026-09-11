import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/mcp_service.dart';
import '../../infrastructure/mcp/mcp_server_config.dart';
import '../../infrastructure/mcp/mcp_tool_provider.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/confirm_action.dart';
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
        title: const Text(AppStrings.addMcpServer),
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
              child: const Text(AppStrings.cancel)),
          FilledButton(
              style: FilledButton.styleFrom(
                elevation: 0,
                backgroundColor: AppPalette.brandAction,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                ),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text(AppStrings.saveConfig)),
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
      FloatingToast.show(context, AppStrings.mcpServerAdded,
          tone: ToastTone.success);
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
        title: const Text(AppStrings.editMcpServer),
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
              child: const Text(AppStrings.cancel)),
          FilledButton(
              style: FilledButton.styleFrom(
                elevation: 0,
                backgroundColor: AppPalette.brandAction,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                ),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text(AppStrings.saveConfig)),
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
      FloatingToast.show(context, AppStrings.mcpServerSaved,
          tone: ToastTone.success);
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
      result.ok
          ? AppStrings.mcpConnectionFoundTools(result.toolCount)
          : AppStrings.mcpConnectionFailed(result.error),
      tone: result.ok ? ToastTone.success : ToastTone.danger,
    );
  }

  Future<void> _deleteServer(McpServerConfig server) async {
    final confirmed = await showConfirmAction(
      context,
      title: AppStrings.deleteMcpServer,
      message: AppStrings.confirmDeleteMcpServer(server.name),
      confirmLabel: AppStrings.delete,
      isDanger: true,
      bulletItems: [
        '服务器：${server.name}',
        '模式：${server.kind == McpServerKind.http ? "HTTP 远程" : "STDIO 本地进程"}',
        if (server.url != null) '地址：${server.url}',
        if (server.command != null) '命令：${server.command}',
      ],
    );
    if (!confirmed) return;
    unawaited(HapticFeedback.mediumImpact());
    await _service.delete(server.id);
    await _reload();
    if (mounted) {
      FloatingToast.show(context, AppStrings.mcpServerDeleted,
          tone: ToastTone.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      appBar: NexusPageHeader(
        title: AppStrings.mcpServers,
        subtitle: AppStrings.mcpServersHint,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: AppStrings.addMcpServer,
            onPressed: _add,
          ),
        ],
      ),
      body: _servers.isEmpty
          ? EmptyStateView(
              icon: Icons.dns_outlined,
              title: AppStrings.noMcpServers,
              message: AppStrings.addFirstMcpServerHint,
              actionLabel: AppStrings.addMcpServer,
              onAction: _add,
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _servers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final server = _servers[index];
                final isStdio = server.kind != McpServerKind.http;

                return SectionCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: server.enabled
                                    ? (isDark
                                        ? AppPalette.brandSoftDark
                                        : AppPalette.brandSoftLight)
                                    : (isDark
                                        ? AppPalette.darkSurface
                                        : AppPalette.lightSurface),
                                borderRadius: BorderRadius.circular(
                                    AppTokens.radiusControl),
                                border: Border.all(
                                  color: server.enabled
                                      ? AppPalette.brand
                                      : (isDark
                                          ? AppPalette.darkHairline
                                          : AppPalette.lightHairline),
                                ),
                              ),
                              child: Icon(
                                isStdio
                                    ? Icons.terminal_rounded
                                    : Icons.dns_outlined,
                                size: 20,
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
                                  Text(
                                    server.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      // 状态
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: server.enabled
                                              ? AppPalette.success
                                                  .withValues(alpha: 0.12)
                                              : (isDark
                                                  ? AppPalette.darkSurface
                                                  : AppPalette.lightSurface),
                                          borderRadius: BorderRadius.circular(
                                              AppTokens.radiusPill),
                                        ),
                                        child: Text(
                                          server.enabled ? '已启用' : '已停用',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: server.enabled
                                                ? AppPalette.success
                                                : (isDark
                                                    ? AppPalette.darkTextMuted
                                                    : AppPalette
                                                        .lightTextMuted),
                                          ),
                                        ),
                                      ),
                                      // 来源
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? AppPalette.darkSurface
                                              : AppPalette.lightSurface,
                                          borderRadius: BorderRadius.circular(
                                              AppTokens.radiusPill),
                                          border: Border.all(
                                            color: isDark
                                                ? AppPalette.darkHairline
                                                : AppPalette.lightHairline,
                                          ),
                                        ),
                                        child: Text(
                                          isStdio ? 'STDIO 进程' : 'HTTP 远程',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w500,
                                            color: isDark
                                                ? AppPalette.darkTextMuted
                                                : AppPalette.lightTextMuted,
                                          ),
                                        ),
                                      ),
                                      // 风险等级
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: isStdio
                                              ? Colors.amber
                                                  .withValues(alpha: 0.12)
                                              : AppPalette.brand
                                                  .withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                              AppTokens.radiusPill),
                                        ),
                                        child: Text(
                                          isStdio ? '高权限本地执行' : '受控网络请求',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w500,
                                            color: isStdio
                                                ? Colors.amber.shade800
                                                : AppPalette.brand,
                                          ),
                                        ),
                                      ),
                                    ],
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
                            PopupMenuButton<String>(
                              icon:
                                  const Icon(Icons.more_vert_rounded, size: 20),
                              tooltip: '更多操作',
                              onSelected: (action) {
                                switch (action) {
                                  case 'test':
                                    _testConnection(server);
                                    break;
                                  case 'edit':
                                    _edit(server);
                                    break;
                                  case 'delete':
                                    _deleteServer(server);
                                    break;
                                }
                              },
                              itemBuilder: (ctx) => [
                                PopupMenuItem(
                                  value: 'test',
                                  child: Row(
                                    children: [
                                      _testing[server.id] == true
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            )
                                          : const Icon(
                                              Icons.wifi_tethering_rounded,
                                              size: 18),
                                      const SizedBox(width: 8),
                                      const Text('测试连接'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 18),
                                      SizedBox(width: 8),
                                      Text('编辑配置'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline_rounded,
                                          size: 18, color: AppPalette.danger),
                                      SizedBox(width: 8),
                                      Text(
                                        '删除服务器',
                                        style:
                                            TextStyle(color: AppPalette.danger),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppPalette.darkSurface
                                : AppPalette.lightSurface,
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusControl),
                          ),
                          child: SelectableText(
                            server.url ?? server.command ?? '未指定地址',
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: isDark
                                  ? AppPalette.darkTextMuted
                                  : AppPalette.lightTextMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        backgroundColor: AppPalette.brandAction,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        ),
        tooltip: AppStrings.addMcpServer,
        child: const Icon(Icons.add),
      ),
    );
  }
}
