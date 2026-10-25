import '../widgets/empty_state_view.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_page_layout.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:drift/drift.dart' show Variable;
import '../../application/artifact_service.dart';
import '../../application/artifact_result_actions.dart';
import '../../application/non_file_result_actions.dart';
import '../../application/research_artifact_service.dart';
import '../../domain/research_artifact.dart';
import '../../application/global_search_service.dart';
import '../../application/jobs/job_board.dart';
import '../../application/providers.dart';
import '../../application/log_service.dart';
import '../../application/result_action_service.dart';
import '../../application/result_action_approval_scope.dart';
import '../../application/nexus_guard.dart';
import '../../domain/models.dart' show ToolApproval;
import '../../domain/result_card.dart';
import '../../domain/system_connector_request.dart';
import '../../domain/unique_id.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/database/result_action_store.dart';
import '../../infrastructure/database/conversation_result_store.dart';
import '../../infrastructure/tools/android_system_editor_actions.dart';
import '../chat/widgets/result_card_view.dart';
import '../projects/project_change_set_page.dart';
import '../search/global_search_page.dart';
import '../tasks/task_details_page.dart';
import '../widgets/tool_approval_helper.dart';
import 'research_artifacts_page.dart';

class ArtifactCenterPage extends ConsumerStatefulWidget {
  const ArtifactCenterPage(
      {super.key,
      this.service = const ArtifactService(),
      this.readOnly = false,
      this.initialArtifactId,
      this.resultActions,
      this.initialResultCardId,
      this.resultScope,
      this.sourceIsCurrent});
  final ArtifactService service;
  final bool readOnly;
  final String? initialArtifactId;

  /// Direct detail entry, using the same executor and approval UI as the center.
  final String? initialResultCardId;
  final ConversationResultScope? resultScope;
  final bool Function()? sourceIsCurrent;

  /// 通过组合执行器接入文件、系统编辑器、提醒与工作流。
  final ResultActionService? resultActions;
  @override
  ConsumerState<ArtifactCenterPage> createState() => _ArtifactCenterPageState();
}

class _ArtifactCenterPageState extends ConsumerState<ArtifactCenterPage> {
  final _items = <ProjectArtifact>[];
  SearchCursor? _next;
  bool _busy = false, _started = false;
  String? _error;

