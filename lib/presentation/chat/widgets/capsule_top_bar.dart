import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';

/// 顶栏统一高度常量 (56px)
const double kCapsuleTopBarHeight = AppTokens.kTopBarHeight;

/// 首页 / 对话页顶部栏（对标 DeepSeek App）。
///
/// 与 DeepSeek 一致的三点：
///   1. **没有底部分隔线**，顶栏与页面融为一体；
///   2. 左侧是自定义的两段式抽屉图标（长线 + 短线），不是通用汉堡图标；
///   3. 右侧是「圆圈 + 加号」，不是裸加号。
/// 新会话时中间**留空**（DeepSeek 首页不显示「新会话」这类标题），
/// 只有进入具体会话后才居中显示会话标题。
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

    return Container(
      height: kCapsuleTopBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: canvas,
      child: Row(
        children: [
          // 左侧：40px 触控区，两段式抽屉图标
          SizedBox(
            width: 40,
            height: 40,
            child: Semantics(
              label: '打开会话列表',
              button: true,
              child: GestureDetector(
                onTap: onMenu,
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: CustomPaint(
                    size: const Size(22, 14),
                    painter: _DrawerGlyphPainter(color: textColor),
                  ),
                ),
              ),
            ),
          ),

          // 中间：仅在有会话标题时显示，17/500 单行省略
          Expanded(
            child: title.isEmpty
                ? const SizedBox.shrink()
                : GestureDetector(
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
          ),

          // 右侧：40px 触控区，圆圈加号
          SizedBox(
            width: 40,
            height: 40,
            child: Semantics(
              label: '新建对话',
              button: true,
              child: GestureDetector(
                onTap: onNewChat,
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: textColor, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.add_rounded, size: 16, color: textColor),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
