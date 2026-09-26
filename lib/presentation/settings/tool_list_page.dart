import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/audit_service.dart';
import '../../application/nexus_guard.dart';
import '../../application/providers.dart';
import '../../domain/models.dart';
import '../../infrastructure/providers/tool_trust_store.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_sheet.dart';
import 'settings_components.dart';

class ToolListPage extends ConsumerStatefulWidget {
  const ToolListPage({super.key});

  @override
  ConsumerState<ToolListPage> createState() => _ToolListPageState();
}

enum _RiskFilter { all, safe, requiresConfirmation, dangerous, sensitive }

class _ToolEntry {
  final String name;
  final String displayName;
  final String description;
  final ToolRisk risk;
  final bool isSensitive = false;
  final String approvalPolicy;
  final String category;

  const _ToolEntry({
    required this.name,
    required this.displayName,
    required this.description,
    required this.risk,
    required this.approvalPolicy,
    required this.category,
  });
}

class _ToolListPageState extends ConsumerState<ToolListPage> {
  static const _workspaceFilesKey = 'settings.tool.workspace_files';
  static const _terminalKey = 'settings.tool.terminal';
  static const _legacyTerminalFileKey = 'settings.tool.terminal_file';

  final _searchController = TextEditingController();
  _RiskFilter _filter = _RiskFilter.all;
  bool _workspaceFilesEnabled = true;
  bool _terminalEnabled = true;

