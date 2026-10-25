import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/desktop_theme.dart';
import 'empty_state_view.dart';
import 'nexus_page_header.dart';

class DesktopResourceFilter<T> {
  const DesktopResourceFilter(this.label, this.matches);
  final String label;
  final bool Function(T item) matches;
}

class DesktopResourceSort<T> {
  const DesktopResourceSort(this.label, this.compare);
  final String label;
  final int Function(T a, T b) compare;
}

/// 桌面管理页的检索与操作布局。筛选和排序仅作用于本地已加载副本。
class DesktopResourceView<T> extends StatefulWidget {
  const DesktopResourceView(
      {super.key,
      required this.title,
      required this.description,
      required this.icon,
      required this.items,
      required this.searchText,
      required this.itemBuilder,
      required this.emptyTitle,
      required this.emptyMessage,
      this.searchHint = '搜索资源',
      this.actions = const [],
      this.filters = const [],
      this.sorts = const [],
      this.banner,
      this.loading = false,
      this.error,
      this.onReload,
      this.onTitleTap});
  final String title, description, searchHint, emptyTitle, emptyMessage;
  final IconData icon;
  final List<T> items;
  final String Function(T item) searchText;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final List<Widget> actions;
  final List<DesktopResourceFilter<T>> filters;
  final List<DesktopResourceSort<T>> sorts;
  final Widget? banner;
  final bool loading;
  final Object? error;
  final VoidCallback? onReload, onTitleTap;
  @override
  State<DesktopResourceView<T>> createState() => _DesktopResourceViewState<T>();
}

class _DesktopResourceViewState<T> extends State<DesktopResourceView<T>> {
  final _search = TextEditingController();
  int _filter = 0, _sort = 0;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
        _search.clear();
        _filter = 0;
      });
  @override
  Widget build(BuildContext context) {
    final colors = DesktopTheme.of(context);
    final query = _search.text.trim().toLowerCase();
    final filterIndex = _filter <= widget.filters.length ? _filter : 0;
    final sortIndex = _sort <= widget.sorts.length ? _sort : 0;
    final visible = widget.items
        .where((item) =>
            (query.isEmpty ||
                widget.searchText(item).toLowerCase().contains(query)) &&
            (filterIndex == 0 || widget.filters[filterIndex - 1].matches(item)))
        .toList();
    if (sortIndex > 0) visible.sort(widget.sorts[sortIndex - 1].compare);
    final unavailable = widget.loading || widget.error != null;
    Widget toolbar() =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
              key: const ValueKey('desktop-resource-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空搜索',
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close, size: 17)))),
          const SizedBox(height: 12),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                    label: const Text('全部'),
                    selected: filterIndex == 0,
                    onSelected: (_) => setState(() => _filter = 0)),
                for (var i = 0; i < widget.filters.length; i++)
                  ChoiceChip(
                      label: Text(widget.filters[i].label),
                      selected: filterIndex == i + 1,
                      onSelected: (_) => setState(() => _filter = i + 1)),
                if (widget.sorts.isNotEmpty)
                  PopupMenuButton<int>(
                      tooltip: '排序',
                      initialValue: sortIndex,
                      onSelected: (value) => setState(() => _sort = value),
                      itemBuilder: (_) => [
                            const PopupMenuItem(value: 0, child: Text('默认顺序')),
                            for (var i = 0; i < widget.sorts.length; i++)
                              PopupMenuItem(
                                  value: i + 1,
                                  child: Text(widget.sorts[i].label))
                          ],
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.sort_rounded,
                                size: 16, color: colors.muted),
                            const SizedBox(width: 5),
                            Text(
                                sortIndex == 0
                                    ? '默认顺序'
                                    : widget.sorts[sortIndex - 1].label,
                                style: TextStyle(
                                    color: colors.muted,
                                    fontSize: AppTokens.fontSizeCaption)),
                          ]))),
                Text(
                    unavailable
                        ? (widget.loading ? '正在读取…' : '读取失败')
                        : '显示 ${visible.length} / ${widget.items.length} 项已加载资源',
                    style: TextStyle(
                        color: colors.muted,
                        fontSize: AppTokens.fontSizeFootnote)),
              ]),
        ]);
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: NexusPageHeader(
          title: widget.title,
          subtitle: '资源管理',
          onTitleTap: widget.onTitleTap,
          actions: [
            if (widget.onReload != null)
              IconButton(
                  tooltip: '刷新资源',
                  onPressed: widget.loading ? null : widget.onReload,
                  icon: const Icon(Icons.refresh_rounded))
          ]),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: CustomScrollView(
                  key: PageStorageKey('desktop-resources-${widget.title}'),
                  slivers: [
                    SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                        sliver: SliverToBoxAdapter(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                            color: colors.selected,
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        child: Icon(widget.icon,
                                            color: colors.accent, size: 24)),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(widget.title,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headlineSmall),
                                          const SizedBox(height: 6),
                                          Text(widget.description,
                                              style: TextStyle(
                                                  color: colors.muted,
                                                  height: 1.6)),
                                        ])),
                                  ]),
                              if (widget.actions.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    children: widget.actions)
                              ],
                              if (widget.banner != null) ...[
                                const SizedBox(height: 18),
                                widget.banner!
                              ],
                              const SizedBox(height: 22),
                              toolbar(),
                            ]))),
                    if (unavailable || visible.isEmpty)
                      SliverFillRemaining(
                          hasScrollBody: false,
                          child: widget.loading
                              ? const Center(child: CircularProgressIndicator())
                              : widget.error != null
                                  ? EmptyStateView(
                                      icon: Icons.error_outline,
                                      title: '资源读取失败',
                                      message: '无法读取本地记录，请重试；原有配置不会因此被清空。',
                                      actionLabel: '重试',
                                      onAction: widget.onReload)
                                  : EmptyStateView(
                                      icon: widget.items.isEmpty
                                          ? widget.icon
                                          : Icons.search_off_rounded,
                                      title: widget.items.isEmpty
                                          ? widget.emptyTitle
                                          : '没有匹配的资源',
                                      message: widget.items.isEmpty
                                          ? widget.emptyMessage
                                          : '试试其他关键词，或重置当前筛选。',
                                      actionLabel:
                                          widget.items.isEmpty ? null : '重置筛选',
                                      onAction:
                                          widget.items.isEmpty ? null : _reset))
                    else
                      SliverPadding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                          sliver: SliverList.builder(
                              itemCount: visible.length,
                              itemBuilder: (context, index) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: widget.itemBuilder(
                                      context, visible[index])))),
                  ]))),
    );
  }
}

