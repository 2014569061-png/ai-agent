import '../theme/mobile_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import '../theme/desktop_theme.dart';
import '../widgets/desktop_resource_view.dart';
import 'package:flutter/services.dart';

import '../../application/mcp_service.dart';
import '../../domain/unique_id.dart';
import '../../infrastructure/mcp/mcp_server_config.dart';
import '../../infrastructure/mcp/mcp_tool_provider.dart';
import '../l10n/app_strings.dart';
import '../motion/nexus_motion.dart';
import '../motion/motion_preferences.dart';
import '../motion/nexus_staggered_entrance.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/confirm_action.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_loading_skeleton.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_status_badge.dart';
import '../widgets/section_card.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/nexus_segmented_button.dart';
import '../widgets/nexus_switch.dart';

/// 独立的 MCP 服务器管理页，供设置页和深链接复用。
class McpServersPage extends StatefulWidget {
  const McpServersPage({super.key, this.service});

  /// 可注入同一持久化服务，便于隔离工作区和页面测试；默认行为不变。
  final McpService? service;

  @override
  State<McpServersPage> createState() => _McpServersPageState();
}

class _McpServersPageState extends State<McpServersPage> {
  late final McpService _service;
  final _toolProvider = McpToolProvider();
  bool _loading = true;
  Object? _loadError;
  final Set<String> _toggling = {};
  List<McpServerConfig> _servers = const [];
  final Map<String, bool> _testing = {};
  final Map<String, ({bool ok, int toolCount, String? error})>
      _connectionResults = {};

  /// stdio 真机开关（默认关闭）。开启前页面完全不暴露本地进程模式。
  bool _stdioEnabled = false;

