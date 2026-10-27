import '../widgets/nexus_error_notice.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/artifact_service.dart';
import '../../application/development_verification.dart';
import '../../application/providers.dart';
import '../../application/static_web_project_service.dart';
import '../../domain/unique_id.dart';
import '../workspace/workspace_editor_page.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_page_layout.dart';
import '../widgets/section_card.dart';
import '../../application/local_error_copy.dart';

class StaticWebDeliveryPage extends ConsumerStatefulWidget {
  const StaticWebDeliveryPage(
      {super.key,
      required this.projectId,
      required this.workspacePath,
      required this.projectName,
      this.artifacts = const ArtifactService()});
  final String projectId, workspacePath, projectName;
  final ArtifactService artifacts;

  @override
  ConsumerState<StaticWebDeliveryPage> createState() =>
      _StaticWebDeliveryPageState();
}

class _StaticWebDeliveryPageState extends ConsumerState<StaticWebDeliveryPage> {
  final _service = const StaticWebProjectService();
  final _preview = StaticWebPreviewServer();
  WebProjectReview? _review;
  ProjectArtifact? _artifact;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    unawaited(_preview.stop());
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final review = await _service.review(widget.workspacePath);
      if (mounted) {
        setState(() {
          _review = review;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _review = null;
          _error = LocalErrorCopy.of(error).headline();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = LocalErrorCopy.of(error).headline());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPreview() => _perform(() async {
        final uri = _preview.url ?? await _preview.start(widget.workspacePath);
        if (!mounted) return;
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw StateError('无法打开浏览器，请确认已安装浏览器后重试');
        }
      });

  Future<void> _edit(String relative) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WorkspaceEditorPage(
          workspacePath: widget.workspacePath,
          relativePath: relative,
          projectId: widget.projectId),
    ));
    if (!mounted) return;
    setState(() => _busy = true);
    await _refresh();
  }

  Future<void> _save() => _perform(() async {
        final review = _review;
        if (review == null) return;
        final temp =
            await (await getTemporaryDirectory()).createTemp('nexus-web-');
        try {
          final file = await _service.export(
              review, File(p.join(temp.path, 'website.zip')));
          if (!mounted) return;
          final db = await ref.read(databaseProvider.future);
          final runId = UniqueId.generate('web-export');
          final artifact = await widget.artifacts.record(
              db: db,
              projectId: widget.projectId,
              taskId: 'manual-export',
              runId: runId,
              workspacePath: temp.path,
              inspection: ArtifactInspection(
                  relativePath: 'website.zip',
                  exists: true,
                  bytes: await file.length(),
                  sha256: ArtifactService.hashBytes(await file.readAsBytes()),
                  notes: [
                    '用户核对的网页资源副本；未执行浏览器功能测试',
                    '文件数 ${review.files.length}，源文件总计 ${review.bytes} 字节'
                  ]));
          if (mounted) setState(() => _artifact = artifact);
        } finally {
          // This directory is created and owned exclusively by this operation.
          await temp.delete(recursive: true);
        }
      });

  Future<void> _share() => _perform(() async {
        final artifact = _artifact;
        if (artifact == null) return;
        final file = await widget.artifacts.verifiedPayload(artifact);
        final result = await SharePlus.instance.share(
            ShareParams(files: [XFile(file.path)], title: widget.projectName));
        if (!mounted) return;
        final message = result.status == ShareResultStatus.success
            ? '已交给所选应用；成果副本仍保留在成果中心'
            : '成果副本已保留，可稍后再次导出';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      });

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar:
              NexusPageHeader(title: '网页预览与交付', subtitle: widget.projectName),
          body: NexusPageLayout(
              child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              const SectionCard(
                  padding: EdgeInsets.all(16),
                  child: Text('无需安装环境，即可在浏览器预览。保存修改后刷新浏览器；退出本页会停止预览。')),
              const SizedBox(height: 12),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) ...[
                NexusErrorNotice(
                  title:
                      _error!.contains('index.html') ? '未找到网页入口文件' : '当前操作未完成',
                  message: _error!.contains('index.html')
                      ? '项目根目录需要 index.html。请回到项目文件添加入口，再重新核对。'
                      : '请检查项目目录和文件是否可访问。已保存的成果副本不会因此被删除。',
                  details: _error,
                  retryLabel: '重新核对文件',
                  onRetry: _busy ? null : _refresh,
                ),
                const SizedBox(height: 12),
              ],
              SectionCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    FilledButton.icon(
                        key: const ValueKey('web-open-preview'),
                        onPressed:
                            _busy || review == null ? null : _openPreview,
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text('打开网页预览')),
                    const SizedBox(height: 8),
                    if (_preview.url != null)
                      TextButton.icon(
                          onPressed:
                              _busy ? null : () => _perform(_preview.stop),
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('停止预览')),
                    if (_error == null)
                      OutlinedButton.icon(
                          onPressed: _busy ? null : () => _perform(_refresh),
                          icon: const Icon(Icons.refresh),
                          label: const Text('刷新文件核对')),
                  ])),
              const SizedBox(height: 12),
              if (review != null)
                SectionCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Text(
                          '交付文件 · ${review.files.length} 项 · ${review.bytes} 字节',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      const Text('导出前请核对下列网页资源及内容。隐藏文件、依赖目录和符号链接不打包。'),
                      if (review.excluded > 0)
                        Text('已排除 ${review.excluded} 个文件或目录'),
                      const SizedBox(height: 8),
                      for (final file in review.files)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(file.path, softWrap: true),
                          subtitle: Text('${file.bytes} 字节'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _busy ||
                                  !const {
                                    '.html',
                                    '.htm',
                                    '.css',
                                    '.js',
                                    '.mjs',
                                    '.json',
                                    '.svg',
                                    '.webmanifest'
                                  }.contains(
                                      p.extension(file.path).toLowerCase())
                              ? null
                              : () => _edit(file.path),
                        ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                          key: const ValueKey('web-save-delivery'),
                          onPressed: _busy ? null : _save,
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('确认文件并保存成果副本')),
                    ])),
              if (_artifact != null) ...[
                const SizedBox(height: 12),
                SectionCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      const Text('网页 ZIP 副本已保存到成果中心'),
                      Text('${_artifact!.bytes} 字节 · 源码后续修改不会替换此副本'),
                      OutlinedButton.icon(
                          key: const ValueKey('web-share-delivery'),
                          onPressed: _busy ? null : _share,
                          icon: const Icon(Icons.ios_share),
                          label: const Text('导出已保存的 ZIP')),
                    ])),
              ],
            ],
          )),
        ));
  }
}