  /// 信任清单纯属运行时状态：会话级授权只存在内存里，所以必须复用 provider
  /// 持有的那个实例，另建一个 ToolTrustStore 会看不到本会话已授予的项。
  ToolTrustStore? _trustStore;
  List<String> _sessionTrusted = const [];
  List<String> _alwaysTrusted = const [];

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _loadTrust();
  }

  Future<void> _loadTrust() async {
    final store = await ref.read(toolTrustStoreProvider.future);
    if (!mounted) return;
    setState(() {
      _trustStore = store;
      _sessionTrusted = store.sessionAllowed;
      _alwaysTrusted = store.alwaysAllowed;
    });
  }

  /// 直接改的是 provider 持有的实例，不是响应式 notifier，所以手动重读刷新。
  Future<void> _refreshTrust() async {
    final store = _trustStore;
    if (store == null || !mounted) return;
    setState(() {
      _sessionTrusted = store.sessionAllowed;
      _alwaysTrusted = store.alwaysAllowed;
    });
  }

  /// 撤销与授予留痕对称：撤销同样是安全相关动作，必须能在审计页看到。
  void _logRevoke(String toolName, {required String scope}) {
    final audit = ref.read(auditServiceProvider);
    final db = ref.read(databaseProvider.future);
    unawaited(
      NexusGuard.silentlyAsync<bool>('trust.revoke', () async {
        final database = await db;
        await audit.logSecurityEvent(
          database,
          type: 'tool_revoke_$scope',
          detail: toolName,
          decision: 'revoked',
        );
        return true;
      }),
    );
  }

  Future<void> _revokeSession(String name) async {
    _trustStore?.revokeSession(name);
    _logRevoke(name, scope: 'session');
    await _refreshTrust();
  }

  Future<void> _revokeAlways(String name) async {
    await _trustStore?.removeAlways(name);
    _logRevoke(name, scope: 'always');
    await _refreshTrust();
  }

  Future<void> _revokeAll() async {
    final store = _trustStore;
    if (store == null) return;
    for (final name in store.alwaysAllowed) {
      await store.removeAlways(name);
      _logRevoke(name, scope: 'always');
    }
    for (final name in store.sessionAllowed) {
      _logRevoke(name, scope: 'session');
    }
    store.clearSession();
    await _refreshTrust();
  }

  String _labelForName(String name) {
    for (final tool in _allTools) {
      if (tool.name == name) return tool.displayName;
    }
    return name;
  }

  IconData _iconForName(String name) {
    for (final tool in _allTools) {
      if (tool.name == name) return _toolIcon(tool);
    }
    return Icons.handyman_rounded;
  }

  /// 免审批清单。清单为空时也要显示，否则用户无法区分「没人免审批」和
  /// 「这里根本没有这个功能」。
  List<Widget> _trustTiles() {
    final rows = <Widget>[];
    void add(Widget tile) {
      if (rows.isNotEmpty) rows.add(const SettingsDivider());
      rows.add(tile);
    }

    if (_sessionTrusted.isEmpty && _alwaysTrusted.isEmpty) {
      add(const SettingsTile(
        icon: Icons.verified_user_outlined,
        title: '当前没有工具处于免审批状态',
        subtitle: '所有需要确认的工具都会逐次弹出审批窗。',
        showChevron: false,
      ));
      return rows;
    }

    for (final name in _sessionTrusted) {
      add(SettingsTile(
        icon: _iconForName(name),
        title: _labelForName(name),
        subtitle: '本会话免审批 · 退出应用后失效',
        showChevron: false,
        trailingWidget: TextButton(
          onPressed: () => _revokeSession(name),
          child: const Text('撤销'),
        ),
      ));
    }
    for (final name in _alwaysTrusted) {
      add(SettingsTile(
        icon: _iconForName(name),
        title: _labelForName(name),
        subtitle: '始终允许 · 重启后仍免审批',
        showChevron: false,
        trailingWidget: TextButton(
          onPressed: () => _revokeAlways(name),
          child: const Text('撤销'),
        ),
      ));
    }
    add(SettingsTile(
      icon: Icons.lock_reset_rounded,
      title: '撤销全部免审批',
      subtitle: '恢复为每个需确认的工具都逐次审批',
      showChevron: false,
      trailingWidget: TextButton(
        onPressed: _revokeAll,
        child: const Text('撤销全部'),
      ),
    ));
    return rows;
  }

  Future<void> _loadPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getBool(_legacyTerminalFileKey) ?? true;
    if (!mounted) return;
    setState(() {
      _workspaceFilesEnabled = prefs.getBool(_workspaceFilesKey) ?? legacy;
      _terminalEnabled = prefs.getBool(_terminalKey) ?? legacy;
    });
  }

  Future<void> _setWorkspaceFilesEnabled(bool enabled) async {
    setState(() => _workspaceFilesEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_workspaceFilesKey, enabled);
  }

  Future<void> _setTerminalEnabled(bool enabled) async {
    setState(() => _terminalEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_terminalKey, enabled);
  }

  static const List<_ToolEntry> _allTools = [
    _ToolEntry(
      name: 'android_device',
      displayName: 'Android 设备控制',
      description: '控制应用、文件、网络与系统设置；变更前提供只读预览，并按 action 风险审批。',
      risk: ToolRisk.requiresConfirmation,
      approvalPolicy: 'Root、危险系统开关、网络规则与不可逆操作需逐次明确批准；Root 变更须先预览。',
      category: 'Android 设备',
    ),
    _ToolEntry(
      name: 'android_automation',
      displayName: 'Android 设备自动化',
      description: '创建定时、连上 Wi-Fi、低电量触发的设备自动化规则；触发后只发通知，由你确认后执行。',
      risk: ToolRisk.requiresConfirmation,
      approvalPolicy: '创建/启用规则需确认；含 Root 或不可撤销动作的规则按危险操作审批。每次执行仍需在通知中确认。',
      category: 'Android 设备',
    ),
    _ToolEntry(
      name: 'web_search',
      displayName: '网页搜索 (Web Search)',
      description: '使用搜索引擎检索互联网实时信息与文档。',
      risk: ToolRisk.safe,
      approvalPolicy: '安全工具，已配置 Key 时自动执行。',
      category: '网络与知识',
    ),
    _ToolEntry(
      name: 'http_request',
      displayName: 'HTTP 请求 (HTTP Request)',
      description: '向指定 URL 发起 HTTP GET/POST 网络请求，具备外部副作用。',
      risk: ToolRisk.dangerous,
      approvalPolicy: '高危网络操作，每次调用均需用户手动审批。',
      category: '网络与知识',
    ),
    _ToolEntry(
      name: 'calculator',
      displayName: '数学计算器 (Calculator)',
      description: '对数字进行精确加减乘除与数学公式求值。',
      risk: ToolRisk.safe,
      approvalPolicy: '安全纯函数，无需审批自动执行。',
      category: '通用计算',
    ),
    _ToolEntry(
      name: 'get_time',
      displayName: '获取本地时间 (Get Time)',
      description: '读取当前系统的本地日期与时间。',
      risk: ToolRisk.safe,
      approvalPolicy: '安全只读接口，自动执行。',
      category: '通用计算',
    ),
    _ToolEntry(
      name: 'json_query',
      displayName: 'JSON 字段解析 (JSON Query)',
      description: '按点号路径提取 JSON 文本中的键值内容。',
      risk: ToolRisk.safe,
      approvalPolicy: '安全数据解析，自动执行。',
      category: '通用计算',
    ),
    _ToolEntry(
      name: 'read_file',
      displayName: '读取文件 (Read File)',
      description: '从当前工作区沙箱读取文本文件内容。',
      risk: ToolRisk.safe,
      approvalPolicy: '沙箱内只读操作，自动放行。',
      category: '工作区与文件',
    ),
    _ToolEntry(
      name: 'write_file',
      displayName: '写入文件 (Write File)',
      description: '向工作区指定路径写入新文件或全量覆盖。',
      risk: ToolRisk.requiresConfirmation,
      approvalPolicy: '写文件操作，按当前审批策略确认后执行。',
      category: '工作区与文件',
    ),
    _ToolEntry(
      name: 'edit_file',
      displayName: '编辑文件 (Edit File)',
      description: '针对已有文件执行精确的代码块或文本替换。',
      risk: ToolRisk.requiresConfirmation,
      approvalPolicy: '代码与文本修改，需要审批或信任放行。',
      category: '工作区与文件',
    ),
    _ToolEntry(
      name: 'delete_file',
      displayName: '删除文件 (Delete File)',
      description: '从工作区永久删除指定文件。',
      risk: ToolRisk.dangerous,
      approvalPolicy: '不可逆高危破坏性操作，强制单次逐条审批。',
      category: '工作区与文件',
    ),
    _ToolEntry(
      name: 'move_file',
      displayName: '移动/重命名 (Move File)',
      description: '在工作区内移动文件或变更文件名。',
      risk: ToolRisk.requiresConfirmation,
      approvalPolicy: '文件结构调整，按当前审批策略控制。',
      category: '工作区与文件',
    ),
    _ToolEntry(
      name: 'list_directory',
      displayName: '列出目录 (List Directory)',
      description: '枚举工作区或子目录中的文件与文件夹树。',
      risk: ToolRisk.safe,
      approvalPolicy: '沙箱内只读枚举，自动放行。',
      category: '工作区与文件',
    ),
    _ToolEntry(
      name: 'search_files',
      displayName: '文件搜索 (Search Files)',
      description: '在工作区内根据关键字进行文件名与内容检索。',
      risk: ToolRisk.safe,
      approvalPolicy: '沙箱只读搜索，自动放行。',
      category: '工作区与文件',
    ),
    _ToolEntry(
      name: 'terminal',
      displayName: '终端命令执行 (Terminal Command)',
      description: '在 Termux 或系统环境中执行 Shell 脚本与系统命令。cwd 不是完整沙箱边界。',
      risk: ToolRisk.requiresConfirmation,
      approvalPolicy: '默认始终需要确认；完全访问模式下终端可自动执行。cwd 不是完整沙箱。',
      category: '终端与执行',
    ),
    _ToolEntry(
      name: 'remember',
      displayName: '长期记忆写入 (Remember)',
      description: '将用户偏好或关键上下文持久化写入长期记忆库。',
      risk: ToolRisk.safe,
      approvalPolicy: '用户偏好存储，安全自动放行。',
      category: 'Agent 与上下文',
    ),
    _ToolEntry(
      name: 'sub_agent',
      displayName: '子任务自主委派 (Sub Agent)',
      description: '派生独立的子 Agent 无 UI 处理耗时计算或搜索任务。',
      risk: ToolRisk.requiresConfirmation,
      approvalPolicy: '受「自主委派」总开关控制；关闭时需逐次确认。',
      category: 'Agent 与上下文',
    ),
    _ToolEntry(
      name: 'generate_image',
      displayName: '图像生成 (Generate Image)',
      description: '调用绘图模型生成高质量视觉图片与设计资产。',
      risk: ToolRisk.safe,
      approvalPolicy: '需要配置对应模型或服务端点。',
      category: '多模态',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_ToolEntry> get _filteredTools {
    final query = _searchController.text.trim().toLowerCase();
    return _allTools.where((t) {
      final matchesQuery = query.isEmpty ||
          t.name.toLowerCase().contains(query) ||
          t.displayName.toLowerCase().contains(query) ||
          t.description.toLowerCase().contains(query) ||
          t.category.toLowerCase().contains(query);
      if (!matchesQuery) return false;

      return switch (_filter) {
        _RiskFilter.all => true,
        _RiskFilter.safe => t.risk == ToolRisk.safe && !t.isSensitive,
        _RiskFilter.requiresConfirmation =>
          t.risk == ToolRisk.requiresConfirmation && !t.isSensitive,
        _RiskFilter.dangerous => t.risk == ToolRisk.dangerous,
        _RiskFilter.sensitive => t.isSensitive,
      };
    }).toList();
  }

  IconData _toolIcon(_ToolEntry tool) {
    if (tool.isSensitive) return Icons.security_rounded;
    return switch (tool.name) {
      'web_search' => Icons.search_rounded,
      'http_request' => Icons.http_rounded,
      'calculator' => Icons.calculate_rounded,
      'get_time' => Icons.access_time_rounded,
      'json_query' => Icons.data_object_rounded,
      'read_file' => Icons.file_present_rounded,
      'write_file' => Icons.note_add_rounded,
      'edit_file' => Icons.edit_note_rounded,
      'delete_file' => Icons.delete_outline_rounded,
      'move_file' => Icons.drive_file_move_rounded,
      'list_directory' => Icons.folder_open_rounded,
      'search_files' => Icons.find_in_page_rounded,
      'terminal' => Icons.terminal_rounded,
      'remember' => Icons.psychology_rounded,
      'sub_agent' => Icons.smart_toy_rounded,
      'generate_image' => Icons.palette_rounded,
      'android_device' => Icons.phone_android_rounded,
      'android_automation' => Icons.bolt_rounded,
      _ => Icons.handyman_rounded,
    };
  }

  void _showToolDetail(_ToolEntry tool) {
    showNexusSheet(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    // X2：中性图标底，风险只由徽标表达。
                    decoration: BoxDecoration(
                      color: AppTheme.semanticOf(context)
                          .textPrimary
                          .withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _toolIcon(tool),
                      color: AppTheme.semanticOf(context).textMuted,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tool.displayName,
                          style: const TextStyle(
                            fontSize: AppTokens.fontSizeBodyLarge,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '代码: ${tool.name} · 分类: ${tool.category}',
                          style: TextStyle(
                            fontSize: AppTokens.fontSizeBadge,
                            color: isDark
                                ? AppPalette.darkTextMuted
                                : AppPalette.lightTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildRiskBadge(tool),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                tool.description,
                style: TextStyle(
                  fontSize: AppTokens.fontSizeSubhead,
                  color: isDark ? AppPalette.darkText : AppPalette.lightText,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppPalette.darkHairline.withValues(alpha: 0.5)
                      : AppPalette.lightSurface,
                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '权限与审批策略',
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeCaption,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tool.approvalPolicy,
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeMeta,
                        color: isDark
                            ? AppPalette.darkTextMuted
                            : AppPalette.lightTextMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          tool.isSensitive
                              ? Icons.warning_amber_rounded
                              : Icons.verified_user_outlined,
                          size: 16,
                          color: tool.isSensitive
                              ? AppPalette.warning
                              : AppPalette.brandTextFor(isDark),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tool.isSensitive
                                ? '敏感权限：涉及设备硬件或隐私操作，强制二次审批。'
                                : '遵循全局当前生效的审批策略与沙箱安全边界。',
                            style: TextStyle(
                              fontSize: AppTokens.fontSizeSubcaption,
                              color: tool.isSensitive
                                  ? AppPalette.warning
                                  : (isDark
                                      ? AppPalette.darkTextMuted
                                      : AppPalette.lightTextMuted),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppPalette.brandAction,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    '我知道了',
                    style: TextStyle(
                        fontSize: AppTokens.fontSizeBody,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRiskBadge(_ToolEntry tool) {
    Widget badge(String label, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: AppTokens.fontSizeBadge,
              fontWeight: FontWeight.w500,
            ),
          ),
        );

    final riskBadge = switch (tool.risk) {
      ToolRisk.safe => badge('安全', AppPalette.success),
      ToolRisk.requiresConfirmation => badge('需确认', AppPalette.brand),
      ToolRisk.dangerous => badge('高危', AppPalette.danger),
    };

    if (tool.isSensitive) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          badge('🔒 敏感', AppPalette.warning),
          const SizedBox(width: 4),
          riskBadge,
        ],
      );
    }
    return riskBadge;
  }

  @override
  Widget build(BuildContext context) {
    final tools = _filteredTools;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: const NexusPageHeader(
        title: '受控工具清单',
        subtitle: '查看与管理 Agent 可调用的全部工具及权限等级',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
        children: [
          const SettingsSectionTitle('工作区权限'),
          SettingsGroupCard(
            children: [
              SettingsTile(
                icon: Icons.folder_open_rounded,
                title: '允许 Agent 读写当前工作区文件',
                subtitle: '创建和编辑网页、代码、文档等项目文件',
                showChevron: false,
                trailingWidget: Switch(
                  value: _workspaceFilesEnabled,
                  onChanged: _setWorkspaceFilesEnabled,
                ),
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.terminal_rounded,
                title: '允许 Agent 执行终端命令',
                subtitle: '安装依赖、运行脚本和构建项目需要此权限',
                showChevron: false,
                trailingWidget: Switch(
                  value: _terminalEnabled,
                  onChanged:
                      _workspaceFilesEnabled ? _setTerminalEnabled : null,
                ),
              ),
            ],
          ),
          const SettingsSectionTitle('免审批范围'),
          SettingsGroupCard(children: _trustTiles()),
          // iOS Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color:
                    isDark ? AppPalette.darkSurface : AppPalette.lightSurface,
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                border: Border.all(
                  color: isDark
                      ? AppPalette.darkHairline
                      : AppPalette.lightHairline,
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: AppTokens.fontSizeSubhead),
                decoration: InputDecoration(
                  hintText: '搜索工具名称、功能或分类…',
                  hintStyle: TextStyle(
                    fontSize: AppTokens.fontSizeBodySmall,
                    color: settingsMutedColor(context),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: settingsMutedColor(context),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          child: Icon(
                            Icons.cancel_rounded,
                            size: 16,
                            color: settingsMutedColor(context),
                          ),
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(minWidth: 36),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildFilterChip('全部', _RiskFilter.all),
                const SizedBox(width: 8),
                _buildFilterChip('安全 (Safe)', _RiskFilter.safe),
                const SizedBox(width: 8),
                _buildFilterChip('需确认', _RiskFilter.requiresConfirmation),
                const SizedBox(width: 8),
                _buildFilterChip('高危', _RiskFilter.dangerous),
                const SizedBox(width: 8),
                _buildFilterChip('敏感工具', _RiskFilter.sensitive),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SettingsSectionTitle('可用工具 (${tools.length})'),
          if (tools.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: EmptyStateView(
                icon: Icons.build_circle_outlined,
                title: '未找到匹配的工具',
                message: '尝试更换搜索关键字或切换风险筛选条件',
                actionLabel: '重置筛选',
                onAction: () {
                  _searchController.clear();
                  setState(() => _filter = _RiskFilter.all);
                },
              ),
            )
          else
            SettingsGroupCard(
              children: [
                for (var i = 0; i < tools.length; i++) ...[
                  SettingsTile(
                    icon: _toolIcon(tools[i]),
                    title: tools[i].displayName,
                    subtitle: tools[i].description,
                    trailingBadge: _buildRiskBadge(tools[i]),
                    showChevron: true,
                    onTap: () => _showToolDetail(tools[i]),
                  ),
                  if (i < tools.length - 1) const SettingsDivider(),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, _RiskFilter value) {
    final selected = _filter == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: AppTokens.fontSizeMeta,
          fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          color: selected
              ? Colors.white
              : (isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted),
        ),
      ),
      selected: selected,
      selectedColor: AppPalette.brandAction,
      backgroundColor:
          isDark ? AppPalette.darkSurface : AppPalette.lightSurface,
      side: BorderSide(
        color: selected
            ? Colors.transparent
            : (isDark ? AppPalette.darkHairline : AppPalette.lightHairline),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      ),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      onSelected: (val) {
        if (val) setState(() => _filter = value);
      },
    );
  }
}