  /// 连点标题解锁真机开关的计数。
  int _tapCount = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? McpService();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final servers = await _service.loadAll();
      final stdioEnabled = await McpStdioAvailability.readEnabled();
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _stdioEnabled = stdioEnabled;
        _connectionResults.clear();
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error;
          _loading = false;
        });
      }
    }
  }

  /// 连点标题 5 次切换 stdio 真机开关。开启时给出明确的风险确认。
  Future<void> _handleTitleTap() async {
    _tapCount++;
    if (_tapCount < 5) return;
    _tapCount = 0;
    if (!McpStdioAvailability.supportedByPlatform) {
      FloatingToast.show(context, '当前平台不支持本地进程模式', tone: ToastTone.danger);
      return;
    }
    if (_stdioEnabled) {
      await McpStdioAvailability.writeEnabled(false);
      await _reload();
      if (mounted) {
        FloatingToast.show(context, '已关闭本地进程模式（STDIO）');
      }
      return;
    }
    final confirmed = await showConfirmAction(
      context,
      title: '开启本地进程模式（STDIO）',
      message: 'STDIO 型 MCP 服务器会以你的身份在本机启动任意可执行文件，'
          '拥有与 App 相同的文件与网络权限，且不受网络访问策略保护。'
          '仅在你完全信任该服务器来源时开启。',
      confirmLabel: '我已了解风险，开启',
      isDanger: true,
      bulletItems: const [
        '启动的进程拥有 App 的全部本地权限',
        '每个 STDIO 服务器保存前仍需再次确认',
        '子进程不会继承 App 的环境变量',
      ],
    );
    if (!confirmed) return;
    await McpStdioAvailability.writeEnabled(true);
    await _reload();
    if (mounted) {
      FloatingToast.show(context, '本地进程模式已开启', tone: ToastTone.success);
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
    // 编辑历史遗留的 stdio 配置时，若真机开关已关，回落到 HTTP 模式，
    // 避免在一个被禁用的模式上停留。
    if (kind == McpServerKind.stdio && !_stdioEnabled) {
      kind = McpServerKind.http;
    }
    final nameCtrl = TextEditingController(text: server?.name ?? '');
    final urlCtrl = TextEditingController(text: server?.url ?? '');
    final cmdCtrl = TextEditingController(text: server?.command ?? '');
    final argsCtrl = TextEditingController(text: server?.args.join(' ') ?? '');

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;

    // 在 builder 外捕获：builder 闭包里拿不到 State 字段，且开表期间不应变化。
    final stdioEnabled = _stdioEnabled;

    final saved = await showNexusSheet<bool>(
      context: context,
      isScrollControlled: true,
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
                        Expanded(
                          child: Text(
                            isEdit
                                ? AppStrings.editMcpServer
                                : AppStrings.addMcpServer,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppTokens.fontSizeBodyLarge,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          tooltip: '关闭配置',
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
                          fontSize: AppTokens.fontSizeFootnote,
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
                            avatar:
                                const Icon(Icons.language_rounded, size: 14),
                            label: const Text('Streamable HTTP'),
                            labelStyle: const TextStyle(
                                fontSize: AppTokens.fontSizeFootnote),
                            onPressed: () => applyPreset(
                              '远程 HTTP 服务',
                              McpServerKind.http,
                              // 不要用 127.0.0.1：MCP HTTP 出口走 NetworkAccessPolicy，
                              // 本机 / 内网地址会被直接拒绝，预设必须是公网示例。
                              'https://mcp.example.com/mcp',
                            ),
                          ),
                          if (stdioEnabled) ...[
                            ActionChip(
                              avatar: const Icon(Icons.table_chart_outlined,
                                  size: 14),
                              label: const Text('SQLite 数据库'),
                              labelStyle: const TextStyle(
                                  fontSize: AppTokens.fontSizeFootnote),
                              onPressed: () => applyPreset(
                                'SQLite 数据库',
                                McpServerKind.stdio,
                                'uvx',
                                'mcp-server-sqlite --db-path ./workspace.db',
                              ),
                            ),
                            ActionChip(
                              avatar:
                                  const Icon(Icons.folder_outlined, size: 14),
                              label: const Text('文件系统'),
                              labelStyle: const TextStyle(
                                  fontSize: AppTokens.fontSizeFootnote),
                              onPressed: () => applyPreset(
                                '本地文件系统',
                                McpServerKind.stdio,
                                'npx',
                                '-y @modelcontextprotocol/server-filesystem .',
                              ),
                            ),
                            ActionChip(
                              avatar:
                                  const Icon(Icons.terminal_rounded, size: 14),
                              label: const Text('自定义 STDIO'),
                              labelStyle: const TextStyle(
                                  fontSize: AppTokens.fontSizeFootnote),
                              onPressed: () => applyPreset(
                                'STDIO 进程',
                                McpServerKind.stdio,
                                'python',
                                'server.py',
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 模式选择 SegmentedButton
                    Center(
                      child: NexusSegmentedButton<McpServerKind>(
                        segments: [
                          const ButtonSegment(
                            value: McpServerKind.http,
                            label: Text('HTTP 远程'),
                            icon: Icon(Icons.cloud_outlined, size: 16),
                          ),
                          // stdio 型在移动端默认隐藏：它会 spawn 任意本地可执行
                          // 文件，属于高权限本地执行面。需连点标题 5 次打开开关。
                          if (stdioEnabled)
                            const ButtonSegment(
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

                    if (isHttp) ...[
                      TextField(
                        controller: urlCtrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'HTTP URL *',
                          hintText: 'https://mcp.example.com/mcp',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '仅支持公网地址；本机（127.0.0.1）与内网地址会被安全策略拒绝。',
                        style: TextStyle(
                            fontSize: AppTokens.fontSizeBadge,
                            color: textMuted),
                      ),
                    ] else ...[
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
                      height: DesktopTheme.maybeOf(context) == null
                          ? null
                          : AppTokens.kControlHeight,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: Size.fromHeight(
                              DesktopTheme.maybeOf(context) == null
                                  ? AppTokens.kMinTouchTarget
                                  : AppTokens.kControlHeight),
                          backgroundColor: MobileTheme.brand(context),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                MobileTheme.controlRadius(context)),
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
                          isEdit
                              ? AppStrings.saveConfig
                              : AppStrings.addMcpServer,
                          style: const TextStyle(
                              fontSize: AppTokens.fontSizeBody,
                              fontWeight: FontWeight.w500),
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
      removeInnerViewInsets: true,
    );

    if (saved != true || !mounted) return;

    final isHttp = kind == McpServerKind.http;
    final name =
        nameCtrl.text.trim().isEmpty ? 'MCP Server' : nameCtrl.text.trim();
    final command = isHttp ? '' : cmdCtrl.text.trim();
    final args = isHttp
        ? const <String>[]
        : argsCtrl.text
            .split(RegExp(r'\s+'))
            .where((arg) => arg.isNotEmpty)
            .toList();

    // stdio 型保存前必须过一道高危确认：它等于把本地命令执行权交给了这个配置。
    if (!isHttp) {
      if (!_stdioEnabled) {
        FloatingToast.show(context, '本地进程模式未开启，无法保存 STDIO 服务器',
            tone: ToastTone.danger);
        return;
      }
      final confirmed = await showConfirmAction(
        context,
        title: '保存本地进程服务器',
        message: '该配置会在每次连接时以你的身份启动下列命令。'
            '请确认来源可信、参数无误。',
        confirmLabel: '确认保存',
        isDanger: true,
        bulletItems: [
          '服务名称：$name',
          '启动命令：$command',
          if (args.isNotEmpty) '参数：${args.join(' ')}',
        ],
      );
      if (!confirmed) return;
    }

    if (isEdit) {
      await _service.save(server.copyWith(
        name: name,
        kind: kind,
        url: isHttp ? urlCtrl.text.trim() : null,
        command: isHttp ? null : command,
        args: isHttp ? server.args : args,
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
        command: isHttp ? null : command,
        args: args,
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
    ({bool ok, int toolCount, String? error}) result;
    try {
      result = await _toolProvider.testConnection(server);
    } catch (error) {
      result = (ok: false, toolCount: 0, error: error.toString());
    }
    if (!mounted) return;
    setState(() {
      _testing[server.id] = false;
      _connectionResults[server.id] = result;
    });
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

  Future<void> _desktopToggle(McpServerConfig server, bool enabled) async {
    if (_toggling.contains(server.id)) return;
    setState(() => _toggling.add(server.id));
    try {
      await _service.toggleServer(server.id, enabled);
      await _reload();
    } catch (_) {
      if (mounted) {
        FloatingToast.show(context, '状态保存失败，请重试', tone: ToastTone.danger);
      }
    } finally {
      if (mounted) setState(() => _toggling.remove(server.id));
    }
  }

  Widget _desktopServers() => DesktopResourceView<McpServerConfig>(
        title: 'MCP 服务',
        icon: Icons.dns_outlined,
        description: '管理外部工具连接。启用配置不等于在线；测试结果仅反映最近一次手动检查。',
        items: _servers,
        loading: _loading,
        error: _loadError,
        onReload: _reload,
        onTitleTap: _handleTitleTap,
        searchHint: '搜索服务名称或传输类型',
        searchText: (server) =>
            '${server.name} ${server.kind == McpServerKind.http ? 'HTTP 远程' : 'STDIO 本地'}',
        filters: [
          DesktopResourceFilter('已启用', (server) => server.enabled),
          DesktopResourceFilter('已停用', (server) => !server.enabled),
          DesktopResourceFilter(
              'HTTP', (server) => server.kind == McpServerKind.http),
          if (_stdioEnabled ||
              _servers.any((server) => server.kind == McpServerKind.stdio))
            DesktopResourceFilter(
                'STDIO', (server) => server.kind == McpServerKind.stdio),
        ],
        sorts: [
          DesktopResourceSort('名称 A–Z',
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()))
        ],
        actions: [
          FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('添加 MCP 服务'))
        ],
        emptyTitle: '还没有 MCP 服务',
        emptyMessage: '添加受信任的服务，连接前先核对地址、传输方式和工具权限。',
        itemBuilder: (context, server) {
          final result = _connectionResults[server.id];
          final testing = _testing[server.id] == true;
          final http = server.kind == McpServerKind.http;
          return DesktopResourceCard(
            key: ValueKey('desktop-mcp-${server.id}'),
            title: server.name,
            icon: http ? Icons.dns_outlined : Icons.terminal_outlined,
            description: http
                ? desktopEndpointLabel(server.url ?? '')
                : '本地进程配置 · 请在编辑器中核对命令与参数',
            metadata: [
              server.enabled ? '已启用配置' : '已停用配置',
              http ? 'HTTP 远程' : 'STDIO · 本地执行权限',
              if (testing)
                '测试中…'
              else if (result == null)
                '尚未测试连接'
              else if (result.ok)
                '最近测试通过 · ${result.toolCount} 项工具'
              else
                '最近测试失败'
            ],
            actions: [
              OutlinedButton.icon(
                  onPressed: testing || _toggling.contains(server.id)
                      ? null
                      : () => _testConnection(server),
                  icon: Icon(testing ? Icons.sync : Icons.wifi_tethering,
                      size: 16),
                  label: Text(testing ? '测试中…' : '测试连接')),
              TextButton.icon(
                  onPressed: testing ? null : () => _edit(server),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('编辑')),
              TextButton(
                  onPressed: _toggling.contains(server.id) || testing
                      ? null
                      : () => _desktopToggle(server, !server.enabled),
                  child: Text(server.enabled ? '停用配置' : '启用配置')),
              TextButton.icon(
                  onPressed: testing ? null : () => _deleteServer(server),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('删除'))
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    if (DesktopTheme.maybeOf(context) != null) return _desktopServers();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: MobileTheme.pageBackground(context),
      appBar: NexusPageHeader(
        title: AppStrings.mcpServers,
        // 连点标题右侧 5 次解锁 stdio 真机开关（无可见入口，避免误触）。
        onTitleTap: _handleTitleTap,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: AppStrings.addMcpServer,
            onPressed: _add,
          ),
        ],
      ),
      body: NexusPageLayout(
          child: _loadError != null
              ? EmptyStateView(
                  icon: Icons.error_outline,
                  title: 'MCP 配置读取失败',
                  actionLabel: '重试',
                  onAction: _reload)
              : _loading
                  ? const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: NexusListSkeleton(itemCount: 3),
                    )
                  : _servers.isEmpty
                      ? const EmptyStateView(
                          icon: Icons.dns_outlined,
                          title: AppStrings.noMcpServers,
                          message: AppStrings.addFirstMcpServerHint,
                        )
                      : NexusStaggeredEntrance(
                          child: ListView.separated(
                            physics: NexusMotion.listPhysics,
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                            itemCount: _servers.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppTokens.sp3),
                            itemBuilder:
                                NexusStaggeredItem.wrap((context, index) {
                              final server = _servers[index];
                              final isStdio = server.kind != McpServerKind.http;
                              final connectionResult =
                                  _connectionResults[server.id];

                              return SectionCard(
                                glass: false,
                                child: Padding(
                                  padding: const EdgeInsets.all(AppTokens.sp4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                                      : AppPalette
                                                          .brandSoftLight)
                                                  : (isDark
                                                      ? AppPalette.darkSurface
                                                      : AppPalette
                                                          .lightSurface),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      MobileTheme.controlRadius(
                                                          context)),
                                              border: Border.all(
                                                color: server.enabled
                                                    ? MobileTheme.brand(context)
                                                    : (isDark
                                                        ? AppPalette
                                                            .darkHairline
                                                        : AppPalette
                                                            .lightHairline),
                                              ),
                                            ),
                                            child: Icon(
                                              isStdio
                                                  ? Icons.terminal_rounded
                                                  : Icons.dns_outlined,
                                              size: 20,
                                              color: server.enabled
                                                  ? MobileTheme.brand(context)
                                                  : (isDark
                                                      ? AppPalette.darkTextMuted
                                                      : AppPalette
                                                          .lightTextMuted),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  server.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize:
                                                        AppTokens.fontSizeBody,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: [
                                                    if (_testing[server.id] ==
                                                        true)
                                                      const NexusStatusBadge(
                                                        label: '测试中...',
                                                        tone: NexusBadgeTone
                                                            .warning,
                                                        showDot: true,
                                                      )
                                                    else
                                                      NexusStatusBadge(
                                                        label: server.enabled
                                                            ? '已启用'
                                                            : '已停用',
                                                        tone: server.enabled
                                                            ? NexusBadgeTone
                                                                .success
                                                            : NexusBadgeTone
                                                                .neutral,
                                                      ),
                                                    NexusStatusBadge(
                                                      label: isStdio
                                                          ? 'STDIO 进程'
                                                          : 'HTTP 远程',
                                                      tone: NexusBadgeTone
                                                          .neutral,
                                                    ),
                                                    NexusStatusBadge(
                                                      label: isStdio
                                                          ? '高权限本地执行'
                                                          : '受控网络请求',
                                                      tone: isStdio
                                                          ? NexusBadgeTone
                                                              .warning
                                                          : NexusBadgeTone
                                                              .brand,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          NexusSwitch(
                                            value: server.enabled,
                                            onChanged: (enabled) async {
                                              unawaited(HapticFeedback
                                                  .selectionClick());
                                              await _service.toggleServer(
                                                  server.id, enabled);
                                              await _reload();
                                            },
                                          ),
                                          PopupMenuButton<String>(
                                            icon: const Icon(
                                                Icons.more_vert_rounded,
                                                size: 20),
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
                                                            color: AppPalette
                                                                .brandAction,
                                                          )
                                                        : const Icon(
                                                            Icons
                                                                .wifi_tethering_rounded,
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
                                                    Icon(Icons.edit_outlined,
                                                        size: 18),
                                                    SizedBox(width: 8),
                                                    Text('编辑配置'),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                        Icons
                                                            .delete_outline_rounded,
                                                        size: 18,
                                                        color:
                                                            AppPalette.danger),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      '删除服务器',
                                                      style: TextStyle(
                                                          color: AppPalette
                                                              .danger),
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
                                          borderRadius: BorderRadius.circular(
                                              MobileTheme.controlRadius(
                                                  context)),
                                          border: Border.all(
                                            color: isDark
                                                ? AppPalette.darkHairline
                                                : AppPalette.lightHairline,
                                            width: 1.0,
                                          ),
                                        ),
                                        child: SelectableText(
                                          server.url ??
                                              server.command ??
                                              '未指定地址',
                                          style: TextStyle(
                                            fontSize:
                                                AppTokens.fontSizeFootnote,
                                            fontFamily:
                                                AppTokens.fontFamilyMono,
                                            color: isDark
                                                ? AppPalette.darkTextMuted
                                                : AppPalette.lightTextMuted,
                                          ),
                                        ),
                                      ),
                                      AnimatedSize(
                                        duration:
                                            MotionPreferences.adjustDuration(
                                          context,
                                          NexusMotion.fast,
                                        ),
                                        alignment: Alignment.topCenter,
                                        child: connectionResult == null
                                            ? const SizedBox.shrink()
                                            : AnimatedSwitcher(
                                                duration: MotionPreferences
                                                    .adjustDuration(
                                                  context,
                                                  NexusMotion.fast,
                                                ),
                                                switchInCurve:
                                                    NexusMotion.curveEnter,
                                                switchOutCurve:
                                                    NexusMotion.curveExit,
                                                child: Column(
                                                  key: ValueKey(
                                                      connectionResult),
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      connectionResult.ok
                                                          ? '最近测试：连接成功 · ${connectionResult.toolCount} 个工具'
                                                          : '最近测试：连接失败',
                                                      style: TextStyle(
                                                        fontSize: AppTokens
                                                            .fontSizeFootnote,
                                                        fontFeatures: const [
                                                          FontFeature
                                                              .tabularFigures()
                                                        ],
                                                        color: connectionResult
                                                                .ok
                                                            ? AppPalette
                                                                .brandAction
                                                            : AppPalette.danger,
                                                      ),
                                                    ),
                                                    if (!connectionResult.ok &&
                                                        connectionResult.error
                                                                ?.isNotEmpty ==
                                                            true)
                                                      Text(
                                                        connectionResult.error!,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall,
                                                      ),
                                                  ],
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ),
                        )),
    );
  }
}
