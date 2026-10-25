import '../widgets/empty_state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/providers.dart';
import '../../application/research_artifact_service.dart';
import '../../domain/research_artifact.dart';
import '../../domain/unique_id.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_page_layout.dart';

class ResearchArtifactsPage extends ConsumerStatefulWidget {
  const ResearchArtifactsPage({super.key, this.readOnly = false});
  final bool readOnly;
  @override
  ConsumerState<ResearchArtifactsPage> createState() =>
      _ResearchArtifactsPageState();
}

class _ResearchArtifactsPageState extends ConsumerState<ResearchArtifactsPage> {
  List<ResearchArtifact> _items = [];
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<ResearchArtifactService> _service() async =>
      ResearchArtifactService(await ref.read(databaseProvider.future));

  Future<void> _load() async {
    try {
      final items = await (await _service()).list();
      if (mounted) {
        setState(() {
          _items = items;
          _busy = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '研究成果读取失败，请重试';
        });
      }
    }
  }

  Future<void> _create() async {
    if (_busy || widget.readOnly) return;
    final service = await _service();
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => _ResearchEditor(service: service)));
    if (saved == true) await _load();
  }

  Future<void> _verify(ResearchArtifact artifact) async {
    if (_busy || widget.readOnly) return;
    setState(() => _busy = true);
    try {
      final updated =
          await (await _service()).refreshVerification(artifactId: artifact.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(updated.version == artifact.version
              ? '未能从来源页面确认引用，保留原核验时间；请检查原文、网络或访问限制'
              : '已重新读取并匹配部分或全部引用原文；结论仍需结合上下文判断')));
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '核验未完成，已保留原证据';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar:
            NexusPageHeader(title: '研究成果', subtitle: '结论、引用与来源时效性', actions: [
          IconButton(
              tooltip: '添加研究资料',
              onPressed: widget.readOnly || _busy ? null : _create,
              icon: const Icon(Icons.add)),
          IconButton(
              tooltip: '刷新列表',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh)),
        ]),
        body: NexusPageLayout(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('引用核验只确认来源页面仍包含摘录；不代表结论自动成立。访问失败或内容变化时，保留原核验时间。'),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            EmptyStateView.compact(
                icon: Icons.error_outline_rounded,
                title: '研究成果读取失败',
                message: _error,
                actionLabel: '重试',
                onAction: _load),
          if (!_busy && _error == null && _items.isEmpty)
            const EmptyStateView(
                icon: Icons.manage_search_rounded,
                title: '暂无研究成果',
                message: '点击右上角添加资料与引用'),
          for (final artifact in _items)
            Card(
                child: ExpansionTile(
              title: Text(artifact.topic),
              subtitle: Text(
                  'v${artifact.version} · ${artifact.totalCitations} 条引用 · ${artifact.supportLevel.label}'),
              childrenPadding: const EdgeInsets.all(12),
              children: [
                SelectableText(artifact.summary),
                for (final claim in artifact.claims)
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        SelectableText(claim.statement,
                            style: Theme.of(context).textTheme.titleSmall),
                        Text(claim.evaluateSupport().label),
                        for (final citation in claim.citations)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(citation.sourceTitle),
                                    SelectableText(citation.excerpt),
                                    Text(
                                        '最近核验：${citation.verifiedAt.millisecondsSinceEpoch == 0 ? "尚未核验" : citation.verifiedAt.toLocal().toString().substring(0, 16)}'),
                                    TextButton(
                                        onPressed: () async {
                                          final uri =
                                              Uri.tryParse(citation.sourceUri);
                                          final valid = uri != null &&
                                              const {'http', 'https'}
                                                  .contains(uri.scheme) &&
                                              uri.host.isNotEmpty;
                                          if (!valid ||
                                              !await launchUrl(uri,
                                                  mode: LaunchMode
                                                      .externalApplication)) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(const SnackBar(
                                                      content:
                                                          Text('来源链接不可用')));
                                            }
                                          }
                                        },
                                        child: Text(citation.sourceUri)),
                                  ])),
                      ]),
                if (!widget.readOnly)
                  OutlinedButton.icon(
                      onPressed: _busy ? null : () => _verify(artifact),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('从来源重新核对引用')),
              ],
            )),
        ])),
      );
}

class _ResearchEditor extends StatefulWidget {
  const _ResearchEditor({required this.service});
  final ResearchArtifactService service;
  @override
  State<_ResearchEditor> createState() => _ResearchEditorState();
}

class _ResearchEditorState extends State<_ResearchEditor> {
  final _topic = TextEditingController(),
      _summary = TextEditingController(),
      _claim = TextEditingController(),
      _url = TextEditingController(),
      _excerpt = TextEditingController();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    for (final controller in [_topic, _summary, _claim, _url, _excerpt]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_topic.text.trim().isEmpty || _claim.text.trim().isEmpty) {
        throw const FormatException('请填写主题与待核查结论');
      }
      final uri = Uri.tryParse(_url.text.trim());
      if ((_url.text.isNotEmpty || _excerpt.text.isNotEmpty) &&
          (uri == null ||
              uri.scheme != 'https' ||
              uri.host.isEmpty ||
              _excerpt.text.trim().isEmpty)) {
        throw const FormatException('引用需同时填写 HTTPS 来源地址和原文摘录');
      }
      final now = DateTime.now().toUtc();
      await widget.service
          .create(topic: _topic.text, summary: _summary.text, claims: [
        ResearchClaim(
          id: UniqueId.generate('claim'),
          statement: _claim.text.trim(),
          citations: [
            if (_url.text.isNotEmpty)
              EvidenceCitation(
                  id: UniqueId.generate('citation'),
                  sourceTitle: uri!.host,
                  sourceUri: uri.toString(),
                  excerpt: _excerpt.text.trim(),
                  capturedAt: now,
                  verifiedAt:
                      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)),
          ],
        )
      ]);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is FormatException ? error.message : '保存失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const NexusPageHeader(title: '添加研究资料'),
        body: NexusPageLayout(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          TextField(
              controller: _topic,
              decoration: const InputDecoration(labelText: '研究主题'),
              maxLength: 256),
          TextField(
              controller: _summary,
              decoration: const InputDecoration(labelText: '摘要'),
              maxLines: 3),
          TextField(
              controller: _claim,
              decoration: const InputDecoration(labelText: '待核查结论'),
              maxLines: 3),
          TextField(
              controller: _url,
              decoration: const InputDecoration(labelText: 'HTTPS 来源地址（可选）')),
          TextField(
              controller: _excerpt,
              decoration: const InputDecoration(labelText: '对应原文摘录'),
              maxLines: 4),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存为待核查资料')),
        ])),
      );
}
