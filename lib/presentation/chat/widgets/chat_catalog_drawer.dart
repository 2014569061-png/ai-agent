import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_provider.dart';
import '../../../domain/models.dart';
import '../../history/history_page.dart';
import '../../settings/settings_page.dart';
import '../../dashboard/dashboard_page.dart';
import '../../agents/agents_page.dart';
import '../../memory/memory_page.dart';
import '../../scheduled/scheduled_tasks_page.dart';
import '../../sync/sync_page.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/immersive_surface.dart';
import '../../widgets/floating_toast.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../l10n/app_strings.dart';

/// 侧边工作台目录抽屉 (Catalog Drawer)
/// 严格依据 NEXUS UI 设计优化规范重构，固定为四组：
/// 一、当前会话（新建会话、最近会话、历史会话）
/// 二、工作台（当前工作区两级路径与复制、仪表盘）
/// 三、工具（当前模型、MCP服务、提示词库、计划模式、审批策略）
/// 四、系统（Agent管理、服务商设置、记忆与知识库、定时任务、同步与安全）
class ChatCatalogDrawer extends StatefulWidget {
  final String? currentWorkspacePath;
  final String activeModel;
  final String activeProviderName;
  final List<ChatMessage> messages;
  final bool isRunning;
  final bool planModeEnabled;
  final ApprovalMode approvalMode;
  final VoidCallback onNewConversation;
  final ValueChanged<Conversation> onSelectConversation;
  final VoidCallback onWorkspaceTap;
  final VoidCallback onModelTap;
  final VoidCallback onMcpMenu;
  final VoidCallback onPromptLibrary;
  final VoidCallback onPlanModeToggle;
  final VoidCallback? onApprovalModeTap;
  final VoidCallback? onMore;
  final VoidCallback? onOpenHistory;

  final String? currentConversationId;

  /// 上下文窗口与实时执行预算
  final int contextTokens;
  final int liveContextTokens;

  const ChatCatalogDrawer({
    super.key,
    this.currentConversationId,
    required this.contextTokens,
    this.liveContextTokens = 0,
    required this.currentWorkspacePath,
    required this.activeModel,
    required this.activeProviderName,
    required this.messages,
    required this.isRunning,
    required this.planModeEnabled,
    this.approvalMode = ApprovalMode.ask,
    required this.onNewConversation,
    required this.onSelectConversation,
    required this.onWorkspaceTap,
    required this.onModelTap,
    required this.onMcpMenu,
    required this.onPromptLibrary,
    required this.onPlanModeToggle,
    this.onApprovalModeTap,
    this.onMore,
    this.onOpenHistory,
  });

  @override
  State<ChatCatalogDrawer> createState() => _ChatCatalogDrawerState();
}

