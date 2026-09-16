import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/mcp_service.dart';
import '../../domain/unique_id.dart';
import '../../infrastructure/mcp/mcp_server_config.dart';
import '../../infrastructure/mcp/mcp_tool_provider.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/confirm_action.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_loading_skeleton.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_status_badge.dart';
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
  bool _loading = true;
  List<McpServerConfig> _servers = const [];
  final Map<String, bool> _testing = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final servers = await _service.loadAll();
    if (mounted) {
      setState(() {
        _servers = servers;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _toolProvider.dispose();
    super.dispose();
  }

  Future<void> _add() => _openServerConfigSheet(null);

  Future<void> _edit(McpServerConfig server) => _openServerConfigSheet(server);

  Future<void> _openServerConfigSheet(McpServerConfig? server) async {
    final isEdit = server != null;
    var kind = server?.kind ?? McpServerKind.http;
    final nameCtrl = TextEditingController(text: server?.name ?? '');
    final urlCtrl = TextEditingController(text: server?.url ?? '');
    final cmdCtrl = TextEditingController(text: server?.command ?? '');
    final argsCtrl = TextEditingController(text: server?.args.join(' ') ?? '');

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final hairline = isDark ? AppPalette.darkHairline : AppPalette.lightHairline;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTokens.radiusModal)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final isHttp = kind == McpServerKind.http;

          void applyPreset(String name, McpServerKind k, String urlOrCmd,
              [String args = '']) {
            setSheetState(() {
              kind = k;
              nameCtrl.text = name;
              if (k == McpServerKind.http) {
                urlCtrl.text = urlOrCmd;
                cmdCtrl.clear();
                argsCtrl.clear();
              } else {
                urlCtrl.clear();
                cmdCtrl.text = urlOrCmd;
                argsCtrl.text = args;
              }
            });
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isEdit ? AppStrings.editMcpServer : AppStrings.addMcpServer,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(sheetContext, false),
                        ),
                      ],
                    ),
                    Divider(height: 1, color: hairline),
                    const SizedBox(height: 12),

                    if (!isEdit) ...[
                      Text(
                        '常用预设模版',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.language_rounded, size: 14),
                            label: const Text('Streamable HTTP'),
                            labelStyle: const TextStyle(fontSize: 12),
                            onPressed: () => applyPreset(
                              '远程 HTTP 服务',
                              McpServerKind.http,
                              'http://127.0.0.1:8000/mcp',
                            ),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.table_chart_outlined, size: 14),
                            label: const Text('SQLite 数据库'),
                            labelStyle: const TextStyle(fontSize: 12),
                            onPressed: () => applyPreset(
                              'SQLite 数据库',
                              McpServerKind.stdio,
                              'uvx',
                              'mcp-server-sqlite --db-path ./workspace.db',
                            ),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.folder_outlined, size: 14),
                            label: const Text('文件系统'),
                            labelStyle: const TextStyle(fontSize: 12),
                            onPressed: () => applyPreset(
                              '本地文件系统',
                              McpServerKind.stdio,
                              'npx',
                              '-y @modelcontextprotocol/server-filesystem .',
                            ),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.terminal_rounded, size: 14),
                            label: const Text('自定义 STDIO'),
                            labelStyle: const TextStyle(fontSize: 12),
                            onPressed: () => applyPreset(
                              'STDIO 进程',
                              McpServerKind.stdio,
                              'python',
                              'server.py',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 模式选择 SegmentedButton
                    Center(
                      child: SegmentedButton<McpServerKind>(
                        segments: const [
                          ButtonSegment(
                            value: McpServerKind.http,
                            label: Text('HTTP 远程'),
                            icon: Icon(Icons.cloud_outlined, size: 16),
                          ),
                          ButtonSegment(
                            value: McpServerKind.stdio,
                            label: Text('STDIO 进程'),
                            icon: Icon(Icons.terminal_rounded, size: 16),
                          ),
                        ],
                        selected: {kind},
                        onSelectionChanged: (val) {
                          setSheetState(() => kind = val.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 14),

                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '服务名称 *',
                        hintText: '如：生产数据库、GitHub API',
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (isHttp)
                      TextField(
                        controller: urlCtrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'HTTP URL *',
                          hintText: 'http://127.0.0.1:8000/mcp',
                        ),
                      )
                    else ...[
                      TextField(
                        controller: cmdCtrl,
                        decoration: const InputDecoration(
                          labelText: '启动命令 *',
                          hintText: '如：uvx, npx, python, node',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: argsCtrl,
                        decoration: const InputDecoration(
                          labelText: '参数（空格分隔）',
                          hintText: '如：mcp-server-sqlite --db-path ./app.db',
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: AppTokens.kControlHeight,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppPalette.brand,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusControl),
                          ),
                        ),
                        onPressed: () {
                          if (nameCtrl.text.trim().isEmpty) {
                            FloatingToast.show(sheetContext, '请输入服务名称');
                            return;
                          }
                          if (isHttp && urlCtrl.text.trim().isEmpty) {
                            FloatingToast.show(sheetContext, '请输入 HTTP URL');
                            return;
                          }
                          if (!isHttp && cmdCtrl.text.trim().isEmpty) {
                            FloatingToast.show(sheetContext, '请输入启动命令');
                            return;
                          }
                          Navigator.pop(sheetContext, true);
                        },
                        child: Text(
                          isEdit ? AppStrings.saveConfig : AppStrings.addMcpServer,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (saved != true || !mounted) return;

    final isHttp = kind == McpServerKind.http;
    final name = nameCtrl.text.trim().isEmpty ? 'MCP Server' : nameCtrl.text.trim();

    if (isEdit) {
      await _service.save(server.copyWith(
        name: name,
        kind: kind,
        url: isHttp ? urlCtrl.text.trim() : null,
        command: isHttp ? null : cmdCtrl.text.trim(),
        args: isHttp
            ? server.args
            : argsCtrl.text
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
    } else {
      await _service.save(McpServerConfig(
        id: UniqueId.generate('mcp'),
        name: name,
        kind: kind,
        url: isHttp ? urlCtrl.text.trim() : null,
        command: isHttp ? null : cmdCtrl.text.trim(),
        args: isHttp
            ? const []
            : argsCtrl.text
                .split(RegExp(r'\s+'))
                .where((arg) => arg.isNotEmpty)
                .toList(),
      ));
      unawaited(HapticFeedback.mediumImpact());
      await _reload();
      if (mounted) {
        FloatingToast.show(context, AppStrings.mcpServerAdded,
            tone: ToastTone.success);
      }
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
      body: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: NexusListSkeleton(itemCount: 3),
            )
          : _servers.isEmpty
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
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          if (_testing[server.id] == true)
                                            const NexusStatusBadge(
                                              label: '测试中...',
                                              tone: NexusBadgeTone.warning,
                                              showDot: true,
                                            )
                                          else
                                            NexusStatusBadge(
                                              label: server.enabled ? '已启用' : '已停用',
                                              tone: server.enabled
                                                  ? NexusBadgeTone.success
                                                  : NexusBadgeTone.neutral,
                                            ),
                                          NexusStatusBadge(
                                            label: isStdio ? 'STDIO 进程' : 'HTTP 远程',
                                            tone: NexusBadgeTone.neutral,
                                          ),
                                          NexusStatusBadge(
                                            label: isStdio ? '高权限本地执行' : '受控网络请求',
                                            tone: isStdio
                                                ? NexusBadgeTone.warning
                                                : NexusBadgeTone.brand,
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
                                          ? const Icon(
                                              Icons.sync_rounded,
                                              size: 18,
                                              color: AppPalette.brandAction,
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
