import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/brand_mark.dart';

class QuickAction {
  const QuickAction({this.id = '', required this.label, String? prompt})
      : prompt = prompt ?? label;

  final String id;
  final String label;
  final String prompt;
}

class ChatEmptyState extends StatefulWidget {
  const ChatEmptyState({
    super.key,
    this.suggestions = const [],
    this.onSuggestionTap,
    this.hasWorkspace = false,
    this.providerConfigured = false,
    this.keyboardVisible = false,
    this.workspaceLabel,
    this.modelLabel,
    this.onWorkspaceTap,
    this.onModelTap,
    this.onConfigureModel,
    this.onAnalyzeWorkspace,
  });

  final List<QuickAction> suggestions;
  final ValueChanged<QuickAction>? onSuggestionTap;
  final bool hasWorkspace;
  final bool providerConfigured;
  final bool keyboardVisible;
  final String? workspaceLabel;
  final String? modelLabel;
  final VoidCallback? onWorkspaceTap;
  final VoidCallback? onModelTap;
  final VoidCallback? onConfigureModel;
  final VoidCallback? onAnalyzeWorkspace;

  @override
  State<ChatEmptyState> createState() => _ChatEmptyStateState();
}

class _ChatEmptyStateState extends State<ChatEmptyState> {
  int _selectedCategoryIndex = 0;