/// 标题、真实元信息与显式操作分层；窄窗口和放大文字下操作自动换行。
class DesktopResourceCard extends StatelessWidget {
  const DesktopResourceCard(
      {super.key,
      required this.title,
      required this.icon,
      this.description,
      this.metadata = const [],
      this.actions = const [],
      this.selected = false,
      this.content,
      this.onTap});
  final String title;
  final IconData icon;
  final String? description;
  final List<String> metadata;
  final List<Widget> actions;
  final bool selected;
  final Widget? content;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final colors = DesktopTheme.of(context);
    Widget details() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                      color: colors.selected,
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 20, color: colors.accent)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Tooltip(
                        message: title,
                        child: Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall)),
                    if (description?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Tooltip(
                          message: description,
                          child: Text(description!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: colors.muted,
                                  height: 1.5,
                                  fontSize: DesktopTheme.labelSize))),
                    ],
                  ])),
            ]),
            if (metadata.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final text in metadata)
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: colors.hover,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(text,
                          style: TextStyle(
                              color: colors.muted,
                              fontSize: DesktopTheme.smallSize))),
              ]),
            ],
          ],
        );
    Widget actionBar() => Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: actions);
    return Material(
      color: colors.panel,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? colors.accent : colors.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(builder: (context, box) {
              final compact = box.maxWidth >= 760 &&
                  content == null &&
                  MediaQuery.textScalerOf(context).scale(14) <= 19;
              if (compact && actions.isNotEmpty) {
                return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: details()),
                      const SizedBox(width: 20),
                      SizedBox(width: 240, child: actionBar()),
                    ]);
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    details(),
                    if (content != null) ...[
                      const SizedBox(height: 12),
                      content!
                    ],
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: actions),
                    ],
                  ]);
            }),
          )),
    );
  }
}

/// 隐去 URL 用户信息、查询参数与片段；不把凭据带入概览卡片。
String desktopEndpointLabel(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '未设置有效地址';
  return uri
      .replace(userInfo: '', query: '', fragment: '')
      .toString()
      .replaceFirst(RegExp(r'[?#]+$'), '');
}