class _ChatCatalogDrawerState extends State<ChatCatalogDrawer> {
  List<Conversation> _recentConversations = [];
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final db = await DatabaseProvider.instance.database;
      final list = (await db.recentConversations()).take(5).toList();
      if (mounted) {
        setState(() {
          _recentConversations = list;
          _loadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  String _formatWorkspaceDisplay(String? path) {
    if (path == null || path.isEmpty) return '未选择工作区';
    final parts = p
        .split(path)
        .where((s) => s.isNotEmpty && s != '/' && s != '\\')
        .toList();
    if (parts.isEmpty) return '未选择工作区';
    if (parts.length == 1) return parts.first;
    return '${parts[parts.length - 2]}/${parts.last}';
  }

  String _approvalTitle(ApprovalMode mode) => switch (mode) {
        ApprovalMode.ask => '每次询问',
        ApprovalMode.autoSafe => '自动批准低风险',
        ApprovalMode.fullAccess => '完全访问',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = math.min(MediaQuery.sizeOf(context).width * 0.86, 350.0);

    return Drawer(
      width: width,
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      child: ImmersiveSurface(
        level: ImmersiveMaterialLevel.ultraThick,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
        child: SafeArea(
          child: Column(
            children: [
              // 1. 顶部 Header 与「新建对话」大按钮
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const BrandMark(size: 34, withGlow: true),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '工作台目录',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (widget.onMore != null)
                          IconButton(
                            tooltip: '更多操作',
                            icon:
                                const Icon(Icons.more_horiz_rounded, size: 20),
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onMore!();
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                        IconButton(
                          tooltip: '关闭目录',
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(context),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 新建对话大按钮
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: isDark
                              ? AppTheme.brandBright
                              : theme.colorScheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(context);
                          widget.onNewConversation();
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text(
                          '新建对话',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, indent: 16, endIndent: 16),

              // 2. 中间滚动区域：四大清晰分组
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    // ==========================================
                    // 第一组：当前会话与历史
                    // ==========================================
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const _SectionHeader(title: '最近会话'),
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: () async {
                            Navigator.pop(context);
                            if (widget.onOpenHistory != null) {
                              widget.onOpenHistory!();
                            } else {
                              final selected = await Navigator.of(context)
                                  .push<Conversation>(
                                MaterialPageRoute(
                                    builder: (_) => const HistoryPage()),
                              );
                              if (selected != null) {
                                widget.onSelectConversation(selected);
                              }
                            }
                          },
                          child: const Text('查看全部 >',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    if (_loadingHistory)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Center(
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))),
                      )
                    else if (_recentConversations.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          '暂无历史会话',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      )
                    else
                      ..._recentConversations.map(
                        (c) => _HistoryTile(
                          conversation: c,
                          isSelected: c.id == widget.currentConversationId,
                          onTap: () {
                            Navigator.pop(context);
                            widget.onSelectConversation(c);
                          },
                        ),
                      ),

                    const SizedBox(height: 14),

                    // ==========================================
                    // 第二组：工作台 (Workbench)
                    // ==========================================
                    const _SectionHeader(title: '工作台'),
                    // 工作区项（显示后两级路径 + 复制按钮）
                    _CatalogTile(
                      icon: Icons.folder_open_rounded,
                      title: '当前工作区',
                      subtitle:
                          _formatWorkspaceDisplay(widget.currentWorkspacePath),
                      trailingAction: (widget.currentWorkspacePath != null &&
                              widget.currentWorkspacePath!.isNotEmpty)
                          ? IconButton(
                              tooltip: '复制工作区路径',
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 28),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(
                                    text: widget.currentWorkspacePath!));
                                FloatingToast.show(context, '已复制工作区路径',
                                    tone: ToastTone.success);
                              },
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        widget.onWorkspaceTap();
                      },
                    ),
                    const SizedBox(height: 6),
                    // 仪表盘
                    _CatalogTile(
                      icon: Icons.dashboard_outlined,
                      title: AppStrings.dashboard,
                      subtitle: AppStrings.dashboardSubtitle,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DashboardPage(
                              onConversationSelected:
                                  widget.onSelectConversation,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),

                    // ==========================================
                    // 第三组：工具 (Tools)
                    // ==========================================
                    const _SectionHeader(title: '工具与能力'),
                    _CatalogTile(
                      icon: Icons.psychology_outlined,
                      title: '当前模型',
                      subtitle: widget.activeModel.isNotEmpty
                          ? widget.activeModel
                          : (widget.activeProviderName.isNotEmpty
                              ? widget.activeProviderName
                              : '配置模型'),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onModelTap();
                      },
                    ),
                    const SizedBox(height: 6),
                    _CatalogTile(
                      icon: Icons.widgets_outlined,
                      title: 'MCP 工具服务',
                      subtitle: '已支持外部模型协议扩展',
                      onTap: () {
                        Navigator.pop(context);
                        widget.onMcpMenu();
                      },
                    ),
                    const SizedBox(height: 6),
                    _CatalogTile(
                      icon: Icons.keyboard_command_key_rounded,
                      title: '提示词库',
                      subtitle: '预设任务指令与快捷模板',
                      onTap: () {
                        Navigator.pop(context);
                        widget.onPromptLibrary();
                      },
                    ),
                    const SizedBox(height: 6),
                    _CatalogTile(
                      icon: widget.planModeEnabled
                          ? Icons.front_hand_rounded
                          : Icons.pan_tool_alt_rounded,
                      iconColor: widget.planModeEnabled
                          ? AppTheme.warning
                          : theme.colorScheme.primary,
                      title: '计划模式',
                      subtitle:
                          widget.planModeEnabled ? '已开启 · 工具调用前确认' : '已关闭',
                      trailingAction: Switch(
                        value: widget.planModeEnabled,
                        onChanged: (_) {
                          widget.onPlanModeToggle();
                        },
                      ),
                      onTap: widget.onPlanModeToggle,
                    ),
                    if (widget.onApprovalModeTap != null) ...[
                      const SizedBox(height: 6),
                      _CatalogTile(
                        icon: widget.approvalMode == ApprovalMode.fullAccess
                            ? Icons.shield_outlined
                            : Icons.verified_user_outlined,
                        iconColor:
                            widget.approvalMode == ApprovalMode.fullAccess
                                ? AppTheme.warning
                                : null,
                        title: '审批策略',
                        subtitle: _approvalTitle(widget.approvalMode),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onApprovalModeTap!();
                        },
                      ),
                    ],

                    const SizedBox(height: 14),

                    // ==========================================
                    // 第四组：系统 (System)
                    // ==========================================
                    const _SectionHeader(title: '系统与配置'),
                    _CatalogTile(
                      icon: Icons.smart_toy_outlined,
                      title: 'Agent 管理',
                      subtitle: '切换与管理专业 Agent 预设',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AgentsPage()),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    _CatalogTile(
                      icon: Icons.settings_outlined,
                      title: '服务商设置',
                      subtitle: '管理 API 密钥、接口地址与协议',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SettingsPage()),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    _CatalogTile(
                      icon: Icons.psychology_alt_outlined,
                      title: '记忆与知识库',
                      subtitle: '长期事实与工程知识库管理',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const MemoryPage()),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    _CatalogTile(
                      icon: Icons.schedule_rounded,
                      title: '定时任务',
                      subtitle: '定时巡检与免唤醒自动化',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ScheduledTasksPage()),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    _CatalogTile(
                      icon: Icons.cloud_sync_outlined,
                      title: '同步与隐私安全',
                      subtitle: '端到端加密同步与保险箱',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SyncPage()),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, indent: 16, endIndent: 16),

              // 3. 抽屉底部：版本号与网络/就绪状态
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppTheme.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '本地就绪',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final Widget? trailingAction;
  final VoidCallback onTap;

  const _CatalogTile({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailingAction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor ?? theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (trailingAction != null)
              trailingAction!
            else
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Conversation conversation;
  final bool isSelected;
  final VoidCallback onTap;

  const _HistoryTile({
    required this.conversation,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1.5),
      decoration: isSelected
          ? BoxDecoration(
              color: theme.colorScheme.primary
                  .withValues(alpha: isDark ? 0.16 : 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.35),
                width: 1,
              ),
            )
          : null,
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(
          conversation.isPinned
              ? Icons.push_pin_rounded
              : (isSelected
                  ? Icons.chat_bubble_rounded
                  : Icons.chat_bubble_outline_rounded),
          size: 16,
          color: isSelected
              ? theme.colorScheme.primary
              : (conversation.isPinned
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
        ),
        title: Text(
          conversation.title.isEmpty ? '新会话' : conversation.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? theme.colorScheme.primary : null,
          ),
        ),
        trailing: isSelected
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '当前',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