  /// 结果卡与成果索引分开容错：结果卡表未迁移或损坏时，成果列表仍然可用。
  List<ResultCard> _cards = const [];
  List<ResearchArtifact> _research = const [];
  String? _cardsError;
  ResultActionService? _actions;
  @override
  void initState() {
    super.initState();
    _load();
    if (widget.initialArtifactId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openById(widget.initialArtifactId!));
      });
    }
  }

  Future<AppDatabase> _db() => ref.read(databaseProvider.future);
  Future<ProjectArtifact?> _current(String id) async {
    final rows = await (await _db()).customSelect(
        'SELECT id, project_id AS projectId, task_id AS taskId, run_id AS runId, kind, relative_path AS relativePath, hash, bytes, inspection_json AS inspectionJson, created_at AS createdAt FROM artifacts WHERE id = ? LIMIT 1',
        variables: [Variable<String>(id)]).get();
    if (rows.isEmpty) return null;
    final artifact = ProjectArtifact.fromJson(rows.first.data);
    final scope = widget.resultScope;
    if (scope != null) {
      final card = await ConversationResultRepository(await _db(), scope)
          .findCard(widget.initialResultCardId ?? 'artifact-$id');
      if (card == null ||
          card.resourceType != 'artifact' ||
          card.resourceId != id ||
          card.taskId != artifact.taskId ||
          card.turnId != artifact.runId) {
        return null;
      }
    }
    return artifact;
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = await _db();
      if (widget.resultScope != null && widget.initialResultCardId == null) {
        throw StateError('Scoped entry requires a selected result');
      }
      if (widget.initialResultCardId != null) {
        final actions = await _resultActionService();
        final card = await actions.findCard(widget.initialResultCardId!);
        if (!mounted) return;
        setState(() {
          _cards = card == null ? [] : [card];
          _started = true;
        });
        return;
      }
      final page = await GlobalSearchService(db)
          .search(kind: SearchKind.artifact, after: more ? _next : null);
      final rows = <ProjectArtifact>[];
      for (final hit in page.items) {
        final row = await _current(hit.id);
        if (row != null) rows.add(row);
      }
      // 只在首次/刷新时重读结果卡；分页加载更多成果不重复覆盖卡片列表。
      final cards = more ? null : await _loadResultCards();
      final research = more ? null : await ResearchArtifactService(db).list();
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(rows);
        if (cards != null) _cards = cards;
        if (research != null) _research = research;
        _next = page.next;
        _started = true;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '成果读取失败，已保留先前结果；请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openById(String id) async {
    try {
      final current = await _current(id);
      if (!mounted) return;
      if (current == null) throw StateError('Record deleted');
      await _open(current);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('成果记录已删除或读取失败，请刷新')));
      }
    }
  }

  Future<bool> _open(ProjectArtifact stale,
      {bool verifiedPreviewOnly = false}) async {
    try {
      final current = await _current(stale.id);
      if (current == null ||
          jsonEncode(current.toJson()) != jsonEncode(stale.toJson())) {
        throw StateError('Record deleted or changed');
      }
      final payload = await widget.service.inspectPayload(current);
      if (verifiedPreviewOnly && payload.state != ArtifactPayloadState.intact) {
        throw StateError('Verified preview unavailable');
      }
      String? preview;
      if (payload.state == ArtifactPayloadState.intact &&
          const ['text', 'web'].contains(current.kind)) {
        final file = payload.file!;
        preview = utf8.decode(
            (await file
                    .openRead(0, math.min(await file.length(), 128000))
                    .toList())
                .expand((b) => b)
                .toList(),
            allowMalformed: true);
        if (current.bytes > 128000) preview += '\n[仅预览前 128000 字节]';
      }
      if (!mounted || (verifiedPreviewOnly && !_canInteract())) return false;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => _ArtifactDetail(
              artifact: current,
              payload: payload,
              preview: preview,
              // Result-card previews cannot bypass the share confirmation flow.
              readOnly: widget.readOnly || verifiedPreviewOnly,
              reload: () => _current(current.id),
              service: widget.service)));
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('成果已删除、读取失败或无权限；请刷新后重试')));
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.initialResultCardId != null) {
      final actions = _actions ?? widget.resultActions;
      if (!_started || actions == null || _cards.isEmpty || _error != null) {
        return Scaffold(
            appBar: const NexusPageHeader(title: '结果卡详情'),
            body: NexusPageLayout(
                child: Center(
                    child: _busy
                        ? const CircularProgressIndicator()
                        : Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_error ?? '结果卡已删除或已不属于当前会话，请返回刷新'),
                            TextButton(
                                onPressed: () => _load(),
                                child: const Text('重新读取')),
                          ]))));
      }
      return _ResultCardDetail(
          card: _cards.single,
          service: actions,
          database: _db,
          readOnly: widget.readOnly,
          onOpenTask: _openTask);
    }
    return Scaffold(
        appBar: NexusPageHeader(title: '成果中心', actions: [
          IconButton(
              tooltip: '研究成果与引用',
              icon: const Icon(Icons.fact_check_outlined),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) =>
                          ResearchArtifactsPage(readOnly: widget.readOnly)))),
          IconButton(
              tooltip: '搜索全部成果',
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) =>
                          GlobalSearchPage(readOnly: widget.readOnly)))),
          IconButton(
              tooltip: '刷新成果',
              icon: const Icon(Icons.refresh),
              onPressed: _busy ? null : () => _load())
        ]),
        body: NexusPageLayout(
            child: Column(children: [
          const ExpansionTile(
            title: Text('成果状态说明'),
            children: [
              Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text('本地成果索引。文件完整性、格式验证和任务成功互不等同；文件缺失不会冒充交付完成。'))
            ],
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          _resultCardSection(Theme.of(context)),
          if (_research.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '可核查研究成果 (${_research.length})',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      for (final r in _research.take(2))
                        Text(
                          '• ${r.topic} · 引用 ${r.totalCitations} 条 · ${r.supportLevel.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
              child: (!_busy && _started && _items.isEmpty)
                  ? const EmptyStateView(
                      icon: Icons.description_outlined,
                      title: '还没有成果',
                      message: '生成并成功保存文件后会出现在这里')
                  : ListView.builder(
                      itemCount: _items.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _items.length) {
                          return _next == null
                              ? const SizedBox(height: 24)
                              : Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: OutlinedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _load(more: true),
                                      child: const Text('加载更多成果')));
                        }
                        final item = _items[index];
                        return Card(
                            child: InkWell(
                                onTap: () => _open(item),
                                child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(item.relativePath,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium),
                                          Text(
                                              '${item.kind} · ${item.bytes} 字节 · ${item.createdAt.toUtc().toIso8601String()}'),
                                          Text(item.projectId.isEmpty
                                              ? '非项目成果'
                                              : '项目：${item.projectId}'),
                                          Text(
                                              '任务：${item.taskId} · 运行：${item.runId}'),
                                        ]))));
                      }))
        ])));
  }

  /// Only file actions are wired. No arbitrary path/command from a card is used.
  Future<ResultActionService> _resultActionService() async {
    final injected = widget.resultActions;
    if (injected != null) return injected;
    final cached = _actions;
    if (cached != null) return cached;
    final db = await _db();
    final repo = widget.resultScope == null
        ? SqlResultActionRepository(db)
        : ConversationResultRepository(db, widget.resultScope!);
    final artifactReader = ArtifactResultResourceReader(
        lookup: _current, artifacts: widget.service);
    final artifactExecutor = ArtifactResultActionExecutor(
        lookup: _current,
        artifacts: widget.service,
        canInteract: _canInteract,
        openPreview: (artifact) => _open(artifact, verifiedPreviewOnly: true),
        shareFile: (file) async {
          final result = await SharePlus.instance
              .share(ShareParams(files: [XFile(file.path)]));
          return switch (result.status) {
            ShareResultStatus.success => ArtifactShareOutcome.handedOff,
            ShareResultStatus.dismissed => ArtifactShareOutcome.dismissed,
            ShareResultStatus.unavailable => ArtifactShareOutcome.unavailable,
          };
        });
    final built = ResultActionService(
        repository: repo,
        resources: CompositeResultResourceReader(
          db: db,
          repository: repo,
          artifactReader: artifactReader,
        ),
        permissions: _ArtifactResultPermissionChecker(_canInteract),
        executor: CompositeResultActionExecutor(
          db: db,
          repository: repo,
          artifactExecutor: artifactExecutor,
          canInteract: _canInteract,
          openRoute: _launchRouteQuery,
          reviewDiff: _openDiffReview,
          adjustCalendar: _launchCalendarAdjust,
        ));
    _actions = built;
    return built;
  }

  bool _canInteract() =>
      mounted &&
      !widget.readOnly &&
      (widget.sourceIsCurrent?.call() ?? true) &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<bool> _launchRouteQuery(String query, ResultCard card) async {
    final logs = ref.read(logServiceProvider);
    void logFailure(String message, {Map<String, dynamic>? detail}) =>
        unawaited(
            logs.warning(message, category: 'result_action', detail: detail));
    final encoded = Uri.encodeQueryComponent(query);
    final geoUri = Uri.parse('geo:0,0?q=$encoded');
    try {
      if (await launchUrl(geoUri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (error, stackTrace) {
      NexusGuard.degradeCaught('artifact.openGeo', error, stackTrace,
          logger: logFailure);
    }
    final webUri =
        Uri.parse('https://www.openstreetmap.org/search?query=$encoded');
    try {
      if (await launchUrl(webUri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (error, stackTrace) {
      NexusGuard.degradeCaught('artifact.openMapFallback', error, stackTrace,
          logger: logFailure);
    }
    return false;
  }

  Future<bool> _openDiffReview(
      ResultCard card, Task? task, Project? project) async {
    if (!mounted) return false;
    if (project != null) {
      await Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => ProjectChangeSetPage(
                projectId: project.id,
                workspacePath: project.canonicalRootPath,
                taskId: task?.id,
              )));
      return true;
    }
    if (card.taskId.trim().isNotEmpty) {
      await _openTask(card.taskId.trim());
      return true;
    }
    return false;
  }

  Future<bool> _launchCalendarAdjust(
      SystemConnectorRequest request, ResultCard card) async {
    final logs = ref.read(logServiceProvider);
    try {
      final result = await AndroidSystemEditorActions.execute(request.toJson());
      if (result.ok) return true;
    } catch (error, stackTrace) {
      NexusGuard.degradeCaught('artifact.openCalendar', error, stackTrace,
          logger: (message, {detail}) => unawaited(logs.warning(message,
              category: 'result_action', detail: detail)));
    }
    return false;
  }

  Future<List<ResultCard>?> _loadResultCards() async {
    try {
      final service = await _resultActionService();
      final cards = await service.cards(limit: 20);
      if (mounted && _cardsError != null) setState(() => _cardsError = null);
      return cards;
    } catch (_) {
      if (mounted) {
        setState(() => _cardsError = '结果卡读取失败（可能尚未完成数据表迁移）；成果索引不受影响，可稍后重试');
      }
      return null;
    }
  }

  Future<void> _refreshCards() async {
    final cards = await _loadResultCards();
    if (cards != null && mounted) setState(() => _cards = cards);
  }

  Future<void> _openResultCard(ResultCard stale) async {
    try {
      final service = await _resultActionService();
      // 点开前重新读一次：列表里的卡片可能已被其他设备改动或删除。
      final current = await service.findCard(stale.id);
      if (!mounted) return;
      if (current == null) {
        await _refreshCards();
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('结果卡已删除；已刷新列表')));
        }
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => _ResultCardDetail(
              card: current,
              service: service,
              database: _db,
              readOnly: widget.readOnly,
              onOpenTask: _openTask)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('结果卡读取失败或资源已失效；请刷新后重试')));
      }
    } finally {
      if (mounted) await _refreshCards();
    }
  }

  /// 返回关联任务：任务可能已被删除，此时只提示不跳转。
  Future<void> _openTask(String taskId) async {
    try {
      if (widget.resultScope != null) {
        final card = await (await _resultActionService())
            .findCard(widget.initialResultCardId ?? '');
        if (card == null ||
            card.taskId != taskId ||
            !(widget.sourceIsCurrent?.call() ?? true)) {
          return;
        }
      }
      final task = await JobBoard(await _db()).findTaskInfo(taskId);
      if (!mounted) return;
      if (task == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('关联任务已删除')));
        return;
      }
      await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => TaskDetailsPage(task: task)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开关联任务，请稍后重试')));
      }
    }
  }

  Widget _resultCardSection(ThemeData theme) {
    if (_cards.isEmpty && _cardsError == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(children: [
            Text('结果卡', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            Expanded(
                child: Text('${_cards.length} 张可操作结果；点开查看动作与状态',
                    style: theme.textTheme.bodySmall))
          ])),
      if (_cardsError != null)
        Padding(padding: const EdgeInsets.all(12), child: Text(_cardsError!)),
      if (_cards.isNotEmpty)
        SizedBox(
            // 紧凑卡的标题最多两行、摘要最多两行；184 是这两行都占满时仍不溢出
            // 的高度（168 会差 1px 触发 RenderFlex overflow）。
            height: 184,
            child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _cards.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final card = _cards[index];
                  return SizedBox(
                      width: 280,
                      child: InkWell(
                          onTap: () => _openResultCard(card),
                          child: ResultCardView(
                              card: card, compact: true, readOnly: true)));
                }))
    ]);
  }
}

