import '../widgets/empty_state_view.dart';
import '../widgets/nexus_search_field.dart';
import '../widgets/nexus_page_layout.dart';
import 'dart:async';
import '../artifacts/artifact_center_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/global_search_service.dart';
import '../../application/jobs/job_board.dart';
import '../../application/providers.dart';
import '../projects/project_home_page.dart';
import '../tasks/task_details_page.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';

class GlobalSearchPage extends ConsumerStatefulWidget {
  const GlobalSearchPage(
      {super.key,
      this.onConversationSelected,
      this.returnConversation = false,
      this.initialQuery = '',
      this.readOnly = false});
  final ValueChanged<String>? onConversationSelected;
  final bool returnConversation;
  final String initialQuery;

  /// Isolated debug fixtures disable navigation into execution-capable pages.
  final bool readOnly;
  @override
  ConsumerState<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends ConsumerState<GlobalSearchPage> {
  late final _query = TextEditingController(text: widget.initialQuery);
  final _project = TextEditingController();
  Timer? _debounce;
  SearchKind? _kind;
  DateTimeRange? _dates;
  List<SearchHit> _hits = const [];
  SearchCursor? _next;
  int _generation = 0;
  bool _loading = true, _more = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _project.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _generation++;
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 300), () => unawaited(_load()));
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_loading || _more || _next == null)) return;
    _debounce?.cancel();
    final generation = ++_generation;
    final query = _query.text, project = _project.text;
    final kind = _kind, dates = _dates, cursor = more ? _next : null;
    setState(() {
      if (more) {
        _more = true;
      } else {
        _loading = true;
        _more = false;
      }
      _error = null;
    });
    try {
      final db = await ref.read(databaseProvider.future);
      final result = await GlobalSearchService(db).search(
          query: query,
          kind: kind,
          projectId: project,
          since: dates?.start,
          before: dates == null
              ? null
              : DateTime(dates.end.year, dates.end.month, dates.end.day + 1),
          after: cursor);
      if (!mounted || generation != _generation) return;
      setState(() {
        final current = more ? _hits : const <SearchHit>[];
        _hits = {
          for (final h in [...current, ...result.items]) h.key: h
        }.values.toList();
        _next = result.next;
        _loading = false;
        _more = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _more = false;
        _error = '搜索失败，原有结果已保留，请重试';
      });
    }
  }

  Future<void> _chooseDates() async {
    final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: _dates);
    if (!mounted || picked == null) return;
    setState(() => _dates = picked);
    await _load();
  }

  Future<void> _open(SearchHit hit) async {
    try {
      final db = await ref.read(databaseProvider.future);
      final source = await GlobalSearchService(db).readSource(hit);
      if (!mounted) return;
      if (source == null) {
        FloatingToast.show(context, '记录已删除，请刷新结果');
        return;
      }
      final canConversation = !widget.readOnly &&
          hit.conversationId != null &&
          (widget.onConversationSelected != null || widget.returnConversation);
      final action = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(hit.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                content: SizedBox(
                    width: double.maxFinite,
                    height: 400,
                    child:
                        SingleChildScrollView(child: SelectableText(source))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭')),
                  if (canConversation)
                    TextButton(
                        onPressed: () => Navigator.pop(context, 'conversation'),
                        child: const Text('打开关联会话')),
                  if (!widget.readOnly && hit.kind == SearchKind.task)
                    TextButton(
                        onPressed: () => Navigator.pop(context, 'task'),
                        child: const Text('打开任务')),
                  if (!widget.readOnly && hit.kind == SearchKind.artifact)
                    TextButton(
                        onPressed: () => Navigator.pop(context, 'artifact'),
                        child: const Text('检查与使用成果')),
                  if (!widget.readOnly && hit.kind == SearchKind.project)
                    TextButton(
                        onPressed: () => Navigator.pop(context, 'project'),
                        child: const Text('打开项目')),
                ],
              ));
      if (!mounted || action == null) return;
      if (action == 'conversation') {
        final conversation = await db.findConversation(hit.conversationId!);
        if (!mounted) return;
        if (conversation == null) {
          FloatingToast.show(context, '关联会话已删除');
          return;
        }
        Navigator.of(context)
            .pop(widget.returnConversation ? conversation : null);
        widget.onConversationSelected?.call(conversation.id);
      } else if (action == 'artifact') {
        await Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => ArtifactCenterPage(initialArtifactId: hit.id)));
      } else if (action == 'task') {
        final task = await JobBoard(db).findTaskInfo(hit.id);
        if (!mounted) return;
        if (task == null) {
          FloatingToast.show(context, '任务已删除');
          return;
        }
        await Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => TaskDetailsPage(
                task: task,
                onConversationSelected: widget.onConversationSelected)));
      } else if (action == 'project') {
        if (await db.findProject(hit.id) == null) {
          if (mounted) FloatingToast.show(context, '项目已删除');
          return;
        }
        if (!mounted) return;
        await Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => ProjectHomePage(projectId: hit.id)));
      }
    } catch (_) {
      if (mounted) FloatingToast.show(context, '读取来源失败，未执行任何搜索结果');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: NexusPageHeader(
            title: '全量搜索',
            subtitle: '仅在本地查询，不调用模型或上传检索词',
            onBack: () => Navigator.of(context).pop(),
            actions: [
              IconButton(
                  tooltip: '刷新搜索',
                  onPressed: () => _load(),
                  icon: const Icon(Icons.refresh))
            ]),
        body: NexusPageLayout(
            child: Column(children: [
          Flexible(
              child: SingleChildScrollView(
                  child: Column(children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: NexusSearchField(
                    controller: _query,
                    hintText: '搜索历史、任务、项目、成果及资料',
                    maxLength: 512,
                    onChanged: _changed,
                    onSubmitted: (_) => _load(),
                    onClear: () {
                      _query.clear();
                      _changed('');
                    })),
            ExpansionTile(
                title: Text(
                    '筛选 · ${_kind == null ? "全部类型" : GlobalSearchService.label(_kind!)}${_dates == null ? "" : " · 已选日期"}'),
                children: [
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: DropdownButtonFormField<SearchKind?>(
                          initialValue: _kind,
                          decoration: const InputDecoration(
                              labelText: '结果类型', border: OutlineInputBorder()),
                          items: [
                            const DropdownMenuItem<SearchKind?>(
                                value: null, child: Text('全部类型')),
                            for (final k in SearchKind.values)
                              DropdownMenuItem(
                                  value: k,
                                  child: Text(GlobalSearchService.label(k)))
                          ],
                          onChanged: (kind) {
                            setState(() => _kind = kind);
                            unawaited(_load());
                          })),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: TextField(
                          controller: _project,
                          maxLength: 256,
                          onChanged: _changed,
                          decoration: const InputDecoration(
                              labelText: '项目 ID（留空为全部；不把全局资料冒充项目资料）',
                              border: OutlineInputBorder(),
                              counterText: ''))),
                  Wrap(spacing: 8, children: [
                    TextButton.icon(
                        onPressed: _chooseDates,
                        icon: const Icon(Icons.date_range),
                        label: Text(_dates == null
                            ? '按设备本地日期筛选'
                            : '${_dates!.start.toIso8601String().split('T').first} 至 ${_dates!.end.toIso8601String().split('T').first}')),
                    if (_dates != null)
                      TextButton(
                          onPressed: () {
                            setState(() => _dates = null);
                            unawaited(_load());
                          },
                          child: const Text('清除日期'))
                  ]),
                ]),
          ]))),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  Expanded(child: Text(_error!)),
                  TextButton(onPressed: () => _load(), child: const Text('重试'))
                ])),
          Expanded(
              flex: 2,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _hits.isEmpty
                      ? const EmptyStateView(
                          icon: Icons.search_off_rounded,
                          title: '没有匹配记录',
                          message: '试试其他关键词；搜索不限于最近列表')
                      : ListView.builder(
                          key: const ValueKey('global-search-results'),
                          itemCount: _hits.length + 1,
                          itemBuilder: (context, index) {
                            if (index == _hits.length) {
                              return Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 12, 20, 12),
                                  child: _more
                                      ? const Center(
                                          child: CircularProgressIndicator())
                                      : _next == null
                                          ? const Center(
                                              child: Text('已到当前查询末尾；记录变化后请刷新'))
                                          : OutlinedButton(
                                              onPressed: () =>
                                                  _load(more: true),
                                              child: const Text('加载更多')));
                            }
                            final hit = _hits[index];
                            final displayTitle = hit.title.trim().isEmpty ||
                                    hit.title == hit.id ||
                                    (hit.kind == SearchKind.task &&
                                        hit.title == '任务 ${hit.id}')
                                ? '未命名${GlobalSearchService.label(hit.kind)}'
                                : hit.title;
                            final snippet = hit.kind == SearchKind.task
                                ? const {
                                      'completed': '已完成',
                                      'success': '已完成',
                                      'failed': '失败',
                                      'running': '执行中',
                                      'paused': '已暂停',
                                      'cancelled': '已取消'
                                    }[hit.snippet.trim()] ??
                                    hit.snippet
                                : hit.snippet;
                            final timeStr = hit.updatedAt
                                .toLocal()
                                .toString()
                                .substring(0, 16);
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                key: ValueKey(hit.key),
                                isThreeLine: true,
                                title: Text(displayTitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    '${GlobalSearchService.label(hit.kind)} · $timeStr\n$snippet',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _open(hit),
                              ),
                            );
                          })),
        ])),
      );
}
