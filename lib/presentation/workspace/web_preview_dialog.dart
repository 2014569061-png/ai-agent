import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../widgets/immersive_dropdown.dart';
import 'phone_preview_view.dart';

/// 在电脑上以手机视口比例预览网页项目。
///
/// Web 端通过 iframe 嵌入用户输入的开发服务器地址；桌面/移动端保留
/// 同一套工具界面，并提供系统浏览器打开能力。
class WebPreviewDialog extends StatefulWidget {
  const WebPreviewDialog({
    super.key,
    required this.indexPath,
    required this.workspacePath,
    this.initialUrl,
  });

  final String indexPath;
  final String workspacePath;
  final String? initialUrl;

  @override
  State<WebPreviewDialog> createState() => _WebPreviewDialogState();
}

class _WebPreviewDialogState extends State<WebPreviewDialog> {
  static const _devices = <_DevicePreset>[
    _DevicePreset(
      name: 'iPhone 15 Pro',
      width: 393,
      height: 852,
      description: '常用 iOS 手机视口',
    ),
    _DevicePreset(
      name: 'iPhone SE',
      width: 375,
      height: 667,
      description: '小尺寸 iOS 手机视口',
    ),
    _DevicePreset(
      name: 'Pixel 8',
      width: 412,
      height: 915,
      description: '常用 Android 手机视口',
    ),
    _DevicePreset(
      name: 'Android 小屏',
      width: 360,
      height: 800,
      description: '兼容性检查用窄屏视口',
    ),
  ];

  late final TextEditingController _urlController;
  late _DevicePreset _device;
  String _previewUrl = '';
  String? _validationMessage;
  bool _landscape = false;
  double _zoom = 1;
  int _previewVersion = 0;

  @override
  void initState() {
    super.initState();
    _device = _devices.first;
    final initial = widget.initialUrl?.trim();
    final pathAsUrl = _looksLikeUrl(widget.indexPath) ? widget.indexPath : '';
    _urlController = TextEditingController(
      text: initial?.isNotEmpty == true ? initial : pathAsUrl,
    );
    if (_urlController.text.trim().isNotEmpty) {
      _previewUrl = _normaliseUrl(_urlController.text.trim());
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  bool _looksLikeUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  String _normaliseUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty || _looksLikeUrl(value)) return value;
    if (value.startsWith('localhost:') ||
        value.startsWith('127.0.0.1:') ||
        value.startsWith('0.0.0.0:')) {
      return 'http://$value';
    }
    return value;
  }