/// 成果中心没有独立权限源：只读模式即不可操作，其余交给统一审批把关。
class _ArtifactResultPermissionChecker implements ResultPermissionChecker {
  _ArtifactResultPermissionChecker(this._allowed);
  final bool Function() _allowed;

  @override
  Future<bool> canPerform(ResultActionSpec spec, ResultCard card) async =>
      _allowed();
}

class _ArtifactDetail extends StatefulWidget {
  const _ArtifactDetail(
      {required this.artifact,
      required this.payload,
      required this.preview,
      required this.readOnly,
      required this.reload,
      required this.service});
  final ProjectArtifact artifact;
  final ArtifactPayload payload;
  final String? preview;
  final bool readOnly;
  final Future<ProjectArtifact?> Function() reload;
  final ArtifactService service;
  @override
  State<_ArtifactDetail> createState() => _ArtifactDetailState();
}

class _ArtifactDetailState extends State<_ArtifactDetail> {
  bool _busy = false;
  String? _status;
  Future<void> _action(bool share) async {
    if (_busy || widget.readOnly) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final current = await widget.reload();
      if (current == null ||
          jsonEncode(current.toJson()) !=
              jsonEncode(widget.artifact.toJson())) {
        throw StateError('Resource changed');
      }
      final file = await widget.service.verifiedPayload(current);
      if (share) {
        final result = await SharePlus.instance
            .share(ShareParams(files: [XFile(file.path)]));
        if (mounted) {
          setState(() => _status = result.status == ShareResultStatus.dismissed
              ? '已取消系统分享'
              : '已交给系统分享；不代表接收方已经保存或收到');
        }
      } else {
        if (!const ['text', 'web'].contains(current.kind)) {
          throw StateError('Not text');
        }
        final bytes = await file.length();
        if (bytes > 128000) {
          throw StateError('Use file share for large contents');
        }
        await Clipboard.setData(ClipboardData(text: await file.readAsString()));
        if (mounted) setState(() => _status = '内容已复制到系统剪贴板，请注意敏感数据');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = '操作未完成：记录已变化、文件失效、内容过大或系统分享不可用；请返回刷新');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.artifact;
    final state = switch (widget.payload.state) {
      ArtifactPayloadState.intact => '副本完整（SHA-256 一致；不代表内容安全或任务验证通过）',
      ArtifactPayloadState.missing => '文件缺失：保留来源索引，可回到来源任务重新生成',
      ArtifactPayloadState.changed => '副本内容已变化：已禁用交付操作',
      ArtifactPayloadState.unverified => '旧记录缺少可信摘要：尚未校验，不能作为已验证副本交付',
      ArtifactPayloadState.invalid => '路径或记录不合法：已阻止访问'
    };
    final enabled = !widget.readOnly &&
        !_busy &&
        widget.payload.state == ArtifactPayloadState.intact;
    return Scaffold(
        appBar: const NexusPageHeader(title: '成果详情'),
        body: NexusPageLayout(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          SelectableText(
              '${a.relativePath}\n$state\n记录：${a.id}\n任务：${a.taskId}\n运行：${a.runId}\n项目：${a.projectId.isEmpty ? '非项目' : a.projectId}\n大小：${a.bytes} 字节\n创建：${a.createdAt.toUtc().toIso8601String()}\nSHA-256：${a.hash}'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: enabled ? () => _action(true) : null,
                icon: const Icon(Icons.ios_share),
                label: const Text('系统分享／导出副本')),
            if (widget.preview != null)
              OutlinedButton.icon(
                  onPressed: enabled ? () => _action(false) : null,
                  icon: const Icon(Icons.copy),
                  label: const Text('复制文本内容'))
          ]),
          if (_status != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_status!)),
          if (widget.preview != null) ...[
            const SizedBox(height: 16),
            Text(a.kind == 'web' ? '网页源码预览（不执行脚本）' : '文本预览',
                style: Theme.of(context).textTheme.titleMedium),
            SelectableText(widget.preview!)
          ],
          const SizedBox(height: 16),
          const Text('每次交付前重新读取记录并校验文件。分享不代表第三方已经完成保存；已生成的历史副本不会随工作区编辑自动改变。'),
        ])));
  }
}

