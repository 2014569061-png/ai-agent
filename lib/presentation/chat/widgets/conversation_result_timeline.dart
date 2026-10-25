import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/artifact_service.dart';
import '../../../application/providers.dart';
import '../../../domain/result_card.dart';
import '../../../infrastructure/database/conversation_result_store.dart';
import '../../artifacts/artifact_center_page.dart';
import 'result_card_view.dart';

/// Durable, bounded results in the message flow. Membership comes from stored
/// task/conversation ownership, never assistant text or a guessed message ID.
class ConversationResultTimeline extends ConsumerStatefulWidget {
  const ConversationResultTimeline(
      {super.key,
      required this.scope,
      this.running = false,
      this.readOnly = false,
      this.sourceIsCurrent,
      this.artifacts = const ArtifactService(),
      this.title = '本会话已保存结果',
      this.showEmpty = false});
  final ConversationResultScope scope;
  final bool running, readOnly;
  final bool Function()? sourceIsCurrent;
  final ArtifactService artifacts;
  final String title;
  final bool showEmpty;
  @override
  ConsumerState<ConversationResultTimeline> createState() =>
      _ConversationResultTimelineState();
}

class _ConversationResultTimelineState
    extends ConsumerState<ConversationResultTimeline>
    with WidgetsBindingObserver {
  List<ResultCard> _cards = [];
  ConversationResultCursor? _next;
  bool _busy = false, _loadedOlder = false, _refreshQueued = false;
  String? _error;
  int _epoch = 0;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _setPolling();
  }

  @override
  void didUpdateWidget(covariant ConversationResultTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope.key != widget.scope.key) {
      _epoch++;
      _cards = [];
      _next = null;
      _error = null;
      _busy = false;
      _loadedOlder = false;
      _refreshQueued = false;
      unawaited(_load());
    } else if (oldWidget.running != widget.running && !_loadedOlder) {
      unawaited(_load());
    }
    if (oldWidget.scope.key != widget.scope.key ||
        oldWidget.running != widget.running) {
      _setPolling();
    }
  }

  void _setPolling() {
    _poll?.cancel();
    if (!widget.running) return;
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          !_loadedOlder) {
        unawaited(_load());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loadedOlder) unawaited(_load());
  }

  @override
  void dispose() {
    _epoch++;
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) {
      if (!more) _refreshQueued = true;
      return;
    }
    final epoch = _epoch;
    final scope = widget.scope;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = await ref.read(databaseProvider.future);
      final page = await ConversationResultRepository(db, scope)
          .page(after: more ? _next : null);
      if (!mounted || epoch != _epoch || scope.key != widget.scope.key) return;
      setState(() {
        _cards = more
            ? [
                ..._cards,
                ...page.items.where((c) => !_cards.any((old) => old.id == c.id))
              ]
            : page.items;
        _next = page.next;
        _loadedOlder = more;
      });
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = '结果读取失败，可重试；不会影响聊天或执行动作');
      }
    } finally {
      if (mounted && epoch == _epoch) {
        setState(() => _busy = false);
        if (_refreshQueued) {
          _refreshQueued = false;
          unawaited(_load());
        }
      }
    }
  }

  Future<void> _open(ResultCard observed) async {
    final epoch = _epoch;
    final scope = widget.scope;
    bool current() =>
        mounted &&
        epoch == _epoch &&
        widget.scope.key == scope.key &&
        (widget.sourceIsCurrent?.call() ?? true);
    try {
      final db = await ref.read(databaseProvider.future);
      final card =
          await ConversationResultRepository(db, scope).findCard(observed.id);
      if (!mounted || !current()) return;
      if (card == null) {
        await _load();
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ArtifactCenterPage(
              initialResultCardId: card.id,
              resultScope: scope,
              sourceIsCurrent: current,
              readOnly: widget.readOnly,
              service: widget.artifacts)));
    } catch (_) {
      if (current()) setState(() => _error = '结果卡已失效或暂时无法打开，请刷新');
    } finally {
      if (current()) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cards.isEmpty && _error == null && !widget.showEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(
                    child: Text(widget.title,
                        style: Theme.of(context).textTheme.titleSmall)),
                IconButton(
                    tooltip: '刷新会话结果',
                    onPressed: _busy ? null : () => _load(),
                    icon: const Icon(Icons.refresh))
              ]),
              const Text('按来源任务归属展示；保存文件不代表任务验证通过。'),
              if (_cards.isEmpty && !_busy && _error == null)
                const Text('本轮还没有已保存的结果'),
              if (_error != null) Text(_error!),
              if (_error != null)
                TextButton(
                    onPressed: _busy ? null : () => _load(),
                    child: const Text('重试读取结果')),
              for (final card in _cards)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InkWell(
                        key: ValueKey('conversation-result-${card.id}'),
                        onTap: () => _open(card),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ResultCardView(
                                  card: card, compact: true, readOnly: true),
                              Text(
                                  '来源任务：${card.taskId} · 运行：${card.turnId.isEmpty ? '未记录' : card.turnId}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ]))),
              if (_next != null)
                TextButton(
                    onPressed: _busy ? null : () => _load(more: true),
                    child: const Text('加载更早结果')),
              if (_busy) const LinearProgressIndicator(),
            ]));
  }
}

/// Plan dock entry: optional task/run scope, without growing the dock itself.
Future<void> openConversationResults(BuildContext context,
        {required ConversationResultScope scope,
        bool Function()? sourceIsCurrent,
        ArtifactService artifacts = const ArtifactService()}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('本轮已保存结果')),
            body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConversationResultTimeline(
                    scope: scope,
                    artifacts: artifacts,
                    sourceIsCurrent: sourceIsCurrent,
                    title: '本轮已保存结果',
                    showEmpty: true)))));