  void _loadPreview() {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _previewUrl = '';
        _validationMessage = null;
      });
      return;
    }

    final normalised = _normaliseUrl(raw);
    final uri = Uri.tryParse(normalised);
    final valid = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (!valid) {
      setState(() => _validationMessage = '请输入有效地址，例如 http://localhost:3000');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _previewUrl = normalised;
      _validationMessage = null;
      _previewVersion++;
    });
  }

  void _reloadPreview() {
    if (_previewUrl.isEmpty) {
      _loadPreview();
      return;
    }
    setState(() => _previewVersion++);
  }

  Future<void> _openInBrowser() async {
    final raw = _previewUrl.isNotEmpty
        ? _previewUrl
        : (_looksLikeUrl(widget.indexPath) ? widget.indexPath : '');
    final uri = raw.isNotEmpty ? Uri.tryParse(raw) : Uri.file(widget.indexPath);
    if (uri == null) return;

    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _showMessage('系统浏览器暂时无法打开这个地址');
      }
    } catch (_) {
      if (mounted) _showMessage('系统浏览器暂时无法打开这个地址');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Size get _viewportSize => _landscape
      ? Size(_device.height, _device.width)
      : Size(_device.width, _device.height);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(1180.0, math.max(320.0, screen.width - 32));
    final height = math.min(820.0, math.max(480.0, screen.height - 48));

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _buildHeader(theme),
            _buildAddressBar(theme),
            Divider(height: 1, color: colors.outlineVariant),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 760) {
                    return Column(
                      children: [
                        Expanded(child: _buildPreviewArea(theme)),
                        _buildCompactControls(theme),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: _buildPreviewArea(theme)),
                      SizedBox(
                        width: 270,
                        child: _buildControls(theme),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final colors = theme.colorScheme;
    final relativePath = _relativeIndexPath();
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.phone_iphone_rounded, color: colors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '手机视口预览',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  relativePath.isEmpty
                      ? '输入开发服务器地址，在电脑上模拟手机页面'
                      : '入口文件：$relativePath',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _urlController,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _loadPreview(),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.link_rounded, size: 19),
                hintText: '输入网址，例如 http://localhost:3000',
                errorText: _validationMessage,
                suffixIcon: _urlController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        onPressed: () {
                          _urlController.clear();
                          setState(() {
                            _previewUrl = '';
                            _validationMessage = null;
                          });
                        },
                        icon: const Icon(Icons.clear_rounded, size: 18),
                      ),
              ),
              onChanged: (_) {
                setState(() {
                  _validationMessage = null;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _loadPreview,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('加载'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _openInBrowser,
            child: const Icon(Icons.open_in_new_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  String _relativeIndexPath() {
    if (widget.indexPath.trim().isEmpty ||
        widget.workspacePath.trim().isEmpty) {
      return '';
    }
    try {
      return p.relative(widget.indexPath, from: widget.workspacePath);
    } catch (_) {
      return p.basename(widget.indexPath);
    }
  }

  Widget _buildPreviewArea(ThemeData theme) {
    final colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 18, 12, 18),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF111827)
            : const Color(0xFFF2F5FA),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 12, 8),
            child: Row(
              children: [
                Icon(Icons.preview_rounded, size: 17, color: colors.primary),
                const SizedBox(width: 7),
                const Text(
                  '预览画布',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (_previewUrl.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2BA471).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 7, color: Color(0xFF2BA471)),
                        SizedBox(width: 5),
                        Text('已嵌入', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                IconButton(
                  tooltip: '刷新页面',
                  onPressed: _reloadPreview,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewport = _viewportSize;
                final phoneWidth = viewport.width + 28;
                final phoneHeight = viewport.height + 28;
                final fitScale = math.min(
                  (constraints.maxWidth - 42) / phoneWidth,
                  (constraints.maxHeight - 42) / phoneHeight,
                );
                final scale = math.max(.32, math.min(1.2, fitScale * _zoom));

                return Scrollbar(
                  thumbVisibility: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(21),
                    child: Center(
                      child: SizedBox(
                        width: phoneWidth * scale,
                        height: phoneHeight * scale,
                        child: Transform.scale(
                          scale: scale,
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: phoneWidth,
                            height: phoneHeight,
                            child: _buildPhoneFrame(viewport),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneFrame(Size viewport) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF05070B) : const Color(0xFF161A22),
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .22),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.white,
              child: _previewUrl.isEmpty
                  ? _buildEmptyPreview()
                  : PhonePreviewView(
                      key: ValueKey('$_previewUrl-$_previewVersion'),
                      url: _previewUrl,
                    ),
            ),
            IgnorePointer(child: _buildPhoneChrome(viewport)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPreview() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phone_android_rounded,
                size: 48, color: Colors.blueGrey.shade300),
            const SizedBox(height: 14),
            const Text(
              '输入地址开始预览',
              style: TextStyle(
                color: Color(0xFF334155),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '先启动你的 Web 开发服务器，\n再把地址粘贴到上方输入框。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneChrome(Size viewport) {
    final horizontal = viewport.width > viewport.height;
    if (horizontal) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 25,
          height: 86,
          margin: const EdgeInsets.only(left: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .82),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: 104,
        height: 25,
        margin: const EdgeInsets.only(top: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .82),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildControls(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(6, 18, 18, 18),
      child: _buildControlContent(theme),
    );
  }

  Widget _buildCompactControls(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border:
            Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: _buildControlContent(theme, compact: true),
    );
  }

  Widget _buildControlContent(ThemeData theme, {bool compact = false}) {
    final colors = theme.colorScheme;
    final viewport = _viewportSize;
    final deviceField = ImmersiveDropdown<_DevicePreset>(
      labelText: '设备尺寸',
      prefixIcon: const Icon(Icons.devices_other_rounded, size: 19),
      initialValue: _device,
      items: _devices
          .map(
            (device) => DropdownMenuItem<_DevicePreset>(
              value: device,
              child: Text(device.name),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) setState(() => _device = value);
      },
    );
    final orientationField = SegmentedButton<bool>(
      segments: const [
        ButtonSegment<bool>(
          value: false,
          icon: Icon(Icons.stay_current_portrait_rounded, size: 17),
          label: Text('竖屏'),
        ),
        ButtonSegment<bool>(
          value: true,
          icon: Icon(Icons.stay_current_landscape_rounded, size: 17),
          label: Text('横屏'),
        ),
      ],
      selected: {_landscape},
      onSelectionChanged: (selection) {
        setState(() => _landscape = selection.first);
      },
      showSelectedIcon: false,
    );
    final zoomField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.zoom_out_map_rounded,
                size: 17, color: colors.onSurfaceVariant),
            const SizedBox(width: 7),
            const Text('画布缩放', style: TextStyle(fontSize: 12)),
            const Spacer(),
            Text('${(_zoom * 100).round()}%',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          ],
        ),
        Slider(
          value: _zoom,
          min: .7,
          max: 1.2,
          divisions: 10,
          label: '${(_zoom * 100).round()}%',
          onChanged: (value) => setState(() => _zoom = value),
        ),
      ],
    );
    final sizeCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${viewport.width.round()} × ${viewport.height.round()} px',
            style: TextStyle(
              color: colors.primary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _device.description,
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
    final tips = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '使用提示',
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '页面必须先通过 http://localhost 等地址运行。若页面设置了禁止 iframe 的响应头，请点击右上角按钮用系统浏览器打开。',
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 11,
            height: 1.45,
          ),
        ),
      ],
    );

    if (!compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('预览设置',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          deviceField,
          const SizedBox(height: 12),
          orientationField,
          const SizedBox(height: 17),
          zoomField,
          sizeCard,
          const SizedBox(height: 14),
          tips,
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 190, child: deviceField),
          const SizedBox(width: 10),
          SizedBox(width: 260, child: orientationField),
          const SizedBox(width: 12),
          SizedBox(width: 230, child: zoomField),
          const SizedBox(width: 12),
          SizedBox(width: 180, child: sizeCard),
        ],
      ),
    );
  }
}

class _DevicePreset {
  const _DevicePreset({
    required this.name,
    required this.width,
    required this.height,
    required this.description,
  });

  final String name;
  final double width;
  final double height;
  final String description;
}
