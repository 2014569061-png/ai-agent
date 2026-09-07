import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_provider.dart';
import '../../../domain/models.dart';
import '../../history/history_page.dart';
import '../../settings/settings_page.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/immersive_surface.dart';
import '../../theme/app_tokens.dart';

/// 侧边汉堡叠层目录抽屉 (Catalog Drawer)
/// 承载会话管理、工作区切换、模型配置、上下文 HUD 与扩展工具。
class ChatCatalogDrawer extends StatefulWidget {
  final String? currentWorkspacePath;
  final String activeModel;
  final String activeProviderName;
  final List<ChatMessage> messages;
  final bool isRunning;
  final bool planModeEnabled;
  final VoidCallback onNewConversation;
  final ValueChanged<Conversation> onSelectConversation;
  final VoidCallback onWorkspaceTap;
  final VoidCallback onModelTap;
  final VoidCallback onMcpMenu;
  final VoidCallback onPromptLibrary;
  final VoidCallback onPlanModeToggle;
  final VoidCallback? onMore;
  final VoidCallback? onOpenHistory;

  /// 激活 Provider 的上下文窗口,HUD 与实际执行预算同源。
  final int contextTokens;

  const ChatCatalogDrawer({
    super.key,
    required this.contextTokens,
    required this.currentWorkspacePath,
    required this.activeModel,
    required this.activeProviderName,
    required this.messages,
    required this.isRunning,
    required this.planModeEnabled,
    required this.onNewConversation,
    required this.onSelectConversation,
    required this.onWorkspaceTap,
    required this.onModelTap,
    required this.onMcpMenu,
    required this.onPromptLibrary,
    required this.onPlanModeToggle,
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
    _loadHistory();
  }

  Future<void> _loadHistory() async {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = math.min(MediaQuery.sizeOf(context).width * 0.84, 340.0);

    // 计算上下文用量与 Token 统计
    final totalTokens = widget.messages.fold<int>(
      0,
      (acc, m) => acc + (m.usage?.totalTokens ?? 0),
    );
    // 最新一条含 usage 的助手消息即代表当前上下文尺寸
    final latestUsage = widget.messages.reversed
        .where((m) => m.usage != null)
        .map((m) => m.usage!)
        .firstOrNull;
    final currentContextTokens = latestUsage != null
        ? (latestUsage.promptTokens + latestUsage.completionTokens)
        : 0;

    final maxContextLimit = widget.contextTokens; // G1 与 Provider 设置同源
    final contextRatio =
        (currentContextTokens / maxContextLimit).clamp(0.0, 1.0);

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
              // 1. 顶部身份与「新建对话」按钮
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const BrandMark(size: 36, withGlow: true),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '工作台目录',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
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
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(context),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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

              // 2. 中间滚动区域
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    // --- 工作区与模型快速设置 ---
                    _CatalogTile(
                      icon: Icons.folder_open_rounded,
                      title: '当前工作区',
                      subtitle: widget.currentWorkspacePath != null &&
                              widget.currentWorkspacePath!.isNotEmpty
                          ? p.basename(widget.currentWorkspacePath!)
                          : '未选择工作区',
                      onTap: () {
                        Navigator.pop(context);
                        widget.onWorkspaceTap();
                      },
                    ),
                    const SizedBox(height: 6),
                    _CatalogTile(
                      icon: Icons.psychology_outlined,
                      title: '当前模型',
                      subtitle: widget.activeModel.isNotEmpty
                          ? widget.activeModel
                          : (widget.activeProviderName.isNotEmpty
                              ? widget.activeProviderName
                              : '选择模型'),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onModelTap();
                      },
                    ),

                    const SizedBox(height: 14),

                    // --- 运行时上下文 HUD (默认折叠) ---
                    Theme(
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const _SectionHeader(title: '运行状态与HUD (点击展开)'),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.black.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '上下文窗口 (${(widget.contextTokens / 1000).toStringAsFixed(0)}k)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      '${(contextRatio * 100).toStringAsFixed(1)}%',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w700,
                                        color: contextRatio > 0.8
                                            ? AppTheme.danger
                                            : (contextRatio > 0.6
                                                ? AppTheme.warning
                                                : AppTheme.success),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: contextRatio == 0 ? 0.01 : contextRatio,
                                    minHeight: 6,
                                    backgroundColor: isDark
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : Colors.black.withValues(alpha: 0.06),
                                    color: contextRatio > 0.8
                                        ? AppTheme.danger
                                        : AppTheme.brandBright,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '当前轮: $currentContextTokens tok',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      '累计: $totalTokens tok',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        color: theme.colorScheme.onSurfaceVariant,
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

                    const SizedBox(height: 14),

                    // --- 历史会话列表 ---
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
                        padding: EdgeInsets.all(12),
                        child: Center(
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))),
                      )
                    else if (_recentConversations.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '暂无历史对话记录',
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
                          onTap: () {
                            Navigator.pop(context);
                            widget.onSelectConversation(c);
                          },
                        ),
                      ),
                  ],
                ),
              ),

              const Divider(height: 1, indent: 16, endIndent: 16),

              // 3. 底部功能集合 (MCP / 提示词 / 计划模式 / 设置)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'MCP 服务',
                      icon: const Icon(Icons.widgets_outlined, size: 20),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onMcpMenu();
                      },
                    ),
                    IconButton(
                      tooltip: '提示词库',
                      icon: const Icon(Icons.keyboard_command_key_rounded,
                          size: 20),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onPromptLibrary();
                      },
                    ),
                    IconButton(
                      tooltip: widget.planModeEnabled ? '关闭计划模式' : '开启计划模式',
                      icon: Icon(
                        widget.planModeEnabled
                            ? Icons.front_hand_rounded
                            : Icons.pan_tool_alt_rounded,
                        size: 20,
                        color: widget.planModeEnabled ? AppTheme.warning : null,
                      ),
                      onPressed: () {
                        widget.onPlanModeToggle();
                      },
                    ),
                    IconButton(
                      tooltip: '应用设置',
                      icon: const Icon(Icons.settings_outlined, size: 20),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SettingsPage()),
                        );
                      },
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
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CatalogTile({
    required this.icon,
    required this.title,
    required this.subtitle,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
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
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const _HistoryTile({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(
        conversation.isPinned
            ? Icons.push_pin_rounded
            : Icons.chat_bubble_outline_rounded,
        size: 16,
        color: conversation.isPinned
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
      title: Text(
        conversation.title.isEmpty ? '新对话' : conversation.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      onTap: onTap,
    );
  }
}
