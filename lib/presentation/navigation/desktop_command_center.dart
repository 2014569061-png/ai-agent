import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/desktop_search_service.dart';
import '../theme/desktop_theme.dart';

/// 命令中心条目：一个可执行的导航或命令动作。
class DesktopCommandAction {
  const DesktopCommandAction({
    required this.icon,
    required this.label,
    required this.onRun,
    this.group = '命令',
    this.hint,
  });

  final IconData icon;
  final String label;
  final String group;
  final String? hint;
  final VoidCallback onRun;
}

sealed class _Entry {
  const _Entry();
}

class _HeaderEntry extends _Entry {
  const _HeaderEntry(this.title);

  final String title;
}

class _ActionEntry extends _Entry {
  const _ActionEntry(this.action);

  final DesktopCommandAction action;
}

class _ResultEntry extends _Entry {
  const _ResultEntry(this.result);

  final DesktopSearchResult result;
}

/// 桌面命令中心（Ctrl+K）：命令 / 页面导航与会话、项目、任务
/// 全局搜索的统一入口。↑↓ 选择、Enter 执行、Esc 关闭。
class DesktopCommandCenter extends ConsumerStatefulWidget {
  const DesktopCommandCenter({
    super.key,
    required this.actions,
    required this.onOpenResult,
    this.maxSearchResults = 8,
  });

  final List<DesktopCommandAction> actions;
  final FutureOr<void> Function(DesktopSearchResult result) onOpenResult;
  final int maxSearchResults;

  @override
  ConsumerState<DesktopCommandCenter> createState() =>
      _DesktopCommandCenterState();
}

class _DesktopCommandCenterState extends ConsumerState<DesktopCommandCenter> {
  final TextEditingController _query = TextEditingController();
  late final FocusNode _inputFocus = FocusNode(onKeyEvent: _handleKey);
  List<_Entry> _entries = const <_Entry>[];
  int _highlight = 0;