/// 结果卡详情：动作按「准备 → 待确认 → 执行」推进，每次失败都保留真实状态。
class _ResultCardDetail extends StatefulWidget {
  const _ResultCardDetail(
      {required this.card,
      required this.service,
      required this.database,
      required this.readOnly,
      required this.onOpenTask});
  final ResultCard card;
  final ResultActionService service;
  final Future<AppDatabase> Function() database;
  final bool readOnly;
  final Future<void> Function(String taskId) onOpenTask;
  @override
  State<_ResultCardDetail> createState() => _ResultCardDetailState();
}

class _ResultCardDetailState extends State<_ResultCardDetail> {
  late ResultCard _card;
  final _feedback = <String, ResultCardActionFeedback>{};
  final _pending = <String, String>{};
  bool _busy = false;
  ResultActionApprovalScope? _approvalScope;

  @override
  void dispose() {
    final scope = _approvalScope;
    if (scope != null) {
      unawaited(NexusGuard.silentlyAsync<void>(
          'resultApproval.dispose', scope.close));
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _card = widget.card;
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _feedback.clear();
      _pending.clear();
    });
    try {
      final refreshed = await widget.service.refresh(_card.id);
      if (!mounted) return;
      if (refreshed == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('结果卡已删除')));
        return;
      }
      setState(() => _card = refreshed);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('刷新失败；请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(ResultActionSpec spec) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _feedback[spec.actionType] = const ResultCardActionFeedback(
          phase: ResultCardFeedbackPhase.preparing, message: '正在重新读取资源、版本与权限…');
    });
    try {
      final prepared = await widget.service.prepare(_card, spec.actionType,
          // A new explicit file-open/share click is a new user intent. Keep the
          // same action ID through confirmation/execution; never auto-replay a
          // cancelled/unknown handoff under the old idempotency key.
          idempotencyKey:
              const {'file.preview', 'file.share'}.contains(spec.actionType)
                  ? UniqueId.generate('result-file-intent')
                  : null);
      if (!mounted) return;
      _apply(spec, prepared);
      final action = prepared.action;
      // 校验失败：没有落库，资源修好后可以重试。
      if (prepared.hasError) return;
      // 需要确认的动作先停在待确认；确认前绝不调用执行器。
      if (prepared.pendingConfirmation) return;
      if (action != null) await _execute(spec, action.id);
    } catch (_) {
      if (mounted) {
        setState(() => _feedback[spec.actionType] =
            const ResultCardActionFeedback(
                phase: ResultCardFeedbackPhase.failed,
                message: '准备阶段出错，未执行任何动作；请重试',
                errorCode: ResultActionErrorCode.unknown));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _apply(ResultActionSpec spec, ResultActionRun run) {
    final action = run.action;
    if (run.card != null) _card = run.card!;
    if (action != null && run.pendingConfirmation) {
      _pending[spec.actionType] = action.id;
    } else {
      _pending.remove(spec.actionType);
    }
    setState(() =>
        _feedback[spec.actionType] = ResultCardActionFeedback.fromRun(run));
  }

  Future<void> _confirm(ResultActionSpec spec) async {
    final actionId = _pending[spec.actionType];
    if (actionId == null || _busy) return;
    setState(() => _busy = true);
    try {
      final scope = await ResultActionApprovalScope.open(
          await widget.database(), actionId);
      if (scope == null) {
        final rejected = await widget.service.rejectPending(actionId);
        if (mounted) _apply(spec, rejected);
        return;
      }
      _approvalScope = scope;
      if (!mounted) return;
      final decision = await promptResultActionApproval(context, scope);
      if (!mounted) return;
      if (decision != ToolApproval.allowOnce) {
        final rejected = await widget.service.rejectPending(actionId);
        if (mounted) _apply(spec, rejected);
        return;
      }
      final confirmed = await widget.service.confirm(actionId, scope.approval);
      if (!mounted) return;
      _apply(spec, confirmed);
      if (confirmed.hasError || confirmed.pendingConfirmation) return;
      await _execute(spec, actionId);
    } catch (_) {
      if (mounted) {
        setState(() => _feedback[spec.actionType] =
            const ResultCardActionFeedback(
                phase: ResultCardFeedbackPhase.failed,
                message: '确认阶段出错，动作未执行；请重试',
                errorCode: ResultActionErrorCode.unknown));
      }
    } finally {
      final scope = _approvalScope;
      _approvalScope = null;
      if (scope != null) {
        await NexusGuard.silentlyAsync<void>(
            'resultApproval.close', scope.close);
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _execute(ResultActionSpec spec, String actionId) async {
    setState(() => _feedback[spec.actionType] = const ResultCardActionFeedback(
        phase: ResultCardFeedbackPhase.executing, message: '正在执行…'));
    final run = await widget.service.execute(actionId,
        canContinue: () =>
            mounted &&
            !widget.readOnly &&
            (ModalRoute.of(context)?.isCurrent ?? false));
    if (!mounted) return;
    _apply(spec, run);
  }

  @override
  Widget build(BuildContext context) {
    final taskId = _card.taskId.trim();
    return Scaffold(
        appBar: const NexusPageHeader(title: '结果卡详情'),
        body: NexusPageLayout(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          ResultCardView(
              card: _card,
              feedback: _feedback,
              onAction: widget.readOnly ? null : _run,
              onConfirm: widget.readOnly ? null : _confirm,
              onRefresh: _refresh,
              onOpenTask:
                  taskId.isEmpty ? null : () => widget.onOpenTask(taskId),
              readOnly: widget.readOnly),
          if (_busy)
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator()),
          const SizedBox(height: 16),
          const Text(
              '每次点击都会重新读取资源、版本与权限；只有注册表内的动作会出现在这里，模型生成的任意命令不会被执行。失败会保留真实状态，不会显示成功。'),
        ])));
  }
}
