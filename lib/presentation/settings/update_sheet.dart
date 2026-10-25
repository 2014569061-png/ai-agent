import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../infrastructure/update/update_service.dart';

/// G1 发现新版本的更新说明弹层:版本号 + Release 说明 + 下载安装(带进度)。
class UpdateSheet extends StatefulWidget {
  const UpdateSheet({super.key, required this.info, this.service});

  final UpdateInfo info;
  final UpdateService? service;

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;
  bool _launched = false;
  String? _downloadedPath;
  bool get _windows => widget.info.windowsZipUrl != null;

  Future<void> _downloadAndInstall() async {
    final url = widget.info.windowsZipUrl ?? widget.info.apkUrl;
    if (_downloading || url == null) return;
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });
    final service = widget.service ?? UpdateService();
    void progress(double value) {
      if (mounted) setState(() => _progress = value);
    }

    if (_windows) {
      final result = await service.downloadWindowsPackage(url,
          expectedSha256: widget.info.sha256, onProgress: progress);
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadedPath = result.path;
        _error = result.error;
      });
      return;
    }
    final result = await service.downloadAndInstallDetailed(
      url,
      expectedSha256: widget.info.sha256,
      requireSha256: true,
      onProgress: progress,
    );
    if (!mounted) return;
    setState(() {
      _downloading = false;
      if (result.success) {
        _launched = true; // 已拉起系统安装器,用户确认后安装
      } else {
        _error = result.message ?? '下载或安装失败，请重试';
      }
    });
  }

  Future<void> _openDownloadDirectory() async {
    try {
      await Process.start('explorer.exe', [p.dirname(_downloadedPath!)],
          mode: ProcessStartMode.detached);
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开下载目录：$_downloadedPath');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
        child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.system_update_alt_rounded,
                color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
                child: Text('发现新版本 v${widget.info.version}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w500))),
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
          if (_windows) ...[
            Text(
                '关闭程序后，将完整压缩包解压到新目录，再运行其中的 mobile_agent.exe。保留 DLL 和 data 文件夹。',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
          ],
          if (_downloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: _progress, minHeight: 6),
            ),
            const SizedBox(height: 6),
            Text('下载中 ${(_progress * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
          ],
          if (_error != null) ...[
            Text(_error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
            const SizedBox(height: 12),
          ],
          if (_downloadedPath != null) ...[
            Text('Windows 更新包已下载，SHA-256 校验通过。',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                    onPressed: _openDownloadDirectory,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('打开下载位置'))),
          ] else if (_launched)
            Text('已拉起系统安装,请在弹出的安装页确认。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary))
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _downloading ||
                        (widget.info.apkUrl == null &&
                            widget.info.windowsZipUrl == null)
                    ? null
                    : _downloadAndInstall,
                icon: const Icon(Icons.download_rounded),
                label: Text(_downloading
                    ? '下载中...'
                    : _windows
                        ? '下载 Windows 更新包'
                        : '下载并安装'),
              ),
            ),
        ],
      ),
    ));
  }
}