  @override
  void dispose() {
    _query.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  static bool _matches(String label, String query) =>
      label.toLowerCase().contains(query);

  List<_Entry> get _selectable => <_Entry>[
        for (final entry in _entries)
          if (entry is! _HeaderEntry) entry,
      ];

  void _activate(_Entry entry) {
    if (entry is _ActionEntry) {
      Navigator.of(context).pop();
      entry.action.onRun();
      return;
    }
    if (entry is _ResultEntry) {
      Navigator.of(context).pop();
      Future<void> open() async => widget.onOpenResult(entry.result);
      unawaited(open());
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final selectable = _selectable;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (selectable.isNotEmpty) {
        setState(() => _highlight = (_highlight + 1) % selectable.length);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (selectable.isNotEmpty) {
        setState(() => _highlight =
            (_highlight - 1 + selectable.length) % selectable.length);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (selectable.isNotEmpty) {
        final index = _highlight >= selectable.length ? 0 : _highlight;
        _activate(selectable[index]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  IconData _resultIcon(DesktopSearchKind kind) => switch (kind) {
        DesktopSearchKind.conversation => Icons.chat_bubble_outline,
        DesktopSearchKind.project => Icons.folder_outlined,
        DesktopSearchKind.task => Icons.task_alt,
        DesktopSearchKind.file => Icons.description_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DesktopTheme.maybeOf(context);
    final accent = colors?.accent ?? theme.colorScheme.primary;
    final muted = colors?.muted ?? theme.hintColor;
    final border = colors?.border ?? theme.dividerColor;
    final panel = colors?.panel ?? theme.colorScheme.surface;

    final rawQuery = _query.text.trim();
    final query = rawQuery.toLowerCase();
    final search = rawQuery.isEmpty
        ? const AsyncData<List<DesktopSearchResult>>(<DesktopSearchResult>[])
        : ref.watch(desktopSearchProvider(rawQuery));

    final matchedActions = <DesktopCommandAction>[
      for (final action in widget.actions)
        if (query.isEmpty ||
            _matches(action.label, query) ||
            _matches(action.group, query))
          action,
    ];
    final groups = <String, List<DesktopCommandAction>>{};
    for (final action in matchedActions) {
      groups
          .putIfAbsent(action.group, () => <DesktopCommandAction>[])
          .add(action);
    }
    final entries = <_Entry>[];
    for (final group in groups.entries) {
      entries.add(_HeaderEntry(group.key));
      for (final action in group.value) {
        entries.add(_ActionEntry(action));
      }
    }
    final results = [
      ...?search.asData?.value,
      ...?(rawQuery.isEmpty
          ? null
          : ref.watch(desktopFileSearchProvider(rawQuery)).asData?.value)
    ];
    if (query.isNotEmpty && results.isNotEmpty) {
      entries.add(const _HeaderEntry('搜索结果'));
      for (final result in results.take(widget.maxSearchResults)) {
        entries.add(_ResultEntry(result));
      }
    }
    _entries = entries;
    final selectableCount = _selectable.length;
    if (_highlight >= selectableCount && selectableCount > 0) {
      _highlight = 0;
    }
    final nothingFound = selectableCount == 0 && !search.isLoading;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      backgroundColor: panel,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              child: Row(children: [
                Icon(Icons.search_rounded, size: 18, color: muted),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey('command-center-input'),
                    controller: _query,
                    focusNode: _inputFocus,
                    autofocus: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '输入命令，或搜索会话 / 项目 / 任务',
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => setState(() => _highlight = 0),
                  ),
                ),
                if (rawQuery.isNotEmpty)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '清空',
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () => setState(() {
                      _query.clear();
                      _highlight = 0;
                    }),
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors?.hover,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: border),
                  ),
                  child: Text(
                    'ESC',
                    style: DesktopTheme.monospaceStyle(context,
                        size: 10.5, color: muted),
                  ),
                ),
              ]),
            ),
            Divider(height: 1, color: border),
            if (search.hasError)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      '搜索失败，可重试；命令不受影响',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(desktopSearchProvider(rawQuery)),
                    child: const Text('重试'),
                  ),
                ]),
              ),
            Flexible(
              child: nothingFound
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          query.isEmpty ? '暂无可执行命令' : '没有匹配的命令或结果',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: muted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      shrinkWrap: true,
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        if (entry is _HeaderEntry) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                            child: Text(
                              entry.title,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: muted),
                            ),
                          );
                        }
                        final selectableIndex = entries
                            .take(index)
                            .where((item) => item is! _HeaderEntry)
                            .length;
                        final isHighlight = selectableIndex == _highlight;
                        final highlightColor = isHighlight
                            ? (colors?.selected ??
                                accent.withValues(alpha: 0.14))
                            : null;
                        final highlightShape = RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        );
                        if (entry is _ActionEntry) {
                          final action = entry.action;
                          return ListTile(
                            key: ValueKey(
                                'command-center-action-${action.group}-${action.label}'),
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            tileColor: highlightColor,
                            shape: highlightShape,
                            leading: Icon(action.icon,
                                size: 17,
                                color: isHighlight ? colors?.text : muted),
                            title: Text(action.label,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isHighlight
                                        ? FontWeight.w600
                                        : FontWeight.w400),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            trailing: action.hint == null
                                ? null
                                : Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: colors?.hover,
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(color: border)),
                                    child: Text(action.hint!,
                                        style: DesktopTheme.monospaceStyle(
                                            context,
                                            size: 11,
                                            color: muted))),
                            onTap: () => _activate(entry),
                          );
                        }
                        final result = (entry as _ResultEntry).result;
                        return ListTile(
                          key: ValueKey(
                              'command-center-result-${result.kind.name}-${result.id}'),
                          dense: true,
                          tileColor: highlightColor,
                          shape: highlightShape,
                          leading: Icon(_resultIcon(result.kind), size: 20),
                          title: Text(result.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(result.subtitle,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _activate(entry),
                        );
                      },
                    ),
            ),
            Divider(height: 1, color: border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Text(
                    '↑↓ 选择 · Enter 执行 · Esc 关闭',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
                if (search.isLoading && rawQuery.isNotEmpty)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
