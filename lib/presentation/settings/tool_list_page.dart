import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/nexus_page_header.dart';
import 'settings_components.dart';

class ToolListPage extends StatefulWidget {
  const ToolListPage({super.key});

  @override
  State<ToolListPage> createState() => _ToolListPageState();
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

class _ToolListPageState extends State<ToolListPage> {
  final _searchController = TextEditingController();
  _RiskFilter _filter = _RiskFilter.all;

  static const List<_ToolEntry> _allTools = [
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
      _ => Icons.handyman_rounded,
    };
  }

  Color _toolColor(_ToolEntry tool) {
    if (tool.isSensitive) return AppPalette.warning;
    if (tool.risk == ToolRisk.dangerous) return AppPalette.danger;
    if (tool.risk == ToolRisk.requiresConfirmation) {
      return AppPalette.brand;
    }
    return switch (tool.category) {
      '网络与知识' => AppPalette.brand,
      '通用计算' => AppPalette.success,
      '工作区与文件' => AppPalette.lightTextMuted,
      '终端与执行' => AppPalette.danger,
      'Agent 与上下文' => AppPalette.lightTextMuted,
      '多模态' => AppPalette.danger,
      _ => AppPalette.lightTextMuted,
    };
  }

  void _showToolDetail(_ToolEntry tool) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppPalette.darkSurface : Colors.white,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTokens.radiusModal)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppPalette.darkHairline
                        : AppPalette.lightHairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _toolColor(tool),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(_toolIcon(tool), color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tool.displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '代码: ${tool.name} · 分类: ${tool.category}',
                          style: TextStyle(
                            fontSize: 11,
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
                  fontSize: 14,
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
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tool.approvalPolicy,
                      style: TextStyle(
                        fontSize: 12.5,
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
                              : AppPalette.brand,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tool.isSensitive
                                ? '敏感权限：涉及设备硬件或隐私操作，强制二次审批。'
                                : '遵循全局当前生效的审批策略与沙箱安全边界。',
                            style: TextStyle(
                              fontSize: 11.5,
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
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
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
              fontSize: 11,
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
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '搜索工具名称、功能或分类…',
                  hintStyle: TextStyle(
                    fontSize: 13.5,
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
                    iconColor: _toolColor(tools[i]),
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
          fontSize: 12.5,
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
