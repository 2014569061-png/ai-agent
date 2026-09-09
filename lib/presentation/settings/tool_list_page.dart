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
  final bool isSensitive;
  final String approvalPolicy;
  final String category;

  const _ToolEntry({
    required this.name,
    required this.displayName,
    required this.description,
    required this.risk,
    this.isSensitive = false,
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
      description: '在 Termux 或系统沙箱中执行 Shell 脚本与系统命令。',
      risk: ToolRisk.dangerous,
      approvalPolicy: '具备底层系统交互能力，强制逐次审批。',
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
    _ToolEntry(
      name: 'device_camera',
      displayName: '设备拍照与相册选择 (Camera & Photos)',
      description: '调用系统相机拍照或打开相册选择图片作为上下文附件。',
      risk: ToolRisk.dangerous,
      isSensitive: true,
      approvalPolicy: '敏感设备权限，需系统权限授权并在调用时二次确认。',
      category: '设备能力',
    ),
    _ToolEntry(
      name: 'device_record',
      displayName: '音频录制与实时识别 (Audio Record & ASR)',
      description: '调用麦克风录制音频并调用语音引擎进行实时语音听写识别。',
      risk: ToolRisk.dangerous,
      isSensitive: true,
      approvalPolicy: '敏感麦克风权限，需系统权限授权并提示录音状态。',
      category: '设备能力',
    ),
    _ToolEntry(
      name: 'device_info',
      displayName: '读取敏感设备信息 (Device Info)',
      description: '获取设备硬件标识、系统版本、网络状态与电池详情。',
      risk: ToolRisk.dangerous,
      isSensitive: true,
      approvalPolicy: '敏感权限控制，需总开关开启并在调用时二次确认。',
      category: '设备能力',
    ),
    _ToolEntry(
      name: 'device_action',
      displayName: '敏感设备操作 (Device Action)',
      description: '调整设备设置、触发震动、屏幕常亮或前后台状态控制。',
      risk: ToolRisk.dangerous,
      isSensitive: true,
      approvalPolicy: '敏感高危设备控制，不绕过任何单次审批。',
      category: '设备能力',
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
    if (tool.isSensitive) {
      return switch (tool.name) {
        'device_camera' => Icons.camera_alt_rounded,
        'device_record' => Icons.mic_rounded,
        'device_info' => Icons.perm_device_information_rounded,
        'device_action' => Icons.phonelink_setup_rounded,
        _ => Icons.security_rounded,
      };
    }
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
    if (tool.isSensitive) return const Color(0xFFFF9500);
    if (tool.risk == ToolRisk.dangerous) return const Color(0xFFFF3B30);
    if (tool.risk == ToolRisk.requiresConfirmation) return const Color(0xFF007AFF);
    return switch (tool.category) {
      '网络与知识' => const Color(0xFF007AFF),
      '通用计算' => const Color(0xFF34C759),
      '工作区与文件' => const Color(0xFF5856D6),
      '终端与执行' => const Color(0xFFFF3B30),
      'Agent 与上下文' => const Color(0xFFAF52DE),
      '多模态' => const Color(0xFFFF2D55),
      _ => const Color(0xFF8E8E93),
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
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                    color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _toolColor(tool),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(_toolIcon(tool), color: Colors.white, size: 19),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tool.displayName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
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
                  color: isDark ? const Color(0xFFEBEBF5) : const Color(0xFF3C3C43),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '权限与审批策略',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tool.approvalPolicy,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
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
                          size: 15,
                          color: tool.isSensitive
                              ? const Color(0xFFFF9500)
                              : const Color(0xFF007AFF),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tool.isSensitive
                                ? '敏感权限：涉及设备硬件或隐私操作，强制二次审批。'
                                : '遵循全局当前生效的审批策略。',
                            style: TextStyle(
                              fontSize: 11,
                              color: tool.isSensitive
                                  ? const Color(0xFFFF9500)
                                  : (isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
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
                    backgroundColor: const Color(0xFF007AFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    '我知道了',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        );

    final riskBadge = switch (tool.risk) {
      ToolRisk.safe => badge('安全', const Color(0xFF34C759)),
      ToolRisk.requiresConfirmation => badge('需确认', const Color(0xFF007AFF)),
      ToolRisk.dangerous => badge('高危', const Color(0xFFFF3B30)),
    };

    if (tool.isSensitive) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          badge('🔒 敏感', const Color(0xFFFF9500)),
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
              height: 36,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '搜索工具名称、功能或分类…',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: settingsMutedColor(context),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: settingsMutedColor(context),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 34),
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
                  suffixIconConstraints: const BoxConstraints(minWidth: 32),
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
                _buildFilterChip('敏感设备能力', _RiskFilter.sensitive),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SettingsSectionTitle('可用工具 (${tools.length})'),
          if (tools.isEmpty)
            const SizedBox(
              height: 200,
              child: EmptyStateView(
                icon: Icons.build_circle_outlined,
                title: '未找到匹配的工具',
                message: '尝试更换搜索关键字或切换风险筛选条件',
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
                  if (i < tools.length - 1)
                    const SettingsDivider(),
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
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected
              ? Colors.white
              : (isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
        ),
      ),
      selected: selected,
      selectedColor: const Color(0xFF007AFF),
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      onSelected: (val) {
        if (val) setState(() => _filter = value);
      },
    );
  }
}
