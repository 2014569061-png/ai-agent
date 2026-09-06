import 'package:flutter/material.dart';

import '../../../infrastructure/update/update_service.dart';

/// G1 发现新版本的更新说明弹层:版本号 + Release 说明 + 下载安装(带进度)。
class UpdateSheet extends StatefulWidget {
  const UpdateSheet({super.key, required this.info});

  final UpdateInfo info;

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;
  bool _launched = false;

  Future<void> _downloadAndInstall() async {
    if (_downloading || widget.info.apkUrl == null) return;
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });
    final ok = await UpdateService()
        .downloadAndInstall(widget.info.apkUrl!,
            onProgress: (p) => setState(() => _progress = p));
    if (!mounted) return;
    setState(() {
      _downloading = false;
      if (ok) {
        _launched = true; // 已拉起系统安装器,用户确认后安装
      } else {
        _error = '下载或拉起安装失败,请重试';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.system_update_alt_rounded,
                color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('发现新版本 v${widget.info.version}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ]),
          const Divider(height: 20),
          if (widget.info.notes.trim().isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.info.notes.trim(),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(height: 1.5, fontSize: 12.5),
                ),
              ),
            )
          else
            Text('暂无更新说明',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 16),
          if (_downloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: _progress, minHeight: 6),
            ),
            const SizedBox(height: 6),
            Text('下载中 ${( _progress * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
          ],
          if (_error != null) ...[
            Text(_error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
            const SizedBox(height: 12),
          ],
          if (_launched)
            Text('已拉起系统安装,请在弹出的安装页确认。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary))
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _downloading ? null : _downloadAndInstall,
                icon: const Icon(Icons.download_rounded),
                label: Text(_downloading ? '下载中...' : '下载并安装'),
              ),
            ),
        ],
      ),
    );
  }
}
