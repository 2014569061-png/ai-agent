import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';

/// DeepSeek 风格底部附件展开面板 (对标图 2)
/// 包含：
/// 1. 上方横向滑动的相册/截图预览卡片流 (带右上角单选圆圈)
/// 2. 下方 3 颗大圆角主功能卡片：[ 拍照 ] / [ 相册 ] / [ 文件 ]
class AttachmentDrawerPanel extends StatefulWidget {
  const AttachmentDrawerPanel({
    super.key,
    required this.onCamera,
    required this.onGallery,
    required this.onFile,
    this.attachments = const [],
    this.onSelectThumbnail,
  });

  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onFile;
  final List<PlatformFile> attachments;
  final ValueChanged<int>? onSelectThumbnail;

  @override
  State<AttachmentDrawerPanel> createState() => _AttachmentDrawerPanelState();
}

class _AttachmentDrawerPanelState extends State<AttachmentDrawerPanel> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final cardBg = isDark ? AppPalette.darkSurfaceHover : AppPalette.lightCanvas;
    final border = isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted = isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: border, width: 0.8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. 上方缩略图横向滑动流：显示当前真正选中的附件。
          if (widget.attachments.isNotEmpty)
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: widget.attachments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final isSelected = _selectedIndex == index;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedIndex = isSelected ? null : index;
                      });
                      widget.onSelectThumbnail?.call(index);
                    },
                    child: _AttachmentThumbnail(
                      file: widget.attachments[index],
                      selected: isSelected,
                      cardBg: cardBg,
                      border: border,
                      textMuted: textMuted,
                    ),
                  );
                },
              ),
            )
          else
            SizedBox(
              height: 72,
              child: Center(
                child: Text(
                  '选择图片或文件后会显示预览',
                  style: TextStyle(fontSize: 12, color: textMuted),
                ),
              ),
            ),
          const SizedBox(height: 14),

          // 2. 下方 3 颗大圆角功能卡片：拍照、相册、文件 (图 2 样式)
          Row(
            children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.photo_camera_outlined,
                  label: '拍照',
                  cardBg: cardBg,
                  border: border,
                  textColor: textColor,
                  onTap: widget.onCamera,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  icon: Icons.photo_library_outlined,
                  label: '相册',
                  cardBg: cardBg,
                  border: border,
                  textColor: textColor,
                  onTap: widget.onGallery,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  icon: Icons.attach_file_rounded,
                  label: '文件',
                  cardBg: cardBg,
                  border: border,
                  textColor: textColor,
                  onTap: widget.onFile,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachmentThumbnail extends StatelessWidget {
  const _AttachmentThumbnail({
    required this.file,
    required this.selected,
    required this.cardBg,
    required this.border,
    required this.textMuted,
  });

  final PlatformFile file;
  final bool selected;
  final Color cardBg;
  final Color border;
  final Color textMuted;

  bool get _isImage {
    final extension = (file.extension ??
            (file.name.contains('.') ? file.name.split('.').last : ''))
        .toLowerCase();
    return const {'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'heic'}
        .contains(extension);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = file.bytes;
    final canRenderImage = _isImage && bytes != null && bytes.isNotEmpty;

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? AppPalette.brand : border,
          width: selected ? 1.5 : 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.2
                    : 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          canRenderImage
              ? Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fileIcon(),
                )
              : _fileIcon(),
          Positioned(
            top: 5,
            right: 5,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? AppPalette.brand
                    : Colors.black.withValues(alpha: 0.35),
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      size: 10, color: Colors.white)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileIcon() => Center(
        child: Icon(
          _isImage
              ? Icons.broken_image_outlined
              : Icons.insert_drive_file_outlined,
          size: 24,
          color: textMuted.withValues(alpha: 0.55),
        ),
      );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.cardBg,
    required this.border,
    required this.textColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color cardBg;
  final Color border;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 26, color: textColor),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
