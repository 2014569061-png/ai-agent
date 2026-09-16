import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/nexus_execution_status.dart';

/// 顶栏统一高度常量 (56px)
const double kCapsuleTopBarHeight = AppTokens.kTopBarHeight;

/// 首页 / 对话页顶部栏（对标 DeepSeek App）。
///
/// 与 DeepSeek 一致的三点：
///   1. **没有底部分隔线**，顶栏与页面融为一体；
///   2. 左侧是自定义的两段式抽屉图标（长线 + 短线），不是通用汉堡图标；
///   3. 右侧是「圆圈 + 加号」，不是裸加号。
/// 新会话时中间**留空**（DeepSeek 首页不显示「新会话」这类标题），
/// 进入具体会话后显示标题；模型、工作区和当前模式始终显示在标题下方。
class CapsuleTopBar extends StatelessWidget {
  const CapsuleTopBar({
    super.key,
    this.workspaceLabel,
    this.modelLabel,
    this.sessionTitle,
    this.runningStage,
    required this.onMenu,
    required this.onNewChat,
    this.onContextGaugeTap,
    this.onTitleTap,
    this.onModelTap,
    this.onWorkspaceTap,
    this.modeLabel,
    this.onModeTap,
    this.currentContextTokens = 0,
    this.maxContextTokens = 128000,
    this.statusActive = false,
  });

  final String? workspaceLabel;
  final String? modelLabel;
  final String? sessionTitle;
  final String? runningStage;
  final VoidCallback onMenu;
  final VoidCallback onNewChat;
  final VoidCallback? onContextGaugeTap;
  final VoidCallback? onTitleTap;
  final VoidCallback? onModelTap;
  final VoidCallback? onWorkspaceTap;
  final String? modeLabel;
  final VoidCallback? onModeTap;
  final int currentContextTokens;
  final int maxContextTokens;
  final bool statusActive;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final canvas = isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas;

    // 新会话不再回填「新会话」占位文案，保持首页中间留空。
    final title = (sessionTitle ?? '').trim();
    final model = (modelLabel ?? '').trim();
    final workspace = (workspaceLabel ?? '').trim();
    final mode = (modeLabel ?? '').trim();
    final contextUsage = maxContextTokens > 0
        ? '上下文 ${_formatTokens(currentContextTokens)} / ${_formatTokens(maxContextTokens)}'
        : '';
    final contextLabel = [
      if (model.isNotEmpty) model,
      if (workspace.isNotEmpty) workspace,
      if (contextUsage.isNotEmpty) contextUsage,
    ].join(' · ');
    final metaColor =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    final tokenRatio = maxContextTokens > 0
        ? (currentContextTokens / maxContextTokens).clamp(0.0, 1.0)
        : 0.0;
    final gaugeDotColor = tokenRatio >= 0.9
        ? AppPalette.danger
        : tokenRatio >= 0.7
            ? AppPalette.warning
            : (isDark ? AppPalette.brand : AppPalette.brandAction);

    return Container(
      height: kCapsuleTopBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: canvas,
      child: Row(
        children: [
          // 左侧：至少 48px 触控区，两段式抽屉图标
          SizedBox(
            width: 48,
            height: 48,
            child: Semantics(
              label: '打开会话列表',
              button: true,
              child: Material(
                color: Colors.transparent,
                child: InkResponse(
                  onTap: onMenu,
                  radius: 24,
                  child: Center(
                    child: CustomPaint(
                      size: const Size(22, 14),
                      painter: _DrawerGlyphPainter(color: textColor),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 中间：标题 + 始终可见的模型 / 工作区 / 模式信息。
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title.isNotEmpty)
                  GestureDetector(
                    onTap: onTitleTap ?? onModelTap,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (statusActive) ...[
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(
                              color: AppPalette.brand,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                              color: textColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (contextLabel.isNotEmpty ||
                    mode.isNotEmpty ||
                    (runningStage != null && runningStage!.isNotEmpty)) ...[
                  if (title.isNotEmpty) const SizedBox(height: 1),
                  SizedBox(
                    width: double.infinity,
                    height: 20,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (runningStage != null &&
                            runningStage!.isNotEmpty) ...[
                          Flexible(
                            child: NexusExecutionStatus(
                              compact: true,
                              state: _mapRunningStage(runningStage),
                              label: runningStage!,
                            ),
                          ),
                          if (contextLabel.isNotEmpty || mode.isNotEmpty)
                            Text(
                              ' · ',
                              style: TextStyle(fontSize: 11, color: metaColor),
                            ),
                        ],
                        if (contextLabel.isNotEmpty)
                          Flexible(
                            child: GestureDetector(
                              onTap: onContextGaugeTap ??
                                  onTitleTap ??
                                  onModelTap ??
                                  onWorkspaceTap,
                              behavior: HitTestBehavior.opaque,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (maxContextTokens > 0)
                                    Container(
                                      width: 5,
                                      height: 5,
                                      margin: const EdgeInsets.only(right: 4),
                                      decoration: BoxDecoration(
                                        color: gaugeDotColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  Flexible(
                                    child: Text(
                                      contextLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        height: 1.35,
                                        color: metaColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (contextLabel.isNotEmpty && mode.isNotEmpty)
                          Text(
                            ' · ',
                            style: TextStyle(fontSize: 11, color: metaColor),
                          ),
                        if (mode.isNotEmpty)
                          Semantics(
                            button: onModeTap != null,
                            label: '当前模式：$mode',
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: onModeTap,
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 3),
                                  child: Text(
                                    mode,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      height: 1.35,
                                      color: onModeTap == null
                                          ? metaColor
                                          : AppPalette.brand,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 右侧：至少 48px 触控区，圆圈加号
          SizedBox(
            width: 48,
            height: 48,
            child: Semantics(
              label: '新建对话',
              button: true,
              child: Material(
                color: Colors.transparent,
                child: InkResponse(
                  onTap: onNewChat,
                  radius: 24,
                  child: Center(
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: textColor, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child:
                          Icon(Icons.add_rounded, size: 16, color: textColor),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static NexusExecutionState _mapRunningStage(String? stage) {
    if (stage == null) return NexusExecutionState.idle;
    if (stage.contains('等待') || stage.contains('确认') || stage.contains('授权')) {
      return NexusExecutionState.waitingForUser;
    }
    if (stage.contains('准备') || stage.contains('思考')) {
      return NexusExecutionState.preparing;
    }
    if (stage.contains('完成') || stage.contains('成功')) {
      return NexusExecutionState.succeeded;
    }
    if (stage.contains('失败') || stage.contains('错误')) {
      return NexusExecutionState.failed;
    }
    if (stage.contains('取消') || stage.contains('停止')) {
      return NexusExecutionState.cancelled;
    }
    return NexusExecutionState.running;
  }

  static String _formatTokens(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k';
    }
    return '$value';
  }
}

/// 两段式抽屉图标：上方长线 + 下方短线，左对齐。
class _DrawerGlyphPainter extends CustomPainter {
  const _DrawerGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const gap = 6.0;
    final top = (size.height - gap) / 2;
    final bottom = top + gap;

    canvas.drawLine(Offset(0, top), Offset(size.width, top), paint);
    canvas.drawLine(
        Offset(0, bottom), Offset(size.width * 0.62, bottom), paint);
  }

  @override
  bool shouldRepaint(covariant _DrawerGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