  static const List<String> _categories = ['常用', '代码', '审查', '终端'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 44, withGlow: true),
            const SizedBox(height: 16),
            Text(
              '今天想构建什么？',
              textAlign: TextAlign.center,
              style: theme.textTheme.displayMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '审查代码变更 · 执行指令 · 自动化重构',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: textMuted,
              ),
            ),
            if (!widget.keyboardVisible) ...[
              const SizedBox(height: 24),
              // 横向紧凑场景分段芯片（Segmented Chips，释放纵向空间）
              _ScenarioSegmentedBar(
                categories: _categories,
                selectedIndex: _selectedCategoryIndex,
                onSelect: (index) {
                  setState(() => _selectedCategoryIndex = index);
                },
              ),
              const SizedBox(height: 16),
              // 2x2 规整极简工程卡片网格
              _AuthoritativeActionGrid(
                categoryIndex: _selectedCategoryIndex,
                providerConfigured: widget.providerConfigured,
                hasWorkspace: widget.hasWorkspace,
                onConfigureModel: widget.onConfigureModel,
                onPickWorkspace: widget.onWorkspaceTap,
                onAnalyzeWorkspace: widget.onAnalyzeWorkspace,
                onTap: (prompt) {
                  widget.onSuggestionTap?.call(QuickAction(label: prompt));
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 横向紧凑场景分段栏（Segmented Chips，释放纵向高度）
class _ScenarioSegmentedBar extends StatelessWidget {
  const _ScenarioSegmentedBar({
    required this.categories,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> categories;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(categories.length, (index) {
          final isSelected = index == selectedIndex;
          final item = categories[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelect(index),
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                child: AnimatedContainer(
                  duration: AppTokens.durationFast,
                  curve: AppTokens.curveStandard,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? AppPalette.brand : surface,
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    border: Border.all(
                      color: isSelected
                          ? AppPalette.brand
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFE2E8F0)),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : (isDark
                              ? AppPalette.darkText
                              : AppPalette.lightText),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// 2x2 规整极简工程卡片网格
class _AuthoritativeActionGrid extends StatelessWidget {
  const _AuthoritativeActionGrid({
    required this.categoryIndex,
    required this.providerConfigured,
    required this.hasWorkspace,
    this.onConfigureModel,
    this.onPickWorkspace,
    this.onAnalyzeWorkspace,
    required this.onTap,
  });

  final int categoryIndex;
  final bool providerConfigured;
  final bool hasWorkspace;
  final VoidCallback? onConfigureModel;
  final VoidCallback? onPickWorkspace;
  final VoidCallback? onAnalyzeWorkspace;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final (primaryLabel, primaryIcon, primaryCallback) = !providerConfigured
        ? ('配置模型', Icons.tune_rounded, onConfigureModel)
        : !hasWorkspace
            ? ('选择项目', Icons.folder_open_rounded, onPickWorkspace)
            : ('分析当前项目', Icons.bolt_rounded, onAnalyzeWorkspace);

    final cards = switch (categoryIndex) {
      0 => [
          _GridCardData(
            title: '审计变更',
            subtitle: '审查本地未暂存与最近 Commit',
            icon: Icons.rate_review_outlined,
            onTap: () => onTap('请审计当前工作区的 Git 变更与未提交改动。'),
          ),
          _GridCardData(
            title: primaryLabel,
            subtitle: !providerConfigured
                ? '配置 API Key 与模型'
                : (!hasWorkspace ? '选择当前工作目录' : '提取工程结构与依赖'),
            icon: primaryIcon,
            onTap: primaryCallback,
          ),
          _GridCardData(
            title: '实现并验证',
            subtitle: '端到端实现、构建并跑通测试',
            icon: Icons.science_outlined,
            onTap: () => onTap('在当前工作区实现需求并自动分析、测试、构建，检查真实产物。'),
          ),
          _GridCardData(
            title: '自动化重构',
            subtitle: '扫描代码架构并提出解耦建议',
            icon: Icons.build_outlined,
            onTap: () => onTap('扫描当前代码架构中的异味与坏味道，提出模块解耦建议。'),
          ),
        ],
      1 => [
          _GridCardData(
            title: '审计 Git 变更',
            subtitle: '审查本地未暂存与最近 Commit',
            icon: Icons.rate_review_outlined,
            onTap: () => onTap('请审计当前工作区的 Git 变更与未提交改动。'),
          ),
          _GridCardData(
            title: '安全漏洞扫描',
            subtitle: '排查硬编码密钥与敏感凭据泄露',
            icon: Icons.security_rounded,
            onTap: () => onTap('扫描项目中的潜在安全风险与硬编码凭证。'),
          ),
          _GridCardData(
            title: '代码规范检查',
            subtitle: '运行静态 Lint 并整理修复建议',
            icon: Icons.rule_rounded,
            onTap: () => onTap('运行静态分析器并汇总所有代码异味。'),
          ),
          _GridCardData(
            title: '性能损耗审计',
            subtitle: '定位内存泄露与过度构建区域',
            icon: Icons.speed_rounded,
            onTap: () => onTap('审计前端渲染层与异步任务调度的性能损耗。'),
          ),
        ],
      2 => [
          _GridCardData(
            title: '执行全量回归',
            subtitle: '运行测试套件并输出终端摘要',
            icon: Icons.terminal_rounded,
            onTap: () => onTap('在终端运行全量测试套件并报告失败项。'),
          ),
          _GridCardData(
            title: '检查依赖更新',
            subtitle: '核对包依赖冲突与过时版本',
            icon: Icons.inventory_2_outlined,
            onTap: () => onTap('分析 pubspec.yaml 中的过时依赖。'),
          ),
          _GridCardData(
            title: '构建产物打包',
            subtitle: '触发 Release 编译并核对产物体积',
            icon: Icons.build_circle_outlined,
            onTap: () => onTap('执行打包流水线并统计二进制产物大小。'),
          ),
          _GridCardData(
            title: '清理编译缓存',
            subtitle: '清空中间产物与临时锁文件',
            icon: Icons.cleaning_services_rounded,
            onTap: () => onTap('清理所有编译构建临时缓存与衍生资源。'),
          ),
        ],
      _ => [
          _GridCardData(
            title: !providerConfigured ? '配置模型参数' : '切换主力模型',
            subtitle: '设定 API Key、上下文限制与思考模式',
            icon: Icons.tune_rounded,
            onTap: onConfigureModel ?? () => onTap('切换当前主力对话模型与提示词。'),
          ),
          _GridCardData(
            title: !hasWorkspace ? '选择项目目录' : '分析当前项目',
            subtitle: '读取项目结构并在上下文构建知识索引',
            icon: Icons.folder_open_rounded,
            onTap: hasWorkspace
                ? (onAnalyzeWorkspace ?? () => onTap('分析当前项目结构与关键依赖。'))
                : onPickWorkspace,
          ),
          _GridCardData(
            title: '端到端实现验证',
            subtitle: '从需求拆解到代码写入并构建跑通',
            icon: Icons.auto_awesome_rounded,
            onTap: () => onTap('在当前工作区实现需求并自动分析、测试、构建，检查真实产物。'),
          ),
          _GridCardData(
            title: '探索 MCP 技能',
            subtitle: '连接文件系统、数据库与外部协议',
            icon: Icons.extension_outlined,
            onTap: () => onTap('列出当前支持的 MCP 工具与扩展能力。'),
          ),
        ],
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: _EngineeringActionCard(data: cards[0])),
              const SizedBox(width: 8),
              Expanded(child: _EngineeringActionCard(data: cards[1])),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _EngineeringActionCard(data: cards[2])),
              const SizedBox(width: 8),
              Expanded(child: _EngineeringActionCard(data: cards[3])),
            ],
          ),
        ],
      ),
    );
  }
}

class _GridCardData {
  const _GridCardData({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
}

class _EngineeringActionCard extends StatelessWidget {
  const _EngineeringActionCard({required this.data});

  final _GridCardData data;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE2E8F0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            border: Border.all(color: border, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(data.icon, size: 15, color: AppPalette.brand),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                data.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

